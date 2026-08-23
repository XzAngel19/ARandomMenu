# C3 — module-contract conformance

Report only. Base: integration tip `4ae81fe`. The gate is
`tools/check_module_conformance.py`, walked over `src/modules/**`. D owns
the authoring document (`docs/architecture/modules.md`); this file is the
finding list until that tree is clean. Surface fixes go through D / A.

Hard-fail flips in the same commit the last row below dies.

## Allowed config namespaces

`Universal.*`, `UI.*`, `ClickGUI.*`, `Shortcut.*`, `WurstLogo.*`.

## Findings

| File | Kind | Why it stays |
|---|---|---|
| `src/modules/Combat/KillAura.luau` | ScreenGui reach-in | Target readout parents onto `host.ScreenGui`. A HUD overlay belongs on a documented host surface, not a chrome name. |
| `src/modules/Combat/AutoClicker.luau` | ScreenGui reach-in | `isGameButton` excludes descendants of `host.ScreenGui` so the clicker does not fight the menu. Same chrome name. |
| `src/modules/Combat/ProjectileCalibration.luau` | bare print/warn | Dataset write/stop/delete narrate to the console. The injected shadows mute them at runtime, but the calls are still a contract miss. |
| `src/modules/Utility/RejoinServer.luau` | bare warn | Teleport failure path. Same: muted at runtime, still a reach for `warn`. |
| `src/modules/Utility/RemoteLogger.luau` | bare print | Report dump. Same. |

No config key outside the documented namespaces. The Spoof pair persists
`Universal.AnimationChanger.SavedIDs` and `Universal.EmotePlayer.SavedIDs`.

## What the silence gate already hard-fails

`tools/check_silence.py` refuses `realPrint` / `realWarn` (and a
`getfenv().print` grab) in `src/**` and `runtime/bundle.luau`. The shell's
own shadows in `ARandomMenu.luau` are the only allowed site.

`C_ARCHITECTURE_GATES_READY`
