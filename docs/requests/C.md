# Requests from agent C

The integrator owns `ARandomMenu.luau`. Agent D owns `src/modules/**` and
`src/games/**`. C cannot edit those. The category remap below has to land
before the category gate can fail — turning it on today is a permanent
red: `CATEGORY_ORDER` is still Combat / Movement / Visuals / Protection /
Utility / Spoof.

## Remap category windows to official Wurst

Require exactly this order, in `ClickGui.CATEGORY_ORDER`,
`Framework.KNOWN_CATEGORIES`, `FEATURE_CATEGORIES` values, the manifest
fallback and the bundle:

1. Combat
2. Render
3. Blocks
4. Movement
5. Chat
6. Fun
7. Items
8. Other

Delete the windows named Visuals, Protection, Utility, Spoof. Do not
leave empty official windows: move every card with the map in
`docs/wurst-categories.md`.

Suggested landing:

| Current | Official |
|---|---|
| Visuals | Render |
| Protection | Movement (NoFall, SafeWalk) or Other |
| Utility | Other |
| Spoof | Fun |
| Combat | Combat |
| Movement | Movement |

Blocks and Chat may start empty only if a later module actually belongs
there. Prefer filing existing cards into Other over opening a blank
Blocks window.

The moment this lands, C will fail the gate if Visuals / Protection /
Utility / Spoof reappear as window titles, and if the official eight are
missing or out of order. Until then the contract lives here, not in a
red step.

## WurstLogo chip

`WURSTLOGO_BACKGROUND` is still `#000000` and the chip stays
`BackgroundTransparency = 1` until a player stores a colour. Official
Wurst always fills `y=6..17` with the setting, default `#FFFFFF` at
half alpha (`WurstLogo.java`). Restore:

- constant default `#FFFFFF`
- drawn alpha 0.5
- stripe at logical y=6..17 (12..34 at GUI scale 2)
- live `SetBackground` already exists
- never `BackgroundTransparency = 0`

The gate already prints the `#000000` seed as ungrounded. It will fail
the moment the constant is named and still wrong after you switch it
back to white — so switch the constant and the draw together.

## Navigator keys

Landed: search, three-column grid, preference sort, Enter activates,
shows with ClickGUI, hides with it. Still owed if we claim Navigator
parity:

- Space opens the selected feature's settings
- arrows move the selection
- Escape / Backspace close Navigator (today they do nothing extra;
  closing ClickGUI hides it)

RightShift opening ClickGUI (and therefore Navigator) is a recorded
Roblox adaptation. Do not steal the menu key for a second surface
unless the brief changes.

## Product name leftovers

Do **not** change `guiName`, `blurName` or `storageFolder`.

MM2 and ProjectileCalibration still hard-code `RandomTestingMenu0001`.
That is D.
