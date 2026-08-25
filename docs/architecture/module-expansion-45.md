# Universal inventory expansion: 45 modules

The deliberate universal inventory now contains 45 modules. This update adds two
universal surfaces and one shared library without changing the eight Wurst
category windows:

| Addition | Category | Ownership |
| --- | --- | --- |
| Aim Assist | Combat | Camera-only local assist backed by `Targeting`. |
| Learning | Other | Manual local screenshot plus metadata sidecar. |
| Targeting library | Shared library | Read-only target selection; not a card or inventory entry. |

The inventory authority is `tools/inventory_snapshot.json`. The manifest,
runtime fallback, generated bundle and parity matrix are updated together. The
previous `module-expansion-43.md` remains the record of the Chams, Arrows,
NPCESP, WallHop and SpinBot expansion.

These additions do not create a universal Silent Aim hook. A source file being
called a module does not isolate `hookfunction`, `hookmetamethod`, remote
rewriting or shared Instance mutation. Aim Assist therefore moves only the
local camera and pauses while menu input is active. See
`docs/architecture/targeting-and-learning.md` for the boundary and for the
existing MVSD-specific path that is not generalized.

Learning is opt-in per sample. It never starts a capture loop or uploads data.
Standard Roblox Luau has no screen-capture API, so the card reports
`unavailable` when the executor does not provide the optional capability.
