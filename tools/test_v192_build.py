#!/usr/bin/env python3
"""v192 build rules, checked without booting the UI.

Every rule here is one the player asked for in this build, and every one of them
is a source-level invariant that a later edit can silently break:

  * one build number, derived from SOURCE_STAMP: "0.NNN" in the window titles
    and "0.NNN Release" on the product line (no hardcoded "0.823" left);
  * "Rejoin Server" is gone from Server Settings;
  * a hop only accepts a server with a FREE SLOT and "smallest" skips empty
    instances;
  * "Show server info" builds an overlay (title + uptime + server clock rows);
  * the menu never leaves the player on the phone input scheme: Roblox's
    TouchGui is disabled on a keyboard+mouse machine and a game that mirrors the
    setting in the `Device` attribute is put back on "PC";
  * the Disguise option is called "Use target movement animations if able" and
    asks for that repair after every apply, and its per-body flags are reset on
    respawn;
  * the Fling roster no longer compares a Player's parent with the CLONED
    Players table (the v191 bug that left it empty);
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
        raise SystemExit(f"FAIL v192: {message}")


# --- 1. one build number, derived -----------------------------------------
check('local SOURCE_STAMP: string = "v192-' in WURST, "the v192 stamp ships this build")
check('local BUILD_NUMBER: string? = string.match(SOURCE_STAMP, "^v(%d+)")' in WURST,
      "the build number is parsed from SOURCE_STAMP")
check('local BUILD_LABEL: string = if BUILD_NUMBER then "0." .. BUILD_NUMBER else "0.0"' in WURST,
      'the label is "0.NNN"')
check('version = BUILD_LABEL .. " Release",' in WURST,
      'the product line is "0.NNN Release" and reads the same label')
check("0.823" not in WURST, "no hardcoded build number survives in Wurst.lua")
check("0.823" not in CLICKGUI, "no hardcoded build number survives in the header chip")
check("BUILD_LABEL" in CLICKGUI, "the header chip reads the derived label")
check('tostring(host.BUILD_LABEL' in SETTINGS, "the window title reads the derived label")
check('"Version 0."' not in SETTINGS, 'the word "Version" is gone from the watermark')
check("BUILD_LABEL = BUILD_LABEL," in WURST, "modules receive the label")

# --- 2. Rejoin Server is gone ---------------------------------------------
check('addActionOption(card, "Rejoin Server"' not in SERVER, "Rejoin Server is removed")
check("local function rejoin()" not in SERVER, "the rejoin helper is removed with it")

# --- 3. hops with a real slot ---------------------------------------------
check("excludeFullServers=true" in SERVER, "the endpoint excludes full servers")
check("return playing < limit" in SERVER, "a server needs a free slot to be a candidate")
check("local populated: {any} = {}" in SERVER,
      '"smallest" ignores empty instances')
check('if playersIn(entry) >= 1 then' in SERVER, "populated means at least one player")
check('"Hopping to the %s server: %d/%d players…"' in SERVER,
      "the hop message states the real player count")
check("sortOrder=%s" in SERVER, "the sort order reaches the endpoint")
check('mode == "random" then\n            orders = {"Asc", "Desc"}' in SERVER,
      "random merges both ends of the list")

# --- 4. the overlay -------------------------------------------------------
check('local OVERLAY_NAME: string = "WurstServerInfo"' in SERVER, "the overlay has a name")
check('Text = "Server Info"' in SERVER, "the overlay has a title")
for row in ("Job ID", "Players", "In server", "Uptime", "Server clock", "Place", "You", "Build"):
    check(f'label = "{row}"' in SERVER, f"the overlay has a {row} row")
check("workspace.DistributedGameTime" in SERVER, "uptime reads the server clock, not yours")
check("workspace:GetServerTimeNow()" in SERVER, "the overlay shows the server time")
check("AutomaticSize = Enum.AutomaticSize.Y" in SERVER, "the overlay sizes to its rows")
check("header.Draggable = true" in SERVER, "the overlay can be dragged out of the way")

# --- 5. never leave the phone input scheme --------------------------------
check("local function suppressTouchControls(): ()" in WURST, "the desktop-controls guard exists")
check("UserInputService.MouseEnabled" in WURST,
      "it only runs on a keyboard + mouse machine")
check('PlayerGui:FindFirstChild("TouchGui")' in WURST, "it hides Roblox's TouchGui")
check("touchGui.Enabled = false" in WURST, "the TouchGui is disabled, never re-created")
check('device == "Phone" or device == "Tablet"' in WURST,
      "it recognises MM2's phone/tablet device mode")
check('PlayerGui:SetAttribute("Device", "PC")' in WURST, "it puts the game back on PC")
check("suppressTouchControls = suppressTouchControls," in WURST, "modules can call it")
check("UserInputService.TouchEnabled\n    and not UserInputService.KeyboardEnabled" in WURST,
      "a keyboard machine is never treated as mobile")
GUARD_START = WURST.index("local function suppressTouchControls(): ()")
GUARD = WURST[GUARD_START:WURST.index("pcall(function(): ()\n    suppressTouchControls()", GUARD_START)]
check("TouchEnabled = " not in GUARD, "the guard never writes TouchEnabled")
check("MouseIconEnabled" not in GUARD, "the guard never touches the mouse icon")
check("MouseBehavior" not in GUARD, "the guard never changes the input scheme")
check("Enabled = false" in GUARD, "the guard only disables GUIs")

# --- 6. Disguise ----------------------------------------------------------
check('Name = "Use target movement animations if able",' in DISGUISE, "the option is renamed")
check("host.suppressTouchControls" in DISGUISE,
      "the disguise asks for the desktop-controls repair after applying")
check("emotesAppliedToHumanoid = false\n                    animationOverrideApplied = false" in DISGUISE,
      "the per-body flags are reset on respawn")

# --- 7. Fling roster ------------------------------------------------------
check("player.Parent ~= playerService" not in FLING,
      "the cloned-Players comparison is gone")
check("local function isLivePlayer(player: any): boolean" in FLING, "the roster guard checks the instance")
check('className ~= "Player"' in FLING, "the guard asks the instance what it is")

# --- 8. MM2 round data by UserId -----------------------------------------
check("if type(key) == \"number\" then\n        local resolved = Players:GetPlayerByUserId(key)" in BASE,
      "a UserId-keyed round table resolves to a player")

# --- 9. the documents this build promises ---------------------------------
for name in ("docs/FIXES-v192.md", "docs/skills/agent-run-efficiency.md",
             "docs/skills/roblox-menu-change.md"):
    check((ROOT / name).exists(), f"{name} exists")

print("PASS v192 build: one derived build number, no Rejoin, hops with a real slot, "
      "server info overlay, desktop controls kept, Disguise renamed, Fling roster fixed")
