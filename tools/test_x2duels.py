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

local p0 = {X = 0, Y = 0, Z = 0}
local p1 = {X = 100, Y = 0, Z = 0}
local zeroVelocity = {X = 0, Y = 0, Z = 0}
local timeStationary = rules.projectileInterceptTime(p0, p1, zeroVelocity, 100, 0, 5)
check("stationary projectile intercept", timeStationary ~= nil and math.abs(timeStationary - 1) < 0.00001, true)
local movingTime = rules.projectileInterceptTime(p0, p1, {X = 0, Y = 0, Z = 20}, 100, 0, 5)
check("moving target leads", movingTime ~= nil and math.abs(movingTime - 1.0206207) < 0.0001, true)
local gravityTime = rules.projectileInterceptTime(p0, p1, zeroVelocity, 100, 50, 5)
check("gravity trajectory intercept", gravityTime ~= nil and gravityTime > 1 and
    math.abs(10000 + (25 * gravityTime * gravityTime)^2 - (100 * gravityTime)^2) < 0.01, true)
check("unreachable target", rules.projectileInterceptTime(p0, p1, {X = 200, Y = 0, Z = 0}, 100, 0, 5), nil)
check("reject invalid projectile speed", rules.projectileInterceptTime(p0, p1, zeroVelocity, 0, 0, 5), nil)
check("reject invalid gravity", rules.projectileInterceptTime(p0, p1, zeroVelocity, 100, -1, 5), nil)
check("reject malformed vector", rules.projectileInterceptTime(p0, {}, zeroVelocity, 100, 0, 5), nil)
check("horizon respected", rules.projectileInterceptTime(p0, p1, zeroVelocity, 100, 0, 0.5), nil)

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
    forbid(base, 'settings.silentMode', "visible Legit camera-lock mode")
    forbid(base, 'X2DuelsLegitAim', "continuous Silent camera-lock render")
    require(base, 'runService.Heartbeat:Wait()', "post-equip readiness frame")
    require(base, 'local function discoverMouseCast', "optional native MouseCast adapter")
    require(base, 'local function isWeaponCaller', "weapon-only redirect attribution")
    require(base, 'local function anonymousMouseTarget', "bounded anonymous Mouse fallback")
    require(base, 'local function observedGunSignature', "captured gun fingerprint")
    require(base, 'local function replaceRawMouseIndex', "restorable raw metatable fallback")
    require(base, '"Target Part"', "independent Silent target-part selector")
    require(base, '"Aim FOV"', "optional screen-space aim filter")
    require(base, '"Aim FOV Radius"', "screen-space aim radius")
    require(base, '"Raycast Compatibility"', "explicit OTH broad Raycast option")
    require(base, 'offset.Magnitude > direction.Magnitude', "native ray range preservation")
    require(base, 'You can\'t shoot: a wall or another body is blocking the shot.', "visible wall reason")
    require(base, 'TextWrapped = true', "readable mobile status")
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
    require(decompiler, "snapshotWeapons = snapshotWeapons", "late-spawning weapon source snapshot")
    require(decompiler, "weaponSnapshotsCompleted", "weapon capture completion reporting")
    require(decompiler, "local currentRoots: {Instance} = table.clone(roots)", "current respawn hierarchy")
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
HarnessMouseCastModule = Instance.new("ModuleScript")
HarnessMouseCastModule.Name = "MouseCast"
HarnessMouseCastModule.Parent = modules
HarnessMouseCastReady = false
HarnessMouseCalls = {}
HarnessMouseCast = {}
for _, method in ipairs({"WithParams", "Exclude", "Include", "WithPositionExclude", "WithPositionInclude"}) do
    HarnessMouseCast[method] = function(...)
        table.insert(HarnessMouseCalls, {method = method, arguments = table.pack(...)})
        return "original", "original endpoint"
    end
end
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
    elseif module == HarnessMouseCastModule then
        if not HarnessMouseCastReady then error("MouseCast not ready") end
        return HarnessMouseCast
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
    ["Gun Probe"] = true,
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
assert(x2CardCount == 8, "expected exactly eight X2 cards, got " .. tostring(x2CardCount))
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
assert(not ex.state.valueControls["MVSD.SilentAIM.Mode"],
    "obsolete visible camera-lock mode is still exposed")
assert(ex.state.toggleControls["MVSD.SilentAIM.WallCheck"], "Silent Wall Check is missing")
assert(ex.state.toggleControls["MVSD.SilentAIM.RaycastCompatibility"]
    and ex.state.toggleControls["MVSD.SilentAIM.AimFOV"]
    and ex.state.valueControls["MVSD.SilentAIM.AimFOVRadius"]
    and ex.state.valueControls["MVSD.SilentAIM.TargetPart"],
    "Silent mobile compatibility/FOV/target selector missing")
assert(not ex.state.x2duelsCore.settings.mouseCompatibility
    and not ex.state.x2duelsCore.settings.silentAimFov,
    "continuous anonymous compatibility and Aim FOV must default OFF")
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
-- Older fixtures below still exercise the historical backend explicitly;
-- production defaults to OTH and never selects Legacy from the UI.
local autoWinFeature = featuresByName["Auto Win"]
local autoShootFeature = featuresByName["Auto Shoot"]
local knifeThrowFeature = featuresByName["Knife Throw"]
local senderBinding = ex.state.shortcutBindings["MVSD.SilentAIM"]
assert(senderBinding and senderBinding.onPress, "Silent AIM action binding missing")
-- OTH default: no detected legacy hook fallback; broad mode is opt-in.
do
    assert(core.settings.silentBackend == "Oth" and not core.settings.raycastCompatibility,
        "OTH and conservative Raycast compatibility defaults changed")
    local oldOth, oldMeta, oldMethod, oldCheck, oldCaller, oldDebug = oth, getrawmetatable, getnamecallmethod, checkcaller, getcallingscript, debug
    local installed, legacyCalls, calls, captured = nil, 0, 0, nil
    local hookInstalls, currentOthMethod = 0, "Raycast"
    local previousWriteFile, previousReadFile, previousIsFile = writefile, readfile, isfile
    local files = {}
    local fsWrite = function(path, data) files[path] = data end
    local fsRead = function(path) if files[path] == nil then error("not found") end return files[path] end
    local fsExists = function(path) return files[path] ~= nil end
    -- Functions may be in getgenv only. Test workspace without activating
    -- Gun Probe, Silent AIM, or a hook, and preserve the existing report.
    writefile, readfile, isfile = nil, nil, nil
    GENV.writefile, GENV.readfile, GENV.isfile = fsWrite, fsRead, fsExists
    local probeCard = featuresByName["Gun Probe"]
    -- The real UI animates in a nested spawned task; the harness runs spawn
    -- synchronously, so suppress that nested animation while testing callbacks.
    local oldSpawn, actionRunning = task.spawn, false
    task.spawn = function(fn, ...)
        if actionRunning then return end
        actionRunning = true
        fn(...)
        actionRunning = false
    end
    local testWorkspace = ex.state.shortcutBindings[probeCard.configKey .. "Test workspace"]
    assert(testWorkspace and testWorkspace.onPress, "workspace test action missing")
    files["X2Duels-calibration.json"] = "previous report"
    testWorkspace.onPress()
    assert(files["X2Duels-workspace-test.txt"] == "ARandomMenu workspace test\n"
        and files["X2Duels-calibration.json"] == "previous report" and hookInstalls == 0
        and string.find(probeCard.status, "content verified", 1, true),
        "workspace test did not use getgenv/verify or installed a hook/overwrote report")
    GENV.writefile, GENV.readfile, GENV.isfile = nil, nil, nil
    testWorkspace.onPress()
    assert(string.find(probeCard.status, "writefile unavailable", 1, true), "missing writefile not reported")
    writefile = function() return false end
    testWorkspace.onPress()
    assert(string.find(probeCard.status, "writefile: false", 1, true), "false writefile result not reported")
    writefile = function() end
    readfile = function() return "wrong" end
    testWorkspace.onPress()
    assert(string.find(probeCard.status, "content differs", 1, true), "readback mismatch not reported")
    readfile, isfile = nil, function() return false end
    testWorkspace.onPress()
    assert(string.find(probeCard.status, "not visible", 1, true), "invisible file not reported")
    isfile = nil
    testWorkspace.onPress()
    assert(string.find(probeCard.status, "unverified", 1, true), "unverified write not distinguished")
    writefile, readfile, isfile = fsWrite, fsRead, fsExists
    task.spawn = oldSpawn
    local previousHookMeta, previousHookFunction = hookmetamethod, hookfunction
    hookmetamethod = function() legacyCalls += 1; error("legacy hook invoked") end
    hookfunction = function() legacyCalls += 1; error("legacy hook invoked") end
    local predecessor = function(object, ...) calls += 1; captured = table.pack(...); return object, "ok" end
    getrawmetatable = function() return {__namecall = predecessor} end
    getnamecallmethod = function() return currentOthMethod end
    checkcaller = function() return false end
    getcallingscript, debug = nil, {}
    oth = nil
    silentFeature.onToggle(true)
    assert(legacyCalls == 0 and string.find(silentFeature.status, "unavailable", 1, true),
        "absent OTH did not fail closed")
    silentFeature.onToggle(false)
    featuresByName["Gun Probe"].onToggle(true)
    assert(string.find(featuresByName["Gun Probe"].status, "unavailable", 1, true) and legacyCalls == 0,
        "probe must report missing OTH without legacy fallback")
    featuresByName["Gun Probe"].onToggle(false)
    oth = {hook = function() error("simulated Oth failure") end}
    featuresByName["Gun Probe"].onToggle(true)
    assert(string.find(featuresByName["Gun Probe"].status, "unavailable", 1, true) and legacyCalls == 0,
        "failed OTH hook did not fail closed")
    featuresByName["Gun Probe"].onToggle(false)
    files["X2Duels-calibration.json"] = nil
    oth = {hook = function(target, callback)
        hookInstalls += 1
        assert(files["X2Duels-calibration.json"] ~= nil, "initial report was not written before OTH installation")
        assert(target == predecessor)
        installed = callback
        return predecessor
    end}
    probeCard.onToggle(true)
    assert(installed and hookInstalls == 1, "probe-first did not install its node")
    probeCard.onToggle(false)
    nativeHumanoid:EquipTool(nativeGun)
    silentFeature.onToggle(true)
    nativeNow += 0.2
    coreTask.callback(0.1)
    assert(installed and legacyCalls == 0, "OTH did not install independently")
    local origin, direction = Vector3.new(0, 3, 0), Vector3.new(0, 0, -500)
    local cameraBefore = workspace.CurrentCamera.CFrame
    installed(workspace, origin, direction, nil)
    assert(captured.n == 3 and captured[2] == direction, "unattributed Raycast changed without opt-in")
    -- Gun Probe captured a LocalScript issuing a 10,000-stud Exclude ray;
    -- the report contains only its name, so this descendant fixture is a
    -- conditional test, not proof of the real caller's identity.
    local gunLocalScript = Instance.new("LocalScript")
    gunLocalScript.Name = "LocalScript"
    gunLocalScript.Parent = nativeGun
    getcallingscript = function() return gunLocalScript end
    local observedLength = Vector3.new(0, 0, -10000)
    local nativeParams = {FilterType = Enum.RaycastFilterType.Exclude}
    installed(workspace, origin, observedLength, nativeParams)
    assert(captured.n == 3 and captured[2] ~= observedLength
        and math.abs(captured[2].Magnitude - 10000) < 0.01 and captured[3] == nativeParams,
        "attributed observed-signature Raycast lost range or filter")
    getcallingscript = nil
    gunLocalScript.Parent = nil
    local compatibility = ex.state.toggleControls["MVSD.SilentAIM.RaycastCompatibility"]
    assert(compatibility, "OTH compatibility option missing")
    compatibility.setChecked(true)
    installed(workspace, origin, direction, nil)
    assert(captured.n == 3 and captured[2] ~= direction and math.abs(captured[2].Magnitude - 500) < 0.01,
        "OTH Raycast did not redirect/preserve native range and nil arguments")
    assert(workspace.CurrentCamera.CFrame == cameraBefore, "OTH moved camera")
    -- Vape-like scope can handle far origins with the opt-in enabled; without
    -- it, attribution/near-origin restrictions remain in force.
    local farOrigin = Vector3.new(100, 3, 0)
    installed(workspace, farOrigin, direction, nil)
    assert(captured[2] ~= direction, "Vape-like scope did not handle a distant origin")
    compatibility.setChecked(false)
    installed(workspace, farOrigin, direction, nil)
    assert(captured[2] == direction, "conservative mode redirected an unattributed distant origin")
    compatibility.setChecked(true)
    -- With Probe off, non-Raycast namecalls go straight through and must not
    -- run caller/target analysis or change nils/return values.
    currentOthMethod = "FireServer"
    local priorCheck, checkCalls = checkcaller, 0
    checkcaller = function() checkCalls += 1; return false end
    local passthrough, response = installed(workspace, "native", nil, true, nil)
    assert(passthrough == workspace and response == "ok" and captured.n == 4 and checkCalls == 0
        and captured[1] == "native" and captured[2] == nil and captured[4] == nil,
        "non-ray fast path modified native arguments or return values")
    checkcaller, currentOthMethod = priorCheck, "Raycast"
    local short = Vector3.new(0, 0, -1)
    installed(workspace, origin, short)
    assert(captured[2] == short, "OTH extended a native ray beyond its range")
    nativeHumanoid:EquipTool(nativeKnife)
    installed(workspace, origin, direction)
    assert(captured[2] ~= direction, "OTH did not handle the equipped knife's ray")
    local baselineKnifeRay = captured[2]
    local oldHeroVelocity = heroRoot.AssemblyLinearVelocity
    heroRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 20)
    local knifePrediction = ex.state.toggleControls["MVSD.SilentAIM.KnifePrediction"]
    assert(knifePrediction and not core.settings.knifePrediction, "independent Silent Knife Prediction missing")
    knifePrediction.setChecked(true)
    installed(workspace, origin, direction)
    assert(math.abs(captured[2].Z - baselineKnifeRay.Z) > 0.01 and not core.settings.knifePrediction,
        "Silent Knife Prediction did not lead motion or changed automatic Knife settings")
    knifePrediction.setChecked(false)
    heroRoot.AssemblyLinearVelocity = oldHeroVelocity
    nativeHumanoid:EquipTool(nativeGun)
    checkcaller = function() return true end
    installed(workspace, origin, direction)
    assert(captured[2] == direction, "OTH modified executor Raycast")
    checkcaller = function() return false end
    local cameraScript = Instance.new("LocalScript")
    cameraScript.Name = "CameraModule"
    getcallingscript = function() return cameraScript end
    installed(workspace, origin, direction)
    assert(captured[2] == direction, "OTH compatibility changed camera Raycast")
    getcallingscript = nil
    HarnessMatchData[HarnessHeroGuy].team = "Red"
    installed(workspace, origin, direction)
    assert(captured[2] == direction, "OTH targeted a teammate")
    HarnessMatchData[HarnessHeroGuy].team = "Blue"
    silentFeature.onToggle(false)
    installed(workspace, origin, direction)
    assert(captured[2] == direction, "OTH remained active after OFF")
    local node = installed
    silentFeature.onToggle(true)
    nativeNow += 0.2
    coreTask.callback(0.1)
    assert(installed == node, "OTH enabled a duplicate hook")
    installed(workspace, origin, direction)
    assert(captured[2] ~= direction, "OTH reusable node did not resume")
    -- A single OTH node is shared by Silent AIM and Gun Probe. Start passive
    -- observation while Silent is enabled, and verify both toggle orders.
    local oldEncode = HttpService.JSONEncode
    local snapshot, saveCount = nil, 0
    HttpService.JSONEncode = function(_, value)
        snapshot = table.clone(value)
        snapshot.events = table.clone(value.events)
        saveCount += 1
        return "{}"
    end
    local hookNode = installed
    local remote = Instance.new("RemoteEvent")
    remote.Name = "fire"
    remote.Parent = nativeGun
    probeCard.onToggle(true)
    assert(installed == hookNode and hookInstalls == 1 and saveCount >= 2
        and files["X2Duels-calibration.json"] == "{}",
        "probe installed a second OTH hook or missed the initial crash-safe snapshot")
    UserInputService.InputBegan:Fire({UserInputType = Enum.UserInputType.Touch, Position = Vector3.new(25, 25, 0)}, false)
    nativeGun.Activated:Fire()
    currentOthMethod = "Raycast"
    installed(workspace, origin, direction, nil)
    local redirectedArgs = captured
    assert(redirectedArgs[2] ~= direction and redirectedArgs.n == 3,
        "probe broke Silent Raycast or nil forwarding")
    currentOthMethod = "FireServer"
    installed(remote, "private-argument", nil, Vector3.new(1, 2, 3))
    assert(captured.n == 3 and captured[1] == "private-argument" and captured[2] == nil,
        "probe modified native FireServer arguments")
    currentOthMethod = "ViewportPointToRay"
    installed(workspace.CurrentCamera, 500, 250)
    for _, method in ipairs({"FindPartOnRay", "FindPartOnRayWithIgnoreList", "FindPartOnRayWithWhitelist"}) do
        currentOthMethod = method
        local resultObject, resultText = installed(workspace, "ray-placeholder", nil, true, nil)
        assert(resultObject == workspace and resultText == "ok" and captured.n == 4
            and captured[1] == "ray-placeholder" and captured[2] == nil and captured[3] == true
            and captured[4] == nil, "probe changed FindPartOnRay arguments or returns")
    end
    nativeNow += 3.1
    coreTask.callback(0.1)
    assert(saveCount >= 2, "probe did not periodically save partial evidence")
    local earlySnapshot = snapshot
    currentOthMethod = "Raycast"
    silentFeature.onToggle(false)
    installed(workspace, origin, direction)
    assert(captured[2] == direction, "probe alone modified aim")
    silentFeature.onToggle(true)
    nativeNow += 0.2
    coreTask.callback(0.1)
    installed(workspace, origin, direction)
    assert(captured[2] ~= direction and hookInstalls == 1, "shared hook did not resume Silent")
    for i = 1, 450 do installed(workspace, origin, direction) end
    currentOthMethod = "FireServer"
    installed(remote, "latest-shot")
    probeCard.onToggle(false)
    currentOthMethod = "Raycast"
    assert(snapshot and snapshot.backend == "Oth shared namecall" and snapshot.namecallHook
        and snapshot.aim.enabled and snapshot.aim.backend == "Oth namecall Raycast"
        and #snapshot.events == 400 and snapshot.dropped > 0,
        "probe omitted OTH/aim info or bounded buffer")
    local newest = snapshot.events[#snapshot.events - 1]
    assert(newest.event == "namecall" and newest.detail.method == "FireServer",
        "overflow discarded the latest evidence instead of the oldest")
    local foundCall, foundInput, foundRay, foundRedirect, foundCamera, foundActivation, foundAim = false, false, false, false, false, false, false
    local foundLegacyRays = {}
    for _, event in ipairs(earlySnapshot.events) do
        if event.event == "namecall" and event.detail.method == "FireServer" then
            foundCall = foundCall or (event.detail.object == "fire" and event.detail.argumentTypes[1] == "string"
                and event.detail.argumentTypes[2] == "nil" and event.detail.argumentTypes[3] == "Vector3"
                and event.detail.argumentValues == nil)
        elseif event.event == "namecall" and event.detail.method == "Raycast" then
            if event.detail.redirected then foundRedirect = true
            else foundRay = foundRay or (event.detail.origin[2] == 3 and event.detail.direction[3] == -500) end
        elseif event.event == "namecall" and string.sub(event.detail.method, 1, 13) == "FindPartOnRay" then foundLegacyRays[event.detail.method] = true
        elseif event.event == "namecall" and event.detail.method == "ViewportPointToRay" then foundCamera = true
        elseif event.event == "input_began" then foundInput = true
        elseif event.event == "tool_activated" then foundActivation = true
        elseif event.event == "aim_configuration" then foundAim = event.detail.enabled and event.detail.compatibility end
    end
    assert(foundCall and foundInput and foundRay and foundRedirect and foundCamera and foundActivation and foundAim
        and foundLegacyRays.FindPartOnRay and foundLegacyRays.FindPartOnRayWithIgnoreList
        and foundLegacyRays.FindPartOnRayWithWhitelist,
        "shared probe omitted touch, activation, input/redirected ray, camera or remote types")
    local count = #snapshot.events
    installed(workspace, origin, direction)
    assert(captured[2] ~= direction and #snapshot.events == count, "probe OFF disturbed Silent or kept recording")
    silentFeature.onToggle(false)
    compatibility.setChecked(false)
    probeCard.onToggle(true)
    assert(hookInstalls == 1, "probe ON reinstalled the hook")
    nativeNow += 61
    coreTask.callback(0.1)
    assert(string.find(probeCard.status, "60 seconds", 1, true), "probe did not expire safely")
    probeCard.onToggle(false)
    local previousWrite = writefile
    writefile = function() error("simulated writefile failure") end
    probeCard.onToggle(true)
    assert(string.find(probeCard.status, "save failed", 1, true), "probe hid writefile failure")
    probeCard.onToggle(false)
    writefile = previousWrite
    HttpService.JSONEncode = function() error("simulated JSON failure") end
    probeCard.onToggle(true)
    assert(string.find(probeCard.status, "JSONEncode", 1, true), "JSON encoding failure not reported")
    probeCard.onToggle(false)
    writefile, readfile, isfile = previousWriteFile, previousReadFile, previousIsFile
    HttpService.JSONEncode = oldEncode
    remote.Parent = nil
    oth, getrawmetatable, getnamecallmethod, checkcaller, getcallingscript, debug = oldOth, oldMeta, oldMethod, oldCheck, oldCaller, oldDebug
    hookmetamethod, hookfunction = previousHookMeta, previousHookFunction
end
core.settings.silentBackend = "Legacy" -- historical integration tests only
local shotsAtStart = nativeGunShots
senderBinding.onPress()
assert(nativeGunShots == shotsAtStart, "Silent AIM action fired while disabled")
silentFeature.activate()
assert(silentFeature.enabled and core.settings.silentAim, "Silent AIM did not enable through its card")

-- Without a usable adapter the button still equips, but must not spend a
-- shot aimed at the user's ordinary cursor and claim it was silent.
do
local cameraBeforeKey = workspace.CurrentCamera.CFrame
senderBinding.onPress()
assert(nativeGun.Parent == nativeLocal.Character and nativeGunShots == shotsAtStart,
    "unsupported executor did not equip safely or fired an unredirected shot")
assert(string.find(silentFeature.status, "unavailable", 1, true),
    "unsupported executor was not diagnosed")
silentFeature.activate()

-- Model the decompiled shared MouseCast contract. This is a fixture, not
-- evidence that the missing native Gun LocalScript uses it in the live game.
local oldVector2New = Vector2.new
Vector2.new = function(x, y) return setmetatable({X = x or 0, Y = y or 0}, Vector2) end
HarnessMouseCastReady = true
local nativeGunScript = Instance.new("LocalScript")
nativeGunScript.Name = "LocalScript"
nativeGunScript.Parent = nativeGun
local pingScript = Instance.new("LocalScript")
pingScript.Name = "PingsController"
pingScript.Parent = X2Networking
local oldGetCallingScript = getcallingscript
local nativeCaller = nativeGunScript
getcallingscript = function() return nativeCaller end
local nativeRaycast = workspace.Raycast
local lastAimRay = nil
workspace.Raycast = function(_self, origin, direction, parameters)
    lastAimRay = {origin = origin, direction = direction, parameters = parameters}
    return {Instance = nativeTarget.part}
end
local cameraAtActivation = nil
nativeGun.Activate = function()
    nativeGunShots += 1
    cameraAtActivation = workspace.CurrentCamera.CFrame
    local result, endpoint = HarnessMouseCast:WithPositionExclude(
        Vector2.new(1070, 615), {nativeLocal.Character}
    )
    assert(result and result.Instance == nativeTarget.part, "native MouseCast did not see the target")
    assert(endpoint.X > 0 and lastAimRay.direction.Magnitude > 499.99
        and lastAimRay.direction.Magnitude < 500.01, "aim endpoint/range changed")
    assert(lastAimRay.parameters.FilterType == Enum.RaycastFilterType.Exclude
        and lastAimRay.parameters.FilterDescendantsInstances[1] == nativeLocal.Character,
        "native touch cast filters were not preserved")
end
silentFeature.activate()
assert(core.settings.silentAim and string.find(silentFeature.status, "unconfirmed", 1, true),
    "loading an adapter was falsely reported as proven gun support")
local enabledBeforeKey = silentFeature.enabled
senderBinding.onPress()
assert(nativeGunShots == shotsAtStart + 1 and silentFeature.enabled == enabledBeforeKey,
    "enabled action did not activate the gun independently of its toggle")
assert(cameraAtActivation == cameraBeforeKey and workspace.CurrentCamera.CFrame == cameraBeforeKey,
    "Silent action visibly moved the camera")
assert(string.find(silentFeature.status, "redirected", 1, true),
    "real intercepted aim input was not distinguished from an attempted shot")

-- Shared MouseCast is also used by PingsController: an unrelated script must
-- retain BOTH original return values and never consume the authored raycast.
nativeCaller = pingScript
lastAimRay = nil
local pingResult, pingEnd = HarnessMouseCast:Exclude({nativeLocal.Character})
assert(pingResult == "original" and pingEnd == "original endpoint" and lastAimRay == nil,
    "a ping was redirected while the local gun was equipped")
nativeCaller = nativeGunScript
local testParams = {fixture = "native params"}
local targetResult, aimedEndpoint = HarnessMouseCast:WithParams(testParams)
assert(targetResult.Instance == nativeTarget.part and lastAimRay.parameters == testParams
    and aimedEndpoint.X > 0, "WithParams did not retain native parameters")
local include = {HarnessHeroGuy.Character}
HarnessMouseCast:WithPositionInclude(Vector2.new(15, 500), include)
assert(lastAimRay.parameters.FilterType == Enum.RaycastFilterType.Include
    and lastAimRay.parameters.FilterDescendantsInstances == include,
    "mobile Include filter was changed")

-- Stack attribution supports an executor without getcallingscript only when
-- the source names this player's actual Tool/LocalScript. Other sources pass.
local savedDebug = debug
getcallingscript = nil
debug = {info = function(level)
    if level == 3 then return "Players.HarnessPlayer.Backpack.Gun.LocalScript" end
    return "ReplicatedStorage.Client.Modules.MouseCast"
end}
lastAimRay = nil
HarnessMouseCast:Exclude({nativeLocal.Character})
assert(lastAimRay and lastAimRay.direction.X > 0, "weapon stack attribution was not used")
getcallingscript = function() return pingScript end
lastAimRay = nil
assert(HarnessMouseCast:Exclude({nativeLocal.Character}) == "original" and not lastAimRay,
    "an explicit foreign caller was overridden by a weapon-looking stack")
getcallingscript = nil
debug = {info = function() return "Players.HarnessPlayer.Backpack.Gun.LocalScriptImpostor" end}
lastAimRay = nil
assert(HarnessMouseCast:Exclude({nativeLocal.Character}) == "original" and not lastAimRay,
    "a source name with an extra suffix was treated as the weapon")
debug = {info = function() return "ReplicatedStorage.Client.Controllers.PingsController" end}
lastAimRay = nil
assert(HarnessMouseCast:Exclude({nativeLocal.Character}) == "original" and not lastAimRay,
    "unknown stack source was treated as a weapon")
debug = savedDebug
getcallingscript = function() return nativeCaller end

-- A 500-stud MouseCast must not silently grow to reach an out-of-range target.
local targetPosition = nativeTarget.part.Position
nativeTarget.part.Position = Vector3.new(550, 4, 0)
coreTask.callback(0.1)
lastAimRay = nil
assert(HarnessMouseCast:Exclude({nativeLocal.Character}) == "original" and not lastAimRay,
    "MouseCast was extended beyond the captured native 500-stud reach")
nativeTarget.part.Position = targetPosition
nativeNow += 0.2
coreTask.callback(0.1)

-- The button reports blocked walls, range, team, disabled tool and inventory
-- separately; status rows use a full-width wrapping label on mobile.
local statusLabel = nil
for _, row in ipairs(silentFeature.optionRows) do
    local label = row:FindFirstChild("OptionLabel")
    if label and label.Text == "Status" then statusLabel = row:FindFirstChild("StatValue") end
end
assert(statusLabel and statusLabel.TextWrapped and statusLabel.TextTruncate == Enum.TextTruncate.None,
    "combat status remains truncated")
local wall = Instance.new("Part")
workspace.Raycast = function() return {Instance = wall} end
core.settings.wallCheck = true
local previousShots = nativeGunShots
senderBinding.onPress()
assert(nativeGunShots == previousShots and string.find(silentFeature.status, "wall", 1, true)
    and statusLabel.Text == silentFeature.status, "wall did not stop and explain the button shot")
workspace.Raycast = nativeRaycast
core.settings.wallCheck = false
core.settings.maxDistance = 5
senderBinding.onPress()
assert(nativeGunShots == previousShots and string.find(silentFeature.status, "range", 1, true),
    "range rejection was not explained")
core.settings.maxDistance = 1000
HarnessMatchData[HarnessHeroGuy].team = "Red"
senderBinding.onPress()
assert(nativeGunShots == previousShots and string.find(silentFeature.status, "opponent", 1, true),
    "teammate/no-target rejection was not explained")
HarnessMatchData[HarnessHeroGuy].team = "Blue"
nativeGun.Enabled = false
senderBinding.onPress()
assert(nativeGunShots == previousShots and string.find(silentFeature.status, "reloading", 1, true),
    "disabled/reloading gun was not explained")
nativeGun.Enabled = true
nativeGun.Parent = nil
senderBinding.onPress()
assert(nativeGunShots == previousShots and string.find(silentFeature.status, "inventory", 1, true),
    "missing gun was not explained")

-- A real wait is simulated with a suspended coroutine: no activation before
-- Heartbeat, no duplicate presses, and no stale shot after OFF/team change.
workspace.Raycast = function(_self, origin, direction, parameters)
    lastAimRay = {origin = origin, direction = direction, parameters = parameters}
    return {Instance = nativeTarget.part}
end
local savedSpawn = task.spawn
local heartbeat = game:GetService("RunService").Heartbeat
local savedHeartbeatWait = heartbeat.Wait
local equipThread = nil
task.spawn = function(fn)
    equipThread = coroutine.create(fn)
    local ok, err = coroutine.resume(equipThread)
    assert(ok, tostring(err))
end
heartbeat.Wait = function() coroutine.yield() end
nativeGun.Parent = nativeBackpack
senderBinding.onPress()
assert(nativeGun.Parent == nativeLocal.Character and nativeGunShots == previousShots
    and equipThread and coroutine.status(equipThread) == "suspended",
    "gun activated before the post-equip Heartbeat")
local firstThread = equipThread
senderBinding.onPress()
assert(equipThread == firstThread and nativeGunShots == previousShots,
    "duplicate button press replaced the pending equip")
silentFeature.activate()
local okResume, resumeError = coroutine.resume(firstThread)
assert(okResume, tostring(resumeError))
assert(nativeGunShots == previousShots, "disabling Silent did not cancel pending shot")
-- Let hook discovery finish synchronously before the next simulated wait.
task.spawn = savedSpawn
silentFeature.activate()
task.spawn = function(fn)
    equipThread = coroutine.create(fn)
    local ok, err = coroutine.resume(equipThread)
    assert(ok, tostring(err))
end
nativeGun.Parent = nativeBackpack
senderBinding.onPress()
HarnessMatchData[HarnessHeroGuy].team = "Red"
okResume, resumeError = coroutine.resume(equipThread)
assert(okResume, tostring(resumeError))
assert(nativeGunShots == previousShots, "target became a teammate during equip but was attacked")
HarnessMatchData[HarnessHeroGuy].team = "Blue"
nativeGun.Parent = nativeBackpack
senderBinding.onPress()
okResume, resumeError = coroutine.resume(equipThread)
assert(okResume, tostring(resumeError))
assert(nativeGunShots == previousShots + 1 and workspace.CurrentCamera.CFrame == cameraBeforeKey,
    "post-Heartbeat gun did not activate silently")
task.spawn = savedSpawn
heartbeat.Wait = savedHeartbeatWait

-- A third-party wrapper installed after us survives OFF. Our retained wrapper
-- remains inert after a later ON/OFF rather than reactivating in its chain.
local retiredMouseCast = HarnessMouseCast.Exclude
local foreignMouseCast = function(...) return retiredMouseCast(...) end
HarnessMouseCast.Exclude = foreignMouseCast
silentFeature.activate()
assert(HarnessMouseCast.Exclude == foreignMouseCast, "OFF displaced another MouseCast wrapper")
local beforeRetired = #HarnessMouseCalls
assert(HarnessMouseCast:Exclude({nativeLocal.Character}) == "original"
    and #HarnessMouseCalls == beforeRetired + 1, "retired wrapper did not pass through")
silentFeature.activate()
nativeCaller = pingScript
assert(HarnessMouseCast:Exclude({nativeLocal.Character}) == "original",
    "re-enabled wrapper redirected the ping chain")
silentFeature.activate()
assert(HarnessMouseCast.Exclude == foreignMouseCast, "foreign MouseCast chain was not restored")
HarnessMouseCast.Exclude = function(...) return "original", "original endpoint" end
getcallingscript = oldGetCallingScript
Vector2.new = oldVector2New
workspace.Raycast = nativeRaycast
nativeGun.Activate = function() nativeGunShots += 1 end
end

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

-- Auto Shoot uses the same equip wait and must not fire after being disabled
-- or after its target changes team during that wait.
do
    local savedSpawn = task.spawn
    local heartbeat = game:GetService("RunService").Heartbeat
    local savedWait = heartbeat.Wait
    local thread = nil
    task.spawn = function(fn)
        thread = coroutine.create(fn)
        local ok, err = coroutine.resume(thread)
        assert(ok, tostring(err))
    end
    heartbeat.Wait = function() coroutine.yield() end
    nativeGun.Parent = nativeBackpack
    local before = nativeGunShots
    autoShootFeature.onToggle(true)
    nativeNow += 1
    coreTask.callback(0.1)
    assert(thread and coroutine.status(thread) == "suspended" and nativeGunShots == before,
        "Auto Shoot fired before the equip Heartbeat")
    autoShootFeature.onToggle(false)
    local ok, err = coroutine.resume(thread)
    assert(ok, tostring(err))
    assert(nativeGunShots == before, "Auto Shoot fired after being switched off")
    nativeGun.Parent = nativeBackpack
    autoShootFeature.onToggle(true)
    nativeNow += 1
    coreTask.callback(0.1)
    HarnessMatchData[HarnessHeroGuy].team = "Red"
    ok, err = coroutine.resume(thread)
    assert(ok, tostring(err))
    assert(nativeGunShots == before, "Auto Shoot fired at a new teammate after equip")
    HarnessMatchData[HarnessHeroGuy].team = "Blue"
    autoShootFeature.onToggle(false)
    task.spawn = savedSpawn
    heartbeat.Wait = savedWait
end

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
-- Knife Throw's optional prediction is independent of Silent AIM and is
-- applied to the native mobile aim, without editing packets or guessing hits.
do
    local predictionToggle = ex.state.toggleControls["MVSD.KnifeThrow.ProjectilePrediction"]
    assert(predictionToggle and not core.settings.silentKnifePrediction, "automatic prediction option missing")
    local oldLookAt, oldVelocity = CFrame.lookAt, heroRoot.AssemblyLinearVelocity
    local aimed = nil
    CFrame.lookAt = function(a, b) aimed = b; return oldLookAt(a, b) end
    heroRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 20)
    predictionToggle.setChecked(true)
    assert(core.fireKnife(nativeTarget, false, {owner = "Knife Throw", wallCheck = false}), "predicted mobile knife failed")
    assert(aimed and aimed.Z > nativeTarget.part.Position.Z and not core.settings.silentKnifePrediction,
        "automatic Knife prediction did not lead target or changed Silent settings")
    predictionToggle.setChecked(false)
    assert(core.fireKnife(nativeTarget, false, {owner = "Knife Throw", wallCheck = false}), "plain mobile knife failed")
    assert(aimed == nativeTarget.part.Position, "disabled Knife Prediction still led target")
    CFrame.lookAt, heroRoot.AssemblyLinearVelocity = oldLookAt, oldVelocity
end
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
-- The same independent prediction applies on the desktop right-click path.
do
    local predictionToggle = ex.state.toggleControls["MVSD.KnifeThrow.ProjectilePrediction"]
    local oldLookAt, oldVelocity = CFrame.lookAt, heroRoot.AssemblyLinearVelocity
    local aimed, beforeDown, beforeUp = nil, nativeMouseDown, nativeMouseUp
    CFrame.lookAt = function(a, b) aimed = b; return oldLookAt(a, b) end
    heroRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 20)
    predictionToggle.setChecked(true)
    assert(core.fireKnife(nativeTarget, false, {owner = "Knife Throw", wallCheck = false}), "predicted desktop knife failed")
    assert(aimed and aimed.Z > nativeTarget.part.Position.Z and nativeMouseDown == beforeDown + 1
        and nativeMouseUp == beforeUp + 1 and not core.settings.silentKnifePrediction,
        "desktop prediction did not lead, release input, or was not independent")
    predictionToggle.setChecked(false)
    CFrame.lookAt, heroRoot.AssemblyLinearVelocity = oldLookAt, oldVelocity
end
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

-- Exercise the optional legacy Mouse.Hit/Target adapter. The fixture only
-- proves caller scoping and cleanup, not which API the real X2 gun reads.
do
    local nativeMouse = Instance.new("Mouse")
    local otherMouse = Instance.new("Mouse")
    local oldGetMouse = nativeLocal.GetMouse
    nativeLocal.GetMouse = function() return nativeMouse end
    local gunScript = Instance.new("LocalScript")
    gunScript.Name = "LocalScript"
    gunScript.Parent = nativeGun
    local otherScript = Instance.new("LocalScript")
    otherScript.Name = "PingsController"
    otherScript.Parent = X2Networking
    nativeHumanoid:EquipTool(nativeGun)
    local fireRemote, beamRemote = Instance.new("RemoteEvent"), Instance.new("RemoteEvent")
    fireRemote.Name, beamRemote.Name = "fire", "showBeam"
    fireRemote.Parent, beamRemote.Parent = nativeGun, nativeGun
    local nativeHit = CFrame.new(Vector3.new(-9, 0, 0))
    local originalIndex = function(_object, key)
        return key == "Hit" and nativeHit or "native target"
    end
    local currentIndex = originalIndex
    local originalNamecall = function() end
    local currentNamecall = originalNamecall
    local caller = gunScript
    local oldHookMeta, oldCaller, oldMethod = hookmetamethod, getcallingscript, getnamecallmethod
    local oldDebug, oldCheckCaller = debug, checkcaller
    local oldRawMeta, oldReadonly, oldIsReadonly = getrawmetatable, setreadonly, isreadonly
    local originalGunActivate = nativeGun.Activate
    hookmetamethod = function(_game, method, replacement)
        if method == "__index" then
            local previous = currentIndex
            currentIndex = replacement
            return previous
        elseif method == "__namecall" then
            local previous = currentNamecall
            currentNamecall = replacement
            return previous
        end
        error("unexpected metamethod")
    end
    getcallingscript = function() return caller end
    getnamecallmethod = function() return "FireServer" end
    core.settings.wallCheck = false
    silentFeature.onToggle(true)
    nativeNow += 1
    coreTask.callback(0.1)
    local cameraBefore = workspace.CurrentCamera.CFrame
    local hit = currentIndex(nativeMouse, "Hit")
    assert(typeof(hit) == "CFrame" and hit.Position == nativeTarget.part.Position
        and currentIndex(nativeMouse, "Target") == nativeTarget.part,
        "proven weapon Mouse.Hit/Target was not redirected")
    assert(workspace.CurrentCamera.CFrame == cameraBefore, "Mouse adapter rotated the camera")
    caller = otherScript
    assert(currentIndex(nativeMouse, "Hit") == nativeHit
        and currentIndex(otherMouse, "Target") == "native target", "foreign Mouse access was changed")
    caller = gunScript

    -- Target Part belongs to Silent only: other cards keep their own default.
    local partControl = ex.state.valueControls["MVSD.SilentAIM.TargetPart"]
    local torso = HarnessHeroGuy.Character:FindFirstChild("UpperTorso")
    partControl.apply("Body")
    nativeNow += 0.1
    coreTask.callback(0.1)
    assert(currentIndex(nativeMouse, "Target") == torso,
        "Body did not select the R15 torso")
    assert(core.targetFor(HarnessHeroGuy).part == nativeTarget.part,
        "Silent Target Part leaked into the shared/default Auto Shoot target")
    local originalTorsoParent = torso.Parent
    torso.Parent = nil
    nativeNow += 0.1
    coreTask.callback(0.1)
    assert(currentIndex(nativeMouse, "Target") == HarnessHeroGuy.Character:FindFirstChild("Torso"),
        "Body did not fall back to an R6 torso")
    torso.Parent = originalTorsoParent
    partControl.apply("Head")
    nativeNow += 0.1
    coreTask.callback(0.1)
    assert(currentIndex(nativeMouse, "Target") == nativeTarget.part,
        "Head did not restore the head target")

    -- Aim FOV uses screen pixels and nearest cursor, independent of world
    -- distance and the other cards. Revalidate even between selection ticks.
    local camera = workspace.CurrentCamera
    local oldProjection = camera.WorldToScreenPoint
    local inputService = game:GetService("UserInputService")
    local oldMouseLocation = inputService.GetMouseLocation
    local secondPlayer = Instance.new("Player")
    secondPlayer.Name, secondPlayer.UserId = "FovOpponent", 12345
    secondPlayer.Parent = game:GetService("Players")
    local secondCharacter = Instance.new("Model")
    secondCharacter.Parent = workspace
    secondPlayer.Character = secondCharacter
    local secondHumanoid = Instance.new("Humanoid")
    secondHumanoid.Health, secondHumanoid.Parent = 100, secondCharacter
    local secondRoot = Instance.new("Part")
    secondRoot.Name, secondRoot.Position, secondRoot.Parent = "HumanoidRootPart", Vector3.new(30, 3, 0), secondCharacter
    local secondHead = Instance.new("Part")
    secondHead.Name, secondHead.Position, secondHead.Parent = "Head", Vector3.new(30, 4.5, 0), secondCharacter
    HarnessMatchData[secondPlayer] = {gameId = "HarnessMatchOne", team = "Blue", mode = "TeamBased", dead = false}
    local allOffscreen = false
    camera.WorldToScreenPoint = function(_self, position)
        if allOffscreen then return Vector3.new(900, 200, 1), false end
        if position.X > 20 then return Vector3.new(405, 205, 1), true end
        return Vector3.new(490, 200, 1), true
    end
    inputService.GetMouseLocation = function() return Vector2.new(400, 200) end
    local fovControl = ex.state.toggleControls["MVSD.SilentAIM.AimFOV"]
    local radiusControl = ex.state.valueControls["MVSD.SilentAIM.AimFOVRadius"]
    radiusControl.apply(120)
    fovControl.setChecked(true)
    nativeNow += 0.1
    coreTask.callback(0.1)
    assert(currentIndex(nativeMouse, "Target") == secondHead,
        "Aim FOV did not prefer the opponent closest to the PC cursor")
    assert(core.nearestEnemy(1000, true, false, false).player == HarnessHeroGuy,
        "Silent Aim FOV leaked into independent automatic targeting")
    allOffscreen = true
    assert(currentIndex(nativeMouse, "Hit") == nativeHit,
        "Aim FOV retained a target that went offscreen before the next tick")
    local shotsBeforeFov = nativeGunShots
    senderBinding.onPress()
    assert(nativeGunShots == shotsBeforeFov and string.find(silentFeature.status, "FOV", 1, true),
        "FOV rejection did not stop and explain the manual action")
    radiusControl.apply(math.huge)
    senderBinding.onPress()
    assert(nativeGunShots == shotsBeforeFov,
        "an infinite radius incorrectly accepted an offscreen opponent")
    radiusControl.apply(200)
    fovControl.setChecked(false)
    secondPlayer.Parent = nil
    secondCharacter.Parent = nil
    HarnessMatchData[secondPlayer] = nil
    camera.WorldToScreenPoint = oldProjection
    inputService.GetMouseLocation = oldMouseLocation
    nativeNow += 0.1
    coreTask.callback(0.1)

    -- No caller/debug API: the action gets a short, one-gun Mouse lease.
    -- These are fake hooks/native reads, not evidence of real mobile support.
    getcallingscript, debug = nil, {}
    checkcaller = function() return false end
    assert(currentIndex(nativeMouse, "Hit") == nativeHit,
        "anonymous native read redirected before the action")
    local anonymousHit = nil
    local cameraAtAnonymous = nil
    nativeGun.Activate = function()
        nativeGunShots += 1
        cameraAtAnonymous = workspace.CurrentCamera.CFrame
        anonymousHit = currentIndex(nativeMouse, "Hit")
    end
    local anonymousShots = nativeGunShots
    senderBinding.onPress()
    assert(nativeGunShots == anonymousShots + 1 and typeof(anonymousHit) == "CFrame"
        and anonymousHit.Position == nativeTarget.part.Position,
        "the scoped action did not redirect an anonymous native Mouse.Hit")
    assert(cameraAtAnonymous == cameraBefore and workspace.CurrentCamera.CFrame == cameraBefore,
        "anonymous action moved the camera")
    assert(currentIndex(otherMouse, "Hit") == nativeHit
        and currentIndex(nativeMouse, "UnitRay") == "native target",
        "anonymous action touched another Mouse or an unverified ray")
    nativeNow += 0.21
    coreTask.callback(0.1)
    assert(currentIndex(nativeMouse, "Hit") == nativeHit,
        "anonymous action lease did not expire")

    local compatibility = {setChecked = function(value) core.settings.mouseCompatibility = value end}
    compatibility.setChecked(true)
    assert(currentIndex(nativeMouse, "Target") == nativeTarget.part,
        "explicit compatibility did not permit an anonymous native Mouse.Target")
    checkcaller = function() return true end
    assert(currentIndex(nativeMouse, "Hit") == nativeHit, "executor's own Mouse read was redirected")
    checkcaller = function() error("unsupported") end
    assert(currentIndex(nativeMouse, "Hit") == nativeHit, "failed checkcaller was trusted")
    checkcaller = function() return false end
    getcallingscript = function() return otherScript end
    assert(currentIndex(nativeMouse, "Hit") == nativeHit,
        "explicit foreign caller bypassed compatibility protection")
    getcallingscript = nil
    beamRemote.Parent = nil
    assert(currentIndex(nativeMouse, "Hit") == nativeHit, "unrecognized gun signature was redirected")
    beamRemote.Parent = nativeGun
    HarnessMatchData[HarnessHeroGuy].team = "Red"
    assert(currentIndex(nativeMouse, "Hit") == nativeHit, "compatibility targeted a teammate")
    HarnessMatchData[HarnessHeroGuy].team = "Blue"
    HarnessMatchData[HarnessHeroGuy].gameId = "DifferentGame"
    assert(currentIndex(nativeMouse, "Hit") == nativeHit, "compatibility targeted another match")
    HarnessMatchData[HarnessHeroGuy].gameId = "HarnessMatchOne"
    core.settings.wallCheck = true
    local savedRaycast = workspace.Raycast
    local blockingPart = Instance.new("Part")
    workspace.Raycast = function() return {Instance = blockingPart} end
    assert(currentIndex(nativeMouse, "Hit") == nativeHit, "compatibility ignored Wall Check")
    workspace.Raycast = savedRaycast
    core.settings.wallCheck = false
    nativeHumanoid:EquipTool(nativeKnife)
    assert(currentIndex(nativeMouse, "Hit") == nativeHit, "compatibility changed a knife read")
    nativeHumanoid:EquipTool(nativeGun)
    compatibility.setChecked(false)
    assert(currentIndex(nativeMouse, "Hit") == nativeHit, "compatibility OFF did not stop anonymous aim")
    nativeGun.Activate = originalGunActivate
    debug = oldDebug
    getcallingscript = function() return caller end
    caller = gunScript
    local retiredIndex = currentIndex
    local foreignIndex = function(...) return retiredIndex(...) end
    currentIndex = foreignIndex
    silentFeature.onToggle(false)
    assert(currentIndex == foreignIndex and currentIndex(nativeMouse, "Hit") == nativeHit,
        "OFF removed or left active another Mouse hook")
    silentFeature.onToggle(true)
    assert(retiredIndex(nativeMouse, "Hit") == nativeHit,
        "retired Mouse hook was resurrected when Silent was re-enabled")
    silentFeature.onToggle(false)
    assert(currentIndex == foreignIndex, "second OFF displaced foreign Mouse hook")

    -- Some mobile executors expose raw metatable APIs instead of a functional
    -- hookmetamethod. The fallback preserves both read-only states and chains.
    hookmetamethod, getcallingscript, debug = nil, nil, {}
    checkcaller = function() return false end
    local rawMeta = {__index = originalIndex}
    local rawReadonly = true
    getrawmetatable = function(object) assert(object == game); return rawMeta end
    isreadonly = function(meta) assert(meta == rawMeta); return rawReadonly end
    setreadonly = function(meta, value) assert(meta == rawMeta); rawReadonly = value end
    compatibility.setChecked(true)
    silentFeature.onToggle(true)
    nativeNow += 0.1
    coreTask.callback(0.1)
    assert(rawMeta.__index ~= originalIndex and rawReadonly,
        "raw Mouse hook was not installed with read-only state preserved")
    assert(rawMeta.__index(nativeMouse, "Target") == nativeTarget.part,
        "raw Mouse fallback did not redirect an anonymous native target")
    silentFeature.onToggle(false)
    assert(rawMeta.__index == originalIndex and rawReadonly,
        "raw Mouse hook did not restore the original function/state")
    rawReadonly = false
    hookmetamethod = function() error("synthetic unsupported hookmetamethod") end
    silentFeature.onToggle(true)
    nativeNow += 0.1
    coreTask.callback(0.1)
    assert(not rawReadonly, "raw installation froze a previously writable metatable")
    local retiredRaw = rawMeta.__index
    local foreignRaw = function(...) return retiredRaw(...) end
    rawMeta.__index = foreignRaw
    silentFeature.onToggle(false)
    assert(rawMeta.__index == foreignRaw and not rawReadonly
        and rawMeta.__index(nativeMouse, "Hit") == nativeHit,
        "raw cleanup displaced a newer hook or left our node active")
    silentFeature.onToggle(true)
    assert(retiredRaw(nativeMouse, "Hit") == nativeHit,
        "retired raw hook resurrected after ON")
    silentFeature.onToggle(false)
    assert(rawMeta.__index == foreignRaw and not rawReadonly,
        "raw second cleanup displaced a newer hook")
    rawMeta.__index = originalIndex
    isreadonly = nil
    silentFeature.onToggle(true)
    assert(rawMeta.__index == originalIndex,
        "raw fallback guessed the original read-only state")
    anonymousShots = nativeGunShots
    senderBinding.onPress()
    assert(nativeGunShots == anonymousShots
        and string.find(silentFeature.status, "unavailable", 1, true),
        "missing raw capability spent a shot instead of reporting unsupported")
    silentFeature.onToggle(false)
    compatibility.setChecked(false)
    hookmetamethod, getcallingscript, getnamecallmethod = oldHookMeta, oldCaller, oldMethod
    getrawmetatable, setreadonly, isreadonly = oldRawMeta, oldReadonly, oldIsReadonly
    debug, checkcaller = oldDebug, oldCheckCaller
    nativeGun.Activate = originalGunActivate
    fireRemote.Parent, beamRemote.Parent = nil, nil
    nativeLocal.GetMouse = oldGetMouse
    nativeHumanoid:EquipTool(nativeKnife)
end

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
silentFeature.onToggle(true)
nativeNow += 1
coreTask.callback(0.1)
ownNamecall(netRemote, guid, frame, untouched)
assert(packet.arguments[3] == untouched, "retired namecall hook resurrected on re-enable")
ownRay(workspace, frame.Position, originalDirection)
assert(rayDirection == originalDirection, "retired ray hook resurrected on re-enable")
silentFeature.onToggle(false)
assert(currentNamecall == foreignNamecall and currentRay == foreignRay,
    "second cleanup displaced another hook")
hookfunction, hookmetamethod = oldHookFunction, oldHookMeta
getcallingscript, getnamecallmethod = oldGetCaller, oldGetMethod
workspace.Raycast = previousWorkspaceRay
RaycastParams = oldRaycastParams
nativeTarget.part.Position = oldTargetPos
nativeLocal.Character:FindFirstChild("HumanoidRootPart").Position = oldRootPos
workspace.CurrentCamera.CFrame = oldCameraCFrame

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
    and string.find(autoShootFeature.status, "outside the selected range", 1, true),
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
    and string.find(knifeThrowFeature.status, "outside the selected range", 1, true),
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
print("[X2BOOT] 8 cards, probe, independent combat, safe/rematch, duel stats, cleanup: PASS")
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
    marker = "[X2BOOT] 8 cards, probe, independent combat, safe/rematch, duel stats, cleanup: PASS"
    if marker not in output:
        raise AssertionError("X2 bundle boot marker missing\n" + output)
    print(marker)

    # Boot the actual mobile Wurst UI and fire through its touch placement /
    # InputBegan + InputEnded chain, not just the shortcut callback in isolation.
    mobile_boot = audit_menu.build(debug=True).read_text(encoding="utf-8")
    mobile_boot = mobile_boot.replace(
        place_anchor,
        "game = {\n    PlaceId = 124848751642883,\n    GameId = 20260716,",
        1,
    )
    mobile_setup = remote_setup + r'''
UserInputService.props.TouchEnabled = true
UserInputService.props.KeyboardEnabled = false
HarnessMatchReady = true
HarnessMouseCastReady = true
'''
    mobile_boot = mobile_boot.replace(boot_anchor, "\n" + mobile_setup + boot_anchor, 1)
    mobile_boot += r'''
assert(ex.state.isMobile, "mobile fixture did not boot touch UI")
local feature = nil
for _, candidate in ipairs(ex.allFeatures) do
    if candidate.sectionName == "MVSD" and candidate.name == "Silent AIM" then feature = candidate end
end
assert(feature and feature.shortcutButton, "mobile Silent action slot missing")
ex.state.x2duelsCore.settings.silentBackend = "Legacy" -- historical touch fixture
local localPlayer = game:GetService("Players").LocalPlayer
local backpack = localPlayer:FindFirstChildOfClass("Backpack")
local humanoid = localPlayer.Character:FindFirstChildOfClass("Humanoid")
humanoid.EquipTool = function(_self, tool) tool.Parent = localPlayer.Character end
local gun = Instance.new("Tool")
gun.Name = "DefaultGun"
gun.Enabled = true
gun.Parent = backpack
local gunScript = Instance.new("LocalScript")
gunScript.Name = "LocalScript"
gunScript.Parent = gun
getcallingscript = function() return gunScript end
Vector2.new = function(x, y) return setmetatable({X = x or 0, Y = y or 0}, Vector2) end
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
RaycastParams = {new = function() return {} end}
local target = ex.state.x2duelsCore.targetFor(HarnessHeroGuy)
local lastDirection = nil
workspace.Raycast = function(_self, _origin, direction)
    lastDirection = direction
    return {Instance = target.part}
end
local shots = 0
local camera = workspace.CurrentCamera
camera.CFrame = CFrame.new(Vector3.new(0, 3, 0))
local cameraBefore = camera.CFrame
gun.Activate = function()
    shots += 1
    local hit = HarnessMouseCast:WithPositionExclude(Vector2.new(1050, 600), {localPlayer.Character})
    assert(hit and hit.Instance == target.part and lastDirection and lastDirection.X > 0,
        "mobile touch did not redirect the fixture gun")
end
feature.activate()
assert(feature.enabled, "Silent did not enable on mobile")
-- Real delays are asynchronous; queue them instead of triggering the mock's
-- 0.75s long-press editor timer before the simulated finger lifts.
local oldDelay = task.delay
local delayed = {}
task.delay = function(seconds, callback, ...)
    table.insert(delayed, {seconds = seconds, callback = callback, arguments = table.pack(...)})
end
feature.shortcutButton.MouseButton1Click:Fire()
local overlay = CoreGui:FindFirstChild("Wurst"):FindFirstChild("PopupLayer"):FindFirstChild("MobilePlacementOverlay")
assert(overlay and overlay.Visible, "shortcut square did not start mobile placement")
local placementTouch = {UserInputType = Enum.UserInputType.Touch, Position = Vector3.new(1000, 550, 0)}
overlay.InputBegan:Fire(placementTouch)
local id = ex.state.mobileUi.actionId(feature.configKey)
local action = ex.state.mobileUi.actions[id]
assert(action and action.button, "mobile action was not placed")
ex.state.setMenuVisible(false)
local touch = {UserInputType = Enum.UserInputType.Touch, Position = Vector3.new(1000, 550, 0)}
action.button.InputBegan:Fire(touch)
assert(shots == 0, "non-hold mobile action activated before touch release")
UserInputService.InputEnded:Fire(touch)
assert(shots == 1 and gun.Parent == localPlayer.Character and feature.enabled,
    "mobile touch release did not equip and activate the gun")
assert(camera.CFrame == cameraBefore, "mobile Silent moved the camera")
for _, work in ipairs(delayed) do
    if work.seconds == 0.35 then work.callback(unpack(work.arguments, 1, work.arguments.n)) end
end
assert(string.find(feature.status, "redirected", 1, true), "mobile aim diagnostic was not updated")

-- A phone uses the center of the viewport, not the last finger position.
local savedProjection = camera.WorldToViewportPoint
local insideFov = false
camera.WorldToViewportPoint = function()
    return insideFov and Vector3.new(650, 365, 1) or Vector3.new(1000, 360, 1), true
end
local mobileFov = ex.state.toggleControls["MVSD.SilentAIM.AimFOV"]
ex.state.valueControls["MVSD.SilentAIM.AimFOVRadius"].apply(100)
mobileFov.setChecked(true)
action.button.InputBegan:Fire(touch)
UserInputService.InputEnded:Fire(touch)
assert(shots == 1 and string.find(feature.status, "FOV", 1, true),
    "mobile FOV did not reject a distant screen-space target")
insideFov = true
action.button.InputBegan:Fire(touch)
UserInputService.InputEnded:Fire(touch)
assert(shots == 2, "mobile FOV did not accept a target near the viewport center")
mobileFov.setChecked(false)
camera.WorldToViewportPoint = savedProjection

-- Another touch action simulates an executor with hookmetamethod/checkcaller
-- but neither getcallingscript nor debug.info, and a gun reading Mouse.Hit.
-- This remains a fixture: it does not validate Roblox or any named executor.
feature.activate()
local oldMouseGetter = localPlayer.GetMouse
local nativeMouse = Instance.new("Mouse")
localPlayer.GetMouse = function() return nativeMouse end
local fire = Instance.new("RemoteEvent")
fire.Name, fire.Parent = "fire", gun
local beam = Instance.new("RemoteEvent")
beam.Name, beam.Parent = "showBeam", gun
local ordinaryHit = CFrame.new(Vector3.new(-20, 0, 0))
local originalIndex = function() return ordinaryHit end
local currentIndex = originalIndex
local oldHookMeta, oldCaller, oldDebug, oldCheckCaller = hookmetamethod, getcallingscript, debug, checkcaller
hookmetamethod = function(_game, method, replacement)
    assert(method == "__index", "unexpected no-caller mobile hook")
    local previous = currentIndex
    currentIndex = replacement
    return previous
end
getcallingscript, debug = nil, {}
checkcaller = function() return false end
local deferredHit = nil
gun.Activate = function()
    shots += 1
    -- The native handler can read after Activate returns on a later scheduler turn.
    deferredHit = function() return currentIndex(nativeMouse, "Hit") end
end
feature.activate()
action.button.InputBegan:Fire(touch)
UserInputService.InputEnded:Fire(touch)
assert(shots == 3 and deferredHit and deferredHit().Position == target.part.Position,
    "touch action did not support a deferred anonymous Mouse.Hit read")
assert(camera.CFrame == cameraBefore, "anonymous mobile action moved the camera")
for _, work in ipairs(delayed) do
    if work.seconds == 0.35 then work.callback(unpack(work.arguments, 1, work.arguments.n)) end
end
assert(string.find(feature.status, "redirected", 1, true), "anonymous mobile status was not updated")
feature.activate()
assert(currentIndex == originalIndex, "mobile OFF did not restore the Mouse hook")
hookmetamethod, getcallingscript, debug, checkcaller = oldHookMeta, oldCaller, oldDebug, oldCheckCaller
localPlayer.GetMouse = oldMouseGetter

-- The two existing automatic cards remain independently operable from a touch
-- menu; these fixture Activates/ThrowMode writes are not proof of server hits.
local autoShoot, knifeThrow = nil, nil
for _, candidate in ipairs(ex.allFeatures) do
    if candidate.sectionName == "MVSD" and candidate.name == "Auto Shoot" then autoShoot = candidate end
    if candidate.sectionName == "MVSD" and candidate.name == "Knife Throw" then knifeThrow = candidate end
end
local mobileCore = ex.state.x2duelsCore
local scheduledCore = nil
for _, scheduled in pairs(ex.TaskManager.tasks) do
    if scheduled.handle == ex.featureConnections.X2DuelsCore then scheduledCore = scheduled end
end
assert(autoShoot and knifeThrow and scheduledCore, "mobile automatic cards/core missing")
mobileCore.settings.autoShootWallCheck = false
gun.Activate = function() shots += 1 end
autoShoot.activate()
scheduledCore.callback(0.1)
assert(shots == 4 and not feature.enabled and not mobileCore.settings.silentAim,
    "mobile Auto Shoot did not activate independently of Silent AIM")
autoShoot.activate()
local mobileMain = Instance.new("Folder")
mobileMain.Name, mobileMain.Parent = "Main", localPlayer.PlayerGui
local mobileKnifeGui = Instance.new("Folder")
mobileKnifeGui.Name, mobileKnifeGui.Parent = "MobileKnifeGui", mobileMain
local throwMode = Instance.new("BoolValue")
throwMode.Name, throwMode.Value, throwMode.Parent = "ThrowMode", false, mobileKnifeGui
local knife = Instance.new("Tool")
knife.Name, knife.Enabled, knife.Parent = "Knife", true, backpack
gun.Parent = backpack
local throws, sawThrowMode = 0, false
knife.Activate = function()
    throws += 1
    sawThrowMode = throwMode.Value
end
mobileCore.settings.knifeWallCheck = false
knifeThrow.activate()
scheduledCore.callback(0.1)
assert(throws == 1 and sawThrowMode and throwMode.Value == false
    and not feature.enabled and not mobileCore.settings.silentAim,
    "mobile Knife Throw did not use/restore ThrowMode independently")
knifeThrow.activate()

-- The actual touch action with an OTH namecall fixture. This verifies the UI
-- and forwarding contract, not Delta's off-thread behaviour or real hits.
do
    local oldOth, oldMeta, oldMethod, oldCheck, oldCaller, oldClock = oth, getrawmetatable, getnamecallmethod, checkcaller, getcallingscript, os.clock
    local hook, captured, installs = nil, nil, 0
    local original = function(_object, _origin, direction) captured = direction; return {Instance = target.part} end
    getrawmetatable = function() return {__namecall = original} end
    getnamecallmethod = function() return "Raycast" end
    checkcaller = function() return false end
    getcallingscript = function() return gunScript end
    oth = {hook = function(_target, callback) installs += 1; hook = callback; return original end}
    os.clock = function() return 1000 end
    mobileCore.settings.silentBackend = "Oth"
    mobileCore.settings.wallCheck = false
    knife.Parent = backpack
    gun.Parent = localPlayer.Character
    gun.Activate = function()
        shots += 1
        hook(workspace, Vector3.new(0, 3, 0), Vector3.new(0, 0, -500))
    end
    local probe = nil
    for _, candidate in ipairs(ex.allFeatures) do
        if candidate.sectionName == "MVSD" and candidate.name == "Gun Probe" then probe = candidate end
    end
    assert(probe, "mobile Gun Probe card missing")
    local oldEncode, mobileSnapshot = HttpService.JSONEncode, nil
    HttpService.JSONEncode = function(_, value) mobileSnapshot = value; return "{}" end
    probe.onToggle(true) -- probe first; Silent must reuse the same hook
    assert(installs == 1 and hook, "mobile probe failed to install the shared OTH hook")
    feature.activate()
    assert(installs == 1, "Silent added a second OTH hook after probe")
    scheduledCore.callback(0.1)
    local before, beforeCamera = shots, camera.CFrame
    action.button.InputBegan:Fire(touch)
    UserInputService.InputEnded:Fire(touch)
    assert(shots == before + 1 and captured and captured.X > 0,
        "mobile OTH action failed to redirect the native fixture Raycast")
    assert(camera.CFrame == beforeCamera, "mobile OTH changed the camera")
    feature.activate()
    assert(installs == 1, "disabling Silent disturbed the shared probe hook")
    UserInputService.InputBegan:Fire({UserInputType = Enum.UserInputType.Touch, Position = Vector3.new(900, 400, 0)}, false)
    hook(workspace, Vector3.new(0, 3, 0), Vector3.new(0, 0, -500))
    probe.onToggle(false)
    local touchFound, rayFound = false, false
    for _, event in ipairs(mobileSnapshot.events) do
        if event.event == "input_began" then touchFound = true
        elseif event.event == "namecall" and event.detail.method == "Raycast" then rayFound = true end
    end
    assert(touchFound and rayFound and mobileSnapshot.namecallHook, "mobile shared OTH probe missed touch or ray")
    HttpService.JSONEncode = oldEncode
    oth, getrawmetatable, getnamecallmethod, checkcaller, getcallingscript, os.clock = oldOth, oldMeta, oldMethod, oldCheck, oldCaller, oldClock
end
task.delay = oldDelay
ex.state.destruct()
print("[X2MOBILE] touch actions, FOV and independent automatic cards: PASS")
'''
    mobile_path = ROOT / "build" / "x2duels_mobile_boot.luau"
    mobile_path.write_text(mobile_boot, encoding="utf-8")
    mobile_result = subprocess.run(
        [LUAU, str(mobile_path)], cwd=ROOT, capture_output=True,
        text=True, check=False,
    )
    if mobile_result.returncode:
        raise SystemExit(mobile_result.stdout + mobile_result.stderr)
    marker = "[X2MOBILE] touch actions, FOV and independent automatic cards: PASS"
    if marker not in mobile_result.stdout:
        raise AssertionError("X2 mobile boot marker missing\n" + mobile_result.stdout)
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
        ["MVSD.SilentAIM.Mode"] = "Legit",
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
assert(not migrated.settings.silentAim and ex.configData.states["MVSD.AutoFarm"] == true,
    "experimental OTH restored automatically or unrelated preference lost")
assert(ex.configData.values["MVSD.SilentAIM.Mode"] == nil
    and not ex.featureConnections.X2DuelsLegitAim,
    "legacy Legit profile resurrected a visible camera lock")
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
