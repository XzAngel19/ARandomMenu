#!/usr/bin/env python3
"""Pure X2 Duels rules plus native-combat integration contracts.

These tests do not claim live Roblox validation. They lock down conservative
team/result decisions and ensure the module never invents combat packets.
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RULES = ROOT / "src" / "games" / "X2Duels" / "Rules.lua"
BASE = ROOT / "src" / "games" / "X2Duels" / "base.lua"
AUTOFARM = ROOT / "src" / "games" / "X2Duels" / "Other" / "AutoFarm.lua"
TRIGGERBOT = ROOT / "src" / "games" / "universal" / "Combat" / "TriggerBot.lua"
DECOMPILER = ROOT / "tools" / "X2DuelsDecompiler.luau"
LUAU_COMPILE = os.environ.get("LUAU_COMPILE", str(ROOT / "tools" / "luau" / "bin" / "luau-compile"))
LUAU = os.environ.get("LUAU", str(ROOT / "tools" / "luau" / "bin" / "luau"))

PRELUDE = r'''
local failures = 0
local checks = 0
local function check(label, actual, expected)
    checks += 1
    if actual ~= expected then
        failures += 1
        print("FAIL " .. label .. ": got " .. tostring(actual)
            .. " expected " .. tostring(expected))
    end
end

local RULES_SOURCE = [=====[
'''

EPILOGUE = r'''
]=====]
local chunk, compileError = loadstring(RULES_SOURCE, "@src/games/X2Duels/Rules.lua")
assert(type(chunk) == "function", tostring(compileError))
local rules = chunk()

check("trim/case token", rules.normalizeToken("  Sheriff  "), "sheriff")
check("false match is absent", rules.normalizeToken(false), nil)
check("false string is absent", rules.normalizeToken("false"), nil)
check("__none sentinel is absent", rules.normalizeToken("__none"), nil)
check("numeric team token", rules.normalizeToken(2), "2")
check("Team object token", rules.normalizeToken({Name = "Blue"}), "blue")
check("valid MVS team token", rules.normalizeTeamToken("TeamRed"), "teamred")
check("FFA is not a team", rules.normalizeTeamToken("FFA"), nil)
check("lobby is not a team", rules.normalizeTeamToken("Lobby"), nil)
check("neutral is not a team", rules.normalizeTeamToken("Neutral"), nil)

check("known match requires same id", rules.sameMatch("match-a", "match-a"), true)
check("known match rejects other id", rules.sameMatch("match-a", "match-b"), false)
check("known match rejects missing id", rules.sameMatch("match-a", nil), false)
check("missing local match permits manual aim", rules.sameMatch(nil, "match-a"), true)
check("confirmed teammate", rules.relation("red", "red", true), "Teammate")
check("confirmed enemy", rules.relation("red", "blue", true), "Enemy")
check("unknown side", rules.relation("red", nil, true), "Unknown")
check("shared FFA is unknown, not teammate", rules.relation("FFA", "FFA", true), "Unknown")
check("shared lobby is unknown, not teammate", rules.relation("Lobby", "Lobby", true), "Unknown")
check("outside match", rules.relation("red", "blue", false), "Outside")

check("team check accepts enemy", rules.isOpponent("red", "blue", true, true), true)
check("team check protects teammate", rules.isOpponent("red", "red", true, true), false)
check("team check fails closed for unknown", rules.isOpponent("red", nil, true, true), false)
check("team check fails closed for local unknown", rules.isOpponent(nil, "blue", true, true), false)
check("outside match is never target", rules.isOpponent("red", "blue", false, false), false)
check("explicit team-check off allows same-side target", rules.isOpponent("red", "red", true, false), true)

check("default gun", rules.classifyTool("DefaultGun"), "Gun")
check("uzi skin", rules.classifyTool("BlingUzi"), "Gun")
check("lightburst skin", rules.classifyTool("InterstellarLightburst"), "Gun")
check("shot skin", rules.classifyTool("DuskwingShot"), "Gun")
check("default knife", rules.classifyTool("DefaultKnife"), "Knife")
check("sword skin", rules.classifyTool("BlingSword"), "Knife")
check("fang skin", rules.classifyTool("DuskwingFang"), "Knife")
check("cometfall skin", rules.classifyTool("InterstellarCometfall"), "Knife")
check("unknown tool is not forced to knife", rules.classifyTool("Radio"), nil)
check("gun structure fallback", rules.classifyTool("Skin", true, false), "Gun")
check("knife structure fallback", rules.classifyTool("Skin", false, true), "Knife")

check("Play Again text", rules.isPlayAgainText("Play Again"), true)
check("PlayAgainButton name", rules.isPlayAgainText("PlayAgainButton"), true)
check("Rematch text", rules.isPlayAgainText("Rematch"), true)
check("RematchButton name", rules.isPlayAgainText("RematchButton"), true)
check("Queue Again text", rules.isPlayAgainText("Queue Again"), true)
check("plain Play is not Play Again", rules.isPlayAgainText("Play"), false)
check("teleport is not a button label", rules.isPlayAgainText("RematchTeleport"), false)
check("empty label", rules.isPlayAgainText(""), false)

check("victory label", rules.isVictoryText("VICTORY!"), true)
check("you won label", rules.isVictoryText("You Won"), true)
check("defeat is not victory", rules.isVictoryText("Defeat"), false)
check("generic winner prefix is not enough", rules.isVictoryText("Winner: Enemy"), false)
check("local victory GUI label", rules.isLocalVictoryLabel("VICTORY!"), true)
check("local you-won GUI label", rules.isLocalVictoryLabel("You Won"), true)
check("generic Winner GUI label is ambiguous", rules.isLocalVictoryLabel("Winner"), false)
check("generic Win GUI label is ambiguous", rules.isLocalVictoryLabel("Win"), false)

local localPlayer = {Name = "Local", DisplayName = "Local Display", UserId = 101}
local identity = {
    player = localPlayer,
    userId = 101,
    name = "Local",
    displayName = "Local Display",
    team = "red",
}
check("winner Player", rules.didLocalWin({{Winner = localPlayer}}, identity, false), true)
check("winner user id", rules.didLocalWin({{Winner = 101}}, identity, false), true)
check("winner team", rules.didLocalWin({{WinningTeam = "Red"}}, identity, false), true)
check("nested winner team", rules.didLocalWin({{Data = {WinningTeam = {Name = "Red"}}}}, identity, false), true)
check("winner list", rules.didLocalWin({{Winners = {{UserId = 202}, {UserId = 101}}}}, identity, false), true)
check("local outcome", rules.didLocalWin({{Result = "Victory"}}, identity, false), true)
check("local won flag", rules.didLocalWin({{Won = true}}, identity, false), true)
check("direct win-notification team", rules.didLocalWin({"Red", 3}, identity, true), true)
check("direct notification requires opt-in", rules.didLocalWin({"Red", 3}, identity, false), false)
check("defeat overrides direct identity", rules.didLocalWin({"Local", "Defeat"}, identity, true), false)
check("ambiguous result is not a win", rules.didLocalWin({{}}, identity, false), false)
check("enemy result is not a local win", rules.didLocalWin({{UserId = 202, Won = true}}, identity, false), false)
check("enemy nested result is not a local win", rules.didLocalWin({{Players = {{UserId = 202, Won = true}, {UserId = 101, Won = false}}}}, identity, false), false)
check("enemy nested outcome retains identity", rules.didLocalWin({{UserId = 202, Data = {Outcome = "Win"}}}, identity, false), false)
local function resultPage(outcome)
    return {"match-guid", {{Page = "RoundInfo", Data = {Outcome = outcome}}}}
end
check("real result Win", rules.matchResultOutcome(resultPage("Win")), "Win")
check("empty match ID is not a final win", rules.matchResultOutcome({"", {{Page = "RoundInfo", Data = {Outcome = "Win"}}}}), nil)
check("real result Loss", rules.matchResultOutcome(resultPage("Loss")), "Loss")
check("draw is neutral", rules.matchResultOutcome(resultPage("Draw")), "Neutral")
check("forfeit is not a round win", rules.matchResultOutcome(resultPage("Forfeit")), "Neutral")
check("cancelled is neutral", rules.matchResultOutcome(resultPage("Cancelled")), "Neutral")
check("unrecognized schema", rules.matchResultOutcome({{Winner = "Red"}}), nil)
check("MVP alone is not a win", rules.didLocalWin({{MVP = localPlayer}}, identity, false), false)
check("enemy winner is not local", rules.didLocalWin({{Winner = 202}}, identity, false), false)

print(string.format("X2Duels rules: %d checks, %d failures", checks, failures))
if failures > 0 then
    error(string.format("%d X2Duels checks failed", failures))
end
'''


def run_luau_tests() -> None:
    harness = PRELUDE + RULES.read_text(encoding="utf-8") + EPILOGUE
    (ROOT / "build").mkdir(exist_ok=True)
    handle = tempfile.NamedTemporaryFile(
        "w", suffix=".luau", prefix="x2duels-", dir=ROOT / "build",
        encoding="utf-8", delete=False,
    )
    try:
        with handle:
            handle.write(harness)
        result = subprocess.run(
            [LUAU, handle.name], text=True, cwd=ROOT,
            capture_output=True, check=False,
        )
    finally:
        Path(handle.name).unlink(missing_ok=True)
    if result.returncode:
        raise SystemExit(result.stdout + result.stderr)
    print(result.stdout.strip())


def require(source: str, needle: str, label: str) -> None:
    if needle not in source:
        raise AssertionError(f"missing {label}: {needle}")


def forbid(source: str, needle: str, label: str) -> None:
    if needle in source:
        raise AssertionError(f"forbidden {label}: {needle}")


def run_integration_contracts() -> None:
    base = BASE.read_text(encoding="utf-8")
    farm = AUTOFARM.read_text(encoding="utf-8")
    trigger = TRIGGERBOT.read_text(encoding="utf-8")
    decompiler = DECOMPILER.read_text(encoding="utf-8")
    wurst = (ROOT / "src" / "Wurst.lua").read_text(encoding="utf-8")

    # Only the captured zero-argument native Rematch vote may be sent; never
    # fabricate/replay gun, knife, hit or event packets from remote names.
    if base.count(":FireServer(") != 1:
        raise AssertionError("unexpected outgoing X2 remote calls")
    require(base, 'Packages/Networking/RE/Rematch/RematchVote', "captured rematch vote")
    require(base, '(remote :: any):FireServer()', "zero-argument rematch vote")
    forbid(base, 'queue_again', "rematch is not requeue")
    forbid(farm, ":FireServer(", "unverified pumpkin remote request")
    forbid(base, "host.mouse1press", "desktop-only firing")
    forbid(base, "pcall(mouse1press", "desktop-only firing")
    forbid(base, "VirtualInputManager", "GUI automation in the combat module")
    forbid(base, "queueGunBurst", "unverified combat burst")
    forbid(base, "burstRemaining", "unverified combat burst state")
    require(base, "tool:Activate()", "native mobile-compatible activation")
    require(base, "local function fireGun", "shared native gun adapter")
    require(base, "local function fireKnife", "shared native knife adapter")
    require(base, "mouse2press", "desktop knife throw input")
    forbid(base, 'SetAttribute("ForceThrow", true)', "unobserved touch knife attribute")
    require(base, 'mobile:FindFirstChild("ThrowMode")', "native touch knife state")
    require(base, "pending.previousThrowMode", "touch knife state restoration")
    require(base, "discoverMatchState()", "native replicated MatchState discovery")
    require(base, "getcallingscript", "scoped weapon call provenance")
    require(base, "local function redirectKnifeThrow", "observed knife destination hook")
    require(base, "Packages/Networking/RE/Combat/Killed", "observed kill event")
    require(base, '{"Legit", "Silent"}', "Legit/Silent modes")
    require(base, "state.bindFeatureActivationKey", "MM2-style action key binding")
    forbid(base, 'settings.senderMode', "obsolete Button/CFrame gate")
    forbid(base, 'settings.silentAim and settings.autoShoot', "Silent-gated Auto Shoot")
    forbid(base, 'settings.silentAim and settings.knifeThrow', "Silent-gated Knife Throw")
    require(base, 'autoShootCard = card(', "standalone Auto Shoot")
    require(base, 'knifeThrowCard = card(', "standalone Knife Throw")
    require(base, '"Auto Win",', "Auto Win combat card")
    for label in ("Time Spent", "Duels Won", "Current Game mode", "Safe Place", "Revancha"):
        require(base, f'"{label}"', f"Auto Win {label}")
    require(base, 'outcome == "Win" and settings.autoWin', "final-duel-only wins")
    require(base, 'runtimeState.seenResultIds[resultId]', "per-match result deduplication")
    require(base, 'values.TryIndex', "real rematch state")
    require(base, 'rematch.active ~= true', "active rematch gate")
    require(base, 'rematch.cancelled == true', "cancelled rematch gate")
    require(base, 'local function updateSafePlace', "match-bound safe place")
    require(base, 'local function leaveSafePlace', "safe place cleanup")
    require(base, 'local function activeRound', "automatic fight round gate")
    require(base, 'local function registerLoss', "legacy observed local loss counter")
    require(base, 'Packages/Networking/RE/Combat/DestroyBody', "observed kill event")
    forbid(base, '"Trigger Bot"', "duplicate X2 TriggerBot card")
    require(base, '"Hitbox",', "singular Hitbox card")
    require(base, '"Exploits"', "Hitbox Exploits category")
    require(base, 'settings.hitboxTeamCheck', "independent hitbox team check")
    require(base, 'record.part.CanQuery = record.canQuery', "query property restore")
    require(base, "registerTeamProvider", "shared Wurst team provider")
    require(base, "registerRoleProvider", "MVS role colours for universal ESP")
    require(base, "GetRelation", "tri-state MVS team relation")
    require(base, "RoleColors = ROLE_COLORS", "shared MVS role palette")
    require(base, "rules.normalizeTeamToken", "FFA/lobby team sentinel guard")
    require(base, "playerFromEvent(arguments)", "respawn player argument discovery")
    require(base, "RE/Match/SetDead", "native death event")
    require(base, "restoreAllHitboxes()", "hitbox restoration")
    require(base, "uninstallHooks()", "silent-hook cleanup")
    require(base, "Packages/Networking/RE/Match/MatchResults", "results event")
    require(base, "Packages/Networking/RE/Match/RemovePlayer", "round-ended event")
    require(base, "Packages/Networking/RE/Match/PlayerRespawned", "round event")

    require(trigger, "host.state.x2duelsCore", "single TriggerBot X2 adapter")
    require(trigger, "x2Core.equippedTool()", "TriggerBot equipped Gun/Knife")
    require(trigger, "x2Core.fireGun(target, true)", "TriggerBot shared gun without camera aim")
    require(trigger, "x2Core.fireKnife(target, true)", "TriggerBot shared knife without camera aim")
    require(farm, 'FindFirstChild("SpawnablesClient")', "event spawnable folder")
    require(farm, 'collection.GetTagged, collection, "Pumpkin"', "tagged event model discovery")
    require(farm, '(instance :: Model).PrimaryPart', "invisible event Touch part")
    forbid(farm, 'string.match(instance.Name, "^PumpkinCurrency_%d+$")', "decorative pumpkins as pickups")
    require(farm, "claimRoundTeamFromPodiums", "podium team resolution")
    require(farm, "playerFromValue", "StringValue/ObjectValue player resolution")
    require(farm, "nearestOwned", "owned farm selection")
    require(farm, "currencyCFrame: CFrame = part.CFrame", "currency CFrame teleport")
    require(farm, "if not roundStarted then", "round team fail-closed gate")
    require(farm, "TouchTransmitter", "invisible PumpCoins interaction")
    require(farm, "host.firetouchinterest", "native pumpkin contact")
    require(farm, "restoreSavedPosition()", "farm position cleanup")
    require(farm, 'categoryName = "Utilities"', "Auto Farm Utilities category")

    require(wurst, '[124848751642883] = "X2Duels"', "1v1 PlaceId registration")
    require(wurst, '[92876937625630] = "X2Duels"', "current PlaceId registration")
    require(wurst, '[135856908115931] = "X2Duels"', "legacy MVS PlaceId registration")
    require(wurst, 'X2DuelsActive = ACTIVE_GAME_MODULE == "X2Duels"', "GAME_CHECK")
    require(wurst, '"src/games/X2Duels/Rules.lua"', "rules loader path")
    require(wurst, '"src/games/X2Duels/base.lua"', "base loader path")
    require(wurst, '"src/games/X2Duels/Other/AutoFarm.lua"', "farm loader path")
    forbid(wurst, '"src/games/X2Duels/Render/TeamESP.lua"', "separate Team ESP loader")
    require(wurst, '"SetDead"', "current MVS match fingerprint")
    require(wurst, '"LegacyClientScripts"', "current MVS client fingerprint")
    require(wurst, 'provider.GetRelation', "tri-state global team analysis")

    require(decompiler, "remote-calls.jsonl", "remote call capture")
    require(decompiler, "parent = parentPath(remote)", "remote parent capture")
    require(decompiler, "arguments = serialize(arguments)", "remote argument capture")
    require(decompiler, "environment.decompile", "executor decompiler")
    require(decompiler, "environment.getscriptbytecode", "bytecode fallback")
    require(decompiler, "return oldNamecall(self, ...)", "unmodified remote forwarding")
    forbid(decompiler, "loadstring(", "captured-code execution")
    compiled = subprocess.run(
        [LUAU_COMPILE, str(DECOMPILER)], cwd=ROOT,
        capture_output=True, text=True, check=False,
    )
    if compiled.returncode:
        raise SystemExit(compiled.stdout + compiled.stderr)

    for place_id in (124848751642883, 92876937625630, 135856908115931):
        profile = ROOT / "src" / "Profile" / f"{place_id}.lua"
        text = profile.read_text(encoding="utf-8")
        require(text, 'key = "X2Duels"', f"profile {place_id}")
        require(text, '"MVSD"', f"existing MVS section {place_id}")
    print("X2Duels architecture, MM2 structure, farm, TriggerBot and decompiler contracts: PASS")

def run_bundle_boot() -> None:
    """Boot the real stamped bundle as X2 Duels and exercise card cleanup."""
    sys.path.insert(0, str(ROOT / "tools"))
    import audit_menu

    generated = audit_menu.build(debug=True).read_text(encoding="utf-8")
    place_anchor = "game = {\n    PlaceId = 142823291,\n    GameId = 20260716,"
    if generated.count(place_anchor) != 1:
        raise AssertionError("full-boot game PlaceId anchor changed")
    generated = generated.replace(
        place_anchor,
        "game = {\n    PlaceId = 124848751642883,\n    GameId = 20260716,",
        1,
    )
    remote_setup = r'''
local x2Replicated = game:GetService("ReplicatedStorage")
local function x2Folder(parent, name)
    local existing = parent:FindFirstChild(name)
    if existing then return existing end
    local folder = Instance.new("Folder")
    folder.Name = name
    folder.Parent = parent
    return folder
end
local x2Packages = x2Folder(x2Replicated, "Packages")
X2Networking = x2Folder(x2Packages, "Networking")
X2Net = x2Folder(x2Packages, "Net")
local function x2Remote(name)
    local remote = Instance.new("RemoteEvent")
    remote.Name = name
    remote.Parent = X2Networking -- literal slash-containing names, as in the RBXL
    return remote
end
X2MatchResults = x2Remote("RE/Match/MatchResults")
X2RemovePlayer = x2Remote("RE/Match/RemovePlayer")
X2WinNotification = x2Remote("RE/Match/WinNotification")
X2SetDead = x2Remote("RE/Match/SetDead")
X2PlayerRespawned = x2Remote("RE/Match/PlayerRespawned")
X2Killed = x2Remote("RE/Combat/Killed")
X2DestroyBody = x2Remote("RE/Combat/DestroyBody")
X2RematchVote = x2Remote("RE/Rematch/RematchVote")
HarnessRematchVotes = {}
X2RematchVote.FireServer = function(_self, ...)
    table.insert(HarnessRematchVotes, table.pack(...))
end
HarnessRematch = {active = false, cancelled = false, voters = {}}
local x2Local = game:GetService("Players").LocalPlayer
if x2Local.PlayerGui then x2Local.PlayerGui.Parent = x2Local end
local modules = x2Folder(x2Folder(x2Replicated, "Client"), "Modules")
HarnessMatchModule = Instance.new("ModuleScript")
HarnessMatchModule.Name = "MatchState"
HarnessMatchModule.Parent = modules
HarnessGlobalsModule = Instance.new("ModuleScript")
HarnessGlobalsModule.Name = "ClientGlobals"
HarnessGlobalsModule.Parent = modules
HarnessMatchReady = false
HarnessGame = {Phase = "InGame", RoundStarted = true, CurrentRoundEnded = false,
    MatchId = "HarnessMapOne"}
local globalsApi = {GameValues = {TryIndex = function(_self, path)
    if path[1] == "Rematch" then return HarnessRematch end
end}}
HarnessMatchData = {
    [x2Local] = {gameId = "HarnessMatchOne", team = "Red", mode = "TeamBased", dead = false},
    [HarnessHeroGuy] = {gameId = "HarnessMatchOne", team = "Blue", mode = "TeamBased", dead = false},
}
local matchApi = {
    getGameId = function(player) return HarnessMatchData[player] and HarnessMatchData[player].gameId end,
    getTeamId = function(player) return HarnessMatchData[player] and HarnessMatchData[player].team end,
    getMode = function(player) return HarnessMatchData[player] and HarnessMatchData[player].mode end,
    isDead = function(player) return HarnessMatchData[player] and HarnessMatchData[player].dead end,
    getGame = function(player)
        return HarnessMatchData[player] and HarnessMatchData[player].gameId and HarnessGame or nil
    end,
    getMatchId = function(player)
        return HarnessMatchData[player] and HarnessMatchData[player].gameId and HarnessGame.MatchId or nil
    end,
}
local originalRequire = require
require = function(module)
    if module == HarnessMatchModule then
        if not HarnessMatchReady then error("MatchState dependency not ready") end
        return matchApi
    elseif module == HarnessGlobalsModule then
        return globalsApi
    end
    return originalRequire(module)
end
-- Misleading attributes must not override replicated MatchState.
x2Local:SetAttribute("Team", "Blue")
x2Local:SetAttribute("Game", "stale-lobby")
HarnessHeroGuy:SetAttribute("Team", "Blue")
HarnessHeroGuy:SetAttribute("Game", "stale-lobby")
'''
    boot_anchor = "\nlocal ok, err = pcall(function()\n"
    if generated.count(boot_anchor) != 1:
        raise AssertionError("full-boot remote setup anchor changed")
    generated = generated.replace(boot_anchor, "\n" + remote_setup + boot_anchor, 1)
    generated += r'''
local expected = {
    ["Auto Farm"] = true,
    ["Auto Win"] = true,
    ["Silent AIM"] = true,
    ["Auto Shoot"] = true,
    ["Knife Throw"] = true,
    ["Kill Aura"] = true,
    ["Hitbox"] = true,
}
local seen = {}
local featuresByName = {}
local x2CardCount = 0
for _, feature in ipairs(ex.allFeatures) do
    if feature.sectionName == "MVSD" then
        x2CardCount += 1
        assert(expected[feature.name], "unexpected/duplicate X2 card: " .. feature.name)
        assert(not seen[feature.name], "duplicate X2 card: " .. feature.name)
        seen[feature.name] = true
        featuresByName[feature.name] = feature
        local enabled, enableError = pcall(feature.onToggle, true)
        assert(enabled, "X2 enable " .. feature.name .. ": " .. tostring(enableError))
        local disabled, disableError = pcall(feature.onToggle, false)
        assert(disabled, "X2 disable " .. feature.name .. ": " .. tostring(disableError))
    end
end
assert(x2CardCount == 7, "expected exactly seven X2 cards, got " .. tostring(x2CardCount))
for name, _ in pairs(expected) do
    assert(seen[name], "X2 card did not boot: " .. name)
end
assert(not ex.state.toggleControls["MVSD.SilentAIM.AutoShoot"]
    and not ex.state.toggleControls["MVSD.SilentAIM.KnifeThrow"],
    "Auto Shoot/Knife Throw are still nested under Silent AIM")
for _, name in ipairs({"AutoShoot", "KnifeThrow", "Hitbox"}) do
    assert(ex.state.toggleControls["MVSD." .. name .. ".TeamCheck"],
        name .. " has no independent Team Check")
end
for _, name in ipairs({"AutoShoot", "KnifeThrow"}) do
    assert(ex.state.toggleControls["MVSD." .. name .. ".WallCheck"]
        and ex.state.valueControls["MVSD." .. name .. ".Range"]
        and ex.state.valueControls["MVSD." .. name .. ".Cooldown"],
        name .. " has no independent Wall Check/Range/Cooldown")
end
assert(ex.state.toggleControls["MVSD.AutoWin.SafePlace"]
    and ex.state.toggleControls["MVSD.AutoWin.Revancha"],
    "Auto Win options missing")
assert(featuresByName["Auto Win"].categoryName == "Utilities",
    "Auto Win is not in Utilities")
assert(featuresByName["Auto Farm"].categoryName == "Utilities",
    "Auto Farm is not in Utilities")
assert(featuresByName["Silent AIM"].categoryName == "Combat",
    "Silent AIM left Combat")
assert(ex.state.x2duelsCore and ex.state.x2duelsRules,
    "X2 shared core/rules were not published")
assert(ex.state.gameBridge.teamProvider
    and ex.state.gameBridge.teamProvider.Name == "X2Duels",
    "X2 team provider was not registered")
assert(ex.state.gameBridge.roleProvider
    and ex.state.gameBridge.roleProvider.Name == "X2Duels"
    and ex.state.gameBridge.roleProvider.ReplacesTeams == false,
    "X2 role colours must preserve the Team Check filters")

local silentFeature = featuresByName["Silent AIM"]
local modeControl = ex.state.valueControls["MVSD.SilentAIM.Mode"]
assert(modeControl and modeControl.apply, "Silent AIM Mode control was not created")
modeControl.apply("Silent")
modeControl.apply("Legit")
assert(not featuresByName["Auto Shoot"].enabled and not featuresByName["Knife Throw"].enabled,
    "fresh boot unexpectedly enabled combat")

-- Shapes below follow the captured 1v1 log and decompiled client. These are
-- still mocks, not a claim about live server damage or reward authority.
local core = ex.state.x2duelsCore
local coreHandle = ex.featureConnections.X2DuelsCore
local coreTask = nil
for _, scheduled in pairs(ex.TaskManager.tasks) do
    if scheduled.handle == coreHandle then
        coreTask = scheduled
        break
    end
end
assert(coreTask, "X2 core callback was not registered")

-- Native adapter behavior: a Backpack gun must be equipped by fireGun.
-- The mock Tool records real Activate calls; it does not prove server damage.
local nativeLocal = game:GetService("Players").LocalPlayer
local nativeBackpack = nativeLocal:FindFirstChildOfClass("Backpack")
local nativeHumanoid = nativeLocal.Character:FindFirstChildOfClass("Humanoid")
nativeHumanoid.EquipTool = function(_self, tool)
    for _, item in ipairs(nativeLocal.Character:GetChildren()) do
        if item:IsA("Tool") and item ~= tool then item.Parent = nativeBackpack end
    end
    tool.Parent = nativeLocal.Character
end
local nativeGun = Instance.new("Tool")
nativeGun.Name = "Gun"
nativeGun.Enabled = true
local nativeGunShots = 0
nativeGun.Activate = function() nativeGunShots += 1 end
nativeGun.Parent = nativeBackpack
local nativeKnife = Instance.new("Tool")
nativeKnife.Name = "Knife"
nativeKnife.Enabled = true
local nativeKnifeShots = 0
nativeKnife.Activate = function() nativeKnifeShots += 1 end
nativeKnife.Parent = nativeBackpack
nativeKnife.Name = "Orchid"
game:GetService("CollectionService"):AddTag(nativeKnife, "Knife")
assert(core.toolKind(nativeKnife) == "Knife", "tagged skin without a knife name was missed")
game:GetService("CollectionService"):RemoveTag(nativeKnife, "Knife")
nativeKnife.Name = "Knife"
local nativeTarget = core.targetFor(HarnessHeroGuy)
assert(nativeTarget, "native target fixture missing")
assert(not core.isEnemy(HarnessHeroGuy), "loading MatchState fell back to stale lobby attributes")
HarnessMatchReady = true
coreTask.callback(0.1) -- retries the initially unavailable module
assert(core.relation(HarnessHeroGuy) == "Enemy", "replicated enemy side was not resolved")
assert(core.isEnemy(HarnessHeroGuy), "resolved MVS enemy was rejected")
nativeLocal:SetAttribute("Dead", true)
assert(core.isAlive(nativeLocal), "stale Dead attribute overrode replicated MatchState")
nativeLocal:SetAttribute("Dead", nil)
assert(ex.state.teamCheck.analyze(HarnessHeroGuy).hostile == true,
    "global team check did not accept a confirmed enemy")
HarnessMatchData[HarnessHeroGuy].team = "Red"
assert(core.relation(HarnessHeroGuy) == "Teammate" and not core.isEnemy(HarnessHeroGuy),
    "native teammate was not protected")
HarnessMatchData[HarnessHeroGuy].team = "Blue"
HarnessMatchData[HarnessHeroGuy].gameId = "DifferentGame"
assert(not core.isEnemy(HarnessHeroGuy), "another game became a target")
HarnessMatchData[HarnessHeroGuy].gameId = nil
assert(not core.isEnemy(HarnessHeroGuy), "missing game became a target")
HarnessMatchData[nativeLocal].gameId = nil
assert(not core.isEnemy(HarnessHeroGuy), "two lobby nil GameIds were treated as the same game")
HarnessMatchData[nativeLocal].gameId = "HarnessMatchOne"
HarnessMatchData[HarnessHeroGuy].gameId = "HarnessMatchOne"
HarnessMatchData[nativeLocal].mode = "FFA"
assert(core.relation(HarnessHeroGuy) == "Enemy" and core.isEnemy(HarnessHeroGuy),
    "same-game FFA opponent was not resolved")
HarnessMatchData[nativeLocal].mode = "TeamBased"
HarnessMatchData[HarnessHeroGuy].dead = true
assert(not core.isEnemy(HarnessHeroGuy), "replicated dead target remained selectable")
HarnessMatchData[HarnessHeroGuy].dead = false
X2SetDead.OnClientEvent:Fire(HarnessHeroGuy)
assert(not core.isEnemy(HarnessHeroGuy), "SetDead target remained selectable")
X2PlayerRespawned.OnClientEvent:Fire(nil, HarnessHeroGuy)
assert(core.isEnemy(HarnessHeroGuy),
    "second-argument Player respawn did not clear the dead state")
local nativePreviousWallCheck = core.settings.wallCheck
core.settings.wallCheck = false -- isolate native activation from the mock Raycast
local nativePreviousClock = os.clock
local nativeNow = math.max(nativePreviousClock(), 10)
os.clock = function() return nativeNow end
-- The general boot mock intentionally uses zero Magnitude; exercise real
-- distance/LOS decisions here so independent range and wall checks are tested.
local oldVectorNew, oldVectorIndex = Vector3.new, Vector3.__index
Vector3.__index = function(value, key)
    if key == "Magnitude" then
        return math.sqrt(value.X * value.X + value.Y * value.Y + value.Z * value.Z)
    elseif key == "Unit" then
        local mag = math.sqrt(value.X * value.X + value.Y * value.Y + value.Z * value.Z)
        return mag > 0 and Vector3.new(value.X / mag, value.Y / mag, value.Z / mag) or Vector3.new(0, 0, 0)
    end
    return rawget(Vector3, key)
end
Vector3.new = function(x, y, z) return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, Vector3) end
local originalRaycastParams = RaycastParams
RaycastParams = {new = function() return {} end}
workspace.CurrentCamera.CFrame = CFrame.new(Vector3.new(0, 3, 0))

-- Hitbox shares the native team/death state and restores its snapshot.
local heroRoot = HarnessHeroGuy.Character:FindFirstChild("HumanoidRootPart")
heroRoot.Size = Vector3.new(2, 2, 1)
heroRoot.CanCollide = true
heroRoot.CanQuery = false
local originalHeroSize, originalHeroTransparency, originalHeroCollision, originalHeroQuery =
    heroRoot.Size, heroRoot.Transparency, heroRoot.CanCollide, heroRoot.CanQuery
featuresByName["Hitbox"].onToggle(true)
coreTask.callback(0.1)
assert(heroRoot.Size.X == core.settings.hitboxSize and heroRoot.CanQuery == true,
    "enemy hitbox was not expanded/queryable")
HarnessMatchData[HarnessHeroGuy].team = "Red"
core.settings.teamCheck = false -- Silent AIM must not control Hitbox's own check.
nativeNow += 0.3
coreTask.callback(0.1)
assert(heroRoot.Size == originalHeroSize and heroRoot.Transparency == originalHeroTransparency
    and heroRoot.CanCollide == originalHeroCollision and heroRoot.CanQuery == originalHeroQuery,
    "new teammate hitbox properties were not restored")
core.settings.hitboxTeamCheck = false
nativeNow += 0.3
coreTask.callback(0.1)
assert(heroRoot.Size.X == core.settings.hitboxSize, "Hitbox's own Team Check could not be disabled")
featuresByName["Hitbox"].onToggle(false)
assert(heroRoot.Size == originalHeroSize and heroRoot.CanQuery == originalHeroQuery,
    "Hitbox OFF did not restore the original root")
HarnessMatchData[HarnessHeroGuy].team = "Blue"
core.settings.teamCheck = true
core.settings.hitboxTeamCheck = true

local silentFeature = featuresByName["Silent AIM"]
local autoWinFeature = featuresByName["Auto Win"]
local autoShootFeature = featuresByName["Auto Shoot"]
local knifeThrowFeature = featuresByName["Knife Throw"]
local senderBinding = ex.state.shortcutBindings["MVSD.SilentAIM"]
assert(senderBinding and senderBinding.onPress, "Silent AIM action binding missing")
local shotsAtStart = nativeGunShots
senderBinding.onPress()
assert(nativeGunShots == shotsAtStart, "Silent AIM action fired while disabled")
silentFeature.activate()
assert(silentFeature.enabled and core.settings.silentAim, "Silent AIM did not enable through its card")

-- The camera aim must survive a deferred native Activated handler and then
-- restore. Changing the camera independently must not be overwritten.
local oldDelay = task.delay
local pendingAimRestore = nil
task.delay = function(seconds, callback)
    assert(seconds >= 0.05, "native aim expires before deferred activation")
    pendingAimRestore = callback
end
local cameraBeforeKey = workspace.CurrentCamera.CFrame
local cameraAtActivation = nil
nativeGun.Activate = function()
    nativeGunShots += 1
    cameraAtActivation = workspace.CurrentCamera.CFrame
end
local enabledBeforeKey = silentFeature.enabled
senderBinding.onPress()
assert(nativeGunShots == shotsAtStart + 1, "default-mode action key did not fire the native gun")
assert(nativeGun.Parent == nativeLocal.Character, "Backpack gun was not equipped")
assert(silentFeature.enabled == enabledBeforeKey, "action key toggled Silent AIM")
assert(cameraAtActivation ~= cameraBeforeKey and workspace.CurrentCamera.CFrame == cameraAtActivation,
    "native activation did not retain its aim through the current frame")
assert(pendingAimRestore, "native camera restore was not scheduled")
pendingAimRestore()
assert(workspace.CurrentCamera.CFrame == cameraBeforeKey, "native aim did not restore the camera")
senderBinding.onPress()
local cameraMovedByUser = CFrame.new(Vector3.new(4, 8, 2))
workspace.CurrentCamera.CFrame = cameraMovedByUser
pendingAimRestore()
assert(workspace.CurrentCamera.CFrame == cameraMovedByUser, "aim restore overwrote user camera movement")
senderBinding.onPress()
local newerCamera = CFrame.new(Vector3.new(5, 9, 3))
workspace.CurrentCamera.CFrame = newerCamera
senderBinding.onPress()
pendingAimRestore()
assert(workspace.CurrentCamera.CFrame == newerCamera,
    "repeated shots restored an obsolete camera snapshot")
task.delay = oldDelay
workspace.CurrentCamera.CFrame = CFrame.new(Vector3.new(0, 3, 0))
nativeGun.Activate = function() nativeGunShots += 1 end
silentFeature.activate()
assert(not silentFeature.enabled and not core.settings.silentAim, "Silent AIM did not turn off")
modeControl.apply("Silent")
silentFeature.activate()
assert(core.settings.silentAim and silentFeature.status == "Button only: hooks unavailable",
    "missing executor hooks disabled or hid the Silent fallback")
local shotsWithoutHooks = nativeGunShots
senderBinding.onPress()
assert(nativeGunShots == shotsWithoutHooks + 1, "action key did not work without executor hooks")
silentFeature.activate()
modeControl.apply("Legit")

-- Auto Shoot acts without Silent AIM and owns its team, LOS and range policy.
core.settings.autoShootWallCheck = false
nativeGun.Parent = nil
autoShootFeature.onToggle(true)
local shotsBeforeAuto = nativeGunShots
nativeNow += 1
coreTask.callback(0.1)
assert(nativeGunShots == shotsBeforeAuto and autoShootFeature.status == "Waiting for gun",
    "missing gun was not reported")
nativeGun.Parent = nativeBackpack
nativeNow += 1
coreTask.callback(0.1)
assert(nativeGunShots == shotsBeforeAuto + 1 and not core.settings.silentAim,
    "independent Auto Shoot did not fire")
nativeNow += 0.1
coreTask.callback(0.1)
assert(nativeGunShots == shotsBeforeAuto + 2, "Auto Shoot did not keep attempting shots")
core.settings.autoShootRange = 5
nativeNow += 0.1
coreTask.callback(0.1)
assert(nativeGunShots == shotsBeforeAuto + 2, "Auto Shoot ignored its range")
core.settings.autoShootRange = 1000
HarnessMatchData[HarnessHeroGuy].team = "Red"
core.settings.teamCheck = false
core.settings.autoShootTeamCheck = true
nativeNow += 0.1
coreTask.callback(0.1)
assert(nativeGunShots == shotsBeforeAuto + 2, "Auto Shoot used Silent's Team Check")
core.settings.autoShootTeamCheck = false
nativeNow += 0.1
coreTask.callback(0.1)
assert(nativeGunShots == shotsBeforeAuto + 3, "Auto Shoot Team Check could not be disabled")
HarnessMatchData[HarnessHeroGuy].team = "Blue"
core.settings.teamCheck = true
core.settings.autoShootTeamCheck = true
local independentRaycast = workspace.Raycast
local independentWall = Instance.new("Part")
workspace.Raycast = function() return {Instance = independentWall} end
core.settings.wallCheck = false
core.settings.autoShootWallCheck = true
nativeNow += 0.1
coreTask.callback(0.1)
assert(nativeGunShots == shotsBeforeAuto + 3, "Auto Shoot ignored its own Wall Check")
core.settings.autoShootWallCheck = false
nativeNow += 0.1
coreTask.callback(0.1)
assert(nativeGunShots == shotsBeforeAuto + 4, "Auto Shoot used Silent's Wall Check")
workspace.Raycast = independentRaycast
core.settings.autoShootCooldown = 0.5
nativeNow += 1
coreTask.callback(0.1)
assert(nativeGunShots == shotsBeforeAuto + 5, "Auto Shoot missed its cooldown start")
nativeNow += 0.2
coreTask.callback(0.1)
assert(nativeGunShots == shotsBeforeAuto + 5, "Auto Shoot ignored the configured cooldown")
nativeNow += 0.31
coreTask.callback(0.1)
assert(nativeGunShots == shotsBeforeAuto + 6, "Auto Shoot did not resume after cooldown")
core.settings.autoShootCooldown = 0
silentFeature.activate()
nativeNow += 1
coreTask.callback(0.1)
local beforeSilentOff = nativeGunShots
silentFeature.activate()
nativeNow += 1
coreTask.callback(0.1)
assert(nativeGunShots == beforeSilentOff + 1 and not core.settings.silentAim,
    "turning Silent AIM off interrupted independent Auto Shoot")
autoShootFeature.onToggle(false)

local mobileMain = Instance.new("Folder")
mobileMain.Name = "Main"
mobileMain.Parent = nativeLocal.PlayerGui
local mobileGui = Instance.new("Folder")
mobileGui.Name = "MobileKnifeGui"
mobileGui.Parent = mobileMain
local throwMode = Instance.new("BoolValue")
throwMode.Name = "ThrowMode"
throwMode.Value = false
throwMode.Parent = mobileGui
local touchStateDuringActivation = nil
nativeKnife.Activate = function()
    nativeKnifeShots += 1
    touchStateDuringActivation = throwMode.Value
end
local oldMouse2Press = mouse2press
local oldMouse2Release = mouse2release
local oldTouchEnabled = game:GetService("UserInputService").TouchEnabled
game:GetService("UserInputService").TouchEnabled = false
local nativeMouseDown = 0
local nativeMouseUp = 0
mouse2press = function() nativeMouseDown += 1 end
mouse2release = function() nativeMouseUp += 1 end
assert(core.fireKnife(nativeTarget), "desktop knife throw was not queued")
assert(nativeKnifeShots == 1 and nativeMouseDown == 1 and nativeMouseUp == 1,
    "desktop knife did not use the native right-click/Activate chain")
-- Touch takes precedence on a hybrid executor that also exposes mouse2.
game:GetService("UserInputService").TouchEnabled = true
assert(core.fireKnife(nativeTarget), "touch knife throw was not queued")
assert(nativeKnifeShots == 2 and touchStateDuringActivation == true and throwMode.Value == false,
    "touch knife did not use and restore the GUI BoolValue")
assert(nativeMouseDown == 1 and nativeMouseUp == 1, "touch incorrectly chose desktop right-click")
throwMode.Value = true
assert(core.fireKnife(nativeTarget) and throwMode.Value == true,
    "existing user ThrowMode preference was not preserved")
throwMode.Value = false
-- A target switching teams during desktop windup must not be attacked.
local previousSpawn, previousWait = task.spawn, task.wait
local waitingThread = nil
task.spawn = function(fn)
    waitingThread = coroutine.create(fn)
    local okSpawn, spawnError = coroutine.resume(waitingThread)
    assert(okSpawn, tostring(spawnError))
end
task.wait = function() coroutine.yield() end
game:GetService("UserInputService").TouchEnabled = false
local shotsBeforeWindup = nativeKnifeShots
assert(core.fireKnife(nativeTarget), "desktop windup was not queued")
assert(nativeKnifeShots == shotsBeforeWindup and nativeMouseDown == 2,
    "desktop windup did not wait for native input")
HarnessMatchData[HarnessHeroGuy].team = "Red"
local okResume, resumeError = coroutine.resume(waitingThread)
assert(okResume, tostring(resumeError))
assert(nativeKnifeShots == shotsBeforeWindup and nativeMouseUp == 2,
    "stale teammate was attacked or right-click was left pressed")
HarnessMatchData[HarnessHeroGuy].team = "Blue"
task.spawn, task.wait = previousSpawn, previousWait
mouse2press = nil
mouse2release = nil
throwMode.Parent = nil
assert(not core.fireKnife(nativeTarget), "knife queued without native input support")
throwMode.Parent = mobileGui
-- Standalone Knife Throw works with Silent AIM off, via the mobile native path.
throwMode.Parent = mobileGui
game:GetService("UserInputService").TouchEnabled = true
core.settings.knifeWallCheck = false
knifeThrowFeature.onToggle(true)
local standaloneBefore = nativeKnifeShots
nativeNow += 1
coreTask.callback(0.1)
assert(nativeKnifeShots == standaloneBefore + 1 and not core.settings.silentAim,
    "standalone Knife Throw did not use native activation")
core.settings.knifeRange = 5
nativeNow += 0.1
coreTask.callback(0.1)
assert(nativeKnifeShots == standaloneBefore + 1, "Knife Throw ignored its own range")
core.settings.knifeRange = 600
HarnessMatchData[HarnessHeroGuy].team = "Red"
core.settings.teamCheck = false
core.settings.knifeTeamCheck = true
nativeNow += 0.1
coreTask.callback(0.1)
assert(nativeKnifeShots == standaloneBefore + 1, "Knife Throw used Silent's Team Check")
core.settings.knifeTeamCheck = false
nativeNow += 0.1
coreTask.callback(0.1)
assert(nativeKnifeShots == standaloneBefore + 2, "Knife Throw Team Check could not be disabled")
HarnessMatchData[HarnessHeroGuy].team = "Blue"
core.settings.teamCheck = true
core.settings.knifeTeamCheck = true
local knifeRaycast = workspace.Raycast
local knifeWall = Instance.new("Part")
workspace.Raycast = function() return {Instance = knifeWall} end
core.settings.wallCheck = false
core.settings.knifeWallCheck = true
nativeNow += 0.1
coreTask.callback(0.1)
assert(nativeKnifeShots == standaloneBefore + 2, "Knife Throw ignored its own Wall Check")
core.settings.knifeWallCheck = false
nativeNow += 0.1
coreTask.callback(0.1)
assert(nativeKnifeShots == standaloneBefore + 3, "Knife Throw used Silent's Wall Check")
workspace.Raycast = knifeRaycast
silentFeature.activate()
nativeNow += 1
coreTask.callback(0.1)
local throwsBeforeSilentOff = nativeKnifeShots
silentFeature.activate()
nativeNow += 1
coreTask.callback(0.1)
assert(nativeKnifeShots == throwsBeforeSilentOff + 1 and not core.settings.silentAim,
    "turning Silent AIM off interrupted independent Knife Throw")
knifeThrowFeature.onToggle(false)

-- User Cooldown starts AFTER the desktop native windup, not in parallel.
game:GetService("UserInputService").TouchEnabled = false
mouse2press = function() nativeMouseDown += 1 end
mouse2release = function() nativeMouseUp += 1 end
local cooldownThread = nil
task.spawn = function(fn)
    cooldownThread = coroutine.create(fn)
    local okSpawn, err = coroutine.resume(cooldownThread)
    assert(okSpawn, tostring(err))
end
task.wait = function() coroutine.yield() end
core.settings.knifeCooldown = 0.5
knifeThrowFeature.onToggle(true)
nativeNow += 1
coreTask.callback(0.1)
assert(cooldownThread and coroutine.status(cooldownThread) == "suspended", "cooldown fixture has no windup")
local cooldownDown = nativeMouseDown
nativeNow += 0.2
local okCooldown, cooldownError = coroutine.resume(cooldownThread)
assert(okCooldown, tostring(cooldownError))
nativeNow += 0.49
coreTask.callback(0.1)
assert(nativeMouseDown == cooldownDown, "knife cooldown overlapped native windup")
nativeNow += 0.02
coreTask.callback(0.1)
assert(nativeMouseDown == cooldownDown + 1, "knife did not retry after windup plus cooldown")
knifeThrowFeature.onToggle(false)
local okCancel, cancelError = coroutine.resume(cooldownThread)
assert(okCancel, tostring(cancelError))
task.spawn, task.wait = previousSpawn, previousWait
core.settings.knifeCooldown = 0

-- A pending desktop throw owns the weapon until completion/cancellation;
-- Auto Shoot must not equip the gun in the middle of the right-click windup.
game:GetService("UserInputService").TouchEnabled = false
mouse2press = function() nativeMouseDown += 1 end
mouse2release = function() nativeMouseUp += 1 end
local arbitrationThread = nil
task.spawn = function(fn)
    arbitrationThread = coroutine.create(fn)
    local okSpawn, err = coroutine.resume(arbitrationThread)
    assert(okSpawn, tostring(err))
end
task.wait = function() coroutine.yield() end
knifeThrowFeature.onToggle(true)
nativeNow += 1
coreTask.callback(0.1)
assert(arbitrationThread and coroutine.status(arbitrationThread) == "suspended",
    "standalone knife did not enter native windup")
local shotsDuringWindup = nativeGunShots
autoShootFeature.onToggle(true)
nativeNow += 0.1
coreTask.callback(0.1)
assert(nativeGunShots == shotsDuringWindup and nativeKnife.Parent == nativeLocal.Character,
    "Auto Shoot interrupted the pending knife windup")
local rightUpBeforeCancel = nativeMouseUp
knifeThrowFeature.onToggle(false)
assert(nativeMouseUp == rightUpBeforeCancel + 1, "cancelling throw left right-click pressed")
local okArbitration, arbitrationError = coroutine.resume(arbitrationThread)
assert(okArbitration, tostring(arbitrationError))
assert(nativeMouseUp == rightUpBeforeCancel + 1, "cancelled throw released right-click twice")
task.spawn, task.wait = previousSpawn, previousWait
nativeNow += 0.1
coreTask.callback(0.1)
assert(nativeGunShots == shotsDuringWindup + 1 and nativeGun.Parent == nativeLocal.Character,
    "Auto Shoot did not resume after throw cancellation")
autoShootFeature.onToggle(false)
mouse2press = oldMouse2Press
mouse2release = oldMouse2Release
game:GetService("UserInputService").TouchEnabled = oldTouchEnabled

-- Mock the executor hook chain, not Roblox/network authority. Verify that the
-- captured knife packet is edited only when its call comes from the tool.
local oldTargetPos = nativeTarget.part.Position
local oldRootPos = nativeLocal.Character:FindFirstChild("HumanoidRootPart").Position
local oldCameraCFrame = workspace.CurrentCamera.CFrame
nativeTarget.part.Position = Vector3.new(12, 4, 0)
nativeLocal.Character:FindFirstChild("HumanoidRootPart").Position = Vector3.new(0, 3, 0)
workspace.CurrentCamera.CFrame = CFrame.new(Vector3.new(0, 3, 0))
local localRoot = nativeLocal.Character:FindFirstChild("HumanoidRootPart")
local beforeTriggerRotation = localRoot.CFrame
core.settings.silentAim = true
local shotsBeforeTrigger = nativeGunShots
assert(core.fireGun(nativeTarget, true), "TriggerBot native gun adapter did not activate")
assert(nativeGunShots == shotsBeforeTrigger + 1 and localRoot.CFrame == beforeTriggerRotation,
    "TriggerBot's crosshair activation rotated the character")
core.settings.silentAim = false
nativeGun.Parent = nativeBackpack
nativeKnife.Parent = nativeLocal.Character
core.settings.silentAim = true
core.settings.killAura = true
core.settings.killAuraRange = 20
local swingsBeforeAura = nativeKnifeShots
nativeNow += 1
coreTask.callback(0.1)
assert(nativeKnifeShots == swingsBeforeAura + 1 and localRoot.CFrame == beforeTriggerRotation,
    "Kill Aura failed to activate melee or rotated the character")
core.settings.killAura = false
core.settings.silentAim = false
local weaponScript = Instance.new("LocalScript")
weaponScript.Name = "LocalScript"
weaponScript.Parent = nativeKnife
local otherScript = Instance.new("LocalScript")
otherScript.Name = "PingsController"
otherScript.Parent = X2Networking
local netRemote = Instance.new("RemoteEvent")
netRemote.Name = "RE/session-hash"
netRemote.Parent = X2Net
local packet = nil
local originalNamecall = function(remote, ...)
    packet = {remote = remote, arguments = table.pack(...)}
end
local oldRaycastParams = RaycastParams
RaycastParams = {new = function() return {} end}
local previousWorkspaceRay = workspace.Raycast
local wallEnabled = false
local wall = Instance.new("Part")
workspace.Raycast = function()
    if wallEnabled then return {Instance = wall} end
    return nil
end
local realRay = workspace.Raycast
local rayDirection = nil
local currentNamecall = originalNamecall
local currentRay = function(_self, _origin, direction) rayDirection = direction end
local currentCaller, currentMethod = weaponScript, "FireServer"
local oldHookFunction, oldHookMeta = hookfunction, hookmetamethod
local oldGetCaller, oldGetMethod = getcallingscript, getnamecallmethod
hookfunction = function(target, replacement)
    assert(target == realRay, "unexpected mock function hook")
    local previous = currentRay
    currentRay = replacement
    return previous
end
hookmetamethod = function(_game, metamethod, replacement)
    assert(metamethod == "__namecall", "unexpected metamethod hook")
    local previous = currentNamecall
    currentNamecall = replacement
    return previous
end
getcallingscript = function() return currentCaller end
getnamecallmethod = function() return currentMethod end
core.settings.silentMode = "Silent"
core.settings.wallCheck = false
core.settings.autoShoot = false
core.settings.knifeThrow = false
silentFeature.onToggle(true)
nativeNow += 1
coreTask.callback(0.1)
local guid = "959d5e90-231d-4f6e-8861-050e2c22b938"
local frame = CFrame.new(nativeLocal.Character:FindFirstChild("HumanoidRootPart").Position)
local untouched = Vector3.new(20, 8, 10)
currentNamecall(netRemote, guid, frame, untouched)
assert(packet.remote == netRemote and packet.arguments[1] == guid and packet.arguments[2] == frame
    and packet.arguments[3] == nativeTarget.part.Position,
    "observed weapon packet was not scoped/redirected correctly")
local originalDirection = Vector3.new(0, 0, -100)
currentRay(workspace, frame.Position, originalDirection)
assert(rayDirection ~= originalDirection and rayDirection.X > 0,
    "weapon ray did not redirect in the mock")
core.settings.wallCheck = true
wallEnabled = true
currentNamecall(netRemote, guid, frame, untouched)
assert(packet.arguments[3] == untouched, "knife packet redirected through a wall")
currentRay(workspace, frame.Position, originalDirection)
assert(rayDirection == originalDirection, "weapon ray redirected through a wall")
wallEnabled = false
core.settings.wallCheck = false
currentCaller = otherScript
currentNamecall(netRemote, guid, frame, untouched)
assert(packet.arguments[3] == untouched, "unrelated script was redirected")
currentRay(workspace, frame.Position, originalDirection)
assert(rayDirection == originalDirection, "ping ray was redirected")
currentCaller = weaponScript
currentMethod = "InvokeServer"
currentNamecall(netRemote, guid, frame, untouched)
assert(packet.arguments[3] == untouched, "non-FireServer call was redirected")
currentMethod = "FireServer"
currentNamecall(netRemote, "not-a-guid", frame, untouched)
assert(packet.arguments[3] == untouched, "unknown packet schema was redirected")
local foreignNamecall = function(...) return currentNamecall(...) end
local ownNamecall = currentNamecall
foreignNamecall = function(...) return ownNamecall(...) end
currentNamecall = foreignNamecall
local ownRay = currentRay
local foreignRay = function(...) return ownRay(...) end
currentRay = foreignRay
silentFeature.onToggle(false)
assert(currentNamecall == foreignNamecall and currentRay == foreignRay,
    "cleanup displaced a hook installed after ours")
currentNamecall(netRemote, guid, frame, untouched)
assert(packet.arguments[3] == untouched, "disabled hook still redirected calls")
hookfunction, hookmetamethod = oldHookFunction, oldHookMeta
getcallingscript, getnamecallmethod = oldGetCaller, oldGetMethod
workspace.Raycast = previousWorkspaceRay
RaycastParams = oldRaycastParams
nativeTarget.part.Position = oldTargetPos
nativeLocal.Character:FindFirstChild("HumanoidRootPart").Position = oldRootPos
workspace.CurrentCamera.CFrame = oldCameraCFrame
core.settings.silentMode = "Legit"

-- Auto Win fights only in an active round, independently of Silent AIM.
-- These observations are client-side attempts, not server hit verification.
autoWinFeature.activate()
assert(core.settings.autoWin and autoWinFeature.enabled, "Auto Win did not enable")
local function statValue(name)
    for _, row in ipairs(autoWinFeature.optionRows) do
        local label = row:FindFirstChild("OptionLabel")
        if label and label.Text == name then
            local value = row:FindFirstChild("StatValue")
            return value and value.Text
        end
    end
end
assert(statValue("Time Spent") and statValue("Duels Won") == "0"
    and statValue("Current Game mode") == "1v1", "Auto Win stats rows are missing or incorrect")
assert(core.getStats().CurrentGameMode == "1v1", "known 1v1 place was not recognized")
local priorPlace = game.PlaceId
game.PlaceId = 92876937625630
assert(core.getStats().CurrentGameMode == "2v2", "known 2v2 place was not recognized")
game.PlaceId = priorPlace
HarnessMatchData[nativeLocal].mode = "FFA"
assert(core.getStats().CurrentGameMode == "FFA", "native FFA mode was not recognized")
HarnessMatchData[nativeLocal].mode = "TeamBased"
local shotsBeforeWin = nativeGunShots
HarnessGame.RoundStarted = false
nativeNow += 1
coreTask.callback(0.1)
assert(nativeGunShots == shotsBeforeWin, "Auto Win attacked during the countdown")
HarnessGame.RoundStarted = true
nativeNow += 1
coreTask.callback(0.1)
assert(nativeGunShots == shotsBeforeWin + 1 and not core.settings.silentAim,
    "Auto Win did not attempt gun combat independently")
-- With both masters on, Auto Shoot's shorter range/cooldown must not suppress
-- Auto Win's own selection; at most one gun activation occurs per tick.
core.settings.autoShootRange = 5
core.settings.autoShootCooldown = 0
autoShootFeature.onToggle(true)
local beforeSharedGun = nativeGunShots
nativeNow += 1
coreTask.callback(0.1)
assert(nativeGunShots == beforeSharedGun + 1
    and autoShootFeature.status == "Waiting for target / clear path",
    "Auto Win inherited Auto Shoot's range")
core.settings.autoShootRange = 1000
core.settings.autoShootCooldown = 2
nativeNow += 1
coreTask.callback(0.1)
assert(nativeGunShots == beforeSharedGun + 2 and autoWinFeature.status == "Gun shared with Auto Shoot",
    "gun arbiter fired twice or failed to share an available shot")
nativeNow += 0.1
coreTask.callback(0.1)
assert(nativeGunShots == beforeSharedGun + 3, "Auto Win inherited Auto Shoot's cooldown")
autoShootFeature.onToggle(false)
core.settings.autoShootCooldown = 0
local shotsBeforeEnded = nativeGunShots
HarnessGame.CurrentRoundEnded = true
nativeNow += 1
coreTask.callback(0.1)
assert(nativeGunShots == shotsBeforeEnded, "Auto Win attacked after the round ended")
HarnessGame.CurrentRoundEnded = false

-- The same independent fallback/arbitration applies to mobile Knife Throw.
nativeGun.Parent = nil
local touchBeforeShared = game:GetService("UserInputService").TouchEnabled
game:GetService("UserInputService").TouchEnabled = true
core.settings.knifeRange = 5
core.settings.knifeCooldown = 0
knifeThrowFeature.onToggle(true)
local beforeSharedKnife = nativeKnifeShots
nativeNow += 1
coreTask.callback(0.1)
assert(nativeKnifeShots == beforeSharedKnife + 1
    and knifeThrowFeature.status == "Waiting for target / clear path",
    "Auto Win inherited Knife Throw's range")
core.settings.knifeRange = 600
core.settings.knifeCooldown = 2
nativeNow += 1
coreTask.callback(0.1)
assert(nativeKnifeShots == beforeSharedKnife + 2 and autoWinFeature.status == "Knife shared with Knife Throw",
    "knife arbiter launched twice or failed to share a throw")
nativeNow += 0.1
coreTask.callback(0.1)
assert(nativeKnifeShots == beforeSharedKnife + 3, "Auto Win inherited Knife Throw's cooldown")
knifeThrowFeature.onToggle(false)
core.settings.knifeCooldown = 0
game:GetService("UserInputService").TouchEnabled = touchBeforeShared
nativeGun.Parent = nativeBackpack
assert(core.getStats().AutoWinTime >= 3, "Auto Win time did not accumulate while enabled")

-- Safe Place only holds above a real active match map. OFF returns to the
-- snapshot only for the same character, GameId, match and active map.
local safeControl = ex.state.toggleControls["MVSD.AutoWin.SafePlace"]
local safeRoot = nativeLocal.Character:FindFirstChild("HumanoidRootPart")
local safeOrigin = safeRoot.CFrame
safeControl.setChecked(true)
HarnessMatchData[nativeLocal].gameId = nil
nativeNow += 1
coreTask.callback(0.1)
assert(safeRoot.CFrame == safeOrigin and not safeRoot:FindFirstChild("WurstX2SafePlace"),
    "Safe Place moved the player in the lobby")
HarnessMatchData[nativeLocal].gameId = "HarnessMatchOne"
HarnessGame.RoundStarted = false
nativeNow += 1
coreTask.callback(0.1)
assert(safeRoot.CFrame == safeOrigin, "Safe Place moved without a replicated active map")
local maps = Instance.new("Folder")
maps.Name = "ActiveMaps"
maps.Parent = workspace
local safeMap = Instance.new("Model")
safeMap.Name = HarnessGame.MatchId
safeMap.Parent = maps
local floor = Instance.new("Part")
floor.Name = "Floor"
floor.Size = Vector3.new(50, 2, 50)
floor.Position = Vector3.new(0, 10, 0)
floor.CFrame = CFrame.new(floor.Position)
floor.Parent = safeMap
local unsafeRoof = Instance.new("Part")
unsafeRoof.Size = Vector3.new(10, 1000, 10)
unsafeRoof.Position = Vector3.new(0, 0, 0)
unsafeRoof.CFrame = CFrame.new(unsafeRoof.Position)
unsafeRoof.Parent = safeMap
nativeNow += 1
coreTask.callback(0.1)
assert(safeRoot.CFrame == safeOrigin and statValue("Safe Place status") == "Unavailable",
    "Safe Place ignored an excessively high roof")
unsafeRoof:Destroy()
nativeNow += 1.1
coreTask.callback(0.1)
local hold = safeRoot:FindFirstChild("WurstX2SafePlace")
assert(hold and safeRoot.CFrame.Position.Y == 46,
    "Safe Place did not hold above the actual map during countdown")
assert(statValue("Safe Place status") == "Holding", "Safe Place has no in-options status")
assert(not hold:IsA("BasePart"), "Safe Place added a ray-blocking platform")
safeControl.setChecked(false)
assert(hold.destroyed and safeRoot.CFrame == safeOrigin, "Safe Place OFF did not restore the same match")
safeControl.setChecked(true)
nativeNow += 1
coreTask.callback(0.1)
hold = safeRoot:FindFirstChild("WurstX2SafePlace")
local safePosition = safeRoot.CFrame
assert(hold and safePosition ~= safeOrigin, "second Safe Place entry failed")
HarnessMatchData[nativeLocal].gameId = "NewGame"
safeControl.setChecked(false)
assert(hold.destroyed and safeRoot.CFrame == safePosition,
    "Safe Place restored an old GameId's position")
HarnessMatchData[nativeLocal].gameId = "HarnessMatchOne"
safeRoot.CFrame = safeOrigin
safeControl.setChecked(true)
nativeNow += 1
coreTask.callback(0.1)
hold = safeRoot:FindFirstChild("WurstX2SafePlace")
assert(hold, "third Safe Place entry failed")
safeMap.Parent = nil
local beforeMapExit = safeRoot.CFrame
safeControl.setChecked(false)
assert(hold.destroyed and safeRoot.CFrame == beforeMapExit,
    "Safe Place restored a removed map's position")
safeMap.Parent = maps
safeRoot.CFrame = safeOrigin
safeControl.setChecked(true)
nativeNow += 1
coreTask.callback(0.1)
hold = safeRoot:FindFirstChild("WurstX2SafePlace")
assert(hold, "fourth Safe Place entry failed")
X2SetDead.OnClientEvent:Fire(nativeLocal)
assert(hold.destroyed, "Safe Place hold survived local death")
X2PlayerRespawned.OnClientEvent:Fire(nil, nativeLocal)
safeControl.setChecked(false)
safeRoot.CFrame = safeOrigin
safeMap:Destroy()
maps:Destroy()
HarnessGame.RoundStarted = true

-- Rematch uses the real GameValues state and sends a single zero-argument
-- RematchVote only when active, not cancelled and not already voted.
local rematchControl = ex.state.toggleControls["MVSD.AutoWin.Revancha"]
rematchControl.setChecked(true)
HarnessRematch.active = false
nativeNow += 1
coreTask.callback(0.1)
assert(#HarnessRematchVotes == 0, "voted outside an active rematch")
HarnessRematch.active = true
HarnessRematch.cancelled = true
nativeNow += 1
coreTask.callback(0.1)
assert(#HarnessRematchVotes == 0 and statValue("Revancha status") == "Cancelled",
    "cancelled rematch was voted on or not reported")
HarnessRematch.cancelled = false
HarnessRematch.voters[tostring(nativeLocal.UserId)] = true
nativeNow += 1
coreTask.callback(0.1)
assert(#HarnessRematchVotes == 0, "voted despite an existing local vote")
HarnessRematch.active = false
HarnessRematch.voters = {}
nativeNow += 1
coreTask.callback(0.1)
HarnessRematch.active = true
nativeNow += 1
coreTask.callback(0.1)
assert(#HarnessRematchVotes == 1 and HarnessRematchVotes[1].n == 0
    and statValue("Revancha status") == "Vote sent",
    "native RematchVote was not sent/reported with zero arguments")
nativeNow += 3
coreTask.callback(0.1)
rematchControl.setChecked(false)
rematchControl.setChecked(true)
coreTask.callback(0.1)
HarnessRematch.cancelled = true
nativeNow += 1
coreTask.callback(0.1)
HarnessRematch.cancelled = false
nativeNow += 3
coreTask.callback(0.1)
assert(#HarnessRematchVotes == 1, "duplicate vote in one active rematch")
HarnessRematch.active = false
nativeNow += 1
coreTask.callback(0.1)
HarnessRematch.active = true
nativeNow += 3
coreTask.callback(0.1)
assert(#HarnessRematchVotes == 2 and HarnessRematchVotes[2].n == 0,
    "next active rematch did not get its own vote")
HarnessRematch.active = false
nativeNow += 1
coreTask.callback(0.1)
X2RematchVote.Parent = nil
HarnessRematch.active = true
nativeNow += 3
coreTask.callback(0.1)
assert(#HarnessRematchVotes == 2 and statValue("Revancha status") == "Remote unavailable",
    "missing rematch remote was not reported")
X2RematchVote.Parent = X2Networking
nativeNow += 3
coreTask.callback(0.1)
assert(#HarnessRematchVotes == 3, "rematch vote did not retry when the real remote appeared")
HarnessRematch.active = false
rematchControl.setChecked(false)

-- WinNotification is a ROUND; Duels Won counts only final Outcome==Win,
-- including nonadjacent duplicate MatchResults deduplication.
X2Killed.OnClientEvent:Fire(nativeLocal, HarnessHeroGuy)
X2DestroyBody.OnClientEvent:Fire(HarnessHeroGuy, HarnessHeroGuy.Character, nativeLocal)
assert(core.getStats().Kills == 1, "Killed/DestroyBody were not deduplicated")
X2Killed.OnClientEvent:Fire(nativeLocal, HarnessHeroGuy)
assert(core.getStats().Kills == 1, "duplicate kill counted twice")
X2SetDead.OnClientEvent:Fire(nativeLocal)
X2SetDead.OnClientEvent:Fire(nativeLocal)
assert(core.getStats().Loses == 0, "individual death incorrectly counted as team loss")
X2WinNotification.OnClientEvent:Fire(nil)
assert(core.getWins() == 1 and core.getStats().DuelsWon == 0,
    "a round notification was incorrectly counted as a duel")
X2WinNotification.OnClientEvent:Fire(nil)
X2MatchResults.OnClientEvent:Fire("match-guid-one", {{Page = "RoundInfo", Data = {Outcome = "Win"}}})
X2MatchResults.OnClientEvent:Fire("match-guid-one", {{Page = "RoundInfo", Data = {Outcome = "Win"}}})
assert(core.getWins() == 1 and core.getStats().DuelsWon == 1 and statValue("Duels Won") == "1",
    "final Win did not count exactly once")
nativeNow += 1
X2PlayerRespawned.OnClientEvent:Fire(nil, nativeLocal)
X2WinNotification.OnClientEvent:Fire(false)
X2WinNotification.OnClientEvent:Fire(true)
assert(core.getStats().Loses == 1, "boolean round-loss was not counted exactly once")
X2MatchResults.OnClientEvent:Fire("match-guid-two", {{Page = "RoundInfo", Data = {Outcome = "Loss"}}})
assert(core.getStats().Loses == 1 and core.getStats().DuelsWon == 1,
    "final Loss counted as a win or duplicated the round loss")
nativeNow += 1
X2PlayerRespawned.OnClientEvent:Fire(nil, nativeLocal)
X2MatchResults.OnClientEvent:Fire("match-guid-three", {{Page = "RoundInfo", Data = {Outcome = "Win"}}})
assert(core.getWins() == 2 and core.getStats().DuelsWon == 2,
    "final result without a notification was not counted")
X2MatchResults.OnClientEvent:Fire("match-guid-one", {{Page = "RoundInfo", Data = {Outcome = "Win"}}})
X2MatchResults.OnClientEvent:Fire("match-guid-three", {{Page = "RoundInfo", Data = {Outcome = "Win"}}})
X2MatchResults.OnClientEvent:Fire("match-guid-four", {{Page = "RoundInfo", Data = {Outcome = "Draw"}}})
assert(core.getStats().DuelsWon == 2, "delayed duplicate or draw counted as a duel win")
X2MatchResults.OnClientEvent:Fire("match-incomplete", {{Page = "Unknown"}})
assert(core.getStats().DuelsWon == 2, "incomplete result counted as a win")
X2MatchResults.OnClientEvent:Fire("match-incomplete", {{Page = "RoundInfo", Data = {Outcome = "Win"}}})
assert(core.getStats().DuelsWon == 3, "incomplete result masked a later final win")
X2MatchResults.OnClientEvent:Fire("match-incomplete", {{Page = "RoundInfo", Data = {Outcome = "Win"}}})
assert(core.getStats().DuelsWon == 3, "late final win was counted twice")

-- A replicated replacement must disconnect the old event and bind the new one.
local oldSetDead = X2SetDead
oldSetDead.Parent = nil
X2SetDead = Instance.new("RemoteEvent")
X2SetDead.Name = "RE/Match/SetDead"
X2SetDead.Parent = X2Networking
nativeNow += 3
coreTask.callback(0.1)
oldSetDead.OnClientEvent:Fire(HarnessHeroGuy)
assert(core.isEnemy(HarnessHeroGuy), "replaced event still affected the core")
X2SetDead.OnClientEvent:Fire(HarnessHeroGuy)
assert(not core.isEnemy(HarnessHeroGuy), "replacement event was not connected")
X2PlayerRespawned.OnClientEvent:Fire(nil, HarnessHeroGuy)
assert(core.settings.autoWin and autoWinFeature.enabled, "Auto Win switched itself off after a win")
local timeAtDisable = core.getStats().AutoWinTime
autoWinFeature.activate()
assert(not core.settings.autoWin and autoWinFeature.status == nil, "Auto Win did not disable")
nativeNow += 10
assert(core.getStats().AutoWinTime == timeAtDisable, "Auto Win time kept running while disabled")
local winsAtDisable = core.getStats().DuelsWon
X2MatchResults.OnClientEvent:Fire("match-after-disabled", {{Page = "RoundInfo", Data = {Outcome = "Win"}}})
assert(core.getStats().DuelsWon == winsAtDisable, "Auto Win counted a result while disabled")
RaycastParams = originalRaycastParams
Vector3.new, Vector3.__index = oldVectorNew, oldVectorIndex
os.clock = nativePreviousClock
core.settings.wallCheck = nativePreviousWallCheck
nativeGun:Destroy()
nativeKnife:Destroy()

-- Offline behavior only: this proves discovery, a native contact attempt and
-- position restoration. It does not prove that a live server awards currency.
local character = game:GetService("Players").LocalPlayer.Character
local root = character and character:FindFirstChild("HumanoidRootPart")
assert(root, "farm harness has no HumanoidRootPart")
local originalCFrame = root.CFrame
local decoration = Instance.new("Model")
decoration.Name = "PumpkinCurrency_99"
decoration.Parent = workspace
local visualDecoration = Instance.new("Part")
visualDecoration.Name = "Pumpkin"
visualDecoration.Parent = decoration
local spawnables = Instance.new("Folder")
spawnables.Name = "SpawnablesClient"
spawnables.Parent = workspace
local pumpkinModel = Instance.new("Model")
pumpkinModel.Name = "12" -- real controller's numeric clone name
local pumpkin = Instance.new("Part")
pumpkin.Name = "Touch"
pumpkin.Size = Vector3.new(2, 1.9, 2)
pumpkin.Position = Vector3.new(30, 4, 30)
pumpkin.CFrame = CFrame.new(pumpkin.Position)
pumpkin.Transparency = 1
pumpkin.CanTouch = true
pumpkin.Parent = pumpkinModel
pumpkinModel.PrimaryPart = pumpkin
local visibleMesh = Instance.new("Part")
visibleMesh.Name = "Pumpkin"
visibleMesh.CanTouch = false
visibleMesh.Parent = pumpkinModel
pumpkinModel.Parent = spawnables
local previousFireTouch = firetouchinterest
local touchCalls = {}
firetouchinterest = function(rootPart, coinPart, touchState)
    table.insert(touchCalls, {rootPart, coinPart, touchState})
end
featuresByName["Auto Farm"].onToggle(true)
local farmHandle = ex.featureConnections.X2DuelsAutoFarm
assert(farmHandle, "farm task was not connected")
local farmTask = nil
for _, scheduled in pairs(ex.TaskManager.tasks) do
    if scheduled.handle == farmHandle then
        farmTask = scheduled
        break
    end
end
assert(farmTask, "farm callback was not registered")
farmTask.callback(0.1)
assert(#touchCalls == 0, "decoration or untagged clone was treated as a pickup")
-- In the real controller the tag is added AFTER the clone is parented.
game:GetService("CollectionService"):AddTag(pumpkinModel, "Pumpkin")
HarnessMatchData[nativeLocal].gameId = nil
farmTask.callback(0.1)
assert(#touchCalls == 0 and root.CFrame == originalCFrame,
    "event farm moved while match state was missing/lobby")
HarnessMatchData[nativeLocal].gameId = "HarnessMatchOne"
farmTask.callback(0.1)
assert(#touchCalls == 2, "tag-added event did not discover the real spawnable immediately")
assert(touchCalls[1][1] == root and touchCalls[1][2] == pumpkin,
    "farm touched the wrong instances")
assert(touchCalls[1][3] == 0 and touchCalls[2][3] == 1,
    "farm touch states were not begin/end")
assert(root.CFrame.Position.X == 30 and root.CFrame.Position.Y == 5.25
    and root.CFrame.Position.Z == 30, "farm did not move into pumpkin contact")
featuresByName["Auto Farm"].onToggle(false)
assert(root.CFrame == originalCFrame, "farm did not restore its saved CFrame")
featuresByName["Auto Farm"].onToggle(true)
farmTask.callback(0.1)
assert(root.CFrame ~= originalCFrame, "second pickup fixture did not move the player")
HarnessMatchData[nativeLocal].gameId = "OtherMatch"
featuresByName["Auto Farm"].onToggle(false)
assert(root.CFrame ~= originalCFrame, "farm restored an old match position after transition")
root.CFrame = originalCFrame
HarnessMatchData[nativeLocal].gameId = "HarnessMatchOne"
firetouchinterest = previousFireTouch
game:GetService("CollectionService"):RemoveTag(pumpkinModel, "Pumpkin")
pumpkinModel.Parent = nil
decoration.Parent = nil
spawnables.Parent = nil

-- Runtime Farms/PumpCoins: player entries, not distance to a character model,
-- decide the round team. The closer enemy coin must never be selected.
local function podiumFixture(name, team, player)
    local model = Instance.new("Model")
    model.Name = name
    local members = Instance.new("Folder")
    members.Name = "TeamMembers"
    members.Parent = model
    local teamValue = Instance.new("TeamValue")
    teamValue.Name = "TeamValue"
    teamValue.Value = team
    teamValue.Parent = members
    local entry = Instance.new("StringValue")
    entry.Name = "PlayerEntry"
    entry.Value = player.Name
    entry.Parent = members
    model.Parent = workspace
    return model
end
local farmsFolder = Instance.new("Folder")
farmsFolder.Name = "Farms"
farmsFolder.Parent = workspace
local function farmFixture(name, team, coinPosition)
    local model = Instance.new("Model")
    model.Name = name
    model.Parent = farmsFolder
    local teamValue = Instance.new("TeamValue")
    teamValue.Name = "TeamValue"
    teamValue.Value = team
    teamValue.Parent = model
    local ownerRoot = Instance.new("Part")
    ownerRoot.Name = "HumanoidRootPart"
    ownerRoot.Position = Vector3.new(0, 3, 0)
    ownerRoot.CFrame = CFrame.new(ownerRoot.Position)
    ownerRoot.Parent = model
    local pumpCoins = Instance.new("Folder")
    pumpCoins.Name = "PumpCoins"
    pumpCoins.Parent = model
    local coin = Instance.new("Part")
    coin.Name = "InvisibleCoin"
    coin.Transparency = 1
    coin.CanTouch = false
    coin.Position = coinPosition
    coin.CFrame = CFrame.new(coinPosition)
    coin.Parent = pumpCoins
    local transmitter = Instance.new("TouchTransmitter")
    transmitter.Parent = coin
    return model, coin
end
local friendlyFarmModel, friendlyCoin = farmFixture(
    "FriendlyFarm", "Red", Vector3.new(30, 4, 30)
)
local enemyFarmModel, enemyCoin = farmFixture(
    "EnemyFarm", "Blue", Vector3.new(1, 3, 0)
)
local localPodium = podiumFixture("LocalPodium", "Red", nativeLocal)
local enemyPodium = podiumFixture("EnemyPodium", "Blue", HarnessHeroGuy)
local farmTouches = {}
firetouchinterest = function(rootPart, coinPart, touchState)
    table.insert(farmTouches, {rootPart, coinPart, touchState})
end
local farmOriginalCFrame = root.CFrame
featuresByName["Auto Farm"].onToggle(true)
farmTask.callback(0.1)
assert(#farmTouches == 2 and farmTouches[1][2] == friendlyCoin,
    "Auto Farm selected an enemy or owner proxy instead of the friendly currency")
assert(farmTouches[1][2] ~= enemyCoin, "Auto Farm touched the closer enemy coin")
assert(root.CFrame.Position.X == 30 and root.CFrame.Position.Y == 5.25
    and root.CFrame.Position.Z == 30, "Auto Farm did not use the PumpCoin CFrame")
featuresByName["Auto Farm"].onToggle(false)
assert(root.CFrame == farmOriginalCFrame, "team farm did not restore its CFrame")
local touchCountBeforeNoEnemy = #farmTouches
enemyPodium:Destroy()
featuresByName["Auto Farm"].onToggle(true)
farmTask.callback(0.1)
assert(#farmTouches == touchCountBeforeNoEnemy,
    "Auto Farm farmed without an opposing podium entry")
featuresByName["Auto Farm"].onToggle(false)
localPodium:Destroy()
featuresByName["Auto Farm"].onToggle(true)
farmTask.callback(0.1)
assert(#farmTouches == touchCountBeforeNoEnemy,
    "Auto Farm farmed with no podium evidence at all")
featuresByName["Auto Farm"].onToggle(false)
firetouchinterest = previousFireTouch
friendlyFarmModel:Destroy()
enemyFarmModel:Destroy()
farmsFolder:Destroy()

-- Module destruction while Safe Place is active must release its mover and
-- restore only the current match's original position.
local exitMaps = Instance.new("Folder")
exitMaps.Name = "ActiveMaps"
exitMaps.Parent = workspace
local exitMap = Instance.new("Model")
exitMap.Name = HarnessGame.MatchId
exitMap.Parent = exitMaps
local exitFloor = Instance.new("Part")
exitFloor.Size = Vector3.new(40, 2, 40)
exitFloor.Position = Vector3.new(0, 8, 0)
exitFloor.CFrame = CFrame.new(exitFloor.Position)
exitFloor.Parent = exitMap
X2PlayerRespawned.OnClientEvent:Fire(nil, nativeLocal)
local positionBeforeDestroy = root.CFrame
safeControl.setChecked(true)
autoWinFeature.activate()
coreTask.callback(0.1)
local exitHold = root:FindFirstChild("WurstX2SafePlace")
assert(exitHold and root.CFrame ~= positionBeforeDestroy, "destroy cleanup fixture did not enter Safe Place")
ex.state.destruct()
assert(exitHold.destroyed and root.CFrame == positionBeforeDestroy,
    "module destroy did not release/restore Safe Place")
assert(ex.state.x2duelsCore == nil, "X2 core survived destroy")
assert(ex.state.x2duelsRules == nil, "X2 rules survived destroy")
assert(ex.state.mvsdCore == nil, "X2 compatibility core survived destroy")
assert(ex.state.gameBridge.teamProvider == nil, "X2 team provider survived destroy")
assert(ex.state.gameBridge.roleProvider == nil, "X2 role provider survived destroy")
print("[X2BOOT] 7 cards, independent combat, safe/rematch, duel stats, cleanup: PASS")
'''
    output_path = ROOT / "build" / "x2duels_boot.luau"
    output_path.write_text(generated, encoding="utf-8")
    result = subprocess.run(
        [LUAU, str(output_path)], cwd=ROOT, capture_output=True,
        text=True, check=False,
    )
    if result.returncode:
        raise SystemExit(result.stdout + result.stderr)
    output = result.stdout
    marker = "[X2BOOT] 7 cards, independent combat, safe/rematch, duel stats, cleanup: PASS"
    if marker not in output:
        raise AssertionError("X2 bundle boot marker missing\n" + output)
    print(marker)

    # Upgrade a v142 profile with the former status-only Auto Win and nested
    # automations enabled. The migration preserves non-action preferences but
    # must not start any newly automatic module without a fresh user opt-in.
    migration_boot = audit_menu.build(debug=True).read_text(encoding="utf-8")
    migration_boot = migration_boot.replace(
        place_anchor,
        "game = {\n    PlaceId = 124848751642883,\n    GameId = 20260716,",
        1,
    )
    migration_config = r'''
HarnessSavedConfig = [[return {
    version = 1,
    states = {
        ["MVSD.AutoWin"] = true,
        ["MVSD.AutoWin.SafePlace"] = true,
        ["MVSD.AutoWin.Revancha"] = true,
        ["MVSD.SilentAIM"] = true,
        ["MVSD.SilentAIM.AutoShoot"] = true,
        ["MVSD.SilentAIM.KnifeThrow"] = true,
        ["MVSD.SilentAIM.TeamCheck"] = false,
        ["MVSD.SilentAIM.WallCheck"] = false,
        ["MVSD.AutoFarm"] = true,
        ["MVSD.Hitboxes"] = true,
    },
    values = {
        ["X2Duels.layout"] = "v119",
        ["MVSD.SilentAIM.Range"] = 777,
        ["MVSD.SilentAIM.Fireinterval"] = 0.06,
    },
    ui = {},
}]]
'''
    migration_boot = migration_boot.replace(
        boot_anchor, "\n" + remote_setup + migration_config + boot_anchor, 1
    )
    migration_boot += r'''
local migrated = ex.state.x2duelsCore
assert(migrated and ex.configData.values["X2Duels.layout"] == "v143", "migration did not run")
assert(not migrated.settings.autoWin and not migrated.settings.autoShoot and not migrated.settings.knifeThrow,
    "legacy profile started automatic combat")
assert(not migrated.settings.safePlace and not migrated.settings.rematch,
    "legacy profile enabled a new Auto Win option")
assert(ex.configData.states["MVSD.SilentAIM.AutoShoot"] == nil
    and ex.configData.states["MVSD.SilentAIM.KnifeThrow"] == nil,
    "legacy nested toggles were not removed")
assert(migrated.settings.silentAim and ex.configData.states["MVSD.AutoFarm"] == true,
    "migration discarded unrelated v142 preferences")
assert(migrated.settings.autoShootTeamCheck == false and migrated.settings.autoShootWallCheck == false
    and migrated.settings.knifeTeamCheck == false and migrated.settings.knifeWallCheck == false
    and migrated.settings.hitboxTeamCheck == false,
    "legacy non-action policies were not migrated")
assert(migrated.settings.autoShootRange == 777 and migrated.settings.autoShootCooldown == 0.06,
    "legacy Auto Shoot range/delay were not migrated")
ex.state.destruct()
print("[X2MIGRATION] old automatic states stay off; preferences retained: PASS")
'''
    migration_path = ROOT / "build" / "x2duels_migration.luau"
    migration_path.write_text(migration_boot, encoding="utf-8")
    migration_result = subprocess.run(
        [LUAU, str(migration_path)], cwd=ROOT, capture_output=True,
        text=True, check=False,
    )
    if migration_result.returncode:
        raise SystemExit(migration_result.stdout + migration_result.stderr)
    marker = "[X2MIGRATION] old automatic states stay off; preferences retained: PASS"
    if marker not in migration_result.stdout:
        raise AssertionError("X2 migration boot marker missing")
    print(marker)

    # Unknown/future PlaceId: verify the literal-name structural fingerprint
    # rather than accidentally succeeding only through the hard-coded 1v1 ID.
    fingerprint_boot = audit_menu.build(debug=True).read_text(encoding="utf-8")
    fingerprint_boot = fingerprint_boot.replace(
        place_anchor,
        "game = {\n    PlaceId = 99999999999,\n    GameId = 20260716,",
        1,
    )
    extra_remotes = r'''
x2Remote("RE/Rematch/RematchTeleport")
x2Remote("RE/Combat/Beam")
x2Remote("RE/Combat/PlaySound")
'''
    fingerprint_boot = fingerprint_boot.replace(
        boot_anchor, "\n" + remote_setup + extra_remotes + boot_anchor, 1
    )
    fingerprint_boot += r'''
assert(ex.state.x2duelsCore, "literal-name fingerprint did not load X2")
ex.state.destruct()
print("[X2FINGERPRINT] unknown PlaceId, real slash names: PASS")
'''
    fingerprint_path = ROOT / "build" / "x2duels_fingerprint.luau"
    fingerprint_path.write_text(fingerprint_boot, encoding="utf-8")
    fingerprint_result = subprocess.run(
        [LUAU, str(fingerprint_path)], cwd=ROOT, capture_output=True,
        text=True, check=False,
    )
    if fingerprint_result.returncode:
        raise SystemExit(fingerprint_result.stdout + fingerprint_result.stderr)
    marker = "[X2FINGERPRINT] unknown PlaceId, real slash names: PASS"
    if marker not in fingerprint_result.stdout:
        raise AssertionError("X2 fingerprint boot marker missing")
    print(marker)


if __name__ == "__main__":
    run_luau_tests()
    run_integration_contracts()
    run_bundle_boot()
