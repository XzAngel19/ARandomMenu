# D7 module-state migration

## Result

The universal module boundary no longer exposes shell state.

- Before: 26 direct `host.state` references across 20 universal module files.
- After: 0 direct `host.state` references under `src/modules/**`.
- Inventory: 38 modules before and after.
- Visible behavior and config keys: unchanged.

`tools/check_module_conformance.py` now rejects a new direct `host.state` reference.

## Values returned to their owner

These values no longer live on the shell state table:

- Infinite Jump enabled state and jump rate-limit timestamp;
- Fullbright settings, captured Lighting baseline and toggle callback;
- Improve FPS toggle callback and visual cache ownership;
- Remote Logger entries/report callbacks;
- Projectile Calibration tuning alias;
- FOV and PlatformStand owner maps and captured baselines;
- Friend List data;
- Disguise description and emote catalog;
- fling activity state.

The matching obsolete declarations were removed from `state.d.luau`. Remote Logger's test inspection stays on the module export instead of becoming runtime state.

## Context services

The runtime now supplies `context.services`, documented and typed in `src/core/Framework.luau`:

- `movementInput`
- `aim`
- `menu`
- `mobileActions`
- `protectedTargets`
- `fovOwnership`
- `platformStandOwnership`
- `activity`
- `spoofAvatar`
- `projectileCalibration`
- `gameBridge`
- `shortcuts`
- `registries`

The first seven are the architecture-pass contracts requested by D7. The remaining groups replace existing real cross-module contracts: Spoof catalog sharing, calibration teardown, game roles, activation binding, and Wurst registration. None expose a generic get/set state field.

`OwnershipService` keeps a baseline per live instance, gives the last owner priority and restores every baseline when its final owner leaves.

## Callers migrated outside universal modules

- `src/library/Entity.luau` uses aim and protected-target services.
- MM2, BedFight and TRS use `Runtime.Services.protectedTargets`.
- MM2's intentional-fling wait uses `Runtime.Services.activity`.
- Game-module Runtime now receives `Services` beside the legacy `State` bridge.

## Remaining compatibility bridges

These are outside the universal module contract and remain intentionally:

1. `Framework`, Cards, Widgets and shell-owned libraries still receive `host.state` for GUI registries and layout internals. Owner: shell/integrator. Remove when each library gets a renderer or registry context; universal modules must not wait on this migration.
2. Game modules still receive `Runtime.State` for their large, game-specific registries and teardown hooks. Owner: each game module. Remove per game after its cards and runtime registries are moved to a game-context type. Cross-game target and activity reads have already left this bridge.
3. `registries` reads the existing Wurst Options and module-search registries from the shell. Owner: Framework/settings integration. Remove the compatibility lookup when both registries are constructed directly on `ModuleServices` before Framework initialization.

There is no allowlisted direct state access under `src/modules/**`; the conformance allowlist is intentionally empty.

## Proof

Focused suites now build the same service surface as runtime and assert:

- target protection through `protectedTargets`;
- shared fling activity through `activity`;
- Disguise-to-Emote Player catalog sharing through `spoofAvatar`;
- Remote Logger inspection without shell state;
- existing FOV, Fly, Infinite Jump, Item Render, TriggerBot and teardown behavior.

The full validation run is the release gate.
