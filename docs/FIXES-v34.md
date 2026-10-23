# v34-20261016-knife-rebuild

## Manual Shoot is not Auto Shoot

The previous release incorrectly applied the held-only policy to manual Shoot.
The manual action now finds the owned gun in hand OR backpack, equips once if
needed, waits one Heartbeat for the grip/muzzle, then calls the shared firing
path. A weapon/character switch during that wait cancels; it never equips again
in a loop. Reentrant presses are coalesced. There is an explicit **Shoot now**
menu action (with Shoot enabled). Manual shortcut/mobile activation uses the
same function. Auto Shoot retains its held-only check and never calls EquipTool.

## No default keybinds

MM2 Shoot/Get Gun and all TRS action keys start at Unknown. The older .luau
entry points are updated too. Global activation registration no longer silently
turns Unknown into a suggested key. Opening the menu also starts unbound.
The clickable launcher remains available on desktop without a menu key.
A one-time config migration clears old Shortcut entries, key-option values and
the old menu toggle key. Other configuration is retained. After migration,
explicit user assignments are saved and respected normally; they are not erased
on every execution. Flight's built-in movement controls are not activation keys.

## Rebuilt Knife

Re-read BOTH native logs and the place source rather than treating all captured
calls as module calls. In both logs, KnifeThrown captures originate from native
`Backpack.Knife.KnifeClient`, function throwKnife, line 145/147. They contain TWO
CFrames and the origin includes nonidentity rotation. The rebuilt normal path
uses the current Handle.CFrame (hand fallback), preserving orientation instead
of replacing it with an identity-rotation CFrame at the hand position.

Recovered ThrowingKnifeVisuals (referent 23543) integrates:
`position += Direction * ThrowSpeed * dt`, default speed 96 studs/s. No projectile
gravity is added. The new private predictor solves:

```
r = observedTargetPosition + filteredVelocity * liveLatency - releaseOrigin
|r + filteredVelocity * flightTime| = throwSpeed * flightTime
```

It uses cancellation-resistant quadratic roots, the approaching linear limit,
finite guards, the earliest positive intercept and a four-second horizon bound.
A finite explicit ThrowSpeed attribute on the held knife overrides the recovered
96 default. Old aggregate spawn-delay averages/learned speed do not tune this
solver. Live latency is bounded; compensation is a model, not server-hit proof.
Target velocity remains constant over the extrapolation: future opponent turns
and jump-state changes are not knowable from an earlier sample.

### New local animation, not an asset-name fallback

Deleted the v33 clip-name/cache/fallback implementation. The reconstruction now
owns R6's shoulder or R15's shoulder, elbow and wrist. Parent-space shoulder
rotation is essential: R6's rotated bind frame made the previous post-multiplied
X rotation a sideways swing rather than a clear lift.

- 0–200 ms: raise the knife above the shoulder, bending the R15 elbow.
- 200–300 ms: bring the arm forward, extending the elbow.
- At release: re-read held knife, target validity/range, current origin,
  prediction and WallCheck, then author **one** packet.
- 300–550 ms: recover the captured pose.

Uses the render task bucket, after Animator work, rather than the Heartbeat
bucket that can be visually overwritten by Animate. Exact C0/Transform are
restored on completion, OFF, unequip, respawn or joint loss. Pending throws are
cancelled rather than sent after unequip/OFF. With animation OFF (or no supported
joints), the action releases immediately. The cooldown starts at packet release;
wind-up is additional time. No fake animation ID or extra WeaponService throw
call is used. These timings are authored reconstruction, not claimed native
keyframes. This is a local pose; other-client visibility is not guaranteed.

## UGC/catalog emotes

HumanoidDescription.GetEmotes reports catalog item IDs, which can differ from
AnimationTrack.Animation.AnimationId. Checking those numbers as if they were
identical missed unnamed catalog tracks.

Prefer Humanoid.EmoteTriggered(success, actualTrack), including UGC emotes not
present in the initial description. The event is RobloxScriptSecurity in the API
dump, so its connection is protected: executor permissions vary. As a fallback,
resolve equipped catalog containers with GetObjects asynchronously and read the
contained Animation IDs. Temporary objects are never parented/executed and are
destroyed after inspection. Jobs are generation-cancelled on OFF/respawn. If the
executor denies BOTH facilities, only the existing name/ID metadata path remains;
the code does not guess that every Action-priority attack is a dance.

OFF stops the actual remembered UGC source, recognized playing emotes and owned
replacements, and disconnects BOTH listeners. Ordinary combat/locomotion tracks
are excluded. Jump persistence remains.

## Verification

- Actual manual Shoot route: equip once, held gun, cancellation during equip,
  OFF; actual Auto Shoot route stays equipped-only.
- Matrix-based R6/R15 tests prove the arm points UP at wind-up and FORWARD at
  release, including the rotated R6 bind frame, render phase, one packet,
  exact pose restore, OFF, unequip, respawn and stalled frames.
- Actual throw packet tests: no packet during wind-up, fresh prediction on
  release, original oriented handle frame, interval, invalid target and LOS.
- UGC tests: differing catalog/animation IDs, unnamed dynamic engine track,
  denied-event fallback, source/replacement OFF cleanup, async cancellation.
- Key tests execute migration/registration and verify explicit assignments
  survive a second load. All prior regression suites remain included.

Sources: TestingStuff log blobs 1465904de484da7dfc675bbf4792d4677c1498b3 and
58bc36f7643d5bc678c6b4d9f0c2678b11eb6b23; place source blob
755f47708dfbe83a5eaad25d5a60a5a36788dcf6. API signature checked against
MaximumADHD/Roblox-Client-Tracker API-Dump.json. Mock/compile results do not replace
a live R6/R15 and executor compatibility check.
