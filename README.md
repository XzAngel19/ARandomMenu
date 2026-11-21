Loader: 
loadstring(game:HttpGet("https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/main/src/Wurst.lua"))()

## Speed Hub X (standalone menu shell)

`src/SpeedHubX.luau` is a self-contained, single-file, client-sided menu
modeled on the "Speed Hub X | Version: 3.7.0" screenshot (window chrome,
sidebar navigation Home / Main / Farming / Killer / Misc, Skill / Aim /
Body sections, toggles, the "Choose Aim Part" dropdown, floating "S" logo,
"Supa Tech V2: Off" pill and the "CAN YOU EVEN SEE ME?" watermark).

Features are intentionally NOT implemented — every feature callback is an
empty stub (e.g. `Features/Main.luau`). The window chrome itself (drag,
viewport scaling, tab switching, toggle / dropdown visuals, RightControl to
hide, × to destroy) is fully working UI code.

Load it in an executor (works as soon as the branch is pushed; switch
`arena/1695b3a1-arandommenu` for `main` after merging):

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/arena/1695b3a1-arandommenu/src/SpeedHubX.luau"))()
```

Sources live in `src/speedhubx/` — edit those, then rebuild:

```bash
python3 tools/build_speedhubx.py          # regenerate src/SpeedHubX.luau
python3 tools/build_speedhubx.py --check  # verify the bundle is fresh
```
