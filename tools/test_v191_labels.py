#!/usr/bin/env python3
"""v191/v192 labels and keys, without booting the UI.

Every rename in this build must be a VISIBLE-name change only: the config key,
the saved state and the keybind stay where they were, so nothing the player
already configured is lost.

v192 replaced the "Version 0.NNN" watermark with the bare "0.NNN" that the
product line prints as "0.NNN Release"; both come from SOURCE_STAMP, so this
file only checks that the label is DERIVED and that nothing hardcodes a build
number any more.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SETTINGS = (ROOT / "src/guis/Wurst/Code/SettingsPage.lua").read_text(encoding="utf-8")
WIDGETS = (ROOT / "src/guis/Wurst/Code/Widgets.lua").read_text(encoding="utf-8")
WINDOWS = (ROOT / "src/guis/Wurst/Code/WindowManager.lua").read_text(encoding="utf-8")
ARROWS = (ROOT / "src/games/universal/Render/Arrows.lua").read_text(encoding="utf-8")
SPIDER = (ROOT / "src/games/universal/Blatant/Spider.lua").read_text(encoding="utf-8")
SWIM = (ROOT / "src/games/universal/Blatant/Swim.lua").read_text(encoding="utf-8")
MANIFEST = (ROOT / "src/libraries/Manifest.lua").read_text(encoding="utf-8")
WURST = (ROOT / "src/Wurst.lua").read_text(encoding="utf-8")

# --- version label ---------------------------------------------------------
assert 'host.BUILD_LABEL' in SETTINGS, "v192: the watermark reads the derived build label"
assert '"Version 0." ' not in SETTINGS, 'v192: the word "Version" is gone from the watermark'
assert 'uiRecord = configWindow("UISettings", "UI Settings · " .. versionTag' in SETTINGS

# --- palette row rename, saved key preserved -------------------------------
assert '{label = "Buttons", key = "Arrows", default = Theme.arrows, tokens = {"arrows"}}' in SETTINGS, (
    'the Arrows row is now labelled Buttons but keeps its key'
)
assert 'uiPanel.configKey .. "."\n                        .. (row.key or row.label):gsub("%W", "")' in SETTINGS, (
    "the restore path must read the stable key"
)
assert 'local function addColorOption(feature, labelText, defaultColor, callback, hintText, keyText)' in WIDGETS
assert '(keyText or labelText):gsub("%W", "")' in WIDGETS, "addColorOption honours the stable key"
assert 'row.key\n            )' in SETTINGS, "the palette rows pass their key to addColorOption"

# --- pin chip themed by the arrows token -----------------------------------
assert 'local pin: TextButton = chromeButton("pin", Theme.arrows, "arrows")' in WINDOWS
assert 'Name = "PinTint"' in WINDOWS and 'bind(pinTint, "BackgroundColor3", "arrows")' in WINDOWS
assert 'root:SetAttribute("WurstPanelSurface", true)' in WINDOWS
assert 'root.GroupTransparency = 0' in WINDOWS, "v191: the group is never faded"
assert 'root.BackgroundTransparency = 1 - wanted' in WINDOWS, "v191: opacity drives the background"

# --- card renames keep their keys ------------------------------------------
assert 'Name = "Player Pointers"' in ARROWS and 'ConfigKey = "Universal.Arrows"' in ARROWS
assert '"Player Pointers", category = "Render"' in MANIFEST
assert 'Name = "Wall Crawling"' in SPIDER and 'configKey = "Universal.Spider"' in SPIDER
assert '"Wall Crawling", category = "Exploits"' in MANIFEST
assert 'Name = "Air Swim"' in SWIM and 'ConfigKey = "Universal.Swim"' in SWIM
assert '"Air Swim", category = "Exploits"' in MANIFEST
assert '"[Arrows]"' not in MANIFEST and '["Swim"]' not in MANIFEST

# --- the stamp that ships this build ---------------------------------------
assert 'local SOURCE_STAMP: string = "v19' in WURST

print("PASS v191 labels: derived build label, Buttons row keeps its key, pin on the arrows token, renamed cards keep their keys")
