#!/usr/bin/env python3
"""Frame-cost profile of the real menu, booted from the real bundle.

This does not pretend to be Roblox. It measures the one thing only the menu is
responsible for: how much *Lua* its per-frame callbacks burn, and which task is
responsible. If the menu's Lua is cheap and the game still stutters, the stutter
is not coming from here.

    python3 tools/perf_frame.py [--players 11] [--coins 80] [--frames 120]
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "build" / "full_boot.luau"

EPILOGUE = r'''
-- ================= frame cost profile =================
local PROFILE_PLAYERS = __PLAYERS__
local PROFILE_COINS = __COINS__
local PROFILE_FRAMES = __FRAMES__

local ex = GENV.__expose
local host = ex.state.framework.Host
local TM = host.TaskManager
local RS = host.RunService
local world = workspace

-- Extra players with a full R6-style rig, so every render module has something
-- to walk over. They are ordinary mock instances.
local extraPlayers = {}
for index = 1, PROFILE_PLAYERS do
    local player = Instance.new("Player")
    player.Name = "PerfPlayer" .. tostring(index)
    player.UserId = 90000 + index
    local character = Instance.new("Model")
    character.Name = player.Name
    for _, name in ipairs({ "HumanoidRootPart", "Torso", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }) do
        local part = Instance.new("Part", character)
        part.Name = name
        part.CanCollide = (name == "HumanoidRootPart" or name == "Torso")
        part.Position = Vector3.new(index * 4, 0, 0)
        part.CFrame = CFrame.new(index * 4, 0, 0)
        part.AssemblyLinearVelocity = Vector3.zero
        part.AssemblyAngularVelocity = Vector3.zero
    end
    local humanoid = Instance.new("Humanoid", character)
    humanoid.Name = "Humanoid"
    humanoid.Health = 100
    character.PrimaryPart = character:FindFirstChild("HumanoidRootPart")
    character.Parent = world
    player.Character = character
    player.Parent = host.Players
    table.insert(extraPlayers, player)
end

for index = 1, PROFILE_COINS do
    local coin = Instance.new("Part", world)
    coin.Name = "Coin_Server"
    coin.CanCollide = false
    coin.Position = Vector3.new(index % 20, 1, (index // 20) + 1)
end

-- Count instance API traffic per task. Time alone is too coarse (os.clock
-- ticks in milliseconds here), but "this callback walked the tree 900 times in
-- 20 frames" is unambiguous.
local counts = {}
local currentTask = nil
local function bucketFor(id)
    local record = counts[id]
    if not record then
        record = {getDescendants = 0, getChildren = 0, findChild = 0,
                  isA = 0, read = 0, write = 0, calls = 0}
        counts[id] = record
    end
    return record
end
local WATCHED = {
    GetDescendants = "getDescendants",
    GetChildren = "getChildren",
    FindFirstChild = "findChild",
    FindFirstChildOfClass = "findChild",
    FindFirstChildWhichIsA = "findChild",
    IsA = "isA",
}
local wrappedMetatables = setmetatable({}, {__mode = "k"})
local function instrument(instance)
    local mt = getmetatable(instance)
    if type(mt) ~= "table" or wrappedMetatables[mt] then
        return
    end
    wrappedMetatables[mt] = true
    local originalIndex = mt.__index
    local originalNewIndex = mt.__newindex
    mt.__index = function(self, key)
        local value = originalIndex(self, key)
        if currentTask ~= nil then
            local record = bucketFor(currentTask)
            local counter = WATCHED[key]
            if counter then
                record[counter] += 1
            else
                record.read += 1
            end
            if type(value) == "function" and counter then
                return function(...)
                    bucketFor(currentTask).calls += 1
                    return value(...)
                end
            end
        end
        return value
    end
    mt.__newindex = function(self, key, value)
        if currentTask ~= nil then
            bucketFor(currentTask).write += 1
        end
        return originalNewIndex(self, key, value)
    end
end
local function instrumentTree(root)
    instrument(root)
    for _, child in ipairs(root.children) do
        instrument(child)
        local descendants = child.children
        if #descendants > 0 then
            instrumentTree(child)
        end
    end
end
local originalNew = Instance.new
Instance.new = function(class, parent)
    local created = originalNew(class, parent)
    instrument(created)
    return created
end

local function activeIds()
    local ids = {}
    for id in pairs(TM.tasks) do ids[id] = true end
    for id in pairs(TM.renderTasks) do ids[id] = true end
    return ids
end

-- Attribute task ids to features: enable one feature at a time and see which id
-- appears. Anything that errors is skipped, not fatal.
local owner = {}
for _, feature in ipairs(host.allFeatures) do
    if type(feature) == "table" and type(feature.name) == "string"
        and type(feature.onToggle) == "function" and not feature.enabled then
        local before = activeIds()
        local ok = pcall(feature.onToggle, true)
        local after = activeIds()
        if ok then
            for id in pairs(after) do
                if not before[id] and owner[id] == nil then
                    owner[id] = feature.name
                end
            end
            pcall(feature.onToggle, false)
        end
    end
end

-- Enable the modules that actually draw or drive something every frame.
local enabled = {}
local function turnOn(name)
    local feature = host.allFeatures and nil
    for _, candidate in ipairs(host.allFeatures) do
        if candidate.name == name then feature = candidate break end
    end
    if not feature then return end
    local ok = pcall(feature.onToggle, true)
    if ok then table.insert(enabled, name) end
end
for _, name in ipairs({
    "PlayerESP", "Chams", "Nametags", "HP", "Arrows", "ItemESP",
    "Coin ESP", "Auto Vote",
}) do
    turnOn(name)
end

-- Time every per-frame callback the menu owns.
local stats = {}
local function wrap(bucket, id)
    local entry = bucket[id]
    if not entry or entry.__profiled then return end
    local original = entry.callback
    entry.__profiled = true
    entry.callback = function(dt)
        local started = os.clock()
        local previous = currentTask
        currentTask = id
        local ok, err = pcall(original, dt)
        currentTask = previous
        if not ok then
            -- The mock is not Roblox: vector/CFrame stubs make some render
            -- callbacks throw. They are listed once, not per frame.
            local seen = stats[id] and stats[id].error
            if not seen then
                print("PROFILE task error id=" .. tostring(id)
                    .. " (mock limitation): " .. tostring(err))
                if stats[id] then stats[id].error = true end
            end
        end
        local spent = (os.clock() - started) * 1000
        local record = stats[id]
        if not record then
            record = {ms = 0, n = 0}
            stats[id] = record
        end
        record.ms += spent
        record.n += 1
    end
end

local function refreshWrappers()
    for id in pairs(TM.tasks) do wrap(TM.tasks, id) end
    for id in pairs(TM.renderTasks) do wrap(TM.renderTasks, id) end
end
refreshWrappers()

instrumentTree(world)
instrumentTree(CoreGui)
instrumentTree(PlayerGui)

local heartbeat = RS.Heartbeat
local renderStepped = RS.RenderStepped
local started = os.clock()
for frame = 1, PROFILE_FRAMES do
    refreshWrappers()
    heartbeat:Fire(1 / 60)
    renderStepped:Fire(1 / 60)
end
local wall = (os.clock() - started) * 1000

local rows = {}
local total = 0
for id, record in pairs(stats) do
    total += record.ms
    table.insert(rows, {
        id = id, ms = record.ms, n = record.n, owner = owner[id],
        traffic = counts[id] or {},
    })
end
table.sort(rows, function(a, b) return a.ms > b.ms end)

print(string.format(
    "PROFILE frames=%d wallMs=%.1f luaMs=%.1f perFrame=%.3f tasks=%d",
    PROFILE_FRAMES, wall, total, total / PROFILE_FRAMES, #rows
))
for index = 1, math.min(#rows, 12) do
    local row = rows[index]
    local traffic = row.traffic
    print(string.format(
        "PROFILE  %6.2f ms  id=%s  n=%d  desc=%d child=%d find=%d isA=%d read=%d write=%d  %s",
        row.ms, tostring(row.id), row.n,
        traffic.getDescendants or 0, traffic.getChildren or 0,
        traffic.findChild or 0, traffic.isA or 0,
        traffic.read or 0, traffic.write or 0,
        row.owner or "?"
    ))
end
-- The in-menu readout must actually render: it is the number the user will
-- report. Turn the Session Info overlay on, run frames, and look for the line.
local overlay = ex.state.floatingUi and ex.state.floatingUi.overlays
    and ex.state.floatingUi.overlays.SessionInfo
if overlay then
    overlay.enabled = true
end
for _ = 1, 12 do
    heartbeat:Fire(1 / 60)
end
local scriptLine = nil
local function huntLabels(node)
    for _, child in ipairs(node.children) do
        if child.ClassName == "TextLabel" and child.props.Text then
            local text = tostring(child.props.Text)
            if text:find("Script", 1, true) then
                scriptLine = text
            end
        end
    end
    for _, child in ipairs(node.children) do
        huntLabels(child)
    end
end
huntLabels(CoreGui)
local flat = scriptLine and string.gsub(scriptLine, "\n", " | ") or "MISSING"
print("PROFILE session_line=" .. flat)

print("PROFILE features_on=" .. table.concat(enabled, ","))
print("PROFILE players=" .. tostring(#host.Players:GetPlayers()) ..
    " workspace_children=" .. tostring(#world.children))
'''


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--players", type=int, default=10)
    parser.add_argument("--coins", type=int, default=80)
    parser.add_argument("--frames", type=int, default=120)
    args = parser.parse_args()

    if not HARNESS.exists():
        print("building the boot harness…", file=sys.stderr)
        subprocess.run([sys.executable, str(ROOT / "tools" / "gen_full_boot_harness.py")],
                       check=True, cwd=ROOT)
    base = HARNESS.read_text(encoding="utf-8")
    epilogue = (EPILOGUE
                .replace("__PLAYERS__", str(args.players))
                .replace("__COINS__", str(args.coins))
                .replace("__FRAMES__", str(args.frames)))
    target = ROOT / "build" / "profile_frame.luau"
    target.write_text(base + "\n" + epilogue, encoding="utf-8")

    luau = ROOT / "tools" / "luau" / "bin" / "luau"
    result = subprocess.run([str(luau), str(target)], capture_output=True, text=True)
    lines = [line for line in result.stdout.splitlines() if line.startswith("PROFILE")]
    for line in lines:
        print(line)
    if result.returncode != 0 or not lines:
        print(result.stdout[-3000:], file=sys.stderr)
        print(result.stderr[-3000:], file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
