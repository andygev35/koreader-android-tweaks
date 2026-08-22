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
    '-- directory on first run, and upgrade them in place on later runs if a\n'
    '-- newer version is bundled. Upgrade is opt-in per file, via a\n'
    '-- "-- @bundle_version N" marker in the first 512 bytes: a file only\n'
    '-- gets overwritten if BOTH the bundled copy and the already-installed\n'
    '-- copy carry that marker and the bundled one\'s number is higher.\n'
    '-- Files without the marker on both sides (e.g. hand-authored or\n'
    '-- hand-edited patches) are only ever installed if missing, never\n'
    '-- touched once present -- so local edits are always safe.\n'
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
    '            local function readVersion(path)\n'
    '                local f = io.open(path, "rb")\n'
    '                if not f then return nil end\n'
    '                local head = f:read(512) or ""\n'
    '                f:close()\n'
    '                local v = head:match("@bundle_version%s+(%d+)")\n'
    '                return v and tonumber(v) or nil\n'
    '            end\n'
    '            for entry in lfs.dir(bundled_dir) do\n'
    '                if entry:match("%.lua$") then\n'
    '                    local src_path = bundled_dir .. "/" .. entry\n'
    '                    local dest = patches_dir .. "/" .. entry\n'
    '                    local dest_exists = lfs.attributes(dest, "mode") == "file"\n'
    '                    local do_install = false\n'
    '                    if not dest_exists then\n'
    '                        do_install = true\n'
    '                    else\n'
    '                        local src_v = readVersion(src_path)\n'
    '                        local dest_v = readVersion(dest)\n'
    '                        if src_v and dest_v and src_v > dest_v then\n'
    '                            do_install = true\n'
    '                        end\n'
    '                    end\n'
    '                    if do_install then\n'
    '                        local src_f = io.open(src_path, "rb")\n'
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
