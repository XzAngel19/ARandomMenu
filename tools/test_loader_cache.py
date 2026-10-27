#!/usr/bin/env python3
"""Loader contract: one canonical branch, no legacy cache, no frozen version.

The cache half runs the real `state.purgeLegacyCache` / `state.cacheIdentityMatches`
code from `src/Wurst.lua` against a mock executor filesystem. It proves the file
rules, not that a specific executor supports listfiles/delfile.
"""
from __future__ import annotations

import os
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WURST = (ROOT / "src/Wurst.lua").read_text(encoding="utf-8")
README = (ROOT / "README.md").read_text(encoding="utf-8")

canonical = re.search(r'local CANONICAL_BRANCH: string = "([^"]+)"', WURST)
assert canonical, "CANONICAL_BRANCH is missing"
BRANCH = canonical.group(1)
assert "local RUNTIME_BRANCH: string = CANONICAL_BRANCH" in WURST, (
    "RUNTIME_BRANCH must default to the canonical branch"
)
assert f'"{BRANCH}"' in WURST
assert f"/refs/heads/{BRANCH}/src/Wurst.lua" in README, "loader README is not canonical"

# A branch override is still allowed, but it must be validated: a stray value
# used to load another tree silently.
assert "local function normalizeBranchName(value: any): string?" in WURST
for guard in (
    'if cleaned == "" or #cleaned > 120 then',
    'if string.find(cleaned, "^[%w%-%._/]+$") == nil then',
    "if string.find(cleaned, \"%.%.\")",
):
    assert guard in WURST, guard
assert "BRANCH_SOURCE = \"override\"" in WURST

# No second hardcoded tree, and the visible version comes from the stamp.
declared = set(re.findall(r"refs/heads/([^\"']+)/src/Wurst\.lua", WURST))
assert declared == {BRANCH}, f"other branches referenced: {sorted(declared)}"
assert "0.1 Beta" not in WURST
assert "version = BUILD_LABEL" in WURST
assert re.search(r'BUILD_LABEL: string = string\.match\(SOURCE_STAMP, "\^v%d\+"\)', WURST)

# The retired trees must stay retired.
for dead in ("src/gui", "src/library", "src/Profile"):
    assert not (ROOT / dead).exists(), f"{dead} is a legacy tree"
bundle = (ROOT / "src/libraries/bundle.lua").read_text(encoding="utf-8")
for dead in ('["src/gui/', '["src/library/', '["src/Profile/'):
    assert dead not in bundle, f"bundle still ships {dead}"

for anchor in (
    "state.cacheIdentityMatches = function(): boolean",
    "state.writeCacheIdentity = function(): ()",
    "state.purgeLegacyCache = function(force: boolean?): number",
    "local keepIdentity: boolean = state.cacheIdentityMatches() and force ~= true",
    "local CACHE_PROTECTED: string = \"Wurst/Profiles\"",
):
    assert anchor in WURST, anchor

# Reinject must refuse an old loader and must not be served from a cache.
SETTINGS = (ROOT / "src/guis/Wurst/Code/SettingsPage.lua").read_text(encoding="utf-8")
assert 'local declaredBranch: string? = type(bodyOrError) == "string"' in SETTINGS
assert 'stale loader for branch ' in SETTINGS
assert '"?reinject=v4&t="' in SETTINGS and "tostring(os.time())" in SETTINGS
assert "pcall(purgeLegacyCache, true)" in SETTINGS
assert '"ClearCache", "Clear cache", runClearCache' in SETTINGS

# ---------------------------------------------------------------------------
# Behaviour: run the real cache functions against a mock filesystem.
# ---------------------------------------------------------------------------

start = WURST.index("state.ensureSourceFolders = function(path: string): ()")
end = WURST.index("state.fetchRepositorySource = function(path: string): (string?, string?)")
CACHE_CODE = WURST[start:end]

HARNESS = r'''
local files = {}
local folders = {["Wurst"] = true, ["Wurst/src"] = true, ["Wurst/Profiles"] = true}
local env = {}
getfenv = function() return env end
local os = {clock=function() return 0 end}
env.makefolder = function(path)
    folders[path] = true
end
env.isfolder = function(path) return folders[path] == true end
env.isfile = function(path) return files[path] ~= nil end
env.writefile = function(path, body) files[path] = body end
env.readfile = function(path)
    if files[path] == nil then error("no such file: " .. tostring(path)) end
    return files[path]
end
env.delfile = function(path)
    if files[path] == nil then error("no such file: " .. tostring(path)) end
    files[path] = nil
end
local function registerFolders()
    local listed = {}
    for path in pairs(files) do
        local prefix = ""
        for segment in string.gmatch(path, "([^/]+)/") do
            prefix = prefix .. segment
            listed[prefix] = true
            prefix = prefix .. "/"
        end
    end
    for folder in pairs(listed) do
        folders[folder] = true
    end
    folders["Wurst/Profiles"] = true
end
env.listfiles = function(path)
    assert(folders[path], "listfiles on a missing folder: " .. tostring(path))
    local out = {}
    local prefix = path .. "/"
    for file in pairs(files) do
        if string.sub(file, 1, #prefix) == prefix
            and not string.find(string.sub(file, #prefix + 1), "/", 1, true) then
            table.insert(out, file)
        end
    end
    for folder in pairs(folders) do
        if folder ~= path and string.sub(folder, 1, #prefix) == prefix
            and not string.find(string.sub(folder, #prefix + 1), "/", 1, true) then
            table.insert(out, folder)
        end
    end
    table.sort(out)
    return out
end

local SOURCE_STAMP = "__STAMP__"
local RUNTIME_BRANCH = "__BRANCH__"
local CACHE_LAYOUT = "2"
local CACHE_ROOT = "Wurst"
local CACHE_PROTECTED = "Wurst/Profiles"
local state = {
    boot = {bundle = {}},
    sourceLooksValid = function(source, minimum)
        return type(source) == "string" and #source >= minimum
    end,
    assetManifestNames = {["wurst-logo-v1.png"] = true},
}
<<<CACHE_CODE>>>

local function seedLegacy()
    files = {
        ["Wurst/.stamp"] = "v143-20261026-boot-restore-lifecycle",
        ["Wurst/.branch"] = "arena/2fb9a46a-arandommenu",
        ["Wurst/.layout"] = "1",
        ["Wurst/src/games/MM2/Other/AutoFarm.lua"] = "-- old farm " .. string.rep("x", 40),
        ["Wurst/src/games/MM2/Other/Retired.lua"] = "-- retired " .. string.rep("x", 40),
        ["Wurst/Assets/wurst-logo-v1.png"] = string.rep("p", 64),
        ["Wurst/Assets/old-banner.png"] = string.rep("p", 64),
        ["Wurst/Profiles/Game_142823291.lua"] = "-- user config",
        ["Wurst/Profiles/Game_142823291.lua.bak"] = "-- user config backup",
    }
    registerFolders()
end

-- 1. A cache written by another build is not "current".
seedLegacy()
assert(not state.cacheIdentityMatches(), "legacy stamp must not match")
local removed = state.purgeLegacyCache(false)
assert(removed >= 6, "legacy files must be deleted, removed=" .. tostring(removed))
assert(files["Wurst/src/games/MM2/Other/AutoFarm.lua"] == nil, "legacy source kept")
assert(files["Wurst/Assets/old-banner.png"] == nil, "legacy asset kept")
assert(files["Wurst/.stamp"] == nil and files["Wurst/.branch"] == nil
    and files["Wurst/.layout"] == nil, "legacy markers kept")
assert(files["Wurst/Profiles/Game_142823291.lua"] == "-- user config",
    "user profiles must survive a purge")
assert(files["Wurst/Profiles/Game_142823291.lua.bak"] == "-- user config backup",
    "user profile backups must survive a purge")
print("PASS legacy build cache is deleted and profiles survive")

-- 2. A current cache is kept, and unknown entries are still swept.
state.boot.bundle = {["src/games/MM2/Other/AutoFarm.lua"] = "-- new"}
state.writeCacheIdentity()
files["Wurst/src/games/MM2/Other/AutoFarm.lua"] = "-- new farm " .. string.rep("y", 40)
files["Wurst/src/games/MM2/Other/Gone.lua"] = "-- removed module"
files["Wurst/Assets/wurst-logo-v1.png"] = string.rep("p", 64)
files["Wurst/Assets/stale-banner.png"] = string.rep("p", 64)
files["Wurst/legacy-bundle.lua"] = "-- junk from an older loader"
assert(state.cacheIdentityMatches(), "same stamp/branch/layout must match")
assert(state.readCachedSource("src/games/MM2/Other/AutoFarm.lua") ~= nil,
    "matching cache is readable")
removed = state.purgeLegacyCache(false)
assert(removed >= 3, "stale entries swept, removed=" .. tostring(removed))
assert(state.readCachedSource("src/games/MM2/Other/AutoFarm.lua") ~= nil,
    "the current source survives a normal sweep")
assert(files["Wurst/src/games/MM2/Other/Gone.lua"] == nil, "retired module swept")
assert(files["Wurst/Assets/wurst-logo-v1.png"] ~= nil, "current asset kept")
assert(files["Wurst/Assets/stale-banner.png"] == nil, "stale asset swept")
assert(files["Wurst/legacy-bundle.lua"] == nil, "unknown leftover deleted")
assert(files["Wurst/Profiles/Game_142823291.lua"] == "-- user config",
    "profiles survive a normal sweep")
print("PASS current cache kept, unknown leftovers swept")

-- 3. Clear cache (force) drops the current build's cached sources too.
state.purgeLegacyCache(true)
assert(files["Wurst/src/games/MM2/Other/AutoFarm.lua"] == nil, "force drops sources")
assert(files["Wurst/Assets/wurst-logo-v1.png"] == nil, "force drops assets")
assert(files["Wurst/.stamp"] == nil, "force drops the identity marker")
assert(files["Wurst/Profiles/Game_142823291.lua"] == "-- user config",
    "force never deletes profiles")
print("PASS Clear cache drops every generated file but keeps profiles")

-- 4. Switching branch invalidates the cache even with the same stamp.
state.boot.bundle = {["src/games/MM2/Other/AutoFarm.lua"] = "-- new"}
files["Wurst/src/games/MM2/Other/AutoFarm.lua"] = "-- new farm " .. string.rep("y", 40)
state.writeCacheIdentity()
assert(state.cacheIdentityMatches())
RUNTIME_BRANCH = "arena/some-other-branch"
assert(not state.cacheIdentityMatches(), "another branch must not reuse the cache")
assert(state.readCachedSource("src/games/MM2/Other/AutoFarm.lua") == nil,
    "cross-branch cache must not be read")
print("PASS branch switch invalidates the cache")
'''

stamp = re.search(r'local SOURCE_STAMP: string = "([^"]+)"', WURST).group(1)
script = (
    HARNESS.replace("__STAMP__", stamp)
    .replace("__BRANCH__", BRANCH)
    .replace("<<<CACHE_CODE>>>", CACHE_CODE)
)

with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False) as handle:
    handle.write(script)
    path = handle.name
try:
    result = subprocess.run(
        [os.environ.get("LUAU", str(ROOT / "tools/luau/bin/luau")), path],
        text=True, capture_output=True,
    )
    print(result.stdout, end="")
    if result.returncode:
        print(result.stderr, end="")
        raise SystemExit(result.returncode)
finally:
    os.unlink(path)

print("PASS loader: canonical branch only, validated override, stamp-derived "
      "version, and no legacy cache on disk")
