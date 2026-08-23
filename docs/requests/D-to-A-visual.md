# D → A: remaining GUI-swap seams

Architecture audit on base `4ae81fe`.

## Hardened in D

- Framework text options now expose `option:Set(value)`. ItemESP, Friend List and Auto Clicker no longer write `.Object.Text` themselves.
- Killaura's private pixel-built target panel and its `Show target` row are removed. Target count remains available through the module status/HackList.
- No module reads card row/title/arrow/window internals.

## Remaining shared seam

- `src/modules/Combat/AutoClicker.luau` receives `host.ScreenGui` only to reject the menu's own buttons while learning a game attack button. This is not presentation, but it is a shell-instance dependency. A future host contract such as `host.isMenuGui(instance): boolean` would remove the last direct ScreenGui reference without moving hit-testing into the module.

## Documented storage exception

- Animation Changer and Emote Player read/write only their documented saved-ID keys through `host.configData`. They do not inspect layout, theme, windows or unrelated config.

Cards/Widgets remain the GUI seam: modules declare controls; those libraries decide pixels.
