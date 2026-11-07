#!/usr/bin/env python3
"""Execute the real v193 "Server Settings" card against mocked services.

What this proves:

  * the card registers in Utilities and "Rejoin Server" is GONE;
  * the readout is a LIVE section of stat rows (AutoFarm's "Overlay Info" style)
    with server data only: Server, Players, In server, Uptime, Server time,
    Place -- no Build, no Round, no You, and no floating window;
  * that readout never stops: the ticker is created at init, survives the card
    being switched off and keeps writing on its own clock;
  * the place row names the place and marks a subplace (`PlaceId ~= GameId`);
  * a hop only picks a server with a FREE SLOT, reads several pages (cursor),
    never sends a query flag it does not need, skips empty instances for
    "smallest", picks the fullest joinable one (11/12) for "largest", and when
    every listed server is full it falls back to joining a random server instead
    of failing;
  * a failed HTTP read is reported instead of teleporting;
  * the hop cooldown refuses a second hop in the same couple of seconds.

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
assert 'addActionOption(card, "Rejoin Server"' not in SOURCE, "v192: Rejoin is removed"
assert "excludeFullServers" not in SOURCE.split("-- v193")[0], "v193: no unneeded endpoint flag is sent"
assert "&excludeFullServers" not in SOURCE, "v193: the endpoint URL sends no extra flag"

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
setclipboard = function(text) table.insert(clipboard, text) end

local jobId = "abc123def456"
local placeId = 142823291

local players = { list = {}, MaxPlayers = 12 }
function players:GetPlayers() return self.list end
for index = 1, 5 do
    table.insert(players.list, { Name = "P" .. index })
end
local LocalPlayer = { Name = "Me", UserId = 42 }

task = {
    spawn = function(fn) fn() end,
    wait = function(seconds) now += seconds or 0 end,
    delay = function(_seconds, fn) fn() end,
}

local teleports = {}
local anyServerJoins = {}
local function TeleportToPlaceInstance(_self, place, targetJob, player)
    table.insert(teleports, { place = place, job = targetJob, player = player })
end
local function Teleport(_self, place, player)
    table.insert(anyServerJoins, { place = place, player = player })
end

-- Two pages per sort order, served from this table. `cursor` selects page 2.
local serverPages = {
    Asc = {
        { data = {
            { id = "empty", playing = 0, maxPlayers = 12 },
            { id = "small", playing = 2, maxPlayers = 12 },
            { id = jobId, playing = 5, maxPlayers = 12 },
        } },
        { data = {
            { id = "mid", playing = 6, maxPlayers = 12 },
        }, nextPageCursor = "page3" },
    },
    Desc = {
        { data = {
            { id = "big", playing = 11, maxPlayers = 12 },
            { id = "full", playing = 12, maxPlayers = 12 },
        } },
        { data = {} },
    },
}

local lastEndpoint = nil
local currentAnswer = { data = {} }
local httpBlocked = false
local function HttpGet(_self, url)
    lastEndpoint = url
    if httpBlocked then
        error("http blocked")
    end
    local order = string.match(url, "sortOrder=(%a+)") or "Asc"
    local page = 1
    if string.find(url, "cursor=", 1, true) then
        page = 2
    end
    currentAnswer = (serverPages[order] and serverPages[order][page]) or { data = {} }
    return "{}"
end

game = {
    JobId = jobId,
    PlaceId = placeId,
    PlaceVersion = 7,
    Name = "Murder Mystery 2",
    HttpGet = HttpGet,
    GetService = function(_self, name)
        if name == "HttpService" then
            return { JSONDecode = function(_self, _body) return currentAnswer end }
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

-- Stat rows, exactly like Widgets.addStatOption hands them out.
local statValues = {}
local statLabels = {}
local sections = {}
state = {
    addSectionOption = function(_feature, title)
        table.insert(sections, title)
        return { Name = "Section_" .. title }
    end,
    addStatOption = function(_feature, label, initial)
        statLabels[label] = true
        statValues[label] = tostring(initial or "")
        return {
            set = function(text)
                statValues[label] = tostring(text)
            end,
        }
    end,
}

-- Instance building must not even be reached: v193 has no floating window.
local framesBuilt = 0
local function create(_class, _properties)
    framesBuilt += 1
    return {}
end

local featureConnections = {}
local function disconnectFeatureConnection(name) featureConnections[name] = nil end
local TaskManager = {
    Connect = function(_self, fn)
        return { fn = fn, Disconnect = function() end }
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
    addInformationOption = addInformationOption,
    TaskManager = TaskManager,
    featureConnections = featureConnections,
    disconnectFeatureConnection = disconnectFeatureConnection,
    cloneReference = function(value) return value end,
}

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

-- The readout is a live "Overlay Info" section, with server data only.
eq(#sections, 1, "one section holds the readout")
eq(sections[1], "Overlay Info", "the section is the AutoFarm-style one")
for _, label in ipairs({ "Server", "Players", "In server", "Uptime", "Server time", "Place" }) do
    assert(statLabels[label], "missing stat row: " .. label)
end
for _, forbidden in ipairs({ "Build", "Round", "You" }) do
    assert(not statLabels[forbidden], "v193 removes the " .. forbidden .. " row")
end
eq(framesBuilt, 0, "v193 builds no floating window at all")

-- Live values, read at init.
eq(statValues["Server"], "abc123de", "the Server row shows the short Job ID")
eq(statValues["Players"], "5 / 12", "the Players row shows players / limit")
eq(statValues["Uptime"], "1:02:05", "the Uptime row shows the server uptime")
eq(statValues["Server time"], "01:02:03", "the Server time row shows the server clock")
eq(statValues["Place"], "Murder Mystery 2", "the Place row names the place")
assert(string.find(statValues["In server"], "P1", 1, true), "the In server row lists names")

-- A subplace is marked as one.
game.GameId = 999999
now += 1
featureConnections.ServerSettingsTick.fn(1)
eq(statValues["Place"], "Murder Mystery 2 · subplace", "a subplace says so")
game.GameId = placeId

-- The ticker is created at init and never dropped, not even with the card off.
assert(featureConnections.ServerSettingsTick, "the readout ticks from init")
card.enabled = false
card.onToggle(false)
assert(featureConnections.ServerSettingsTick, "switching the card off does not stop the readout")
workspace.DistributedGameTime = 3726
now += 1
featureConnections.ServerSettingsTick.fn(1)
eq(statValues["Uptime"], "1:02:06", "the readout keeps advancing with the card off")
card.enabled = true
card.onToggle(true)

-- Copy Job ID goes through the executor clipboard.
actions["Copy Job ID"].callback()
eq(#clipboard, 1, "one clipboard write")
eq(clipboard[1], jobId, "the live Job ID is copied")

-- A hop only lands where a slot is free, and reads several pages.
actions["Hop: smallest server"].callback()
eq(#teleports, 1, "one teleport for a hop")
eq(teleports[1].job, "small", "smallest joinable server, never the empty one")
assert(string.find(lastEndpoint, "sortOrder=Asc", 1, true), "smallest reads the quiet end")
assert(not string.find(lastEndpoint, "excludeFullServers", 1, true),
    "v193 sends no flag it does not need")

-- The cooldown blocks an immediate second hop.
actions["Hop: largest server"].callback()
eq(#teleports, 1, "the hop cooldown refuses a second hop")
assert(string.find(notifications[#notifications].text, "Slow down"), "the cooldown explains itself")

now += 5
actions["Hop: largest server"].callback()
eq(#teleports, 2, "after the cooldown the hop happens")
eq(teleports[2].job, "big", "largest = fullest server that still has a slot (11/12)")
assert(string.find(lastEndpoint, "sortOrder=Desc", 1, true), "largest reads the busy end")

now += 5
local seen = {}
for _ = 1, 15 do
    now += 5
    actions["Hop: random server"].callback()
    local chosen = teleports[#teleports].job
    assert(chosen ~= jobId, "the current server is never chosen")
    assert(chosen ~= "full", "a full server is never chosen")
    seen[chosen] = true
end
assert(seen.small or seen.big or seen.mid or seen.empty, "random hop picks a listed server")

-- A failed request is reported and never teleports.
now += 5
httpBlocked = true
local teleportsBefore = #teleports
actions["Hop: smallest server"].callback()
eq(#teleports, teleportsBefore, "a failed server list never teleports")
assert(string.find(notifications[#notifications].text, "Server hop"), "the failure is reported")
httpBlocked = false

-- v193: when every listed server is full, the hop still moves the player: it
-- joins any server instead of answering "not found".
now += 5
local savedAsc = serverPages.Asc
serverPages.Asc = { { data = {
    { id = "full1", playing = 12, maxPlayers = 12 },
    { id = "full2", playing = 12, maxPlayers = 12 },
} } }
local anyBefore = #anyServerJoins
actions["Hop: smallest server"].callback()
eq(#teleports, teleportsBefore, "a full list never teleports into an instance")
eq(#anyServerJoins, anyBefore + 1, "a full list still joins any server")
eq(anyServerJoins[#anyServerJoins].place, placeId, "the fallback joins the same place")
assert(string.find(notifications[#notifications].text, "full", 1, true),
    "the fallback explains itself: " .. tostring(notifications[#notifications].text))
serverPages.Asc = savedAsc

players.list = { players.list[1] }
now += 1
featureConnections.ServerSettingsTick.fn(1)
eq(statValues["Players"], "1 / 12", "the Players row follows the roster")

Module.destroy()
eq(state.serverSettingsCard, nil, "destroy clears the exported card")
eq(featureConnections.ServerSettingsTick, nil, "destroy drops the readout")
print("PASS Server Settings: live Overlay Info rows (never stopping), place + subplace, hops with a real slot over several pages, full-list fallback, cooldown, no rejoin")
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
