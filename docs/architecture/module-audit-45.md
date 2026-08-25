# Module audit — current 45-card inventory

## Automated coverage

The ClickGUI boot suite loads every manifest card, opens and reopens each
settings window, preserves enabled state and conditional rows, toggles every
safe toggle twice, and compares task/connection counts after teardown. The
focused suites cover combat, movement, protection, visuals, spoof, utility,
NPC policy and analytics.

The inventory remains the authority in `tools/inventory_snapshot.json`; this
file records the audit scope, not a second list of cards.

## Changes in this pass

- Category bodies now use alphabetic `LayoutOrder` by visible card name. Module
  download order remains a dependency order and is no longer the display order.
- `Anti-Fling`, `Fling` and `Lag Switch` resolve to `Other` in the module,
  manifest, fallback and category documentation.
- Kill Aura has an explicit `Legit`/`Blatant` targeting choice. Legit keeps a
  forward cone; Blatant removes the cone and scans the configured reach without
  requiring a cursor lock. Both modes retain range, wall, team/friend, rate,
  rotation and contact-damage policy.
- Entity indexing keeps player visuals player-only and offers an opt-in,
  signal-indexed `NPCList` to TriggerBot, Aim Assist, Kill Aura and existing
  Hitboxes behavior.
- Team policy normalizes Roblox Team instances, player/NPC attributes, Faction
  values, Team children and common color values. Missing NPC team metadata stays
  neutral and visible instead of being incorrectly treated as a teammate.
- NPCESP now has its own Team check and uses the shared policy.
- Aim Assist exposes `Aim Assist` and `Aimbot` modes. The first respects its
  cursor FOV and smoothing control; the second uses a zero-smoothing lock over
  valid characters, with an explicit `Sticky target` release control, and can
  opt into NPCs. It still only changes the local camera.

## Remaining field debt

Automated Roblox mocks cannot prove every game's server and physics behavior.
The following still need field testing:

- WallHop against sloped, moving and server-owned walls;
- SpinBot while seated, ragdolled, vehicle-welded or server-owned;
- NPC team conventions that do not expose Team, Faction or a documented
  attribute;
- game weapons whose server validates an activation distance or requires a
  place-specific adapter;
- the existing MVSD-specific legacy aim path, which is not generalized by this
  pass.

A field failure must become a named game adapter or an honest unsupported state;
it must not be patched with a global hook or a remote-spoofing fallback.
