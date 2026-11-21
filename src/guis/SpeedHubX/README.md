# Speed Hub X — standalone executor GUI replica (Version 3.7.0)

A client-sided Luau GUI menu replicating the menu in the reference
screenshot, built to run **directly in a live Roblox client via a script
executor** — not in Roblox Studio. No external assets, no `HttpGet`, no
`require` of game content: the shipped file is fully self-contained.

> **Stubs only.** Every feature callback is an empty function
> (`Modules/Features.luau`). Toggles flip, the dropdown selects and the
> slider moves, but no gameplay, combat, farming, movement, automation or
> exploit logic exists in this package.

## Run it

Execute the single generated file in your executor:

```lua
loadstring(game:HttpGet("<url to src/guis/SpeedHubX/SpeedHubX.lua>"))()
```

…or paste/execute `SpeedHubX.lua` directly. Re-running the script destroys
the previous copy first. Controls:

| Action | Behaviour |
| --- | --- |
| Drag title bar | Move the window (can be disabled in Misc) |
| `RightShift` | Show / hide the menu (ignored while typing) |
| `✕` (top-right) | Hide the menu |
| Sidebar | Switch tabs — Main is selected by default, as in the image |
| Home → Unload Menu | Destroy the GUI and disconnect all UI connections |

The handle is returned by the script and also stored at
`getgenv().SpeedHubX` (`SetVisible`, `ToggleVisible`, `SelectPage`,
`SetScale`, `Destroy`, `Window`).

Safe parenting: `syn.protect_gui` when present, then `gethui()` →
`CoreGui` → `PlayerGui`, each step `pcall`-guarded (`Modules/Util.luau`).

## Layout of the code

```
SpeedHubX.lua            GENERATED single-file bundle (what executors run)
Modules/
  Theme.luau             colours / fonts / sizes sampled from the screenshot
  Util.luau              instance factory, safe parenting, dragging, cleanup
  Controls.luau          Section / Toggle / Dropdown / Slider / Button / Paragraph
  Window.luau            window chrome, title bar, sidebar navigation, pages
  Features.luau          EMPTY stub callbacks (the only feature hook points)
  Pages/
    Main.luau            the replicated page (Skill / Aim / Body)
    Home.luau            version info + Hide / Unload (menu chrome only)
    Farming.luau         stub page (tab not visible in the image)
    Killer.luau          stub page (tab not visible in the image)
    Misc.luau            menu-only settings: Menu Scale slider, dragging toggle
  Bootstrap.luau         composition root: builds pages, keybind, App handle
```

Each module file returns a factory `function(Deps) -> Module`. The bundle
generator wires them once (Theme → Util → Features → Controls → Window →
Pages → Bootstrap, sharing one connection bucket so `Destroy()` unloads
everything). To use the modules without the bundle, replicate that wiring —
it is the footer of the generated `SpeedHubX.lua`.

Regenerate / verify the bundle after editing any module:

```bash
python3 tools/build_speedhubx_bundle.py          # regenerate
python3 tools/build_speedhubx_bundle.py --check  # fail if stale
```

## Replica notes (image → UI)

* Window: ~1020×640 near-black (`10,10,10`), 10px corner, thin dark-red
  edge, title `Speed Hub X | Version: 3.7.0`, `✕` close at top-right.
  A `UIScale` shrinks it to fit small viewports.
* Sidebar (260px, dark grey `35,35,35` rows): `Home / Main / Farming /
  Killer / Misc`; **Main** is selected — solid red (`204,0,0`) with
  light-red text. Icons are text glyphs (`⊞ ⌂ ⛏ ☠ ▤`) so no uploaded
  assets are needed.
* **Skill**: `Auto Ultimate` — "This is Meaning Auto Use Ultimate" (**on**,
  red dot); `Auto Dash` — "This is Meaning Auto Use Dash" (**on**).
* **Aim**: `Choose Aim Part` dropdown (value box shows **Head**; options
  `Head / HumanoidRootPart / Torso`); `Aimlock` — "Aimlock = Lock Camera
  Player" (off).
* **Body**: `Anti-Knockback`, `Anti-Stun`, `Anti-Busy`, each subtitled
  `BETA` (all off). Rows are dark cards (`30,30,30`, 8px corner) with a
  square toggle track on the right holding a red (on) / grey (off) dot.
* Not part of the menu and therefore not replicated: the Roblox top bar,
  the game's HUD (`Characters`, `Supa Tech V2: Off`, `CAN YOU EVEN SEE
  ME?`, the floating `S` logo) and the 3D world behind the window.
* Tabs not visible in the image (Home/Farming/Killer/Misc) are honest
  stubs — no feature labels or logic were invented for them. The Misc
  slider/toggle only affect this menu itself; the reusable `Slider`,
  `Button` and `Dropdown` components live in `Modules/Controls.luau`.
