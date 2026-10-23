# v37 — Sprint keybind, Jump modes and live Shoot visibility

Stamp: `v37-20261016-live-shoot-jump`.

## Sprint

- Sprint remains inside Speed, with an inline configurable KEY slot.
- The shortcut toggles the same checkbox/callback/persisted value as a click;
  it does not maintain a second Sprint flag or write WalkSpeed independently.
- It uses the existing shortcut capture, text-focus guards, mobile placement
  and persistence. Default remains unassigned, as requested for non-menu keys.
- Implemented as opt-in `Bindable` for framework toggle options, leaving other
  existing checkbox layouts alone. Auto Shoot also opts in.
- Speed still must be ON for its Sprint option to affect movement.

## Jump

- Keeps only Normal, Rise and Fall.
- Rise speed appears only in Rise. Infinite jump power and jump interval
  appear only in Normal/Fall. These controls also require Infinite jump ON.
  Custom jump power still has its own visibility gate; High Jump remains an
  independent action with its own velocity, not a Rise/Fall setting.
- Fall no longer waits for negative Y and cancels descent. It makes the jump
  with Freefall state and the rig's actual falling animation, even ascending.
- Reads `Character.Animate.fall` and `jump` animation objects; no fixed asset
  is substituted. The supplied place XML actually contains both folders and
  their Animation children. The saved R15 fall ID is 507767968, but runtime
  uses the current character's asset instead of hardcoding that ID.
- Stops only the native jump clip(s), plays an owned fall track at Movement
  priority, and handles native Jumping transitions too. Merely changing to
  Freefall is insufficient because Animate retains its jump timer briefly.
- Handles takeoff if changing state happens before physics applies the jump;
  stops/releases the track on landing, mode change, OFF, respawn and destroy.
  Unrelated emotes are not explicitly stopped.

## Auto Shoot inside Shoot

- Removes the standalone Auto Shoot card. Checkbox belongs to Combat > Shoot,
  uses Shoot's mode and target, and operates only with Shoot ON and gun held.
- Preserves the previous card's saved enabled state and explicit shortcut on
  first migration, without overwriting an already-saved child option value.
- First attempt on enable, then once per current Heartbeat. No distance cap,
  confidence gate or separate Fire delay timer. Turning the option/master OFF
  disconnects the loop. The status reports missing gun, target or rejection.
- Removes the hardcoded 3.1-second lockout measured from our last REQUEST.
  The old interpretation of sparse logs as an authoritative server cooldown
  was too strong: a request without confirmation does not prove an accepted
  shot or justify starting a full local reload window. Failed requests must
  not postpone the next visible opportunity by another 3.1 seconds.
- Native Tool.Enabled, Disabled/Reloading/IsReloading attributes still gate
  readiness. Sending a request is not claiming server acceptance. If reload
  exists only on the server, the server can reject attempts until ready;
  this code does not bypass the server's cooldown or guarantee acceptance.
- Manual Shoot uses the same current-shot path, retaining explicit autoequip;
  Auto never autoequips. Local range checks do not reject a 1000-stud target.

## WallCheck correction

The prior path checked the PREDICTED point first. A ray to empty air could be
clear even though the target had already closed the peek. Fallback body probes
were never consulted if that first check passed.

Now, on EVERY attempt:

1. Read the current target character, body transforms and gun origin.
2. Probe torso/head first, then limbs. Points are based on each part's current
   size/orientation rather than a stored root frame or old peek position.
3. Require the current visibility ray to actually hit the target character.
   A clear ray that hits nothing is not proof of a visible target. This also
   prevents a probe outside a small/mesh hitbox from inventing visibility.
4. Anchor the existing lead displacement to that currently exposed point.
   If cover blocks the lead, use the currently visible point instead.
5. Fully hidden current body fails closed, even if an old/future point is open.

Shared transparency/WeaponPassthrough filters remain. `requireTarget` is an
opt-in current-body check; Knife's finite-flight path/default ray semantics
are not replaced. Silent still intentionally bypasses normal WallCheck.

No speculative new prediction coefficients were added to disguise these
activation/visibility defects. The archived v35 reference remains unchanged.

## Verification

- 17 Python/Luau suites, including actual nested Auto controller, actual Jump
  module and native-track lifecycle, actual Speed+Sprint integration and all
  previous regressions.
- Tests cover a 1000-stud endpoint, immediate retries, native readiness changes,
  master/option OFF, current target movement, hidden body with clear lead,
  partial-body visibility and closing a formerly exposed peek.
- Full mock boot: zero loader failures; inline Sprint shortcut toggles the
  real option; no standalone Auto Shoot; Jump rows change with mode.
- All 77 Lua/Luau sources compile; 68-file bundle regenerated and checked;
  `git diff --check`; archived baseline hashes verified unchanged.

These tests do not establish live hit rate, visual fidelity on a real mobile
or successful server acceptance. No claim of those measurements is made.
