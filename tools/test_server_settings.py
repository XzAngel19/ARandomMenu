#!/usr/bin/env python3
"""Execute the real v191 "Server Settings" card against mocked services.

What this proves:

  * the card registers in Utilities, with the five actions and the two info
    options exactly once;
  * "Copy Job ID" copies the live Job ID (and still reports the id when the
    executor has no clipboard);
  * hoisting picks the smallest / the largest / any other public server from the
    decoded endpoint answer, never the server you are already in;
  * a failed HTTP read or an empty list is reported instead of teleporting;
  * the hop cooldown refuses a second hop in the same couple of seconds;
  * the readout only refreshes while the card is ON.

It does NOT prove that Roblox accepts the teleport: TeleportService is a mock.
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

script = r'''
local now = 0
os = { clock = function() return now end }
local function runDeferred()
    -- task.spawn in this module is only used for the hop body; run it inline.
end
task = {
    spawn = function(fn) fn() end,
    wait = function(seconds) now += seconds or 0 end,
    delay = function(seconds, fn) fn() end,
}

local notifications = {}
local function notify(message, kind) table.insert(notifications, { text = message, kind = kind }) end

local clipboard = {}
local setclipboard = function(text) table.insert(clipboard, text) end

local jobId = "abc123def456"
local placeId = 142823291

local players = { list = {}, MaxPlayers = 12 }
function players:GetPlayers() return self.list end
for index = 1, 5 do
    local player = { Name = "P" .. index }
    table.insert(players.list, player)
end
local LocalPlayer = { Name = "Me" }

local httpCalls = 0
-- httpAnswer is either nil (no answer), a function (a failing request) or the
-- decoded table the endpoint lists; HttpGet always returns JSON TEXT, exactly
-- like the real game:HttpGet.
local jsonPayload = nil
local httpAnswer = nil
local teleports = {}
local game = {
    JobId = jobId,
    PlaceId = placeId,
    GetService = function(_, name)
        if name == "HttpService" then
            -- A real HttpGet hands back the JSON TEXT; JSONDecode parses it.
            return {
                JSONDecode = function(_, body)
                    if body ~= "json" then error("not json: " .. tostring(body)) end
                    return jsonPayload
                end,
            }
        end
        if name == "TeleportService" then
            return {
                TeleportToPlaceInstance = function(_, place, job, player)
                    table.insert(teleports, { place = place, job = job, player = player })
                end,
                Teleport = function(_, place, player)
                    table.insert(teleports, { place = place, job = nil, player = player })
                end,
            }
        end
        if name == "Players" then return players end
        error("unexpected service " .. tostring(name))
    end,
}
function game:HttpGet(url)
    httpCalls += 1
    if type(httpAnswer) == "function" then
        return httpAnswer(url)
    end
    if httpAnswer == nil then
        error("no answer configured")
    end
    jsonPayload = httpAnswer
    return "json"
end

local function node(name) return { Name = name } end

local actions = {}
local toggles = {}
local numbers = {}
local information = {}
local featureConnections = {}
local function disconnectFeatureConnection(key) featureConnections[key] = nil end

local TaskManager = {
    Connect = function(_, fn)
        local connection = { fn = fn }
        function connection:Disconnect() self.gone = true end
        return connection
    end,
}

local function makeFeature(name, description, order, onToggle, options)
    local feature = {
        name = name,
        description = description,
        order = order,
        onToggle = onToggle,
        configuration = options,
        configKey = "Universal." .. name:gsub("%W", ""),
        enabled = false,
        status = nil,
    }
    function feature:SetStatus(text) self.status = text end
    return feature
end

local created = nil
local function createUniversalFeature(name, description, order, onToggle, options)
    created = makeFeature(name, description, order, onToggle, options)
    return created
end
local function addActionOption(feature, label, callback)
    actions[label] = { feature = feature, callback = callback }
end
local function addToggleOption(feature, label, default, callback, hint)
    toggles[label] = { feature = feature, default = default, callback = callback, hint = hint }
end
local function addNumberOption(feature, label, default, minimum, maximum, callback, hint, step, persist)
    numbers[label] = {
        default = default, min = minimum, max = maximum,
        callback = callback, hint = hint, step = step, persist = persist,
    }
end
local function addInformationOption(feature, text)
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

for _, label in ipairs({ "Copy Job ID", "Rejoin Server", "Hop: smallest server",
    "Hop: largest server", "Hop: random server" }) do
    assert(actions[label], "missing action: " .. label)
end
assert(toggles["Show server info"], "the readout toggle exists")
assert(numbers["Refresh every"], "the refresh slider exists")
eq(numbers["Refresh every"].default, 3, "refresh default")
eq(numbers["Refresh every"].min, 1, "refresh min")
eq(numbers["Refresh every"].max, 15, "refresh max")

-- CARD OFF => no status work at all, and no ticker.
eq(card.status, nil, "an OFF card writes no status")
eq(featureConnections.ServerSettingsTick, nil, "an OFF card owns no ticker")

-- CARD ON => the readout shows the short Job ID and the player count.
card.enabled = true
card.onToggle(true)
eq(card.status, "abc123de · 5/12", "readout shows job id and players")
assert(featureConnections.ServerSettingsTick, "an ON card owns its ticker")

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

-- Hopping: the endpoint answer lists other servers only.
local servers = {
    data = {
        { id = "small", playing = 2 },
        { id = "big", playing = 11 },
        { id = "mid", playing = 6 },
        { id = jobId, playing = 5 },
    },
}
httpAnswer = servers
actions["Hop: smallest server"].callback()
eq(#teleports, 1, "one teleport for a hop")
eq(teleports[1].job, "small", "smallest server chosen")
eq(teleports[1].place, placeId, "same place")
eq(teleports[1].player, LocalPlayer, "the local player is teleported")

-- The cooldown blocks an immediate second hop.
actions["Hop: largest server"].callback()
eq(#teleports, 1, "the hop cooldown refuses a second hop")
assert(string.find(notifications[#notifications].text, "Slow down"),
    "the cooldown explains itself: " .. tostring(notifications[#notifications].text))

now += 5
actions["Hop: largest server"].callback()
eq(#teleports, 2, "after the cooldown the hop happens")
eq(teleports[2].job, "big", "largest server chosen")

now += 5
local seen = {}
local function randomChoice()
    actions["Hop: random server"].callback()
    local chosen = teleports[#teleports].job
    assert(chosen ~= jobId, "the current server is never chosen")
    seen[chosen] = true
end
for _ = 1, 20 do
    now += 5
    randomChoice()
end
assert(seen.small or seen.big or seen.mid, "random hop picks a listed server")

-- A failed request must never teleport.
now += 5
httpAnswer = function() error("http blocked") end
local teleportsBefore = #teleports
actions["Hop: smallest server"].callback()
eq(#teleports, teleportsBefore, "a failed server list never teleports")
assert(string.find(notifications[#notifications].text, "Server hop"),
    "the failure is reported")

-- An empty list is reported too.
now += 5
httpAnswer = { data = { { id = jobId, playing = 5 } } }
actions["Hop: smallest server"].callback()
eq(#teleports, teleportsBefore, "no other server means no teleport")
assert(string.find(notifications[#notifications].text, "no other public server"),
    "the empty list is explained")

-- The ticker refreshes the readout, and turning the card off drops it.
httpAnswer = servers
players.list = { players.list[1] }
featureConnections.ServerSettingsTick.fn(10)
eq(card.status, "abc123de · 1/12", "an ON card refreshes its status")
card.enabled = false
card.onToggle(false)
eq(featureConnections.ServerSettingsTick, nil, "turning the card off disconnects the ticker")
eq(card.status, nil, "turning the card off clears the status")

-- Rejoin uses the current instance.
now += 5
local rejoinBefore = #teleports
actions["Rejoin Server"].callback()
eq(#teleports, rejoinBefore + 1, "rejoin teleports once")
eq(teleports[#teleports].job, jobId, "rejoin goes back to the same instance")

Module.destroy()
eq(state.serverSettingsCard, nil, "destroy clears the exported card")
print("PASS Server Settings: readout, clipboard, smallest/largest/random hop, cooldown, failures, rejoin")
'''

with tempfile.TemporaryDirectory(prefix="server-settings-") as temp:
    path = Path(temp) / "server_settings.luau"
    path.write_text(script, encoding="utf-8")
    result = subprocess.run(
        [os.environ.get("LUAU", "luau"), str(path)], capture_output=True, text=True
    )
    if result.returncode:
        raise SystemExit(f"Server Settings failed:\n{result.stdout[-6000:]}\n{result.stderr}")
    print(next(line for line in result.stdout.splitlines() if line.startswith("PASS Server Settings")))
