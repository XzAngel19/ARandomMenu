# v35-20261016-menu-motion

## Requested universal windows

Display order is explicit, not alphabetical:

- Combat: Aim Assist, KillAura, TriggerBot.
- Exploits: Fly, Fling, Noclip, Spider, Speed, Jump, Interact Extender.
- Utilities: Anti Fling, Anti Void, Click Teleport, Freeze Movements, Ghost.
- World: Improve FPS, Gravity, Anti AFK, Safe Walk.

Render and game-specific features remain. The Fun window and universal SpinBot
are removed. HookPart is removed (the final request supersedes its earlier
inclusion). Learning, GameLearning and universal ProjectileCalibration/Metrics
are deleted, not merely disabled. Both the real manifest and fallback manifest
agree. Unlisted non-Render universal extras (WallHop, Disguise, Rejoin Server,
Lag Switch, Remote Logger) are no longer registered in these windows; their
source files are retained, inactive.

ClickGui, Framework and Wurst category definitions now agree. The requested
modules sort ahead of game-specific extras within their respective windows.
Old category names are internal compatibility aliases, not extra visible windows.
MM2 role notifications previously in Fun now belong to Utilities.

Fly's existing Universal.Fly configuration key is retained. Its PlatformStand
option, setting, ownership requests and writes are all removed, including the
implicit CFrame request. This does not remove the shared ownership service from
other modules that still use it. Invisible's display name is now Ghost, in
Utilities. KillAura and the other requested titles use the requested spelling.

## Menu key

RShift/RightShift is the menu default again. A one-time repair restores it when
v34 left the menu key Unknown. Explicit custom menu keys are preserved. Module
activation keys remain unbound by default; no Q/G defaults were reintroduced.

## MM2 calibration remains

The MM2-only card is named Calibration and uses state.mm2CalibrationFeature,
not a shared universal Metrics card. Its recorder, history, status, save/reset
and shot/throw correlation remain. No automatic deletion of existing executor
history files is attempted. Session Info's ordinary HUD is independent of the
removed universal learning/metrics collectors; its settings title is clarified.

## Freeze Movements: Anchor / Motion

There are exactly two modes. Anchor owns only root.Anchored and stops velocities;
it does not rewrite WalkSpeed, JumpPower, JumpHeight or AutoRotate. OFF and mode
changes restore the previous anchored value, including an originally anchored
root. Motion never blocks character movement.

Motion settings are shown only in Motion, with the existing square-checkmark
widget for two independent options:

- Freeze Emotes (default ON): retains classic/catalog emotes and releases source
  and managed tracks on OFF. v34 UGC track identification and catalog fallback
  remain, with the same executor-permission limitations.
- Freeze Animation (default OFF): captures the current eligible locomotion clip
  and loops an owned copy at Action priority. A walking clip therefore stays
  walking through jumps/falls or subsequent motion changes. Playback advances;
  this is not the removed Glitch Animations TimePosition=0 implementation.
  Ordinary attack tracks are not captured/stopped. OFF destroys only the owned
  locomotion copy, letting the native controller's current tracks show again.

With both options on, an active held emote takes precedence over the locomotion
copy. Root/character changes, death, OFF and mode switches release owned tracks.
Saved old Freeze Emotes/Glitch Animations modes migrate to Motion rather than
silently falling back to Anchor and unexpectedly immobilizing the user.

## Improve FPS restoration

Every property this module changes is captured before its first write in the
active generation. Cache entries are strong until restoration; detached objects
are restored too, not skipped because Parent became nil. Restore operations
are isolated per property. Textures, transparency, materials, reflectance,
particle/trail/beam/fire/smoke/sparkle Enabled and CastShadow return to their
captured values, including false, empty and zero originals.

A generation token invalidates paused scans on OFF, refresh and re-enable.
DescendantAdded is subscribed before the initial scan. OFF disconnects it before
restoration; a previous worker cannot wake into a new active session and change
old-scene objects. No textures/emitters are destroyed as an optimization. This
restores changes owned by Improve FPS, not unrelated game/module edits; an
instance destroyed by the game cannot be resurrected.

## Validation

- Full mock boot asserts every requested name, category and display order;
  absence of removed modules/Fun; RShift; unbound module shortcuts; separate
  MM2 Calibration. Weapon Visuals and Freeze toggle probes remain.
- Freeze tests retain UGC coverage and add mode migration, independent boxes,
  walking through jump, no repeated Play/seek, mode switch, recapture after root
  change, original anchored restoration and cleanup.
- New Improve FPS test executes the whole module with a coroutine paused after
  250 descendants, OFF/ON races, option refresh, detached meshes/particles,
  new descendants and exact original-value checks after OFF/destroy.
- Fly regression now asserts NO PlatformStand option or ownership in any tested
  transition, while retaining method/float, WalkSpeed and cleanup coverage.
- Learning evidence tests were removed with the deleted feature; MM2 visibility,
  migration, telemetry, prediction and cosmetics tests remain.

These are source compilation and deterministic mock tests, not an in-game visual
or engine-permissions certification.
