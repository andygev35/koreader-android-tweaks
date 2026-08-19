#!/usr/bin/env python3
"""Applies the bundled-patches self-install hook to a fresh reader.lua.

Usage: apply_bootstrap_patch.py path/to/reader.lua
"""
import sys

ANCHOR = (
    '-- Set up Lua and ffi search paths\n'
    'require("setupkoenv")\n'
    '\n'
    '-- Apply startup user patches and execute startup user scripts\n'
    'local userpatch = require("userpatch")\n'
)

REPLACEMENT = (
    '-- Set up Lua and ffi search paths\n'
    'require("setupkoenv")\n'
    '\n'
    '-- Self-install bundled tweak patches into the external patches\n'
    '-- directory on first run. Idempotent: never overwrites a file that\n'
    '-- already exists there, so local edits made after install (or a\n'
    '-- prior manual install of the same file) are left alone.\n'
    'do\n'
    '    local ok, err = pcall(function()\n'
    '        local lfs = require("libs/libkoreader-lfs")\n'
    '        local DataStorage = require("datastorage")\n'
    '        local patches_dir = DataStorage:getPatchesDir()\n'
    '        if lfs.attributes(patches_dir, "mode") ~= "directory" then\n'
    '            lfs.mkdir(patches_dir)\n'
    '        end\n'
    '        local bundled_dir = lfs.currentdir() .. "/bundled_patches"\n'
    '        if lfs.attributes(bundled_dir, "mode") == "directory" then\n'
    '            for entry in lfs.dir(bundled_dir) do\n'
    '                if entry:match("%.lua$") then\n'
    '                    local dest = patches_dir .. "/" .. entry\n'
    '                    if lfs.attributes(dest, "mode") ~= "file" then\n'
    '                        local src_f = io.open(bundled_dir .. "/" .. entry, "rb")\n'
    '                        if src_f then\n'
    '                            local content = src_f:read("*a")\n'
    '                            src_f:close()\n'
    '                            local dest_f = io.open(dest, "wb")\n'
    '                            if dest_f then\n'
    '                                dest_f:write(content)\n'
    '                                dest_f:close()\n'
    '                            end\n'
    '                        end\n'
    '                    end\n'
    '                end\n'
    '            end\n'
    '        end\n'
    '    end)\n'
    '    if not ok then\n'
    '        io.write(" [*] Bundled patch self-install failed: ", tostring(err), "\\n")\n'
    '    end\n'
    'end\n'
    '\n'
    '-- Apply startup user patches and execute startup user scripts\n'
    'local userpatch = require("userpatch")\n'
)


def main():
    path = sys.argv[1]
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    if ANCHOR not in content:
        sys.exit(
            "FAILED: boot-sequence anchor not found. Upstream reader.lua's "
            "startup order changed -- insert the self-install block "
            "manually, see README.md."
        )

    content = content.replace(ANCHOR, REPLACEMENT, 1)

    with open(path, "w", encoding="utf-8") as f:
        f.write(content)

    print(f"Patched {path}")


if __name__ == "__main__":
    main()
