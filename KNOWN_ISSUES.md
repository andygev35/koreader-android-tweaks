# Known issues / untested territory

Honest inventory of what hasn't been verified, gathered from the whole
build process. Test matrix so far: **one device** (Galaxy Z Fold 7),
**one KOReader version** (v2026.07.1). Treat everything below as "likely
true based on reading the real source" rather than "confirmed working,"
except where noted otherwise.

## Slide animation (`apk/android_gpu_slide.lua`, `apk/apply_patch.py`)

- **Frame delivery / pacing**: each animation step calls
  `Screen:refreshUI()`, which on non-eink Android always does a full
  `ANativeWindow_lock`/`unlockAndPost` regardless of the rect passed in
  (confirmed by reading `koreader-base/ffi/framebuffer_android.lua`).
  Whether SurfaceFlinger reliably presents every call in a tight
  `usleep`-paced loop without dropping/coalescing frames, on your
  specific hardware and Android version, is unverified.
- **Blocking loop**: the animation blocks KOReader's main thread for its
  full duration (default 180ms). Fine at that length; don't push
  `duration_ms` much higher or input will visibly lag during turns.
- **PDF / fixed-layout documents**: only reasoned through against the
  reflowable-document repaint path. Untested on PDFs specifically.
- **Not true GPU layer compositing**: this is CPU-composited (cheap
  blitbuffer ops) then handed to Android's existing hardware-accelerated
  present path — not two independent GPU-blended layers, which would
  require native Java/Kotlin changes outside a Lua patch's reach. Should
  look the same at this frame count, but worth being precise about.

## `apk/build.sh` / repack pipeline

- **Tested KOReader version**: v2026.07.1, arm64 only. `arm` and `x86`
  should work (same `.apk` structure, same download URL pattern) but
  haven't been built or installed.
- **`apply_patch.py` and `apply_bootstrap_patch.py` are anchor-based
  string replacements** against `uimanager.lua` and `reader.lua`
  respectively. They fail loudly (not silently) if upstream changes the
  anchored text, but that also means every KOReader update is a real
  chance the anchors need manual adjustment — check the script's error
  output after a failed rebuild.
- **Self-signed APK**: uninstall-before-install is required (signature
  mismatch with official KOReader), every time, on every device, unless
  you reuse the same `gpuslide-debug.keystore` across rebuilds.

## `patches/2-extra-dim.lua`

- **Only the left-edge swipe gesture is patched** (`DeviceListener:onChangeFlIntensity`).
  The Frontlight settings-dialog slider goes through a different code
  path (`onSetFlIntensity` directly) and will still stop at 0 there,
  unpatched.
- **Only the reader view darkens** — menus and dialogs don't. Deliberate
  scope (see the file's comment header), not an oversight, but worth
  knowing if you expected system-wide dimming.
- **Night-mode handling** (blending white instead of black when
  `bb:getInverse() == 1`) is derived from reading `koreader-base`'s
  invert implementation, and confirmed working via direct user testing —
  this one item is actually verified, unlike most of this list.

## `patches/2-night-mode-links.lua`

- **First-ever toggle in a given direction has nothing saved yet** and
  just leaves the current level/scheme alone. From the second toggle in
  that direction onward, both day and night state are remembered
  properly.
- **The color-scheme-revert logic is generic** (matches any tweak id
  under `^color_scheme_`) but has only been exercised against the eight
  presets in `2-color-schemes-css.lua`. Should work with any other patch
  using the same id convention, untested against anything else.
- **A prior version of this file was named with a `3-` prefix** and
  silently never ran at all — KOReader's patch loader
  (`frontend/userpatch.lua`) only recognizes priority prefixes 0, 1, 2,
  8, 9; "3-7 are reserved for later use" per its own source comment. If
  you're inspecting old copies of this project, that's why an earlier
  version appeared to do nothing.

## General

- All of the above was built by reading KOReader's actual source (fetched
  fresh per KOReader version, not from training-data memory) and
  reasoning through the mechanism, then syntax-checking and — for the APK
  — round-tripping the build pipeline in a sandboxed environment with no
  Android device attached. Everything that *could* be verified without a
  physical device was (syntax, signature validity, zip alignment, file
  presence after round-trip). Everything that requires an actual screen,
  touchscreen, or real frame timing was not, beyond the one device this
  was developed against.
