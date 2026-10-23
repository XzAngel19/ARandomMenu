# v31-20261016-tracer-emote-double

## Tracer Data → Calibration

Calibration already recorded endpoints on matched gun confirmations. The Tracer
Data notification itself had no explicit persistence bridge. Weapon Visuals also
looked for GunFired under an unloaded ModuleScript, unlike the core.

Weapon Visuals now resolves the loaded service through the core and sends its
local-gun feedback to `trajectoryCalibration:noteTracerData`. A gun in the local
Backpack is recognized too (macro unequip before the echo). Invalid/nonfinite
positions are rejected. Vector3 and CFrame event positions are supported.

Events are saved in `session.events` with `phase="tracer-data"` in:
`Wurst/Telemetry/MM2_Trajectory_Calibration.json`.

Each contains origin, endpoint, range, hit-part path if available, observed target
position/identity if available, distance to that observed position, timestamp and
ping. A recent pending shot's ID is attached when its origin matches. Otherwise
it remains unlinked. Feedback does not increment attempt/confirmation counters
or train the predictor as though it proved a hit/miss. Existing bounded events
and batched autosave apply. Manual Metrics → Calibration → Save calibration
writes the same events. Turn on Weapon Visuals and Tracer Data to collect them.

The target position is observed by the client on receipt, NOT the authoritative
position at server impact time. This distinction is stored with each event.

## Landing circle

The hitPart-wide Highlight is removed. A 12-pixel outlined BillboardGui ring
marks the reported endpoint, always visible, and expires after 1.55 seconds.
It faces the camera; it is not a reconstructed surface-normal decal. Tracer Data
alone draws the marker; TrailESP additionally draws the path. Transient folder
children are capped. This visual change does not change shot arguments.

## Double weapons

Copies now use live mirrored weld offsets, correcting skins placed/updated after
the first rebuild and matching the handedness of the mirrored arm. Cloned local
transparency modifiers are reset. Right-arm poses are evaluated from current
Motor6D transforms when available instead of relying on stale physical part
CFrames during PreSimulation. Source weapon parts remain unmodified.

Tests include stale physical CFrames with a changed shoulder Transform, delayed
skin placement, and clone visibility. These do not prove visual fidelity of every
skin or rig in Roblox; the reported mobile skin needs manual confirmation.

## Freeze Emotes

`/e dance2` may expose Animation1/2/3 rather than a dance2 track name. IDs under
Animate's emote folders and ancestry names now participate in detection. After
Animate stops a recognized emote on movement, a separate managed Action-priority
looped track plays that animation. Animate does not own/cancel that new track.
Do not require the original Looped flag: Animate may implement looping itself.
Managed tracks are not rediscovered as new emotes. A new emote replaces the
previous managed one. Jumping, death, mode change and disabling release them.
Generic Action-priority attacks are still not classified as emotes.

The feature intentionally holds the selected emote until those release paths;
manual cancellation while moving cannot always be distinguished from Animate's
movement cancellation. If unwanted, toggle Freeze Emotes off.

## Checks

- Actual calibration writer preserves the new event and does not inflate counts.
- Actual Weapon Visuals service callback works with no murderer, persists feedback,
  draws a landing circle and creates no hitPart Highlight.
- Actual Freeze module handles a nonlooped Animation1 from dance2, preserves the
  independent track despite original-track cancellation, replaces it cleanly and
  releases it on jump/disable.
- Full-boot mock, bundle synchronization, compilation and prior regressions.

Manual: new Roblox server, verify v31 in F9, enable Weapon Visuals + Tracer Data,
fire one shot, save calibration, and inspect session.events for tracer-data.
Then test Double Gun while aiming and /e dance2 followed by walking, jumping and
OFF. For a remaining Double Gun issue, provide the skin name and a short clip
showing right/left arms while aiming; screenshots alone cannot show the motion.
