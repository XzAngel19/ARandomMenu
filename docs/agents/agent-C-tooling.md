# Agent C — Wurst's exact feature list, as a machine-checkable spec

Read `docs/agents/RULES.md` first, then sync (rule 12).

Your parity gate already caught the integrator narrowing a window in Luau while
the prototype said otherwise, and your empty-boot suite found a 49-connection
leak on the day the file it tests first existed. Both worked. This is the same
idea aimed at the rest of the client.

## The decision that changes your queue

The menu is not "inspired by" Wurst any more. It is a port, the way
`VapeV4ForRoblox` is a port of Vape: the same windows, the same settings, the
same names, the same defaults. Anything the old menu had that Wurst does not
have is going away, and anything Wurst has that we lack is missing.

Nobody currently knows what that list *is*. That is your job, and it blocks the
interface work, which means it is the most valuable thing in the repository
right now.

## 1. `docs/wurst-features.md` — the inventory

Sources, in order of authority: `assets/wurst/translations/en_us.json`, which is
already vendored and contains every setting key and description in the client;
`wiki.wurstclient.net`; and the screenshots in `docs/design/reference/`.

Produce a table per window, and for every setting: its exact Wurst name, its
type, its **default value**, and its in-game description. The defaults matter as
much as the names — Wurst's ClickGUI ships Background `#404040`, Accent
`#101010`, Text `#F0F0F0`, and getting one of those wrong is the difference
between a port and an imitation.

The windows to inventory, at minimum:

- **ClickGUI** — Background, Accent, Text, and whatever else 7.x exposes.
- **UI Settings** — the window that opens the ones below.
- **HackList** — Mode, Position, Sort by, Reverse sorting, Animations, Colour.
- **WurstLogo** — Background, Text, Visibility.
- **Navigator** — how search behaves, what it lists, what pressing Enter does.
- **Keybinds** — the manager: add, remove, edit, the command syntax.
- **Presets / Profiles** — what a preset stores and how it is loaded.
- **GlobalToggle**, **Isolate windows**, **Max height**, **Opacity**,
  **Tooltip opacity**, and the taco.

Mark each row with whether it has a Roblox counterpart, no counterpart, or is
meaningless here (anything about chunks, blocks or servers). Do not silently
drop the meaningless ones — write them down as deliberately absent, so nobody
re-discovers them in a month and thinks we forgot.

## 2. Fold the settings into `spec.json`

Every default from that table becomes an entry the parity gate can check, the
same way the pixel numbers already are. When I build the UI Settings window, a
default that does not match Wurst's should fail the build and name both sides.

## 3. Keep the suites ahead of the code

Same as before, for the pieces landing next: the row (filled when enabled, a
triangle only when the module has options, `Show` rules still working inside an
expansion while the window's height follows), the HUD list (exactly the enabled
cards, a status in brackets, a bare name when the status is `nil`), and the UI
Settings window once its spec exists.

## Not now

Anything about the old menu. It is being deleted, and a test that pins its
behaviour is a test that will have to be deleted with it.
