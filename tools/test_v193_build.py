#!/usr/bin/env python3
"""v193 build rules, checked without booting the UI.

Each rule is something the player asked for on this build, or something a later
edit could silently undo:

  * one build number, derived from SOURCE_STAMP ("0.NNN" and "0.NNN Release");
  * "Rejoin Server" stays gone from Server Settings;
  * the server readout is a LIVE section of stat rows (AutoFarm's "Overlay
    Info" style) with server data only -- no Build, no Round, no You, no window,
    no timer that stops;
  * the place row names the place and marks a subplace;
  * a hop needs a FREE SLOT, reads several pages, sends no extra query flag, and
    falls back to joining any server when every listed one is full;
  * the phone controls are hidden by disabling the two ScreenGuis that ARE the
    phone controls on a keyboard machine -- and the game's `Device` attribute is
    NOT rewritten any more (v192 did that, which changes game logic);
  * the Disguise option reads "Use target movement animations if able", asks for
    that repair after every apply, and resets its per-body flags on respawn;
  * the Fling roster never compares a Player's parent with the CLONED Players
    table;
  * MM2 round data keyed by UserId resolves to a player.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WURST = (ROOT / "src/Wurst.lua").read_text(encoding="utf-8")
SETTINGS = (ROOT / "src/guis/Wurst/Code/SettingsPage.lua").read_text(encoding="utf-8")
CLICKGUI = (ROOT / "src/guis/Wurst/Code/ClickGui.lua").read_text(encoding="utf-8")
SERVER = (ROOT / "src/games/universal/Other/ServerSettings.lua").read_text(encoding="utf-8")
DISGUISE = (ROOT / "src/games/universal/Other/Disguise.lua").read_text(encoding="utf-8")
FLING = (ROOT / "src/games/MM2/Other/Fling.lua").read_text(encoding="utf-8")
BASE = (ROOT / "src/games/MM2/base.lua").read_text(encoding="utf-8")


def check(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL v193: {message}")


# --- 1. one build number, derived -----------------------------------------
check('local SOURCE_STAMP: string = "v1' in WURST, "the stamp ships this build")
check('local SOURCE_STAMP: string = "v19' in WURST, "the stamp is a v19x build")
check('local BUILD_NUMBER: string? = string.match(SOURCE_STAMP, "^v(%d+)")' in WURST,
      "the build number is parsed from SOURCE_STAMP")
check('local BUILD_LABEL: string = if BUILD_NUMBER then "0." .. BUILD_NUMBER else "0.0"' in WURST,
      'the label is "0.NNN"')
check('version = BUILD_LABEL .. " Release",' in WURST,
      'the product line is "0.NNN Release" and reads the same label')
check("0.823" not in WURST, "no hardcoded build number survives in Wurst.lua")
check("0.823" not in CLICKGUI, "no hardcoded build number survives in the header chip")
check("BUILD_LABEL" in CLICKGUI, "the header chip reads the derived label")
check("tostring(host.BUILD_LABEL" in SETTINGS, "the window title reads the derived label")
check('"Version 0."' not in SETTINGS, 'the word "Version" is gone from the watermark')

# --- 2. Rejoin stays gone -------------------------------------------------
check('addActionOption(card, "Rejoin Server"' not in SERVER, "Rejoin Server is removed")
check("local function rejoin()" not in SERVER, "the rejoin helper is gone with it")

# --- 3. the readout is live, in-card, server-only -------------------------
check('state.addSectionOption' in SERVER and '"Overlay Info"' in SERVER,
      "the readout is the AutoFarm-style Overlay Info section")
for row in ("Server", "Players", "In server", "Uptime", "Server time", "Place"):
    check(f'label = "{row}"' in SERVER, f"the readout has a {row} row")
for removed, rowName in (('label = "Build"', "Build"), ('label = "Round"', "Round"),
                         ('label = "You"', "You")):
    check(removed not in SERVER, "v193 removes the " + rowName + " row")
check("AutomaticSize" not in SERVER and "ScreenGui" not in SERVER,
      "v193 draws no floating window")
check("workspace.DistributedGameTime" in SERVER, "uptime reads the server clock, not yours")
check("workspace:GetServerTimeNow()" in SERVER, "the readout shows the server time")
check("return label .. \" · subplace\"" in SERVER,
      "the place row marks a subplace (PlaceId ~= GameId)")
check("placeId ~= gameId" in SERVER, "the subplace test compares PlaceId with GameId")

# The ticker must not be tied to the card toggle and must not be capped.
GUARD_START = SERVER.index("local function startTicker()")
TICKER = SERVER[GUARD_START:SERVER.index("local function copyJobId()", GUARD_START)]
check("featureConnections.ServerSettingsTick = tick:Connect(" in TICKER, "the readout owns one ticker")
check("disconnect" not in TICKER.lower(), "the ticker is never dropped while the module lives")
check("STAT_INTERVAL" in SERVER and "local STAT_INTERVAL: number = 1" in SERVER,
      "the readout runs at 1 Hz, not on a user-capped timer")
check("Refresh every" not in SERVER, "the refreshing interval option is gone")
check("startTicker()" in SERVER.split("state.serverSettingsCard = card")[0],
      "the ticker starts at init, not from the card toggle")

# --- 4. hops: free slot, several pages, no extra flag, real fallback ------
check("&excludeFullServers" not in SERVER, "the endpoint URL sends no extra flag")
check("return playing < limit" in SERVER, "a server needs a free slot to be a candidate")
check("local populated: {any} = {}" in SERVER, '"smallest" ignores empty instances')
check("nextPageCursor" in SERVER and "MAX_PAGES" in SERVER, "hops walk several pages")
check("&cursor=" in SERVER, "deeper pages use the cursor")
check("teleportService:Teleport(game.PlaceId, LocalPlayer)" in SERVER,
      "a full list falls back to joining any server")
check('"Hopping to the %s server: %d/%d players…"' in SERVER,
      "the hop message states the real player count")

# --- 5. phone controls hidden without rewriting game state ----------------
check("local function suppressTouchControls(): ()" in WURST, "the desktop-controls guard exists")
check('TouchInteractButtons = true' in WURST,
      "the game's own touch buttons are one of the hidden GUIs")
check('TouchGui = true' in WURST, "Roblox's TouchGui is one of the hidden GUIs")
check('PlayerGui:SetAttribute("Device"' not in WURST,
      "v193 no longer rewrites the game's Device attribute")
check("local function isDesktopMachine(): boolean" in WURST, "desktop detection is explicit")
check("if not UserInputService.KeyboardEnabled then" in WURST,
      "a machine without a keyboard is never treated as a desktop")
check("gui.Enabled = false" in WURST, "the guard only disables GUIs")
GUARD = WURST[WURST.index("local function isDesktopMachine()"):WURST.index("pcall(function(): ()\n    local function watch(", WURST.index("local function isDesktopMachine()"))]
check("TouchEnabled = " not in GUARD, "the guard never writes TouchEnabled")
check("MouseIconEnabled" not in GUARD, "the guard never touches the mouse icon")
check("MouseBehavior" not in GUARD, "the guard never changes the input scheme")
check("suppressTouchControls = suppressTouchControls," in WURST, "modules can call it")
check("UserInputService.TouchEnabled\n    and not UserInputService.KeyboardEnabled" in WURST,
      "a keyboard machine is never treated as mobile")

# --- 6. Disguise ----------------------------------------------------------
check('Name = "Use target movement animations if able",' in DISGUISE, "the option is renamed")
check("host.suppressTouchControls" in DISGUISE,
      "the disguise asks for the phone-controls repair after applying")
check("emotesAppliedToHumanoid = false\n                    animationOverrideApplied = false" in DISGUISE,
      "the per-body flags are reset on respawn")

# --- 7. Fling roster ------------------------------------------------------
check("player.Parent ~= playerService" not in FLING, "the cloned-Players comparison is gone")
check("local function isLivePlayer(player: any): boolean" in FLING, "the roster guard checks the instance")
check('className ~= "Player"' in FLING, "the guard asks the instance what it is")

# --- 8. MM2 round data by UserId -----------------------------------------
check("if type(key) == \"number\" then\n        local resolved = Players:GetPlayerByUserId(key)" in BASE,
      "a UserId-keyed round table resolves to a player")

# --- 9. the documents this build promises ---------------------------------
for name in ("docs/FIXES-v193.md", "docs/skills/agent-run-efficiency.md",
             "docs/skills/roblox-menu-change.md"):
    check((ROOT / name).exists(), f"{name} exists")

print("PASS v193 build: live in-card server readout (never stopping), subplace, hops with a real "
      "slot + fallback, phone controls hidden without rewriting game state, one derived build number")
