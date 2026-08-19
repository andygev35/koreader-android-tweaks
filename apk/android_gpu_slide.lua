--[[--
Continuous push-slide page-turn animation for KOReader on non-eink Android
(OLED/LCD tablets, phones, foldables).

Required directly from a small hook added to frontend/ui/uimanager.lua (see
the comment there) since UIManager:_repaint()'s refresh dispatch has no
external hook point -- it's a closed-over local table. That's the one and
only deviation from upstream in this build; re-apply it after updating
KOReader.

Why this lives in frontend/ (baked into assets/module/koreader.7z) instead
of a plain patches/*.lua file: on Android, koreader/patches/ (external,
user-writable storage) can only run code that hooks *already-loaded*
modules from the outside. It can't reach into the middle of _repaint()
either, for the same closed-over-local reason. So the hook itself has to
live in the shipped uimanager.lua, which means it has to be baked into the
APK. This module could technically still live in patches/ and be found via
_G, but keeping it as a normal required module is simpler to reason about
and avoids load-order questions.

Design, in short:
  - Screen:beforePaint()/afterPaint() are wrapped (harmless everywhere,
    these are no-op stubs on every platform per koreader-base) to snapshot
    the pre-paint framebuffer into Screen.saved_bb.
  - By the time UIManager:_repaint() reaches the refresh-execution point,
    Screen.bb already holds the *fully painted new page* (paintTo already
    ran), and Screen.saved_bb holds the *old page* from just before
    painting. AndroidGPUSlide.run() sweeps between them and presents each
    intermediate frame via Screen:refreshUI(), which -- on non-eink
    Android -- always does a full ANativeWindow blit+present regardless of
    the rect passed in (confirmed in koreader-base's
    ffi/framebuffer_android.lua), so every step is a real presented frame,
    not just an internal buffer update.
  - Device:canDoSwipeAnimation() is overridden to true on Android so the
    stock "Page turn animations" toggle (Settings > Taps and gestures >
    Page turns) and the existing ReaderView:onPageChangeAnimation event
    chain "just work" -- no custom menu UI needed.
  - Eink Android devices (Boox, etc.) are explicitly skipped; they should
    keep using the upstream community wipe-animation plugin, which targets
    their refresh hardware specifically.

Tuning (G_reader_settings, both optional):
  android_slide_steps        - frames per turn (default 12)
  android_slide_duration_ms  - total animation time in ms (default 180)
--]]

local Device = require("device")
local Screen = Device.screen

if not Screen or not Device:isAndroid() then
    return false
end

if Device.hasEinkScreen and Device:hasEinkScreen() then
    return false
end

local ffi = require("ffi")

-- Unlock the stock toggle. The underlying Screen:setSwipeAnimations/
-- setSwipeDirection are harmless no-op stubs outside the MTK backend.
function Device:canDoSwipeAnimation()
    return true
end

-- ==================== Framebuffer integration ====================
if not Screen._android_gpu_slide_patch_applied then
    Screen._android_gpu_slide_patch_applied = true

    local orig_beforePaint = Screen.beforePaint
    function Screen:beforePaint()
        if not self.painting then
            self.painting = true
            if self.swipe_animations then
                if self.saved_bb then self.saved_bb:free() end
                self.saved_bb = self.bb:copy()
            end
        end
        if orig_beforePaint then
            return orig_beforePaint(self)
        end
    end

    local orig_afterPaint = Screen.afterPaint
    function Screen:afterPaint()
        self.painting = false
        if orig_afterPaint then
            return orig_afterPaint(self)
        end
    end

    local orig_setSwipeAnimations = Screen.setSwipeAnimations
    function Screen:setSwipeAnimations(enabled)
        if orig_setSwipeAnimations then
            orig_setSwipeAnimations(self, enabled)
        end
        self.swipe_animations = enabled
    end

    local orig_setSwipeDirection = Screen.setSwipeDirection
    function Screen:setSwipeDirection(direction)
        if orig_setSwipeDirection then
            orig_setSwipeDirection(self, direction)
        end
        self.swipe_forward = direction
    end
end

-- ==================== The slide itself ====================
local AndroidGPUSlide = {}

--- Called from the hook in UIManager:_repaint(), in place of the normal
--- one-shot refresh-execution loop, whenever a page-turn animation was
--- requested. `uiman` is the UIManager instance (self); `dithered` is
--- passed through for parity but isn't currently used -- these are plain
--- RGB blits, no dithering hint needed.
function AndroidGPUSlide.run(uiman, dithered) -- luacheck: ignore dithered
    local screen_w = Screen.bb:getWidth()
    local screen_h = Screen.bb:getHeight()

    local saved_bb = Screen.saved_bb
    Screen.saved_bb = nil

    if not saved_bb then
        -- No pre-paint snapshot (e.g. first paint after launch, or a
        -- repaint that didn't go through beforePaint at all) -- nothing
        -- to animate against. Fall back to a normal instant refresh so
        -- the new page still actually gets presented.
        Screen:refreshUI(0, 0, screen_w, screen_h)
        uiman._refresh_stack = {}
        return
    end

    local new_bb = Screen.bb:copy()

    local steps = tonumber(G_reader_settings:readSetting("android_slide_steps")) or 12
    local duration_ms = tonumber(G_reader_settings:readSetting("android_slide_duration_ms")) or 180
    if steps < 2 then steps = 2 end
    local delay_ms = duration_ms / steps

    local swipe_forward = Screen.swipe_forward
    if swipe_forward == nil then
        swipe_forward = true
    end

    local usleep = ffi and ffi.C and ffi.C.usleep

    -- Start from the old page (Screen.bb currently holds the new page,
    -- freshly painted by the widget loop above us in _repaint).
    Screen.bb:blitFrom(saved_bb, 0, 0, 0, 0, screen_w, screen_h)

    for i = 1, steps do
        local offset = math.floor(screen_w * i / steps)
        if offset > screen_w then offset = screen_w end
        local remaining = screen_w - offset

        if swipe_forward then
            -- Old page's remaining right portion slides to the left edge;
            -- new page's leading portion pushes in from the right.
            if remaining > 0 then
                Screen.bb:blitFrom(saved_bb, 0, 0, offset, 0, remaining, screen_h)
            end
            if offset > 0 then
                Screen.bb:blitFrom(new_bb, remaining, 0, 0, 0, offset, screen_h)
            end
        else
            -- Mirror: new page pushes in from the left.
            if remaining > 0 then
                Screen.bb:blitFrom(saved_bb, offset, 0, 0, 0, remaining, screen_h)
            end
            if offset > 0 then
                Screen.bb:blitFrom(new_bb, 0, 0, screen_w - offset, 0, offset, screen_h)
            end
        end

        -- Every refresh call on non-eink Android re-blits the full buffer
        -- and presents it via ANativeWindow regardless of the rect passed
        -- in, so this is a real presented frame each time.
        Screen:refreshUI(0, 0, screen_w, screen_h)

        if i < steps and usleep and delay_ms > 0 then
            usleep(delay_ms * 1000)
        end
    end

    uiman._refresh_stack = {}
    new_bb:free()
    saved_bb:free()
end

return AndroidGPUSlide
