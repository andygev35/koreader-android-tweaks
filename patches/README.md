# Tier 1 — patches

Drop-in patches for any existing KOReader Android install. No rebuild,
no signature issues, no APK involved.

**Install:** copy whichever files you want into `/sdcard/koreader/patches/`
on your device, restart KOReader.

| File | What it does |
|---|---|
| `2-extra-dim.lua` | Extends brightness below the normal 0 floor using a software darken blend on the page. |
| `2-night-mode-links.lua` | Saves/restores brightness independently per day/night mode; reverts color scheme to default in night mode if `2-color-schemes-css.lua` is also installed. |
| `2-color-schemes-css.lua` | Named background/text color presets (Sepia, Grey, Blue, etc.) as a Style Tweaks submenu. |

Each file has a comment header explaining the specific problem it solves
and any non-obvious design decisions. See [`../KNOWN_ISSUES.md`](../KNOWN_ISSUES.md)
for caveats before relying on any of these.
