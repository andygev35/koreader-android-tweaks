#!/usr/bin/env bash
# Rebuild the Android GPU slide patch into a fresh KOReader APK.
#
# Requires: unzip, zip, p7zip-full (7z), zipalign, apksigner, keytool
#   (Ubuntu/Debian: apt install unzip zip p7zip-full zipalign apksigner)
#
# Usage:
#   ./build.sh <koreader-version-tag> [arch]
#   e.g. ./build.sh v2026.07.1 arm64
#
# Re-run this after every KOReader update: download the new APK, and this
# script re-applies the same two-file patch (frontend/ui/uimanager.lua hook
# + frontend/android_gpu_slide.lua) on top of it. If KOReader's own
# uimanager.lua has changed meaningfully around the refresh-execution loop
# since this was written, the patch step below may need manual adjustment --
# check the diff if `patch` fails.

set -euo pipefail

VERSION="${1:?Usage: ./build.sh <version-tag e.g. v2026.07.1> [arch: arm64|arm|x86]}"
ARCH="${2:-arm64}"
WORKDIR="$(mktemp -d)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "== Working in $WORKDIR =="
cd "$WORKDIR"

APK_NAME="koreader-android-${ARCH}-${VERSION}.apk"
echo "== Downloading $APK_NAME =="
curl -sSL -o original.apk \
  "https://github.com/koreader/koreader/releases/download/${VERSION}/${APK_NAME}"

echo "== Unpacking APK =="
mkdir unpacked
unzip -q original.apk -d unpacked

echo "== Extracting koreader.7z =="
mkdir 7z_extract
(cd 7z_extract && 7z x -y ../unpacked/assets/module/koreader.7z > /dev/null)

echo "== Applying patch to frontend/ui/uimanager.lua =="
UM=7z_extract/frontend/ui/uimanager.lua
if grep -q "AndroidGPUSlide" "$UM"; then
  echo "  (already patched? skipping insert)"
else
  python3 "$SCRIPT_DIR/apply_patch.py" "$UM"
fi

echo "== Dropping in frontend/android_gpu_slide.lua =="
cp "$SCRIPT_DIR/android_gpu_slide.lua" 7z_extract/frontend/android_gpu_slide.lua

echo "== Applying self-install bootstrap hook to reader.lua =="
RD=7z_extract/reader.lua
if grep -q "bundled_patches" "$RD"; then
  echo "  (already patched? skipping insert)"
else
  python3 "$SCRIPT_DIR/apply_bootstrap_patch.py" "$RD"
fi

echo "== Bundling patches/*.lua for self-install =="
mkdir -p 7z_extract/bundled_patches
if [ -d "$SCRIPT_DIR/bundled_patches" ]; then
  cp "$SCRIPT_DIR"/bundled_patches/*.lua 7z_extract/bundled_patches/
  ls 7z_extract/bundled_patches/
else
  echo "  (no $SCRIPT_DIR/bundled_patches directory found -- skipping, none bundled)"
fi

echo "== Syntax-checking patched files =="
luajit -e "assert(loadfile('7z_extract/frontend/ui/uimanager.lua')); print('uimanager.lua OK')"
luajit -e "assert(loadfile('7z_extract/frontend/android_gpu_slide.lua')); print('android_gpu_slide.lua OK')"
luajit -e "assert(loadfile('7z_extract/reader.lua')); print('reader.lua OK')"
for f in 7z_extract/bundled_patches/*.lua; do
  [ -e "$f" ] || continue
  luajit -e "assert(loadfile('$f')); print('$f OK')"
done

echo "== Repacking koreader.7z =="
(cd 7z_extract && 7z a -mx=9 -m0=lzma2 -ms=on ../new_koreader.7z . > /dev/null)

echo "== Staging modified APK contents =="
rm -rf stage && cp -r unpacked stage
cp new_koreader.7z stage/assets/module/koreader.7z
printf '%s-gpuslide1' "${VERSION#v}" > stage/assets/module/version.txt
rm -rf stage/META-INF

echo "== Building unsigned APK (matching original per-entry compression) =="
OUT_UNSIGNED="koreader-${ARCH}-gpuslide-unsigned.apk"
# resources.arsc MUST be stored uncompressed + 4-byte aligned on targetSdk 30+
# (Android refuses to install otherwise: "Targeting R+ requires resources.arsc
# ... stored uncompressed and aligned"). assets/module/koreader.7z is stored
# too, matching the original (it's already compressed, no point deflating it).
(cd stage && \
  zip -X -0 "../$OUT_UNSIGNED" assets/module/koreader.7z resources.arsc && \
  zip -X -r -9 "../$OUT_UNSIGNED" . -x assets/module/koreader.7z resources.arsc > /dev/null)

echo "== Zipaligning =="
zipalign -f -p 4 "$OUT_UNSIGNED" aligned.apk

echo "== Signing =="
KEYSTORE="$SCRIPT_DIR/gpuslide-debug.keystore"
if [ ! -f "$KEYSTORE" ]; then
  echo "  (generating a new debug keystore -- reuse this file on future rebuilds"
  echo "   so you don't have to uninstall/reinstall every single time)"
  keytool -genkeypair -v -keystore "$KEYSTORE" -alias androidgpuslide \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass android123 -keypass android123 \
    -dname "CN=AndroidGPUSlide, OU=Personal, O=Personal, C=US"
fi
FINAL="$SCRIPT_DIR/koreader-${ARCH}-gpuslide-${VERSION#v}.apk"
apksigner sign --ks "$KEYSTORE" --ks-pass pass:android123 --key-pass pass:android123 \
  --ks-key-alias androidgpuslide --out "$FINAL" aligned.apk

apksigner verify "$FINAL" && echo "== Done: $FINAL =="
echo
echo "IMPORTANT: this is signed with a different certificate than the"
echo "official KOReader build. If you already have KOReader installed,"
echo "uninstall it first (adb uninstall org.koreader.launcher) -- Android"
echo "won't let a differently-signed APK upgrade in place. Your library"
echo "and settings live in /sdcard/koreader/ and survive the uninstall."
echo
echo "Then: adb install \"$FINAL\""
