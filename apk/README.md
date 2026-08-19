# Tier 2 — the slide-animation APK build

Builds a repackaged KOReader Android APK with a GPU-composited page-turn
slide animation, plus self-installs the three `patches/` files to
`/sdcard/koreader/patches/` on first run.

Read the root [`README.md`](../README.md) first — this requires
uninstalling any existing KOReader install (signature mismatch, no way
around it without KOReader's real signing key) and trusting a
self-signed build.

## Build

```
./build.sh <koreader-version-tag> <arch>
# e.g.
./build.sh v2026.07.1 arm64
```

Requires `unzip`, `zip`, `p7zip-full`, `zipalign`, `apksigner`, `python3`,
`luajit`. See root README for install commands.

## Files

- `build.sh` — orchestrates the whole rebuild: downloads the official
  APK, unpacks it, applies the two patches below, bundles
  `bundled_patches/`, repacks, zipaligns, signs.
- `apply_patch.py` — inserts the slide-animation hook into
  `frontend/ui/uimanager.lua` (anchor-based, fails loudly if upstream
  changes around the anchor).
- `apply_bootstrap_patch.py` — inserts the self-install-bundled-patches
  hook into `reader.lua`.
- `android_gpu_slide.lua` — the slide animation itself, dropped into
  `frontend/` inside the repacked archive.
- `bundled_patches/` — copies of the `patches/` files, baked in for
  self-install on first run (idempotent, never overwrites an existing
  file at the destination).

First build generates `gpuslide-debug.keystore` next to `build.sh` — keep
it and reuse it on future rebuilds, or you'll need to uninstall/reinstall
every time (new random key each build otherwise).
