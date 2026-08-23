# Universal inventory expansion: 43 modules

The project owner deliberately expanded the universal snapshot from 38 to 43.
This is not a Wurst 7.54 inventory import; each addition solves a Roblox use
case and keeps the existing module/context/render contracts.

| Module | Category | Reference | Runtime approach |
| --- | --- | --- | --- |
| Chams | Render | Vape Chams Highlight mode | pooled Roblox `Highlight` instances, team and wall policy |
| Arrows | Render | Vape Arrows | two pooled renderer lines per off-screen player; optional distance |
| NPCESP | Render | Vape entity NPC targeting | throttled Humanoid model index plus shared Render sets |
| WallHop | Movement | Roblox movement adaptation | one forward raycast per jump request, bounded cooldown |
| SpinBot | Fun | Vape SpinBot | CFrame or angular velocity with complete property restoration |

The inventory authority is `tools/inventory_snapshot.json`. Manifest, fallback
manifest, bundle and tests must match it. Config keys are stable:

- `Universal.Chams`
- `Universal.Arrows`
- `Universal.NPCESP`
- `Universal.WallHop`
- `Universal.SpinBot`

Physics-sensitive behavior still requires field testing across games. C owns
behavioral regression gates; D owns gameplay/reference review. Their current
work orders are in `docs/requests/C.md` and `docs/requests/D.md`.
