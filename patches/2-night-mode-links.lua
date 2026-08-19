-- @bundle_version 3
--[[
    2-night-mode-links.lua

    Two things tied to the night-mode toggle:

    1. Reverts any active "color_scheme_*" style tweak (from your
       2-color-schemes-css.lua patch -- e.g. "Light Sepia") to no scheme
       when entering night mode, and restores whichever one was active
       when leaving night mode. Works generically off the ^color_scheme_
       id prefix that patch already uses for its mutual-exclusion
       (conflicts_with) logic, so it doesn't need to know the specific
       scheme names or be edited if you add/remove presets later.

    2. Saves/restores brightness (and the extra-dim level from
       2-extra-dim.lua, if installed) independently for day vs night
       mode. KOReader doesn't do this natively -- there's an open
       upstream feature request for exactly this (koreader/koreader#13075)
       that's never been implemented. First-ever switch in a given
       direction has nothing saved yet, so it just leaves the current
       level as-is; every switch after that remembers both sides.

    Load-order note: named "2-night-mode-links.lua", specifically NOT
    "3-..." -- checked KOReader's actual patch loader (frontend/userpatch.lua):
    only priority prefixes 0, 1, 2, 8, 9 are ever invoked at all; its own
    source comment says "3-7 are reserved for later use," meaning a "3-"
    prefixed file is silently never executed. Named to alphanumeric-sort
    after both 2-extra-dim.lua and 2-color-schemes-css.lua within the
    same "2" (late) priority tier, since load order within a tier is
    filename-sorted. Both pieces below independently no-op if their
    respective dependency isn't installed, so this is safe to use with
    either one alone too.
--]]

local ok, err = pcall(function()
    local Device = require("device")
    local DeviceListener = require("device/devicelistener")
    local PowerD = Device.powerd

    -- Per-mode saved state. nil fields mean "nothing saved yet for that
    -- mode" -- the corresponding restore step is just skipped.
    local saved = {
        day = { intensity = nil, extra_dim_level = nil, color_scheme = nil },
        night = { intensity = nil, extra_dim_level = nil, color_scheme = nil },
    }

    local function getStyleTweak()
        local req_ok, ReaderUI = pcall(require, "apps/reader/readerui")
        if not req_ok or not ReaderUI.instance then return nil end
        return ReaderUI.instance.styletweak
    end

    local function findActiveColorScheme(styletweak)
        for id in pairs(styletweak.tweaks_by_id or {}) do
            if id:match("^color_scheme_") and styletweak:isTweakEnabled(id) then
                return id
            end
        end
        return nil
    end

    local orig_onToggleNightMode = DeviceListener.onToggleNightMode
    function DeviceListener:onToggleNightMode()
        -- Read the state we're leaving BEFORE the toggle actually flips it,
        -- so we know which saved-state bucket to write to / read from.
        local leaving_night = G_reader_settings:isTrue("night_mode")
        local leaving = leaving_night and saved.night or saved.day
        local entering = leaving_night and saved.day or saved.night

        -- 1. Brightness / extra-dim: capture current, before toggling.
        if PowerD then
            -- Read the raw field directly, not frontlightIntensity() --
            -- that getter clamps to 0 whenever is_fl_on is false, which
            -- (per the restore-step comment below) can itself be stale.
            -- fl_intensity is never zeroed by turnOffFrontlight()/
            -- turnOffFrontlightHW(), so it reliably holds the real last
            -- positive level regardless of on/off bookkeeping.
            leaving.intensity = PowerD.fl_intensity
            if _G.ExtraDim then
                leaving.extra_dim_level = _G.ExtraDim.getLevel()
            end
        end

        -- 2. Color scheme: capture and revert to default (disable it).
        local styletweak = getStyleTweak()
        if styletweak then
            leaving.color_scheme = findActiveColorScheme(styletweak)
            if leaving.color_scheme then
                styletweak:onToggleStyleTweak({ leaving.color_scheme, false }, nil, true)
            end
        end

        -- The actual toggle: flips Screen's invert flag, G_reader_settings, etc.
        orig_onToggleNightMode(self)

        -- Restore whatever was saved for the mode we're entering.
        --
        -- Deliberately NOT using PowerD:setIntensity()/turnOffFrontlight()
        -- here, and not gating on isFrontlightOn()/isFrontlightOff() either.
        -- Those methods (and the is_fl_on flag they read) work fine in
        -- isolation, but mixing setIntensity() -- which never touches
        -- is_fl_on -- with turnOffFrontlight() -- which does -- across
        -- repeated mode switches leaves is_fl_on out of sync with the real
        -- hardware state. A guard like "if isFrontlightOn() then
        -- turnOffFrontlight()" can then silently no-op because the flag
        -- claims the light's already off when it physically isn't, which is
        -- exactly what caused the brightness to only "catch up" on your
        -- next manual swipe (that path forces the real call unconditionally
        -- via a fresh gesture). So: call the underlying HW functions
        -- directly and set the bookkeeping fields ourselves, every time,
        -- regardless of what they currently claim.
        if PowerD then
            if entering.extra_dim_level and entering.extra_dim_level < 0 and _G.ExtraDim then
                _G.ExtraDim.setLevel(entering.extra_dim_level)
                PowerD:turnOffFrontlightHW()
                PowerD.is_fl_on = false
            elseif entering.intensity and entering.intensity > 0 then
                if _G.ExtraDim then _G.ExtraDim.setLevel(0) end
                PowerD.fl_intensity = PowerD:normalizeIntensity(entering.intensity)
                PowerD:setIntensityHW(PowerD.fl_intensity)
                PowerD.is_fl_on = true
                if _G.ExtraDim then _G.ExtraDim.setLevel(0) end
            end
        end
        if styletweak and entering.color_scheme then
            styletweak:onToggleStyleTweak({ entering.color_scheme, true }, nil, true)
        end
    end
end)

if not ok then
    require("logger").warn("[NightModeLinksPatch] failed:", err)
end
