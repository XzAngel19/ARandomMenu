# C8 — module expansion gates

Tools, tests and docs only. Runtime behaviour is held, not rewritten.

`C_MODULE_EXPANSION_GATES`

## Behaviour suites

`tools/test/suites/expansion-behavior.luau` sits next to the registration
checks in `new-modules.luau`. It drives the five added modules through the
mock instead of stopping at "the card exists".

| Module | Held contract |
| --- | --- |
| Chams | teammates off/on, dead players dropped, through-walls depth, respawn re-adorn, disable destroys Highlights |
| Arrows | on-screen hidden, off-screen drawn, teammates excluded, distance label, max distance, disable releases |
| NPCESP | non-player Humanoids only, Player characters excluded, health label, dead/far hidden, disable releases |
| WallHop | no wall / floor-like normal ignored, vertical wall hops with height+push, cooldown, jump callback dropped on disable |
| SpinBot | CFrame rotation, Velocity angular write, AutoRotate off while enabled, respawn takeover, disable restores properties |

## Slider precision

Framework `CreateSlider` forwards `Step` as the eighth `addNumberOption`
argument. Integer sliders stay integral after typed noise and pointer
drags. Decimal sliders without an explicit step snap to hundredths. Config
stores the quantized value, never `1.7339128`.

The host stub now accepts `Step` so a missing forward fails the suite
instead of being dropped on the floor.

## Exclusive surface dragging

A Custom HackList that owns `state.surfaceDragOwner` still prevents an
overlapping window from starting a drag. Window and HackList ownership
clear on pointer release. Furniture destroy clears a live Custom
HackList owner. Do not create a throwaway managed window just to prove
Destroy: that persists a `configData.ui.windows` key and leaks ClickGUI
connections on the shared host.

## Inventory authority

`tools/inventory_snapshot.json` is the count. Suites load it through
`tools/test/inventory.luau` and compare against `ctx.inventory.count`
instead of a copied `43`. The clickgui parity table still names each
module; only the numeric freeze moved.

## Mock improvements (C8.5)

Improved rather than weakening assertions:

- `Humanoid:ChangeState` and default `AutoRotate = true`
- `CFrame.Angles` plus `CFrame * CFrame` keep a running Euler so SpinBot
  is observable
- `WorldToViewportPoint` treats points outside the viewport as off-screen
- `Workspace:Raycast` records the last origin/direction/params
- `Highlight` defaults
- `world.replaceCharacter` for respawn teardown
- host `addNumberOption` accepts and records `Step`

## Remaining mock debt

These still approximate the executor poorly. Do not paper over them in
suites; extend the mock when a test needs the real contract.

| Surface | What the mock does | Why it still matters |
| --- | --- | --- |
| `TweenService:Create` | applies goals immediately, never fires `Completed` | animated HackList drops cannot be exercised |
| `AbsoluteSize` / `AbsolutePosition` | do not follow `Size` / `Position` | APPLY-4 scroll-clip and some hit tests stay source-held |
| `FindFirstChild` | not recursive | suites must walk descendants themselves |
| `HttpService` JSON | encode is a count stub; decode returns `{}` | config round-trips cannot use the real codec |
| `getconnections` | dummy `Fire` that does not know handlers | MM2 timer replay stays untested |
| `hookfunction` / `newcclosure` | absent on the default world | MVSD silent-aim hooks cannot be driven |
| `getcustomasset` / `getsynasset` | absent unless a capability variant installs them | default boot must keep the font fallback |
| `gethui` | absent | shell parenting to a hidden root is untested |
| `http.request` / `syn.request` | absent | remote fetches stay on `game:HttpGet` |
| Geometric `Raycast` | returns the planted `world.raycastResult` | WallHop cannot prove filter descendants |

Physics-sensitive WallHop / SpinBot field behaviour remains D's debt.

## Allowlist

None.
