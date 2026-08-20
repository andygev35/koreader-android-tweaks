-- @bundle_version 3
--[[
    2-slide-animation-settings.lua

    Adds a "Page-turn slide animation" entry to Settings > Taps and gestures
    (right after "Page turn animations") with SpinWidget controls for
    android_slide_steps and android_slide_duration_ms
    (apk/android_gpu_slide.lua), so they can be tuned in-app instead of
    hand-editing settings.reader.lua.

    Why that edit never worked: G_reader_settings is loaded from
    settings.reader.lua exactly once, at process startup (reader.lua). From
    then on the running process only reads/writes its in-memory copy --
    nothing re-reads the file from disk while KOReader is alive. Meanwhile
    frontend/ui/uimanager.lua registers a "SaveState" handler
    (UIManager:flushSettings()) and fires "FlushSettings" on widget close,
    both of which get triggered by ordinary things (closing a book,
    backgrounding the app, screen suspend) and unconditionally serialize the
    *in-memory* table back over settings.reader.lua. So an on-disk edit made
    while the app is running either never gets picked up (nothing reloads
    it) or gets clobbered by the next autosave before you're back in the
    reader to see it -- regardless of whether the edit was made via adb or
    KOReader's own built-in text editor. Editing while the app is *fully*
    closed (no live process to flush a stale copy back over you) is the only
    version of the manual-edit approach that actually works; this patch
    exists so that workaround isn't necessary at all.

    Hooked onto ReaderMenu:setUpdateItemTable (frontend/apps/reader/modules/
    readermenu.lua) rather than anchored into page_turns.lua itself, since
    this patch doesn't verify that file's internal table shape against
    upstream source -- appending a new leaf entry to self.menu_items and
    registering it in the (separately verified) order table gets the same
    end result without depending on page_turns.lua's internals.

    Registration happens in two places, both required to make the entry
    actually appear:
      1. order.taps_and_gestures (frontend/ui/elements/reader_menu_order.lua,
         mutated in place -- require caches the module table, so this
         mutation is visible to every later setUpdateItemTable call) gets
         the new id inserted right after "page_turns", since
         frontend/ui/menusorter.lua only ever walks ids listed in this
         table -- an id present in self.menu_items but absent from every
         list in "order" is simply never visited, not shown anywhere by
         default.
      2. self.menu_items[ITEM_ID] gets set INSIDE the setUpdateItemTable
         hook, and critically BEFORE calling the original function, not
         after. The original setUpdateItemTable ends with
         `self.tab_item_table = MenuSorter:mergeAndSort("reader",
         self.menu_items, order)` -- mergeAndSort consumes self.menu_items
         as the function's own last step. Setting the entry after calling
         the original means mergeAndSort has already run and returned
         before the entry ever existed -- everything else can be correct
         (order mutated, item eventually set) and it will still never show
         up, which is exactly what happened during development here.

    Gated on Device:canDoSwipeAnimation() -- true only when
    apk/android_gpu_slide.lua's own override is active, i.e. only on a
    Tier-2 (rebuilt APK) install where these settings actually do anything.
    A Tier-1-only install won't see this menu entry at all.
--]]

local ok, err = pcall(function()
    local Device = require("device")
    if not (Device:isAndroid() and Device:canDoSwipeAnimation()) then
        return
    end

    local ReaderMenu = require("apps/reader/modules/readermenu")
    local order = require("ui/elements/reader_menu_order")
    local SpinWidget = require("ui/widget/spinwidget")
    local UIManager = require("ui/uimanager")
    local T = require("ffi/util").template
    local _ = require("gettext")

    local DEFAULT_STEPS = 12
    local DEFAULT_DURATION_MS = 180
    local ITEM_ID = "android_gpu_slide_settings"

    -- Register the id in the same cached order table ReaderMenu itself
    -- uses, so MenuSorter actually walks it. Insert right after
    -- "page_turns" for co-location; if that anchor is ever removed or
    -- renamed upstream, fall back to appending at the end of the submenu
    -- rather than silently doing nothing again.
    if order.taps_and_gestures then
        local inserted = false
        for i, id in ipairs(order.taps_and_gestures) do
            if id == "page_turns" then
                table.insert(order.taps_and_gestures, i + 1, ITEM_ID)
                inserted = true
                break
            end
        end
        if not inserted then
            table.insert(order.taps_and_gestures, ITEM_ID)
            require("logger").info("[SlideAnimationSettingsPatch] 'page_turns' anchor not found in taps_and_gestures order; appended instead")
        end
    else
        require("logger").warn("[SlideAnimationSettingsPatch] order.taps_and_gestures not found; menu entry will not appear")
    end

    local orig_setUpdateItemTable = ReaderMenu.setUpdateItemTable
    function ReaderMenu:setUpdateItemTable()
        -- Must run BEFORE orig_setUpdateItemTable -- see file header.
        self.menu_items = self.menu_items or {}
        self.menu_items[ITEM_ID] = {
            text = _("Page-turn slide animation"),
            sub_item_table = {
                {
                    text_func = function()
                        local steps = tonumber(G_reader_settings:readSetting("android_slide_steps")) or DEFAULT_STEPS
                        return T(_("Steps: %1"), steps)
                    end,
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
                        local current = tonumber(G_reader_settings:readSetting("android_slide_steps")) or DEFAULT_STEPS
                        UIManager:show(SpinWidget:new{
                            title_text = _("Slide animation steps"),
                            value = current,
                            value_min = 2,
                            value_max = 30,
                            default_value = DEFAULT_STEPS,
                            keep_shown_on_apply = true,
                            callback = function(spin)
                                G_reader_settings:saveSetting("android_slide_steps", spin.value)
                                G_reader_settings:flush()
                                if touchmenu_instance then touchmenu_instance:updateItems() end
                            end,
                        })
                    end,
                },
                {
                    text_func = function()
                        local ms = tonumber(G_reader_settings:readSetting("android_slide_duration_ms")) or DEFAULT_DURATION_MS
                        return T(_("Duration: %1 ms"), ms)
                    end,
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
                        local current = tonumber(G_reader_settings:readSetting("android_slide_duration_ms")) or DEFAULT_DURATION_MS
                        UIManager:show(SpinWidget:new{
                            title_text = _("Slide animation duration (ms)"),
                            value = current,
                            value_min = 40,
                            value_max = 500,
                            default_value = DEFAULT_DURATION_MS,
                            keep_shown_on_apply = true,
                            callback = function(spin)
                                G_reader_settings:saveSetting("android_slide_duration_ms", spin.value)
                                G_reader_settings:flush()
                                if touchmenu_instance then touchmenu_instance:updateItems() end
                            end,
                        })
                    end,
                },
            },
        }

        orig_setUpdateItemTable(self)
    end
end)

if not ok then
    require("logger").warn("[SlideAnimationSettingsPatch] failed:", err)
end
