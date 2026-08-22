# Project context: koreader-android-tweaks

Paste this as custom project instructions, or upload as project knowledge.
It's written for whichever Claude picks this up next.

## What this project is

A set of KOReader tweaks for non-eink Android (built and tested against a
Galaxy Z Fold 7, KOReader v2026.07.1): a GPU-composited page-turn slide
animation, and brightness that extends below the hardware floor ("extra
dim"). Repo: `github.com/andygev35/koreader-android-tweaks`.

The person (Andy) is technically deep — comfortable with ADB, Lua, git,
GitHub Actions, APK signing, reading source to verify claims rather than
taking them on faith. Match that register: cite the actual source when
making a claim, run real verification (syntax checks, simulated Lua
round-trips, actual builds) rather than asserting something "should work,"
and be upfront about what's untested. Two real bugs this session slipped
through by asserting something was fixed without actually simulating it —
don't repeat that; when a fix is non-trivial, write a small Lua/Python
harness and run it before calling something fixed.

## Repo structure

```
patches/                    Tier 1: drop-in .lua files, no rebuild needed
  2-extra-dim.lua             brightness below 0, software darken blend
  2-slide-animation-settings.lua  in-app Settings UI for the slide steps/
                               duration (Tier-2-only, no-ops without it --
                               see the dedicated section below)
apk/                         Tier 2: requires a rebuilt, self-signed APK
  build.sh                    orchestrates the whole rebuild
  apply_patch.py              inserts slide-animation hook into uimanager.lua
  apply_bootstrap_patch.py    inserts self-install hook into reader.lua
  android_gpu_slide.lua       the slide animation itself
  bundled_patches/             copies of patches/*.lua (both files), self-
                               installed on first APK run (version-aware,
                               see below)
.github/workflows/build-apk.yml   CI: builds + attaches to GitHub Release
                               on push of a `build-*` tag
KNOWN_ISSUES.md              honest inventory of what's unverified
README.md                    two-tier explanation, install/build steps
```

**Critical invariant**: `patches/*.lua` and `apk/bundled_patches/*.lua`
must always be kept identical (same 2 files, byte-for-byte). Every time
you edit a patch file, update both locations.

**Removed (this session)**: `2-night-mode-links.lua` and
`2-color-schemes-css.lua` were deleted from the repo entirely -- from
both `patches/` and `apk/bundled_patches/` -- at Andy's request. The
trigger: Andy deleted `2-color-schemes-css.lua` from
`/sdcard/koreader/patches/` on-device to remove the Color Schemes
submenu, but the self-install logic in `reader.lua` re-copies any
missing bundled file on every startup (it checks `dest_exists`, not a
first-run flag), so the file kept reappearing. There's no supported way
to make the self-install logic respect a deliberate on-device deletion
without adding new logic for it, so the fix taken was to stop bundling
(and stop shipping) the file rather than build that. `2-night-mode-links.lua`
was removed alongside it since it was written specifically against
`2-color-schemes-css.lua`'s `color_scheme_*` tweak-id convention and has
no independent purpose without it. `apk/apply_bootstrap_patch.py`'s
`LEGACY_MIGRATE_FILES` table was trimmed to just `2-extra-dim.lua`
accordingly -- see the bundled-patch versioning section below.

## Architecture facts (verified against real source, not memory)

- **Android's `frontend/` Lua tree is bundled as `assets/module/koreader.7z`
  inside the APK**, extracted to private app storage on launch. No
  writable copy exists without root. Source: inspected a real downloaded
  APK directly.
- **`DataStorage:getPatchesDir()` always resolves to
  `/sdcard/koreader/patches` on Android** (external, user-writable),
  confirmed in `datastorage.lua`. This is why patches/ can be a plain
  drop-in but the slide animation can't.
- **KOReader's patch loader (`frontend/userpatch.lua`) only recognizes
  priority prefixes 0, 1, 2, 8, 9.** A file prefixed `3-` is silently
  never executed ("3-7 are reserved for later use" per its own source
  comment). This bit us once already — a file was named `3-...` and did
  nothing for several turns before we found this.
- **The slide-animation hook lives in `frontend/ui/uimanager.lua`'s
  `_repaint()`**, specifically the refresh-execution loop, which reads
  from a closed-over local (`refresh_methods`) unreachable from outside
  -- hence needing an actual file patch, not a runtime monkeypatch.
- **Night mode inverts via a buffer-level flag** (`Screen.bb:invert()`),
  applied at final display time, not by recoloring content. Any darken/
  lighten blend applied to the buffer needs to check `bb:getInverse()`
  and flip which direction it blends, or it'll go the wrong way under
  night mode. (This bit us once -- extra-dim's night-mode darkening
  initially got lighter instead of darker.)
- **`BasePowerD:frontlightIntensity()` returns 0 whenever the frontlight
  is off**, regardless of the stored `fl_intensity` value. Don't use it
  to capture "the real current brightness" when there's any chance the
  light is off -- read `PowerD.fl_intensity` directly instead.
- **`PowerD.is_fl_on` goes stale** if you mix `setIntensity()` (never
  touches it) with `turnOffFrontlight()`/`turnOnFrontlight()` (which do).
  Don't gate a hardware call on `isFrontlightOn()`/`isFrontlightOff()` if
  there's any chance that flag is out of sync with reality -- call the
  underlying `*HW()` functions directly and set the bookkeeping fields
  yourself. (This caused the night-mode brightness restore bug -- took
  two attempts to actually fix; first attempt still trusted the flag.)
- **GitHub-hosted Ubuntu runners ship a full Android SDK** at
  `$ANDROID_HOME/build-tools/*/`, including `zipalign` and `apksigner`.
  Using those instead of `apt-get download`-ing them avoids a slow/flaky
  fetch of Ubuntu's universe package index.
- **The CI runner's default apt mirror (`azure.archive.ubuntu.com` via
  `/etc/apt/apt-mirrors.txt`) has been consistently unreachable** in this
  project's CI runs. Fixed by overwriting that file to point straight at
  `archive.ubuntu.com`. If this regresses, that mirror file is the first
  place to check.
- **The default `GITHUB_TOKEN` in Actions is read-only** unless the
  workflow requests `permissions: contents: write` -- needed for the
  "attach to release" step, was a real 403 we hit.

## Adding menu items via a user patch (2-slide-animation-settings.lua)

Two separate, real bugs were hit and fixed getting an in-app Settings entry
working for `android_slide_steps`/`android_slide_duration_ms`. Both are
worth knowing before touching KOReader's menu system again:

- **An id has to be registered in the `order` table, not just
  `self.menu_items`.** `frontend/ui/menusorter.lua`'s `MenuSorter:mergeAndSort`
  only ever visits ids that appear somewhere in the relevant order table
  (`frontend/ui/elements/reader_menu_order.lua` for ReaderMenu, required via
  `require("ui/elements/reader_menu_order")` -- require caches the module
  table, so mutating it once at patch-load time, e.g. via `table.insert`
  into `order.taps_and_gestures`, is visible to every later call, the same
  pattern `frontend/ui/plugin/insert_menu.lua` uses internally). An id
  present in `self.menu_items` but absent from every list in `order` is
  simply never visited -- it does **not** get shown anywhere with a "NEW:"
  prefix or similar; it's just invisible. (That "NEW:" orphan-prefix
  behavior mentioned in some docs is real but doesn't apply here -- don't
  assume it'll rescue an unregistered id.)
- **The menu_items entry has to be set *before* calling the original
  `setUpdateItemTable`, not after.** The real `ReaderMenu:setUpdateItemTable`
  (`frontend/apps/reader/modules/readermenu.lua`) ends with
  `self.tab_item_table = MenuSorter:mergeAndSort("reader", self.menu_items, order)`
  -- `mergeAndSort` consumes `self.menu_items` as the function's own last
  step. A hook shaped like `orig_setUpdateItemTable(self); self.menu_items[id] = {...}`
  will silently do nothing, because `mergeAndSort` already ran and returned
  before the new entry existed. Every other diagnostic can pass (order
  correctly mutated, the assignment itself definitely happening) and the
  item will still never appear -- this was the actual root cause after a
  long diagnostic session, and it only showed up once a test harness's
  stub for `orig_setUpdateItemTable` was made to *actually consume*
  `self.menu_items` synchronously like the real one does; a stub that just
  returns without touching it (the original, too-simple version of the
  test) can't catch this class of bug.
- **Tier-"2" user patches load at KOReader's own "After setup" stage**, not
  literally "on startup" -- confirmed directly from the on-device Patch
  Management screen, which buckets patches into "On startup, only after
  update" / "On startup" / "After setup" / "Before exit" / "On exit", and
  both `2-*.lua` patches in this repo show up under "After setup".
  Timing-wise this is still early enough to safely `require()` and hook
  things like `apps/reader/modules/readermenu` (proven working here), but
  worth knowing the real terminology if debugging patch-load-order issues
  again.
- **KOReader can also persist a per-device menu-order override** at
  `koreader/settings/reader_menu_order.lua` / `filemanager_menu_order.lua`
  (separate from the built-in `frontend/ui/elements/*_menu_order.lua`),
  used by KOReader's own menu-customization features. This was checked and
  ruled out as the cause of the bug above (file didn't exist on Andy's
  device), but if a future menu-registration patch behaves correctly in
  every diagnostic and still doesn't show up, checking for that file is a
  fast thing to rule in/out before re-deriving anything.

## Bundled-patch versioning scheme

Each file in `bundled_patches/` may carry a `-- @bundle_version N` comment
in its first 512 bytes. The self-install logic in `reader.lua` (injected
by `apply_bootstrap_patch.py`) only overwrites an already-installed file
if **both** the bundled and installed copies carry the marker and the
bundled one's number is higher. No marker on either side = install-if-
missing only, never touched again -- this is what protects any hand-edited
copy of a bundled file from being clobbered.

**When fixing a bug in `2-extra-dim.lua`: bump `@bundle_version` by 1.**
Otherwise the fix won't propagate through the APK's self-install on the
next rebuild, and Andy has to manually `adb push` it again (this happened
once already).

**Known limitation**: files installed before this versioning scheme
existed have no marker, so they'll never auto-upgrade even after this
fix -- that one-time transition always needs a manual `adb shell rm` +
`adb push`. Already true for Andy's current install as of this writing;
worth checking whether that's still the case or whether it's been
superseded.

## Current known bugs / recently fixed

Check `KNOWN_ISSUES.md` in the repo for the full list, but as of this
context being written, recently fixed and verified:
- Night-mode brightness restore triggering the real hardware call
  (fixed, verified via simulated Lua round-trip and confirmed by Andy
  on-device -- this fix lived in `2-night-mode-links.lua`, since removed
  from the repo; kept here as a historical record of the `is_fl_on`
  staleness lesson, which is still documented under "Architecture facts"
  above since it's a general KOReader gotcha, not specific to that file)

**Currently broken, needs investigation:**
- Extra-dim level not persisting across a full app restart. (This bug
  report originally also covered day/night memory persistence in
  `2-night-mode-links.lua`, since removed from the project -- see
  "Removed (this session)" above -- so only the `2-extra-dim.lua` half
  is still relevant.) A fix was written (G_reader_settings:saveSetting()
  + :flush() calls, added to patches/2-extra-dim.lua, bundle_version
  bumped to 4) and verified via a simulated Lua round-trip harness (set
  value -> simulate restart -> confirm it comes back) -- but **Andy
  confirmed on-device that it did not actually fix the problem.** The
  simulation passing but the real behavior still failing means either:
  the simulation didn't capture something true about the real
  environment (e.g. G_reader_settings behaves differently than the
  stub, the flush timing doesn't survive however Android actually kills
  the process, patch load order interacts with this differently than
  assumed), or the fix never actually made it onto the device correctly
  (worth first confirming the patch file on-device actually contains the
  @bundle_version 4 / flush() code before re-deriving anything -- this
  session already hit two separate cases of "the fix didn't reach the
  device" that turned out to be file-placement/self-install issues
  rather than logic bugs). Start there before assuming the persistence
  logic itself is wrong again.

## Working style notes for this project specifically

- Andy tests on a real device; this environment has no Android device or
  emulator. Every fix needs either (a) a real syntax check via `luajit
  -e "loadfile(...)"`, (b) a simulated Lua round-trip using stub
  `G_reader_settings`/`lfs`/etc. (see the persistence-fix and
  version-marker verification in session history for the pattern), or
  (c) an actual full `apk/build.sh` run verifying the signed APK, before
  calling something fixed. Prefer (b) or (c) over just reading the code
  and asserting it's correct -- this session had two bugs that looked
  right on inspection and weren't.
- KOReader source should be fetched fresh (via `raw.githubusercontent.com`
  or a shallow git clone of `koreader/koreader`) rather than assumed from
  training data -- several findings this session (patch loader priority
  limits, `is_fl_on` staleness, the 7z bundling) were only discoverable by
  actually reading the current source.
- `apt-get` on GitHub Actions runners in this project has been
  historically flaky (see architecture facts above) -- if a CI run hangs
  on "Install build tools" again, check the mirror config and retry
  settings before assuming it's a new problem.
- The APK is signed with a throwaway keystore (`gpuslide-debug.keystore`,
  gitignored, lives locally on Andy's Mac and possibly as a
  `SIGNING_KEYSTORE_B64` GitHub secret). Losing it means one more
  uninstall/reinstall cycle, not a security incident -- there's no real
  trust chain being protected here, just enough of a signature for
  Android to accept the install.
