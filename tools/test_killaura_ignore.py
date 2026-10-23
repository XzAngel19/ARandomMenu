#!/usr/bin/env python3
"""Kill Aura ignore list: parse, match and leave everyone else alone."""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'src/games/universal/Combat/KillAura.lua').read_text()

start = SOURCE.index('local function compileIgnoreList')
end = SOURCE.index('function Module.init(')
helpers = SOURCE[start:end]

script = helpers + r'''
local function entity(name, display, id)
    return {Player = {Name = name, DisplayName = display, UserId = id}}
end
local alice = entity("Alice", "Ali", 11)
local bob = entity("Bob", "Bobby", 22)
local npc = {Character = {}}
local function names(list)
    local out = {}
    for _, e in ipairs(list) do
        out[#out + 1] = e.Player and e.Player.Name or "npc"
    end
    return table.concat(out, ",")
end

-- Empty text is "nobody": the list is not a filter until it has a name.
assert(next(compileIgnoreList("")) == nil)
assert(next(compileIgnoreList(nil)) == nil)

-- Names, display names and ids all match, case-insensitively, with the three
-- separators a user might type.
local byName = compileIgnoreList("alice")
assert(isIgnoredEntity(alice, byName) and not isIgnoredEntity(bob, byName))
assert(isIgnoredEntity(alice, compileIgnoreList("ALI")))
assert(isIgnoredEntity(bob, compileIgnoreList("22")))
assert(not isIgnoredEntity(npc, compileIgnoreList("anything")),
    "NPCs have no Player and are never filtered by the name list")

local mixed = compileIgnoreList("Alice, Bobby; 999")
assert(isIgnoredEntity(alice, mixed) and isIgnoredEntity(bob, mixed))
assert(isIgnoredEntity(bob, compileIgnoreList("  bob  ")), "surrounding spaces")

-- The same filter order the module uses: build once, keep what survives.
local function filter(list, text)
    local ignored = compileIgnoreList(text)
    local kept = {}
    for _, e in ipairs(list) do
        if not isIgnoredEntity(e, ignored) then kept[#kept + 1] = e end
    end
    return kept
end
assert(names(filter({alice, bob, npc}, "alice")) == "Bob,npc")
assert(names(filter({alice, bob, npc}, "")) == "Alice,Bob,npc")
assert(names(filter({alice, bob, npc}, "nobody")) == "Alice,Bob,npc")
print("PASS KillAura ignore list: names, display names, ids, separators, case, NPCs untouched")
'''

with tempfile.TemporaryDirectory(prefix='killaura-ignore-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
