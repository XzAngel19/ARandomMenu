# Wurst categories → this menu

Official Wurst 7 windows, in `ClickGui.init` order at
`4a22e53d774b9a28e395874834f099e779685998`: Combat, Render, Blocks,
Movement, Chat, Fun, Items, Other. Plus Radar's own window, plus UI
Settings. Uncategorised features (ClickGUI, Navigator, HackList,
WurstLogo, Keybinds) do not get a category window.

This port files cards under Combat, Movement, Visuals, Protection,
Utility, Spoof. The names are not a translation error: Visuals is
Render plus camera, Protection is the bits of Movement/Combat that
stop something happening to you, Spoof has no Wurst window.

`kind` is one of:

- **exact** — same job, same category.
- **adapted** — same job, Roblox-shaped, possibly another category.
- **roblox-only** — no Wurst counterpart; keep it, do not invent a
  Wurst name for it.
- **n/a** — Minecraft / Fabric / server; do not port.

| Our card | Our category | Wurst | Wurst category | kind |
|---|---|---|---|---|
| Kill Aura | Combat | Killaura | Combat | adapted |
| TriggerBot | Combat | TriggerBot | Combat | exact |
| Auto Clicker | Combat | — | — | roblox-only |
| Hitboxes | Combat | — | — | roblox-only |
| Projectile Calibration | Combat | Trajectories | Render | adapted |
| Player ESP | Visuals | PlayerESP | Render | adapted |
| Item Render | Visuals | ItemESP | Render | adapted |
| X-Ray | Visuals | X-Ray | Render | adapted |
| Fullbright | Visuals | Fullbright | Render | exact |
| FOV | Visuals | — | — | roblox-only |
| Zoom Unlocker | Visuals | Zoom (keybind) | — | adapted |
| Fly | Movement | Flight | Movement | exact |
| Speed | Movement | SpeedHack | Movement | adapted |
| High Jump | Movement | HighJump | Movement | exact |
| Jump Power | Movement | HighJump | Movement | adapted |
| Infinite Jump | Movement | — | — | roblox-only |
| Noclip | Movement | Noclip | Movement | exact |
| Spider | Movement | Spider | Movement | exact |
| Phase Dash | Movement | — | — | roblox-only |
| Click Teleport | Movement | — | — | roblox-only |
| Vehicle Speed | Movement | BoatFly | Movement | adapted |
| Freeze Movements | Movement | Blink | Movement | adapted |
| No Fall | Protection | NoFall | Movement | adapted |
| Safe Walk | Protection | SafeWalk | Movement | adapted |
| Anti-Void | Protection | — | — | roblox-only |
| Anti-Fling | Protection | AntiKnockback / AntiEntityPush | Combat / Movement | adapted |
| Anti-AFK | Utility | AntiAFK | Other | adapted |
| Gravity | Utility | — | — | roblox-only |
| Fling | Utility | — | — | roblox-only |
| Lag Switch | Utility | Blink | Movement | adapted |
| Improve FPS | Utility | — | — | roblox-only |
| Interact Extender | Utility | Reach | Other | adapted |
| Rejoin Server | Utility | AutoReconnect | Other | adapted |
| Remote Logger | Utility | — | — | roblox-only |
| Friend List | Utility | — | — | roblox-only |
| Disguise | Spoof | — | — | roblox-only |
| Animation Changer | Spoof | — | — | roblox-only |
| Emote Player | Spoof | — | — | roblox-only |

Wurst windows with no card here: Blocks (Nuker, ScaffoldWalk, …), Chat
(MassTPA, InfiniChat, …), Fun (Derp, Taco, …), most of Combat's auras.
Those are **n/a** until a Roblox module actually does the job. Do not
open empty windows for them.

TabGUI is a left-edge HUD, default Disabled — it is not Navigator.
Navigator is a separate full-screen GUI. Neither lives “under the logo”
as a window; the version string does.
