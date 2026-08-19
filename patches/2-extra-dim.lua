-- @bundle_version 3
--[[
    2-extra-dim.lua  (v2)

    Extends KOReader's brightness control below its hardware floor (0)
    using a software darken blend on the rendered page (BlitBuffer:darkenRect,
    the same primitive KOReader's own "page overlap" shading already uses),
    instead of a separate Android overlay surface -- see the v1 comment
    block (kept below) for why that distinction matters.

    WHY THIS VERSION EXISTS: v1 patched PowerD:normalizeIntensity/
    setIntensityHW/setIntensity, assuming the left-edge swipe gesture
    routes through PowerD:setIntensity(). It doesn't, all the way down.
    The real path (frontend/device/devicelistener.lua):

        DeviceListener:onChangeFlIntensity(ges, direction)
          -> new_intensity = powerd:frontlightIntensity() + delta
          -> DeviceListener:onSetFlIntensity(new_intensity)
               -> if new_intensity <= 0: powerd:turnOffFrontlight()   -- (*)
                  else:                  powerd:setIntensity(...)

    (*) is a dead end for our purposes: it never calls setIntensity, so
    none of the v1 hooks ever fire once you swipe down to the old zero
    floor. Worse, BasePowerD:frontlightIntensity() hard-returns 0 whenever
    the frontlight is off -- so even if we did reach setIntensity, the
    *next* gesture's "current + delta" math would still be computing from
    0, not from whatever negative level we'd reached, and could never
    accumulate further down.

    So this version tracks the extra-dim level as its own field
    (PowerD.extra_dim_level), entirely separate from fl_intensity, and
    replaces DeviceListener:onChangeFlIntensity outright rather than
    patching PowerD. The gesture-distance-to-delta math
    (calculateGestureDelta) is a closed-over local in devicelistener.lua,
    unreachable from outside, so it's reimplemented here verbatim from
    upstream (frontend/device/devicelistener.lua) -- if a future KOReader
    update changes that function, this copy will drift out of sync with
    it; check devicelistener.lua's calculateGestureDelta after updating.

    Tuning (G_reader_settings, both optional):
      extra_dim_min          - how far below 0 the range extends (default -40)
      extra_dim_max_factor   - darken factor at the extreme end, 0-1 (default 0.75)

    Known rough edges (untested on-device):
      - Only the left-edge swipe gesture is patched. The Frontlight
        settings-dialog slider still goes through the original
        onSetFlIntensity and will stop at 0, unpatched.
      - Only the reader view darkens, not menus/dialogs (deliberate scope).
--]]

local ok, err = pcall(function()
    local Device = require("device")
    if not Device:hasFrontlight() then
        return
    end
    local PowerD = Device.powerd
    local Screen = Device.screen
    local UIManager = require("ui/uimanager")
    local DeviceListener = require("device/devicelistener")
    local Notification = require("ui/widget/notification")
    local T = require("ffi/util").template
    local _ = require("gettext")

    local EXTRA_DIM_MIN = tonumber(G_reader_settings:readSetting("extra_dim_min")) or -40
    local EXTRA_DIM_MAX_FACTOR = tonumber(G_reader_settings:readSetting("extra_dim_max_factor")) or 0.75

    PowerD.extra_dim_level = PowerD.extra_dim_level or 0    -- 0 or negative; independent of fl_intensity
    PowerD.extra_dim_factor = PowerD.extra_dim_factor or 0  -- 0..EXTRA_DIM_MAX_FACTOR, derived from the level

    local function updateExtraDimFactor()
        local level = PowerD.extra_dim_level
        local factor = 0
        if level < 0 then
            local span = -EXTRA_DIM_MIN
            factor = math.min(EXTRA_DIM_MAX_FACTOR, (-level / span) * EXTRA_DIM_MAX_FACTOR)
        end
        if PowerD.extra_dim_factor ~= factor then
            PowerD.extra_dim_factor = factor
            UIManager:setDirty("all", "ui")
        end
    end

    -- Reimplementation of devicelistener.lua's local calculateGestureDelta
    -- (see the file-header comment for why this can't just be required).
    local function calculateGestureDelta(ges, direction, min, max) -- luacheck: ignore min
        local delta_int
        if type(ges) == "table" then
            local gesture_multiplier
            if ges.ges == "two_finger_swipe" or ges.ges == "swipe" then
                gesture_multiplier = 0.8
            else
                gesture_multiplier = 1
            end
            local gestureScale
            if ges.direction == "south" or ges.direction == "north" then
                gestureScale = Screen:getHeight() * gesture_multiplier
            elseif ges.direction == "west" or ges.direction == "east" then
                gestureScale = Screen:getWidth() * gesture_multiplier
            else
                local width = Screen:getWidth()
                local height = Screen:getHeight()
                gestureScale = math.sqrt(width ^ 2 + height ^ 2) * gesture_multiplier
            end
            if ges.distance == nil then ges.distance = 1 end
            local x = math.min(1, ges.distance / gestureScale)
            delta_int = math.ceil(1 / 2 * max * x ^ 2)
        else
            delta_int = ges
        end
        if direction ~= -1 and direction ~= 1 then
            direction = 1
        end
        return direction * delta_int
    end

    -- Replaces the gesture handler outright so the negative range has
    -- somewhere to accumulate that isn't clamped to 0 by
    -- frontlightIntensity()'s off-means-zero behavior.
    function DeviceListener:onChangeFlIntensity(ges, direction)
        local powerd = Device:getPowerDevice()
        local delta = calculateGestureDelta(ges, direction, powerd.fl_min, powerd.fl_max)

        local base
        if powerd.extra_dim_level < 0 then
            base = powerd.extra_dim_level
        else
            base = powerd:frontlightIntensity()
        end
        local new_intensity = base + delta

        if new_intensity > 0 then
            -- Back into normal hardware-brightness territory.
            if powerd.extra_dim_level < 0 then
                powerd.extra_dim_level = 0
                updateExtraDimFactor()
            end
            powerd:setIntensity(new_intensity)
        else
            local floor = EXTRA_DIM_MIN
            if new_intensity < floor then new_intensity = floor end
            powerd.extra_dim_level = new_intensity
            if powerd:isFrontlightOn() then
                powerd:turnOffFrontlight()
            end
            updateExtraDimFactor()
        end
        powerd:updateResumeFrontlightState()
        self:onShowIntensity()
        return true
    end

    -- "Frontlight disabled." is still technically true while in extra-dim
    -- territory (the hardware really is off), but surface the actual
    -- level instead of leaving it looking like nothing happened.
    local orig_onShowIntensity = DeviceListener.onShowIntensity
    function DeviceListener:onShowIntensity()
        local powerd = Device:getPowerDevice()
        if powerd.extra_dim_level < 0 then
            Notification:notify(T(_("Extra dim: %1"), powerd.extra_dim_level))
            return true
        end
        return orig_onShowIntensity(self)
    end

    -- Apply the darken blend to the page. Night mode inverts at the very
    -- final display step (Screen.bb:invert(), a flag -- not a recolor of
    -- content), so a "darken" blend applied to the pre-invert buffer
    -- displays as *lighter* once the invert flip happens. Check the
    -- buffer's own invert state and blend the opposite way when it's set,
    -- so the on-screen result darkens either way.
    local ReaderView = require("apps/reader/modules/readerview")
    local orig_paintTo = ReaderView.paintTo
    function ReaderView:paintTo(bb, x, y)
        orig_paintTo(self, bb, x, y)
        local factor = PowerD.extra_dim_factor
        if factor and factor > 0 and self.dimen then
            if bb:getInverse() == 1 then
                bb:lightenRect(x, y, self.dimen.w, self.dimen.h, factor)
            else
                bb:darkenRect(x, y, self.dimen.w, self.dimen.h, factor)
            end
        end
    end

    -- Small shared interface for other patches (e.g. one that wants to
    -- save/restore the extra-dim level per some external trigger) to read
    -- and set the level without duplicating updateExtraDimFactor's math.
    _G.ExtraDim = {
        getLevel = function() return PowerD.extra_dim_level end,
        setLevel = function(level)
            PowerD.extra_dim_level = level
            updateExtraDimFactor()
        end,
    }
end)

if not ok then
    require("logger").warn("[ExtraDimPatch] failed:", err)
end
