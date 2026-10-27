#!/usr/bin/env python3
"""Loader, launcher and UI-settings contracts (v138.7).

Three user-visible problems are pinned here:

  1. The loader kept a second copy of the whole source tree on disk
     (Wurst/src/** plus Wurst/.stamp). Every boot paid an isfile+readfile per
     source before touching the network. The loader is now bundle -> memory ->
     one HTTP GET, and the legacy folder is purged in the background.
  2. The old circular launcher (the "circle with three lines") was created
     VISIBLE, so it flashed for the whole load. It must start hidden and only
     appear once every section has initialized.
  3. UI Settings had two unnecessary switches: Random Card Order and Rainbow.
     The shuffle stays (it is what makes the order random), the switches do not.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WURST = (ROOT / "src/Wurst.lua").read_text()
SETTINGS = (ROOT / "src/guis/Wurst/Code/SettingsPage.lua").read_text()
CLICKGUI = (ROOT / "src/guis/Wurst/Code/ClickGui.lua").read_text()
CARDS = (ROOT / "src/guis/Wurst/Code/Cards.lua").read_text()

# --- 1. no per-source disk cache ------------------------------------------
for gone in (
    "readCachedSource",
    "writeCachedSource",
    "ensureSourceFolders",
    "sweepStaleSources",
):
    assert gone not in WURST, f"the old source cache is still referenced: {gone}"

assert "state.purgeLegacySourceCache = function" in WURST
assert 'purge("Wurst/src")' in WURST
# the only remaining mention of the legacy stamp file is deleting it
assert WURST.count("Wurst/.stamp") == 1
assert 'pcall(deleteFile, "Wurst/.stamp")' in WURST
# The purge must not block the boot: it is spawned, never awaited.
purge_call = WURST.split("local purgedSources: number = state.purgeLegacySourceCache()", 1)
assert len(purge_call) == 2
spawn_before = purge_call[0].rstrip().rsplit("task.spawn(function(): ()", 1)
assert len(spawn_before) == 2, "the legacy purge must run inside task.spawn"

fetch = WURST.split("state.fetchRepositorySource = function", 1)[1].split("\nend", 1)[0]
assert "state.boot.bundle" in fetch, "the bundle is the first source"
assert "state.httpGetPath(path)" in fetch, "then one HTTP GET"
assert "readfile" not in fetch and "isfile" not in fetch, "no disk reads per source"

# --- 2. launcher hidden until the menu is ready ---------------------------
assert "Visible = false," in WURST.split("Name = \"MobileMenuButton\"", 1)[1][:800], \
    "the launcher must be created hidden"
assert "MobileMenuButton.Visible = state.menuReady == true" in WURST
assert "state.menuReady = true" in WURST
assert "state.refreshLauncher" in WURST
# and the flag is set only when every section finished
complete = WURST.split("Load complete", 1)[1][:800]
assert "state.menuReady = true" in complete, \
    "menuReady must be set when the last section reports complete"

# --- 3. UI settings cleanup ----------------------------------------------
ui_panel = SETTINGS.split('local uiPanel: any = panelFor(uiRecord, "ClickGUI")', 1)[1]
assert '"Random Card Order"' not in SETTINGS, "the Random Card Order switch must be gone"
assert "state.randomCardOrder" not in SETTINGS
assert "rainbowConnection" not in SETTINGS, "the Rainbow controller in UI settings must be gone"
assert 'addToggleOption(uiPanel, "Rainbow"' not in ui_panel.split("local uiRecord.placed", 1)[0]
# the palette, opacity and the dock controls are still there
for kept in ('"Background"', '"Accent"', '"Opacity"', '"Keep after teleport"'):
    assert kept in ui_panel, f"unrelated UI setting was removed: {kept}"
# the HUD list's own Rainbow is a different panel and stays
assert 'addToggleOption(panel, "Rainbow", HACKLIST_RAINBOW' in SETTINGS

# The shuffle itself survives without the switch.
assert "nextRandomRank" in CARDS and "FeatureSortRank" in CARDS
sort_body = CLICKGUI.split("local function sortCategoryRows", 1)[1].split("for index", 1)[0]
comparator = sort_body.split("table.sort(rows", 1)[1]
assert 'GetAttribute("FeatureSortRank")' in comparator
assert 'GetAttribute("FeatureSortName")' not in comparator, \
    "the alphabetical tie-break must not be back in the card order"
assert "randomCardOrder" not in CLICKGUI
assert "ClickGui.restack" not in CLICKGUI

print("PASS loader has no source cache (bundle -> memory -> one GET, legacy purge in the background)")
print("PASS launcher starts hidden and waits for state.menuReady")
print("PASS UI settings: Random Card Order and Rainbow removed, shuffle kept")
