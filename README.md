# koreader-android-tweaks

Small tweaks for [KOReader](https://github.com/koreader/koreader) on
non-eink Android (phones, tablets, foldables): a GPU-composited page-turn
slide animation, brightness that goes below the hardware floor, and a
couple of quality-of-life hooks around night mode.

Built and tested against a Galaxy Z Fold 7 running KOReader v2026.07.1.
**This is early and has one real device's worth of testing** — see
[KNOWN_ISSUES.md](KNOWN_ISSUES.md) before assuming anything works exactly
as described.

## Two tiers, pick what you need

This repo has two independent things in it. You don't need both.

### Tier 1 — patches (`patches/`): drop-in, no rebuild, no risk

Three plain `.lua` files that go in `/sdcard/koreader/patches/` on any
existing KOReader Android install. No uninstall, no signature issues, no
APK involved.

- **`2-extra-dim.lua`** — extends brightness below KOReader's normal 0
  floor using a software darken blend on the page, instead of a separate
  Android overlay surface (see the comment header in the file for why
  that distinction matters — a KOReader maintainer tried the overlay
  approach years ago and hit real bugs; this avoids that failure class).
- **`2-night-mode-links.lua`** — remembers brightness/dim level
  separately for day vs. night mode, and (if you're also using the color
  schemes patch below) reverts any active color scheme to default when
  entering night mode and restores it on the way back out.
- **`2-color-schemes-css.lua`** — a set of named background/text color
  presets (Sepia, Grey, Blue, etc.) as a Style Tweaks submenu. Not
  strictly part of this project's own work — included because
  `2-night-mode-links.lua` is written against its `color_scheme_*`
  tweak-id convention and the two are meant to be used together, but
  it's a standalone, generically useful patch on its own.

**Install:** copy the files you want into `/sdcard/koreader/patches/`,
restart KOReader.

### Tier 2 — the slide animation (`apk/`): requires a rebuilt APK

The page-turn slide can't be a plain patch. KOReader's Android build
extracts its entire `frontend/` Lua source from a 7z archive bundled
inside the APK into private, non-rooted-inaccessible app storage — there
is no writable copy of it to patch externally. So this piece needs an
APK with a couple of files changed inside that archive.

**What this means for you, concretely:**

- You either build it yourself from source in this repo (`apk/build.sh`,
  fully scripted, no Android Studio needed — see below), or install a
  prebuilt APK from [Releases](../../releases) if one's published.
- Either way, **the resulting APK is signed with a throwaway key, not
  KOReader's real one.** Android will refuse to install it over your
  existing KOReader (signature mismatch) — you'll need to
  `adb uninstall org.koreader.launcher` (or `.fdroid` for the F-Droid
  variant) first. Your library and settings live in `/sdcard/koreader/`
  and aren't touched by the uninstall.
- If you install a prebuilt release APK rather than building it
  yourself, you're trusting whoever built it and this repo's release
  process, the same way you'd trust any sideloaded, modified APK —
  there's no app-store review chain backing it. Building it yourself
  from the script is the more verifiable path if that matters to you.
- It's pinned to whatever KOReader version it was built against, and
  needs rebuilding after every KOReader release. `apk/build.sh` does the
  whole rebuild in one command against any version tag.

The APK build also bundles the three Tier 1 patch files and self-installs
them to `/sdcard/koreader/patches/` on first run if they're not already
there (idempotent — never overwrites a file that already exists, so any
local edits you've made are safe). So if you go the APK route, you get
everything in one install; if you'd rather stay lower-risk, use Tier 1
patches alone on your existing install.

**Build:**

```
cd apk
./build.sh v2026.07.1 arm64   # or whatever KOReader version tag you want, and arm/x86 for other architectures
```

Requires: `unzip`, `zip`, `p7zip-full` (for the `7z` command),
`zipalign`, `apksigner`, `python3`, `luajit` (for the syntax-check step).
On Ubuntu/Debian:

```
sudo apt install unzip zip p7zip-full zipalign apksigner python3 luajit
```

First build generates `apk/gpuslide-debug.keystore` — keep this file and
reuse it on future rebuilds, or every rebuild gets a new random signing
key and you're back to uninstall-before-install each time.

**Install:**

```
adb uninstall org.koreader.launcher   # or org.koreader.launcher.fdroid
adb install apk/koreader-arm64-gpuslide-<version>.apk
```

Then in a book: Settings (⚙) → Taps and gestures → Page turns → enable
**Page turn animations**.

## Tuning

Runtime settings, no rebuild needed either way — set via
`G_reader_settings` (e.g. from a Lua console plugin, or by editing
`/sdcard/koreader/settings.reader.lua` directly while KOReader is closed):

```lua
-- slide animation
G_reader_settings:saveSetting("android_slide_steps", 12)
G_reader_settings:saveSetting("android_slide_duration_ms", 180)

-- extra dim
G_reader_settings:saveSetting("extra_dim_min", -40)
G_reader_settings:saveSetting("extra_dim_max_factor", 0.75)
```

## Why this exists / technical writeups

Each file has a comment header explaining the specific problem it solves
and, where relevant, why the obvious-looking simpler approach doesn't
work (e.g. why the slide animation can't be a plain patch, why night mode
needed a second attempt at the darken blend, why an early attempt at the
night-mode hook silently never ran at all). If you're trying to
understand or extend this, start there rather than re-deriving it.

## License

AGPL-3.0, matching KOReader's own license, since `apk/` ships a modified
derivative of KOReader source (`uimanager.lua`, `reader.lua`) alongside
new files. See [LICENSE](LICENSE).

`patches/2-color-schemes-css.lua` is included as originally written by
its author (comment header preserved); everything else in this repo is
new.

## Contributing / issues

This started as a personal project for one device. If you try it on
different hardware, different KOReader versions, or hit something in
[KNOWN_ISSUES.md](KNOWN_ISSUES.md), issues and PRs are welcome — just
note what device/Android version/KOReader version you're on, since none
of this has a wide test matrix yet.
