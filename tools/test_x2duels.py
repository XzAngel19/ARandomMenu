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
ESP = ROOT / "src" / "games" / "X2Duels" / "Render" / "TeamESP.lua"
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

check("known match requires same id", rules.sameMatch("match-a", "match-a"), true)
check("known match rejects other id", rules.sameMatch("match-a", "match-b"), false)
check("known match rejects missing id", rules.sameMatch("match-a", nil), false)
check("missing local match permits manual aim", rules.sameMatch(nil, "match-a"), true)
check("confirmed teammate", rules.relation("red", "red", true), "Teammate")
check("confirmed enemy", rules.relation("red", "blue", true), "Enemy")
check("unknown side", rules.relation("red", nil, true), "Unknown")
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
    esp = ESP.read_text(encoding="utf-8")
    wurst = (ROOT / "src" / "Wurst.lua").read_text(encoding="utf-8")

    # The evidence does not contain combat schemas. Keep all combat on native
    # activation and real GUI signals rather than fabricated FireServer calls.
    forbid(base, ":FireServer(", "unverified combat/match remote request")
    forbid(base, "host.mouse1press", "desktop-only firing")
    forbid(base, "pcall(mouse1press", "desktop-only firing")
    forbid(base, "VirtualInputManager", "mouse/touch injection substitute")
    forbid(base, 'FireServer("back_to_lobby")', "lobby transition as Play Again")
    require(base, "tool:Activate()", "native mobile-compatible activation")
    require(base, 'settings.senderMode == "CFrame"', "CFrame sender")
    require(base, '{"Legit", "Silent"}', "Legit/Silent modes")
    require(base, '"Target Nearest Player', "nearest-target card")
    require(base, '"Pistol"', "dedicated gun Trigger Bot option")
    require(base, '"Knife"', "dedicated knife Trigger Bot option")
    require(base, "registerTeamProvider", "shared Wurst team provider")
    require(base, "restoreAllHitboxes()", "hitbox restoration")
    require(base, "uninstallHooks()", "silent-hook cleanup")
    require(base, "Packages/Networking/RE/Match/MatchResults", "results event")
    require(base, "Packages/Networking/RE/Match/PlayerRespawned", "round event")
    require(base, "clickNativeButton", "real Play Again button path")
    require(esp, 'Enemy = Color3.fromRGB(255, 82, 82)', "enemy ESP color")
    require(esp, 'Teammate = Color3.fromRGB(75, 220, 135)', "team ESP color")
    require(esp, 'Unknown = Color3.fromRGB(255, 190, 75)', "unknown ESP color")

    require(wurst, '[92876937625630] = "X2Duels"', "current PlaceId registration")
    require(wurst, '[135856908115931] = "X2Duels"', "legacy MVS PlaceId registration")
    require(wurst, 'X2DuelsActive = ACTIVE_GAME_MODULE == "X2Duels"', "GAME_CHECK")
    require(wurst, '"src/games/X2Duels/Rules.lua"', "rules loader path")
    require(wurst, '"src/games/X2Duels/base.lua"', "base loader path")
    require(wurst, '"src/games/X2Duels/Render/TeamESP.lua"', "ESP loader path")

    for place_id in (92876937625630, 135856908115931):
        profile = ROOT / "src" / "Profile" / f"{place_id}.lua"
        text = profile.read_text(encoding="utf-8")
        require(text, 'key = "X2Duels"', f"profile {place_id}")
        require(text, '"MVSD"', f"existing MVS section {place_id}")
    print("X2Duels native-combat and registration contracts: PASS")


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
    generated += r'''
local expected = {
    ["Auto Farm"] = true,
    ["Silent AIM"] = true,
    ["Auto Shoot"] = true,
    ["Knife Throw"] = true,
    ["Kill Aura"] = true,
    ["Trigger Bot"] = true,
    ["Hitboxes"] = true,
    ["Team ESP"] = true,
    ["Play Again"] = true,
}
local seen = {}
for _, feature in ipairs(ex.allFeatures) do
    if feature.sectionName == "MVSD" and expected[feature.name] then
        assert(not seen[feature.name], "duplicate X2 card: " .. feature.name)
        seen[feature.name] = true
        local enabled, enableError = pcall(feature.onToggle, true)
        assert(enabled, "X2 enable " .. feature.name .. ": " .. tostring(enableError))
        local disabled, disableError = pcall(feature.onToggle, false)
        assert(disabled, "X2 disable " .. feature.name .. ": " .. tostring(disableError))
    end
end
for name, _ in pairs(expected) do
    assert(seen[name], "X2 card did not boot: " .. name)
end
assert(ex.state.x2duelsCore and ex.state.x2duelsRules,
    "X2 shared core/rules were not published")
assert(ex.state.gameBridge.teamProvider
    and ex.state.gameBridge.teamProvider.Name == "X2Duels",
    "X2 team provider was not registered")
ex.state.destruct()
assert(ex.state.x2duelsCore == nil, "X2 core survived destroy")
assert(ex.state.x2duelsRules == nil, "X2 rules survived destroy")
assert(ex.state.mvsdCore == nil, "X2 compatibility core survived destroy")
assert(ex.state.gameBridge.teamProvider == nil, "X2 team provider survived destroy")
print("[X2BOOT] 9 cards, toggle callbacks and cleanup: PASS")
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
    marker = "[X2BOOT] 9 cards, toggle callbacks and cleanup: PASS"
    if marker not in output:
        raise AssertionError("X2 bundle boot marker missing\n" + output)
    print(marker)


if __name__ == "__main__":
    run_luau_tests()
    run_integration_contracts()
    run_bundle_boot()
