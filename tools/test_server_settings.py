#!/usr/bin/env python3
"""Execute the real v192 "Server Settings" card against mocked services.

What this proves:

  * the card registers in Utilities and "Rejoin Server" is GONE;
  * "Copy Job ID" copies the live Job ID (and still reports the id when the
    executor has no clipboard);
  * the readout carries the server uptime, and "Show server info" builds an
    overlay whose rows hold the Job ID, the player count, the uptime, the server
    clock, the place, the local player and the build label;
  * a hop only ever picks a server with a FREE SLOT: a 12/12 instance is never a
    candidate, an empty 0/12 instance is never "smallest", "largest" is the
    fullest server that can still be joined (11/12 in a 12-slot place) and
    "random" never picks the server you are already in;
  * a failed HTTP read or a list without a joinable server is reported instead
    of teleporting;
  * the hop cooldown refuses a second hop in the same couple of seconds;
  * the readout only refreshes while the card is ON.

It does NOT prove that Roblox accepts the teleport: TeleportService is a mock.
Nothing here talks to games.roblox.com either: HttpGet answers from a table.
"""

import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/games/universal/Other/ServerSettings.lua").read_text(encoding="utf-8")
MANIFEST = (ROOT / "src/libraries/Manifest.lua").read_text(encoding="utf-8")

assert '"src/games/universal/Other/ServerSettings.lua"' in MANIFEST, (
    "Server Settings must be in the universal load list"
)
assert '["Server Settings"] = "Utilities"' in MANIFEST, "Server Settings lives in Utilities"
assert 'addActionOption(card, "Rejoin Server"' not in SOURCE, (
    "v192: the Rejoin Server action is removed from the card"
)

script = r'''
local now = 0
os = {
    clock = function() return now end,
    time = function() return 1000 end,
    date = function(_format, _stamp) return { hour = 1, min = 2, sec = 3 } end,
}

local notifications = {}
local function notify(message, kind)
    table.insert(notifications, { text = message, kind = kind })
end

local clipboard = {}
local setclipboard = function(text) table.insert(clipboard, text) end

local jobId = "abc123def456"
local placeId = 142823291

-- Enum / UDim2 / Vector2 / Instance building: just enough for the overlay.
local function enumTable()
    return setmetatable({}, { __index = function(self, key)
        local child = enumTable()
        rawset(self, key, child)
        return child
    end })
end
Enum = enumTable()
UDim2 = {
    new = function(x, xo, y, yo) return { x = x, xo = xo, y = y, yo = yo } end,
    fromOffset = function(x, y) return { xo = x, yo = y } end,
    fromScale = function(x, y) return { x = x, y = y } end,
}
UDim = { new = function(a, b) return { a = a, b = b } end }
Vector2 = { new = function(x, y) return { x = x, y = y } end }
Color3 = { fromRGB = function(r, g, b) return { r = r, g = g, b = b, kind = "Color3" } end }
typeof = function(value) return type(value) end

local objects = {}
local function create(class, properties)
    local object = { ClassName = class, Parent = nil, Text = "", Enabled = true }
    object.MouseButton1Click = {
        Connect = function(_self, fn)
            object.onClick = fn
            return { Disconnect = function() end }
        end,
    }
    for key, value in pairs(properties or {}) do
        object[key] = value
    end
    table.insert(objects, object)
    return object
end

-- An object still exists only while its overlay root is parented: the mock
-- keeps every instance it ever built, exactly like a destroyed Frame stays in
-- memory until GC, so "gone" has to mean "detached from the ScreenGui".
local function attached(object)
    local node = object
    while node do
        if node.Name == "WurstServerInfo" and node.Parent == nil then
            return false
        end
        node = node.Parent
    end
    return true
end

local function findText(text)
    for _, object in ipairs(objects) do
        if object.ClassName == "TextLabel" and object.Text == text and attached(object) then
            return object
        end
    end
    return nil
end

ScreenGui = { ClassName = "ScreenGui" }
Theme = {}
PRODUCT = { version = "0.192 Release" }

task = {
    spawn = function(fn) fn() end,
    wait = function(seconds) now += seconds or 0 end,
    delay = function(_seconds, fn) fn() end,
}

local teleports = {}
local function TeleportToPlaceInstance(_self, place, targetJob, player)
    table.insert(teleports, { place = place, job = targetJob, player = player })
end
local Teleport = function() error("Teleport must not be used") end

local httpAnswer = { data = {} }
local function HttpGet(_self, url)
    lastEndpoint = url
    if type(httpAnswer) == "function" then
        httpAnswer()
    end
    -- A real executor returns the JSON text; the mock returns a marker and the
    -- HttpService mock hands the configured answer back.
    return "{}"
end

game = {
    JobId = jobId,
    PlaceId = placeId,
    PlaceVersion = 7,
    Name = "TestPlace",
    HttpGet = HttpGet,
    GetService = function(_self, name)
        if name == "HttpService" then
            return { JSONDecode = function(_self, _body) return httpAnswer end }
        elseif name == "TeleportService" then
            return { TeleportToPlaceInstance = TeleportToPlaceInstance, Teleport = Teleport }
        elseif name == "Players" then
            return { GetPlayers = function() return {} end }
        end
        return {}
    end,
}

workspace = {
    DistributedGameTime = 3725,
    GetServerTimeNow = function(_self) return 1000 end,
}

local players = { list = {}, MaxPlayers = 12 }
function players:GetPlayers() return self.list end
for index = 1, 5 do
    table.insert(players.list, { Name = "P" .. index })
end
local LocalPlayer = { Name = "Me", UserId = 42 }

local featureConnections = {}
local function disconnectFeatureConnection(name) featureConnections[name] = nil end
local TaskManager = {
    Connect = function(_self, fn, _priority, name)
        local record = { fn = fn, name = name }
        return record
    end,
}

local function createUniversalFeature(name, description, order, onToggle, configuration)
    local card = {
        name = name, description = description, order = order,
        onToggle = onToggle, configuration = configuration or {},
        enabled = false, status = nil,
    }
    function card:SetStatus(text) self.status = text end
    return card
end

local actions = {}
local function addActionOption(_feature, label, callback)
    actions[label] = { callback = callback }
end
local toggles = {}
local function addToggleOption(_feature, label, default, callback, hint)
    toggles[label] = { default = default, callback = callback, hint = hint }
end
local numbers = {}
local function addNumberOption(_feature, label, default, minimum, maximum, callback, hint, step, persist)
    numbers[label] = {
        default = default, min = minimum, max = maximum,
        callback = callback, hint = hint, step = step, persist = persist,
    }
end
local information = {}
local function addInformationOption(_feature, text)
    table.insert(information, text)
end

local host = {
    LocalPlayer = LocalPlayer,
    Players = players,
    notify = notify,
    createUniversalFeature = createUniversalFeature,
    addActionOption = addActionOption,
    addToggleOption = addToggleOption,
    addNumberOption = addNumberOption,
    addInformationOption = addInformationOption,
    TaskManager = TaskManager,
    featureConnections = featureConnections,
    disconnectFeatureConnection = disconnectFeatureConnection,
    cloneReference = function(value) return value end,
}

state = {}

local Module = (function()
''' + SOURCE + r'''
end)()

local function eq(actual, expected, message)
    if actual ~= expected then
        error(message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected), 0)
    end
end

Module.init({ host = host, services = {} })
local card = state.serverSettingsCard
assert(card, "the card publishes itself as state.serverSettingsCard")
eq(card.name, "Server Settings", "card name")
eq(card.configuration.categoryName, "Utilities", "card window")
eq(#information, 1, "one information row explains what a client cannot do")

for _, label in ipairs({ "Copy Job ID", "Hop: smallest server",
    "Hop: largest server", "Hop: random server" }) do
    assert(actions[label], "missing action: " .. label)
end
assert(actions["Rejoin Server"] == nil, "v192: Rejoin Server is gone")
assert(toggles["Show server info"], "the readout toggle exists")
assert(numbers["Refresh every"], "the refresh slider exists")
eq(numbers["Refresh every"].default, 3, "refresh default")
eq(numbers["Refresh every"].min, 1, "refresh min")
eq(numbers["Refresh every"].max, 15, "refresh max")

-- CARD OFF => no status work, no ticker, no overlay.
eq(card.status, nil, "an OFF card writes no status")
eq(featureConnections.ServerSettingsTick, nil, "an OFF card owns no ticker")
assert(findText("Server Info") == nil, "an OFF card builds no overlay")

-- CARD ON => the readout shows the short Job ID, the players and the uptime.
card.enabled = true
card.onToggle(true)
eq(card.status, "abc123de · 5/12 · up 1:02:05", "readout shows id, players and uptime")
assert(featureConnections.ServerSettingsTick, "an ON card owns its ticker")

-- The overlay carries every readable field.
assert(findText("Server Info"), "the overlay has a title")
assert(findText("abc123def456"), "the overlay shows the full Job ID")
assert(findText("5 / 12"), "the overlay shows players / limit")
assert(findText("1:02:05"), "the overlay shows the server uptime")
assert(findText("01:02:03 UTC"), "the overlay shows the server clock")
assert(findText("TestPlace · v7"), "the overlay shows the place and its version")
assert(findText("Me (42)"), "the overlay shows the local player")
assert(findText("0.192 Release"), "the overlay shows the derived build label")

-- Copy Job ID goes through the executor clipboard.
actions["Copy Job ID"].callback()
eq(#clipboard, 1, "one clipboard write")
eq(clipboard[1], jobId, "the live Job ID is copied")

-- Without a clipboard the id is still reported.
setclipboard = nil
local beforeNotices = #notifications
actions["Copy Job ID"].callback()
eq(#notifications, beforeNotices + 1, "a missing clipboard still says something")
assert(string.find(notifications[#notifications].text, jobId, 1, true),
    "the message carries the Job ID")

-- Only servers with a free slot are candidates.
local servers = {
    data = {
        { id = "empty", playing = 0, maxPlayers = 12 },
        { id = "small", playing = 2, maxPlayers = 12 },
        { id = "mid", playing = 6, maxPlayers = 12 },
        { id = "big", playing = 11, maxPlayers = 12 },
        { id = "full", playing = 12, maxPlayers = 12 },
        { id = jobId, playing = 5, maxPlayers = 12 },
    },
}
httpAnswer = servers
actions["Hop: smallest server"].callback()
eq(#teleports, 1, "one teleport for a hop")
eq(teleports[1].job, "small", "smallest server with players, never an empty one")
eq(teleports[1].place, placeId, "same place")
eq(teleports[1].player, LocalPlayer, "the local player is teleported")
assert(string.find(lastEndpoint, "excludeFullServers=true", 1, true),
    "the endpoint is asked to exclude full servers: " .. tostring(lastEndpoint))

-- The cooldown blocks an immediate second hop.
actions["Hop: largest server"].callback()
eq(#teleports, 1, "the hop cooldown refuses a second hop")
assert(string.find(notifications[#notifications].text, "Slow down"),
    "the cooldown explains itself: " .. tostring(notifications[#notifications].text))

now += 5
actions["Hop: largest server"].callback()
eq(#teleports, 2, "after the cooldown the hop happens")
eq(teleports[2].job, "big", "largest server = fullest server that still has a slot (11/12)")
assert(string.find(notifications[#notifications].text, "11/12", 1, true),
    "the message states the real player count: " .. tostring(notifications[#notifications].text))

now += 5
local seen = {}
for _ = 1, 20 do
    now += 5
    actions["Hop: random server"].callback()
    local chosen = teleports[#teleports].job
    assert(chosen ~= jobId, "the current server is never chosen")
    assert(chosen ~= "full", "a full server is never chosen")
    seen[chosen] = true
end
assert(seen.small or seen.big or seen.mid or seen.empty, "random hop picks a listed server")

-- A failed request must never teleport.
now += 5
httpAnswer = function() error("http blocked") end
local teleportsBefore = #teleports
actions["Hop: smallest server"].callback()
eq(#teleports, teleportsBefore, "a failed server list never teleports")
assert(string.find(notifications[#notifications].text, "Server hop"),
    "the failure is reported")

-- A list without a joinable server is reported too.
now += 5
httpAnswer = { data = {
    { id = jobId, playing = 5, maxPlayers = 12 },
    { id = "full", playing = 12, maxPlayers = 12 },
} }
actions["Hop: smallest server"].callback()
eq(#teleports, teleportsBefore, "no free slot means no teleport")
assert(string.find(notifications[#notifications].text, "free slot"),
    "the missing slot is explained: " .. tostring(notifications[#notifications].text))

-- The ticker refreshes the readout and the overlay, then turning the card off
-- drops both.
httpAnswer = servers
players.list = { players.list[1] }
workspace.DistributedGameTime = 8
featureConnections.ServerSettingsTick.fn(10)
eq(card.status, "abc123de · 1/12 · up 0:00:08", "an ON card refreshes its status")
assert(findText("1 / 12"), "the overlay refreshes with the card")
card.enabled = false
card.onToggle(false)
eq(featureConnections.ServerSettingsTick, nil, "turning the card off disconnects the ticker")
eq(card.status, nil, "turning the card off clears the status")

-- The option still opens the overlay again when it comes back.
card.enabled = true
card.onToggle(true)
assert(findText("Server Info"), "the overlay comes back with the card")
toggles["Show server info"].callback(false)
assert(findText("Server Info") == nil, "turning the option off removes the overlay")

Module.destroy()
eq(state.serverSettingsCard, nil, "destroy clears the exported card")
print("PASS Server Settings: readout + uptime, overlay, clipboard, smallest/largest/random with a real slot, cooldown, failures, no rejoin")
'''

with tempfile.TemporaryDirectory(prefix="server-settings-") as temp:
    path = Path(temp) / "server_settings.luau"
    path.write_text(script, encoding="utf-8")
    result = subprocess.run(
        [os.environ.get("LUAU", "tools/luau/bin/luau"), str(path)],
        capture_output=True,
        text=True,
    )
    if result.returncode:
        raise SystemExit(f"Server Settings failed:\n{result.stdout[-6000:]}\n{result.stderr}")
    print(next(line for line in result.stdout.splitlines() if line.startswith("PASS Server Settings")))
