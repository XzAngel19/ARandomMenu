Loader: 
loadstring(game:HttpGet("https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/main/src/Wurst.lua"))()

## Standalone Speed Hub X UI replica

[`SpeedHubX.client.luau`](SpeedHubX.client.luau) is a **separate**, paste-and-run client script for a Roblox script executor. Copy the entire file into the executor and execute it while in a live client; it does not require the Wurst loader, external modules, asset IDs, network requests, or Studio. It tries `gethui()`, then `CoreGui`, then `PlayerGui` to parent the GUI. Re-executing replaces only its own previous instance.

The screenshot's menu is reproduced at its reference size and scales down for smaller viewports. The Main page shows the pictured Skill, Aim, and Body rows; the other sidebar pages are intentionally empty except for their headings because their contents are not shown. The launcher opens/closes the panel; tabs, switches, the Aim Part dropdown, and title-bar dragging affect **UI only**. All feature callbacks are empty (no gameplay/automation code). A slider and a button builder are available but not displayed because neither appears in the screenshot. The surrounding Roblox game world and unrelated game HUD are not part of this menu.
