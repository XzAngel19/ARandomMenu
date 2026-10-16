# v32-20261016-arm-jump-shoot

## Data actually reviewed

Three files retrieved from XzAngel19/TestingStuff via GitHub API:

| File | Git blob SHA | Build | Gun confirmations | hitPart-target associations | Tracer events |
|---|---|---|---|---|---|
| MM2_Trajectory_Calibration.json | 38b0cd76499c4465376d9181146ef59aba5dcb86 | v31 | 9 | 3 | 9 |
| MM2_Trajectory_Calibration.json.before-0840b24e-0fb8-4233-af94-9b874df75bc5.json | 5af0bcff9b7cdfc63860159f0e2cfad1f608219c | v30 | 12 | 2 | 0 |
| MM2_Trajectory_Calibration.json.before-76b9bd3a-5667-4557-802c-64ef145df9fd.json | 0f97ae190c0ac597918b5c29218f54e73534e9ab | v31 | 2 | 2 | 2 |

These counts are NOT hit percentages: they describe recorded GunFired echoes,
not a controlled denominator of all intended shots. The six non-target Tracer
endpoints in the latest file refer to map parts. Two lack a matching authored
record, so must not automatically be treated as failures of the Shoot solver.
Stationary examples include a teleporter trigger and a spawn volume; not every
non-hit can be corrected by changing a motion coefficient.

The latest rising shot sequence :40 starts at vertical velocity 42.645 studs/s.
At 150 ms, interpolating the recorded client trajectory gives +4.159 studs.
The old upward cap forced at most +3. A ballistic replay with the default turn
discount gives +4.176; allowing that result reduces this specific client-pose
vertical residual from 1.159 to 0.017 studs. This is not an actual server replay:
pre-shot turn rate/acceleration were not stored, and no new hit is proven.
Other trajectories include landings/direction reversals where the initial
velocity cannot predict a later new input. No claim of perfect accuracy follows.

`tools/audit_calibration_v32.py` reproduces the summary from the three JSON paths.
Downloaded raw files are kept in ignored local research storage, not committed.

## Changes

### Real left-arm joint control

Double weapons now author the desired left shoulder/elbow/wrist pose through
Motor6D.C0 and neutralize the Transform channel each update. Unlike the prior
Transform-only approach, this directly changes the real limb's joint basis.
The equation is C0 = parent^-1 * desiredPart * C1 with Transform = identity.
The original C0/Transform of each touched joint is retained and restored on
unequip, rebuild, disable or character removal. No right-arm joint is modified.
A Part1-based fallback finds custom-named left shoulders. Weapon copies retain
live reflected grip offsets. This is local cosmetic posing, not extra shots.

Tests check C0 writes and exact restoration of a non-identity original C0,
as well as R6/R15, current right-side transforms and delayed skin placement.
Real Roblox/mobile animation fidelity still needs user confirmation.

### Keep emotes across jumps

Jumping no longer clears the selected managed emote. Its separate track keeps
playing while Freeze Emotes is enabled. Death, another emote, mode change,
disable and teardown still release it. Tests verify that jumping retains the
track and OFF subsequently destroys it exactly once.

### Shoot

- Normal Shoot's WallCheck now uses conservative ray checks: an untagged invisible
  part blocks the ray instead of being skipped solely because Transparency=1.
  Explicit WeaponPassthrough exclusions remain. This may reject more shots in
  maps with harmless invisible queryable parts; it does not assert complete
  equivalence with server collision rules. WallCheck OFF still skips that gate.
  Other callers retain the previous cursor-filter behavior unless they request
  the strict fourth argument. Silent mode still bypasses wall visibility.
- Remove fabricated WalkSpeed motion when remote measured velocity is zero but
  MoveDirection is nonzero. Captured remote direction can oppose actual velocity.
- Increase the ballistic upward displacement cap from 3 to 6 studs; keep the
  conservative downward cap at -3 for uncertain landings. Shared Shoot/Silent
  solver uses this change; no arbitrary RTT multiplier was fitted to these files.
- New authored settings save actual leadSeconds, predictedPoint, sampledVelocity
  and errorRadius in both modes, so subsequent calibration can compare the
  exact prediction made rather than infer it from a later server endpoint.

No predictor change guarantees 99.99% hits. Missing pre-shot state, changing
inputs, map occlusion and server validation remain explicit limitations.

## Manual check

Use a fresh server and confirm v32 in F9. Equip Gun with Double Gun enabled;
observe whether the real left arm now raises, then disable and confirm normal
arm pose returns. /e dance2 -> walk -> jump -> walk should keep the held emote;
OFF releases it. For Shoot, first use Lead bias=0 and Auto tune lead OFF so the
new behavior is not mixed with an old adaptive correction. Keep WallCheck ON.
Test a clear straight-motion shot and a jump, then Save calibration. Do not
interpret a deliberately blocked/rejected shot as a prediction miss.
