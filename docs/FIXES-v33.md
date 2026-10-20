# v33-20261016-equipped-actions

## Latest supplied calibration

Reviewed TestingStuff's MM2_Trajectory_Calibration.json blob
`1236f76f510889a8bf2cd0f32d95dfbbe78e9023` (4433 bytes, build v32).
It has three tracer-data events, three unmatched-signal events, zero authored
Shoot records, zero session gun attempts/confirmations, and no target trajectories.
One endpoint hit a target accessory; two hit map parts. Its 23 gun confirmations
and 30 knife confirmations at the top are aggregate history, not this session.
There is no basis to fit a new lead multiplier from these three unmatched echoes.

Also inspected TestingStuff's `place, source.rbxlx` blob
`755f47708dfbe83a5eaad25d5a60a5a36788dcf6` and `message.txt` blob
`07d24ce3815d7634f95d6fd4b729d5511a527b69`. Recovered WeaponService.ThrowKnife
fires a LOCAL BindableEvent, not a remote for positioning a hand or weapon.
Calling it alongside our KnifeThrown packet risks two independent throw paths.
No invented pose remote or unverified animation ID has been added.

## Equipped-only actions

- Knife Throw looks only for the knife equipped by the player. It never calls
  EquipTool. Unequipping pauses automatic throws and releases its local pose.
- `Throw now` is an explicit menu action using the same equipped-only gate,
  prediction, range, WallCheck and cooldown. It does not require the auto-loop.
  The native game's Throw button is left alone: it is NOT hooked to send a
  second predicted throw. This avoids duplicate packets.
- Auto Shoot and manual Shoot likewise do not equip a gun from the backpack.
  Auto Shoot polls while the player holds the gun and fires as soon as cooldown,
  target, enabled-weapon state and configured WallCheck permit.
- Removed Auto Shoot's Max error control and confidence wait. Auto permits the
  solver to return uncertain predictions; manual Shoot retains its uncertainty
  gate. It is an availability trigger, not a guarantee that the shot will hit.
- Server cooldown and fire interval still apply. Silent retains its explicitly
  selected through-wall behavior; normal mode follows Shoot's WallCheck.
- Removed Auto Range from Knife Aura, including the learned-range path. Aura
  uses the manual Aura Range only.

## WallCheck

Normal Shoot returns to the recovered WeaponService cursor-filter behavior:
ignore local character and WeaponPassthrough-tagged objects, iterate past fully
transparent parts with bounded ray work. It no longer requests v32's stricter
speculative mode. This is a client filter, not a claim of exact server behavior.
WallCheck remains a separate user-controlled safety gate.

## Knife animation

Prefer an identified weapon clip named Throw/ThrowAnim/KnifeThrow/ThrowAnimation.
When unavailable, use a LOCAL reconstruction rather than ToolLunge:
120 ms wind-up, 130 ms forward release, 230 ms recovery. It authors the right
shoulder's C0 relative to the captured current pose and neutralizes Transform
while active; restores exact original C0/Transform on completion, OFF, respawn,
or unequip. There is no guessed asset ID and no extra damage remote. This is
not represented as the recovered game's exact native throw animation.
Default interval remains one second; the slider's minimum is now 0.5 s to avoid
repeatedly interrupting the reconstruction with 0.2-second retriggers.

## Weapon Visuals

Remove Electric Knife, Electric color/intensity, beam/carrier code and electric
update tasks. `Trail color` remains solely for shot-feedback visuals.
Double weapons now copy the exact original hand-relative grip for each geometry
part rather than reflect that offset a second time. Real left-arm mirroring and
live grip updates remain; originals are unmodified. Real mobile/skin fidelity
still requires a visual check, not just algebraic mock tests.

## Freeze OFF

Stopping only managed replacements was insufficient if Animate's original dance
was still running. OFF/mode change/cleanup now stops the remembered original,
recognized currently playing emote sources, and owned replacements. Only owned
tracks are destroyed. Stop and Destroy use separate protected calls so a Stop
failure cannot skip cleanup. Ordinary walking/attack tracks are not stopped.
Jump persistence from v32 is retained while the feature is enabled.

## Verification

`test_mm2_equipped_actions.py` executes actual readiness, Auto Shoot tick, gun
firing gate and reconstructed animation functions. Covers backpack/held/unequipped,
no equip calls, high-error automatic availability, cooldown, disabled gun,
wind-up/recovery, and exact pose restoration. Other tests cover native clip cache,
removed electrical controls, original-emote OFF cleanup, high-error solver bypass,
R6/R15 joint cleanup and shot telemetry. Full bundle/compile/mock boot rerun.

Manual check: fresh server -> verify v33 -> enable auto with no weapon in hand:
nothing should equip. Equip yourself to start; unequip to pause. Test Throw now
with knife equipped, then off. Freeze Emotes -> dance -> OFF should stop the dance
both before and after walking. Check Double Gun's grip while aiming. Save a new
calibration after using the module's Shoot/Auto Shoot so authored predictions can
be correlated, rather than collecting only unmatched native-shot echoes.
