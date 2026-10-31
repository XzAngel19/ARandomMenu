#!/usr/bin/env python3
"""Exercise the real MM2 lobby/map distance decisions with typed part mocks.

These are local geometry contracts, not evidence about an actual MM2 map or
server. The simpler code relies on Roblox BasePart.Position being a Vector3.
"""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = (ROOT / "src/games/MM2/base.lua").read_text()
AUTO_WIN = (ROOT / "src/games/MM2/Other/AutoWin.lua").read_text()


def section(text, start, end):
    assert text.count(start) == 1
    return start + text.split(start, 1)[1].split(end, 1)[0]


lobby = section(BASE, "local function isRootNearLobby", "local function detectRoundPhase")
map_check = section(AUTO_WIN, "    local function isCharacterOnMap", "    local function restoreVictims")

script = r'''
type BasePart = any
type Instance = any
type Vector3 = any
local V = {}
local mt = {}
function V.new(x, y, z) return setmetatable({X=x, Y=y, Z=z}, mt) end
mt.__sub = function(a, b) return V.new(a.X-b.X, a.Y-b.Y, a.Z-b.Z) end
mt.__index = function(a, k)
    if k == "Magnitude" then return math.sqrt(a.X*a.X + a.Y*a.Y + a.Z*a.Z) end
end
local root = {Position=V.new(0, 0, 0)}
local lobbyPart = {Position=V.new(350, 0, 0)}
local mapPart = {Position=V.new(1000, 0, 0)}
local map = {}
function map:FindFirstChild(name) if name == "Spawns" and mapPart then return self end end
function map:FindFirstChildWhichIsA() return mapPart end
local activeMap = map
local function findMM2Map() return activeMap end
local function findLobbyReferencePart() return lobbyPart end
local function lobbyReferencePart() return lobbyPart end
''' + lobby + "\n" + map_check + r'''
assert(isRootNearLobby(root, {}) == true, "350 studs is still lobby")
local onMap = isCharacterOnMap(root)
assert(not onMap, "Auto Win must not treat the nearby lobby as a map")
lobbyPart.Position = V.new(351, 0, 0)
assert(not isRootNearLobby(root, {}), "outside lobby threshold")
local valid, pos = isCharacterOnMap(root)
assert(valid and pos == mapPart.Position, "loaded map may be used during countdown")
mapPart.Position = V.new(1501, 0, 0)
assert(not isCharacterOnMap(root), "a map more than 1500 studs away must not match")
mapPart.Position = V.new(1500, 0, 0)
assert(isCharacterOnMap(root), "1500 studs is inside the map threshold")
activeMap = nil
assert(not isCharacterOnMap(root), "without a map Auto Win must not act")
activeMap, lobbyPart, mapPart = map, nil, nil
valid, pos = isCharacterOnMap(root)
assert(valid and pos == root.Position, "a map with no reference keeps the root fallback")
assert(not isRootNearLobby(root, {}), "no lobby part is not a positive lobby match")
print("PASS MM2 map/lobby thresholds, missing map and countdown geometry")
'''

with tempfile.TemporaryDirectory(prefix="mm2-map-checks-") as tmp:
    path = Path(tmp) / "test.luau"
    path.write_text(script)
    subprocess.run([os.environ.get("LUAU", "luau"), str(path)], check=True)
