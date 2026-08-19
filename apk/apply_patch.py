#!/usr/bin/env python3
"""Applies the Android GPU slide hook to a fresh frontend/ui/uimanager.lua.

Usage: apply_patch.py path/to/uimanager.lua

Two edits, both anchored on exact upstream text so this fails loudly
(instead of silently mis-patching) if KOReader's uimanager.lua has changed
around either anchor since this was written against v2026.07.1.
"""
import sys

REQUIRE_ANCHOR = (
    'local Device = require("device")\n'
    'local Event = require("ui/event")\n'
    'local Geom = require("ui/geometry")\n'
)
REQUIRE_REPLACEMENT = (
    'local Device = require("device")\n'
    'local Event = require("ui/event")\n'
    'local Geom = require("ui/geometry")\n'
    '-- Android GPU slide patch: nil on every platform except non-eink Android\n'
    '-- (the module itself checks Device:isAndroid() and returns nil otherwise).\n'
    'local AndroidGPUSlide = require("android_gpu_slide")\n'
)

REFRESH_ANCHOR = (
    '    -- execute refreshes:\n'
    '    for _, refresh in ipairs(self._refresh_stack) do\n'
    '        -- Honor dithering hints from *anywhere* in the dirty stack\n'
    '        refresh.dither = update_dither(refresh.dither, dithered)\n'
    '        -- If HW dithering is disabled, unconditionally drop the dither flag\n'
    '        if not Screen.hw_dithering then\n'
    '            refresh.dither = nil\n'
    '        end\n'
    '        dbg:v("triggering refresh", refresh)\n'
    '\n'
    '        --[[\n'
    '        -- Remember the refresh region\n'
    '        self._last_refresh_region = refresh.region:copy()\n'
    '        --]]\n'
    '        refresh_methods[refresh.mode](Screen,\n'
    '            refresh.region.x, refresh.region.y,\n'
    '            refresh.region.w, refresh.region.h,\n'
    '            refresh.dither)\n'
    '    end\n'
)
REFRESH_REPLACEMENT = (
    '    -- Android GPU slide patch: if a page-turn animation was requested\n'
    '    -- (Screen.swipe_animations, set one-shot by ReaderView:onPageChangeAnimation\n'
    '    -- via Device:canDoSwipeAnimation()), run our own multi-frame slide instead\n'
    '    -- of the normal single-shot refresh execution. See frontend/android_gpu_slide.lua\n'
    '    -- for the animation itself; this hook is the only local deviation from\n'
    '    -- upstream in this file. Re-merge after updating KOReader.\n'
    '    if Screen.swipe_animations and AndroidGPUSlide then\n'
    '        Screen.swipe_animations = false\n'
    '        AndroidGPUSlide.run(self, dithered)\n'
    '    else\n'
    '    -- execute refreshes:\n'
    '    for _, refresh in ipairs(self._refresh_stack) do\n'
    '        -- Honor dithering hints from *anywhere* in the dirty stack\n'
    '        refresh.dither = update_dither(refresh.dither, dithered)\n'
    '        -- If HW dithering is disabled, unconditionally drop the dither flag\n'
    '        if not Screen.hw_dithering then\n'
    '            refresh.dither = nil\n'
    '        end\n'
    '        dbg:v("triggering refresh", refresh)\n'
    '\n'
    '        --[[\n'
    '        -- Remember the refresh region\n'
    '        self._last_refresh_region = refresh.region:copy()\n'
    '        --]]\n'
    '        refresh_methods[refresh.mode](Screen,\n'
    '            refresh.region.x, refresh.region.y,\n'
    '            refresh.region.w, refresh.region.h,\n'
    '            refresh.dither)\n'
    '    end\n'
    '    end\n'
)


def main():
    path = sys.argv[1]
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    if REQUIRE_ANCHOR not in content:
        sys.exit(
            "FAILED: require-block anchor not found. Upstream uimanager.lua's "
            "top-of-file requires have changed -- add `local AndroidGPUSlide = "
            "require(\"android_gpu_slide\")` manually after the Geom require."
        )
    if REFRESH_ANCHOR not in content:
        sys.exit(
            "FAILED: refresh-execution-loop anchor not found. Upstream "
            "UIManager:_repaint() has changed around the refresh dispatch -- "
            "manually wrap the 'execute refreshes' loop, see README.md."
        )

    content = content.replace(REQUIRE_ANCHOR, REQUIRE_REPLACEMENT, 1)
    content = content.replace(REFRESH_ANCHOR, REFRESH_REPLACEMENT, 1)

    with open(path, "w", encoding="utf-8") as f:
        f.write(content)

    print(f"Patched {path}")


if __name__ == "__main__":
    main()
