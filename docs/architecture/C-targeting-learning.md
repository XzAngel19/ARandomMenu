# C — Targeting, Aim Assist and Learning gates

Tools, tests and docs only. Runtime behaviour is held, not rewritten.

`C_TARGETING_LEARNING_GATES`

The product contract lives in `docs/architecture/targeting-and-learning.md`.
This file is the test hold.

## Suite

`tools/test/suites/targeting.luau` now covers:

| Surface | Held contract |
| --- | --- |
| Targeting | teammate skip, Friend List skip, FOV rejection, visibility obstruction, Cursor vs Distance sort, no camera write, destroy unpublishes |
| Aim Assist | camera-only look, no tool/touch/namecall side effects, pause on menu / key capture / focused text / MVSD adapter, disable and destroy drop the render task |
| Learning | group card, no capture on enable, missing screenshot API reports `unavailable` and writes nothing, incomplete service is still unavailable, `Capture now` writes one PNG plus JSON under `PRODUCT.storageFolder/Learning/`, metadata names the manual source, writeText failure keeps the image |

A missing executor screenshot function is not turned into a green fake
capture. The host stub exposes `world.screenCaptureAvailable` so the
unavailable path is a real branch.

## Inventory

Aim Assist and Learning are in `tools/inventory_snapshot.json` (45). The
parity matrix already names both cards. Targeting is a shared library, not
an inventory entry.

## Mock notes

Host `HttpService.JSONEncode` now encodes objects enough to hold the Learning
sidecar schema. The Roblox stand-in `HttpService` remains a `{}` stub and is
not used by this card.

`world.screenCaptureAvailable` defaults to true so an executor-present path
can still be asserted. The unavailable path must flip that flag (or remove
`capture`) and prove zero files.

## Remaining debt

- Physics-sensitive camera feel and real-device screenshot APIs stay field
  debt. The mock cannot prove a PNG is a real frame.
- MVSD Silent Aim remains game-local and is only held as a pause target.
- Geometric raycasts are still a planted `world.raycastResult`.
