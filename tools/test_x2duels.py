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

    # No combat or event argument schema is invented from remote names.
    forbid(base, ":FireServer(", "unverified combat/match remote request")
    forbid(farm, ":FireServer(", "unverified pumpkin remote request")
    forbid(base, "host.mouse1press", "desktop-only firing")
    forbid(base, "pcall(mouse1press", "desktop-only firing")
    forbid(base, "VirtualInputManager", "GUI automation in the combat module")
    forbid(base, "Play Again", "removed Play Again automation")
    forbid(base, "queueGunBurst", "removed Auto Win combat driver")
    forbid(base, "burstRemaining", "removed Auto Win burst state")
    forbid(base, "knifeInterval", "removed Knife Throw interval state")
    forbid(base, "Throw interval", "removed Knife Throw interval option")
    require(base, "tool:Activate()", "native mobile-compatible activation")
    require(base, "local function fireGun", "shared native gun adapter")
    require(base, "local function fireKnife", "shared native knife adapter")
    require(base, "mouse2press", "desktop knife throw input")
    require(base, 'SetAttribute("ForceThrow", true)', "touch knife throw state")
    require(base, 'settings.senderMode == "CFrame"', "CFrame sender")
    require(base, '{"Legit", "Silent"}', "Legit/Silent modes")
    require(base, '"Auto Shoot · "', "mode-labelled nested Auto Shoot")
    require(base, "settings.silentAim and settings.autoShoot", "master-gated Auto Shoot")
    require(base, "state.bindFeatureActivationKey", "MM2-style action key binding")
    require(base, 'settings.senderMode ~= "Button"', "CFrame does not require action key")
    require(base, 'host.addSectionOption(silentAimCard, "Knife")', "Knife section inside Silent AIM")
    require(base, '"Knife Throw",', "nested Knife Throw option")
    require(base, "settings.silentAim and settings.knifeThrow", "master-gated Knife Throw")
    require(base, "runKnifeThrow(600)", "frame-driven Knife Throw")
    require(base, '"Auto Win",', "Auto Win status card")
    require(base, '"Utilities"', "Utilities category")
    require(base, "Wins: %d | Time Played: %s | Kills: %d | Loses: %d", "four status fields")
    require(base, "local function registerLoss", "observed local loss counter")
    require(base, "Packages/Networking/RE/Combat/DestroyBody", "observed kill event")
    forbid(base, '"Trigger Bot"', "duplicate X2 TriggerBot card")
    forbid(base, '"Auto Shoot",\n        "Equip', "standalone Auto Shoot card")
    require(base, '"Hitbox",', "singular Hitbox card")
    require(base, '"Exploits"', "Hitbox Exploits category")
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
    require(trigger, "x2Core.fireGun(target)", "TriggerBot shared gun activation")
    require(trigger, "x2Core.fireKnife(target)", "TriggerBot shared knife activation")
    require(farm, "^PumpkinCurrency_%d+$", "Halloween spawnable discovery")
    require(farm, "claimRoundTeamFromPodiums", "podium team resolution")
    require(farm, "playerFromValue", "StringValue/ObjectValue player resolution")
    require(farm, "nearestOwned", "owned farm selection")
    require(farm, "currencyCFrame: CFrame = part.CFrame", "currency CFrame teleport")
    require(farm, "if not roundStarted then", "round team fail-closed gate")
    require(farm, "TouchTransmitter", "invisible PumpCoins interaction")
    require(farm, "host.firetouchinterest", "native pumpkin contact")
    require(farm, "restoreSavedPosition()", "farm position cleanup")
    require(farm, 'categoryName = "Utilities"', "Auto Farm Utilities category")

    catalog = (ROOT / "src/libraries/Manifest.lua").read_text()
    require(catalog, "{placeId = 92876937625630, module = \"X2Duels\"", "current PlaceId registration")
    require(catalog, "{placeId = 135856908115931, module = \"X2Duels\"", "legacy MVS PlaceId registration")
    require(wurst, 'X2DuelsActive = ACTIVE_GAME_MODULE == "X2Duels"', "GAME_CHECK")
    require(catalog, '"src/games/X2Duels/Rules.lua"', "rules loader path")
    require(catalog, '"src/games/X2Duels/base.lua"', "base loader path")
    require(catalog, '"src/games/X2Duels/Other/AutoFarm.lua"', "farm loader path")
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

    for place_id in (92876937625630, 135856908115931):
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
        "game = {\n    PlaceId = 92876937625630,\n    GameId = 20260716,",
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
local x2Networking = x2Folder(x2Packages, "Networking")
local x2RE = x2Folder(x2Networking, "RE")
local x2Match = x2Folder(x2RE, "Match")
local function x2Remote(name)
    local remote = Instance.new("RemoteEvent")
    remote.Name = name
    remote.Parent = x2Match
    return remote
end
X2MatchResults = x2Remote("MatchResults")
X2RemovePlayer = x2Remote("RemovePlayer")
X2WinNotification = x2Remote("WinNotification")
X2SetDead = x2Remote("SetDead")
X2PlayerRespawned = x2Remote("PlayerRespawned")
local x2Combat = x2Folder(x2RE, "Combat")
X2DestroyBody = Instance.new("RemoteEvent")
X2DestroyBody.Name = "DestroyBody"
X2DestroyBody.Parent = x2Combat
local x2Local = game:GetService("Players").LocalPlayer
-- Match Roblox's real hierarchy so WaitForChild scans this same PlayerGui.
if x2Local.PlayerGui then x2Local.PlayerGui.Parent = x2Local end
x2Local:SetAttribute("Team", "Red")
x2Local:SetAttribute("Game", "HarnessMatchOne")
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
assert(x2CardCount == 5, "expected exactly five X2 cards, got " .. tostring(x2CardCount))
for name, _ in pairs(expected) do
    assert(seen[name], "X2 card did not boot: " .. name)
end
assert(ex.state.toggleControls["MVSD.SilentAIM.AutoShoot"],
    "Auto Shoot is not nested under Silent AIM")
assert(ex.state.toggleControls["MVSD.SilentAIM.KnifeThrow"],
    "Knife Throw is not nested under Silent AIM")
assert(not ex.state.toggleControls["MVSD.KnifeThrow"],
    "standalone Knife Throw card/control survived")
assert(not ex.state.valueControls["MVSD.SilentAIM.Throwinterval"],
    "Knife Throw interval control survived")
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
local autoShootLabel = nil
for _, row in ipairs(silentFeature.optionRows) do
    for _, child in ipairs(row:GetChildren()) do
        if child.Name == "OptionLabel" and string.sub(child.Text, 1, 10) == "Auto Shoot" then
            autoShootLabel = child
            break
        end
    end
end
assert(autoShootLabel, "Auto Shoot mode label was not created")
local autoShootControl = ex.state.toggleControls["MVSD.SilentAIM.AutoShoot"]
local modeControl = ex.state.valueControls["MVSD.SilentAIM.Mode"]
assert(modeControl and modeControl.apply, "Silent AIM Mode control was not created")
autoShootControl.setChecked(true)
assert(silentFeature.status == nil, "master-off Auto Shoot exposed an active status")
modeControl.apply("Silent")
assert(autoShootLabel.Text == "Auto Shoot · Silent", "Silent mode label did not update")
modeControl.apply("Legit")
assert(autoShootLabel.Text == "Auto Shoot · Legit", "Legit mode label did not update")
silentFeature.onToggle(true)
assert(silentFeature.status == "Legit", "enabled Legit Auto Shoot status is wrong")
silentFeature.onToggle(false)
assert(silentFeature.status == nil, "disabled master left an active Auto Shoot status")
assert(ex.configData.states["MVSD.SilentAIM.AutoShoot"] == true,
    "master switch erased the Auto Shoot preference")
modeControl.apply("Silent")
assert(autoShootLabel.Text == "Auto Shoot · Silent" and silentFeature.status == nil,
    "master-off Silent label/status are inconsistent")
modeControl.apply("Legit")
autoShootControl.setChecked(false)

-- Synthetic event schemas exercise only the local state machine. They are not
-- presented as recovered live MatchResults/WinNotification argument schemas.
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
local nativeTarget = core.targetFor(HarnessHeroGuy)
assert(nativeTarget, "native target fixture missing")
HarnessHeroGuy:SetAttribute("Team", "Blue")
HarnessHeroGuy:SetAttribute("Game", "HarnessMatchOne")
nativeLocal:SetAttribute("Team", "Red")
nativeLocal:SetAttribute("Game", "HarnessMatchOne")
assert(core.relation(HarnessHeroGuy) == "Enemy", "MVS enemy side was not resolved")
assert(core.isEnemy(HarnessHeroGuy), "resolved MVS enemy was rejected")
assert(ex.state.teamCheck.analyze(HarnessHeroGuy).hostile == true,
    "global team check did not accept a confirmed enemy")
nativeLocal:SetAttribute("Team", "FFA")
HarnessHeroGuy:SetAttribute("Team", "FFA")
assert(core.relation(HarnessHeroGuy) == "Unknown",
    "shared FFA sentinel was incorrectly treated as a team")
assert(not core.isEnemy(HarnessHeroGuy), "unknown FFA side became a target")
assert(ex.state.teamCheck.analyze(HarnessHeroGuy).hostile == nil,
    "unknown FFA side became a confirmed hostile")
nativeLocal:SetAttribute("Team", "Red")
HarnessHeroGuy:SetAttribute("Team", "Blue")
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

local silentFeature = featuresByName["Silent AIM"]
local autoWinFeature = featuresByName["Auto Win"]
silentFeature.activate()
assert(silentFeature.enabled and core.settings.silentAim,
    "Silent AIM did not enable through its card")
core.settings.senderMode = "Button"
core.settings.autoShoot = false
core.settings.knifeThrow = false
local senderBinding = ex.state.shortcutBindings["MVSD.SilentAIM"]
assert(senderBinding and senderBinding.onPress, "Silent AIM action binding missing")
local enabledBeforeKey = silentFeature.enabled
senderBinding.onPress()
assert(nativeGunShots == 1, "Button sender key did not fire the native gun")
assert(nativeGun.Parent == nativeLocal.Character, "Backpack gun was not equipped")
assert(silentFeature.enabled == enabledBeforeKey,
    "Silent AIM keybind toggled the master feature")
core.settings.senderMode = "CFrame"
senderBinding.onPress()
assert(nativeGunShots == 1, "CFrame sender unexpectedly required the action key")
assert(silentFeature.enabled == enabledBeforeKey,
    "CFrame keybind changed the master feature")
core.settings.autoShoot = true
core.settings.shotInterval = 0.04
coreTask.callback(0.04)
assert(nativeGunShots == 2, "CFrame Auto Shoot did not fire without a key press")
nativeNow += 0.041
coreTask.callback(0.04)
assert(nativeGunShots == 3, "CFrame Auto Shoot did not continue on its interval")
core.settings.autoShoot = false
silentFeature.activate()
assert(not silentFeature.enabled and not core.settings.silentAim,
    "Silent AIM card did not disable cleanly")

local oldMouse2Press = mouse2press
local oldMouse2Release = mouse2release
local nativeMouseDown = 0
local nativeMouseUp = 0
mouse2press = function() nativeMouseDown += 1 end
mouse2release = function() nativeMouseUp += 1 end
assert(core.fireKnife(nativeTarget), "desktop knife throw was not queued")
assert(nativeKnifeShots == 1 and nativeMouseDown == 1 and nativeMouseUp == 1,
    "desktop knife did not use the native right-click/Activate chain")
mouse2press = nil
mouse2release = nil
assert(core.fireKnife(nativeTarget), "touch knife throw was not queued")
assert(nativeKnifeShots == 2 and nativeKnife:GetAttribute("ForceThrow") == nil,
    "touch knife did not use and restore ForceThrow")
mouse2press = oldMouse2Press
mouse2release = oldMouse2Release
assert(ex.state.toggleControls["MVSD.SilentAIM.KnifeThrow"],
    "Knife Throw is not a Silent AIM option")
assert(not ex.state.valueControls["MVSD.SilentAIM.Throwinterval"],
    "Knife Throw still has an interval control")

-- Auto Win is a status-only card. Event fixtures test local accounting, not
-- live server authority and not any GUI/rematch automation.
autoWinFeature.activate()
assert(core.settings.stats and autoWinFeature.enabled, "statistics card did not enable")
local shotsBeforeStats = nativeGunShots
coreTask.callback(0.1)
assert(nativeGunShots == shotsBeforeStats,
    "statistics card unexpectedly drove native combat")
assert(autoWinFeature.status
    and string.find(autoWinFeature.status, "Wins:", 1, true)
    and string.find(autoWinFeature.status, "Time Played:", 1, true)
    and string.find(autoWinFeature.status, "Kills:", 1, true)
    and string.find(autoWinFeature.status, "Loses:", 1, true),
    "statistics card does not expose all four requested fields")
X2DestroyBody.OnClientEvent:Fire(HarnessHeroGuy, nil, nativeLocal)
assert(core.getStats().Kills == 1, "observed local killer was not counted")
X2DestroyBody.OnClientEvent:Fire(HarnessHeroGuy, nil, nativeLocal)
assert(core.getStats().Kills == 1, "duplicate DestroyBody counted twice")
X2SetDead.OnClientEvent:Fire(nativeLocal)
assert(core.getStats().Loses == 1, "local SetDead was not counted as a loss")
X2SetDead.OnClientEvent:Fire(nativeLocal)
assert(core.getStats().Loses == 1, "duplicate local death counted twice")
nativeNow += 1
X2PlayerRespawned.OnClientEvent:Fire(nativeLocal)
X2WinNotification.OnClientEvent:Fire("Red")
assert(core.getWins() == 1, "first confirmed win was not counted")
X2WinNotification.OnClientEvent:Fire("Red")
assert(core.getWins() == 1, "same-round win was counted twice")
X2MatchResults.OnClientEvent:Fire({Winner = "Red"})
assert(core.getWins() == 1, "MatchResults duplicated the same-round win")
nativeNow += 1
X2PlayerRespawned.OnClientEvent:Fire(nativeLocal)
X2WinNotification.OnClientEvent:Fire("Red")
assert(core.getWins() == 2, "second round win was not counted")
assert(core.settings.stats and autoWinFeature.enabled,
    "statistics card switched itself off after a win")
autoWinFeature.activate()
assert(not core.settings.stats and autoWinFeature.status == nil,
    "statistics card did not clear its status on disable")
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
local pumpkinModel = Instance.new("Model")
pumpkinModel.Name = "PumpkinCurrency_99"
pumpkinModel.Parent = workspace
local pumpkin = Instance.new("Part")
pumpkin.Name = "Pumpkin"
pumpkin.Size = Vector3.new(2, 2, 2)
pumpkin.Position = Vector3.new(30, 4, 30)
pumpkin.CFrame = CFrame.new(pumpkin.Position)
pumpkin.Transparency = 0
pumpkin.CanTouch = false -- Matches the saved place evidence.
pumpkin.Parent = pumpkinModel
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
assert(#touchCalls == 2, "expected one native touch begin/end pair")
assert(touchCalls[1][1] == root and touchCalls[1][2] == pumpkin,
    "farm touched the wrong instances")
assert(touchCalls[1][3] == 0 and touchCalls[2][3] == 1,
    "farm touch states were not begin/end")
assert(root.CFrame.Position.X == 30 and root.CFrame.Position.Y == 5.25
    and root.CFrame.Position.Z == 30, "farm did not move into pumpkin contact")
featuresByName["Auto Farm"].onToggle(false)
assert(root.CFrame == originalCFrame, "farm did not restore its saved CFrame")
firetouchinterest = previousFireTouch
pumpkinModel:Destroy()

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

ex.state.destruct()
assert(ex.state.x2duelsCore == nil, "X2 core survived destroy")
assert(ex.state.x2duelsRules == nil, "X2 rules survived destroy")
assert(ex.state.mvsdCore == nil, "X2 compatibility core survived destroy")
assert(ex.state.gameBridge.teamProvider == nil, "X2 team provider survived destroy")
assert(ex.state.gameBridge.roleProvider == nil, "X2 role provider survived destroy")
print("[X2BOOT] 5 cards, MM2 structure, native sender, stats, pumpkin restore, cleanup: PASS")
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
    marker = "[X2BOOT] 5 cards, MM2 structure, native sender, stats, pumpkin restore, cleanup: PASS"
    if marker not in output:
        raise AssertionError("X2 bundle boot marker missing\n" + output)
    print(marker)


if __name__ == "__main__":
    run_luau_tests()
    run_integration_contracts()
    run_bundle_boot()
