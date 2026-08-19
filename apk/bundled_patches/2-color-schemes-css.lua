--[[
    Userpatch to add Color Schemes submenu to Style tweaks with grey, sepia and blue backgrounds


    Place this file in: /koreader/patches/
--]]

local CssTweaks = require("ui/data/css_tweaks")
local _ = require("gettext")

-- Define the color schemes submenu
local color_schemes_menu = {
    title = _("Color schemes"),
    {
        id = "color_scheme_light_sepia",
        conflicts_with = function(id) return id:match("^color_scheme_") end,
        title = _("Light Sepia"),
        description = _("Very light sepia background with dark text."),
        css = [[
body {
    background-color: #f0e6d2 !important;
    color: #111111 !important;
}
        ]],
    },
    {
        id = "color_scheme_medium_sepia",
        conflicts_with = function(id) return id:match("^color_scheme_") end,
        title = _("Medium Sepia"),
        description = _("Classic sepia background with dark text."),
        css = [[
body {
    background-color: #d2b48c !important;
    color: #111111 !important;
}
        ]],
    },
    {
        id = "color_scheme_dark_sepia",
        conflicts_with = function(id) return id:match("^color_scheme_") end,
        title = _("Dark Sepia"),
        description = _("Deep sepia background with light text for low light conditions."),
        css = [[
body {
    background-color: #4F3B28 !important;
    color: #f5f5f5 !important;
}
        ]],
    },
    {
        id = "color_scheme_light_grey",
        conflicts_with = function(id) return id:match("^color_scheme_") end,
        title = _("Light Grey"),
        description = _("Soft light grey background with dark text."),
        css = [[
body {
    background-color: #e8e8e8 !important;
    color: #1a1a1a !important;
}
        ]],
    },
    {
        id = "color_scheme_medium_grey",
        conflicts_with = function(id) return id:match("^color_scheme_") end,
        title = _("Medium Grey"),
        description = _("Medium grey background with dark text."),
        css = [[
body {
    background-color: #b0b0b0 !important;
    color: #0a0a0a !important;
}
        ]],
    },
    {
        id = "color_scheme_dark_grey",
        conflicts_with = function(id) return id:match("^color_scheme_") end,
        title = _("Dark Grey"),
        description = _("Dark grey background with light text for night reading."),
        css = [[
body {
    background-color: #3a3a3a !important;
    color: #e8e8e8 !important;
}
        ]],
    },
    {
        id = "color_scheme_light_blue",
        conflicts_with = function(id) return id:match("^color_scheme_") end,
        title = _("Light Blue"),
        description = _("Soft blue-grey background with navy text."),
        css = [[
body {
    background-color: #c8d8e8 !important;
    color: #001f3f !important;
}
        ]],
    },
    {
        id = "color_scheme_navy",
        conflicts_with = function(id) return id:match("^color_scheme_") end,
        title = _("Navy"),
        description = _("Dark blue background with light text for night reading."),
        css = [[
body {
    background-color: #001f3f !important;
    color: #e8e8e8 !important;
}
        ]],
    },
}

-- Insert the color schemes menu at the beginning of CssTweaks
-- (or you can place it at a specific position by adjusting the index)
table.insert(CssTweaks, 1, color_schemes_menu)

return true