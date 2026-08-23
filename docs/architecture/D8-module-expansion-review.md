# D8 module expansion review

## Scope and authority

Reviewed Chams, Arrows, NPCESP, WallHop and SpinBot against Roblox engine behavior and the VapeV4 universal reference in `reference/vape-v4-universal.lua.txt`. The implementations remain original and use this project's Framework, Entity and Render lifecycles.

The universal inventory remains 43 modules.

## Chams ownership

**Decision: the standalone Chams card is the only owner of player Highlights.**

PlayerESP no longer has a Chams dropdown and no longer calls `DrawingSet:Highlight`. This avoids two Highlights, two target policies and two teardown paths for one character.

Compatibility migration:

- old key: `Universal.PlayerESP.Chams` (`Off`, `Overlay`, `Outline`);
- new card: `Universal.Chams`;
- when the old value is `Overlay` or `Outline` and the new card has never been configured, Chams enables the new card;
- `Outline` seeds `Universal.Chams.Filltransparency` to `1`;
- the old key is retained so an older build can still read the profile;
- an explicitly configured standalone Chams card always wins.

This is a one-way compatibility read, not a permanent cross-module runtime dependency.

## Behavior review

### Chams

VapeV4 owns one visual object per entity and supports Highlight or adornment modes. This port keeps Roblox `Highlight`, the safer engine primitive, and omits the extra adornment mode.

Policy:

- live player characters only;
- local player excluded by Entity;
- teammates excluded unless `Teammates` is enabled;
- Friend List protection always wins;
- respawn changes the existing Highlight's `Adornee`;
- death, removal, disable and destroy delete the Highlight.

All six options change a Highlight property or target inclusion. No option was added.

### Arrows

VapeV4 shows arrows only for off-screen entities. The port now follows the same rule without allocating a render set for an on-screen player.

Policy:

- live players with a root part only;
- friends excluded;
- teammates excluded unless enabled;
- maximum distance enforced before drawing;
- on-screen, dead, removed or newly protected players release their render set;
- a missing camera clears drawings without leaving the enabled layer permanently hidden;
- disable and destroy release the layer pool.

The four existing options remain behavior-bearing.

### NPCESP

VapeV4 routes NPCs through its entity library. This project keeps NPC discovery separate because the shared Entity service is intentionally player-only.

Classification requires a Humanoid parented to a workspace Model with no matching Player character. The local character is rejected explicitly. Discovery is now signal-driven through `DescendantAdded` and `DescendantRemoving`, with one initial scan; the old 0.75-second polling window is gone.

Dead or distant NPCs keep a pooled but hidden set. Streamed-out or reclassified player models release it. Disable and destroy release all sets, Highlights and signal connections.

The seven existing options remain behavior-bearing.

### WallHop

WallHop has no direct VapeV4 universal counterpart in the checked reference. Roblox semantics were reviewed directly:

- one filtered `JumpRequest` connection while enabled;
- one forward raycast excluding the local character;
- `RespectCanCollide` and a near-vertical normal gate;
- outward impulse follows the hit normal;
- existing horizontal and upward velocity are preserved where stronger;
- current character parts are resolved per request, so respawn needs no stale character listener;
- disable and destroy disconnect the jump callback.

The delayed status callback was removed. It changed no movement behavior and could outlive the session. Height, Push, Reach and Cooldown each change the hop.

### SpinBot

VapeV4 offers CFrame, rotational velocity and BodyMover modes with independent axes. This port keeps two engine-backed modes and one selected axis:

- `CFrame`: applies a frame-rate-independent incremental rotation;
- `Velocity`: writes `AssemblyAngularVelocity` in radians per second;
- `Axis`: selects X, Y or Z without three redundant toggles.

The speculative/deprecated BodyMover mode is intentionally absent.

SpinBot captures each character root separately. On death, replacement, disable or destroy it restores `AssemblyAngularVelocity` and `Humanoid.AutoRotate`. CFrame orientation is restored only if CFrame mode actually touched it, preserving current position. A replaced character cannot leave the old root spinning.

## Focused proof

`tools/test/suites/new-modules.luau` now covers:

- old PlayerESP Chams config migration;
- single Chams ownership, teammate filtering, death and disable cleanup;
- Arrows off-screen policy, team policy, death and render-pool cleanup;
- NPC classification, streamed descendants, death hiding and streamed-out cleanup;
- WallHop velocity behavior and jump-connection teardown;
- SpinBot angular velocity, AutoRotate, death and disable restoration.

PlayerESP's focused suite asserts that it creates no Highlight.

## Field-test debt

### WallHop

Needs live testing against:

- sloped MeshParts and UnionOperation collision normals;
- moving or unanchored walls;
- games that replace `AssemblyLinearVelocity` after Humanoid state changes;
- high-latency character ownership changes;
- touch JumpRequest repeat cadence.

No extra mode should be added until a reproducible engine failure identifies one.

### SpinBot

Needs live testing against:

- server-owned assemblies and games that clamp angular velocity;
- seated characters and vehicle welds;
- first-person camera controllers;
- ragdoll systems that replace the Humanoid or root during a frame;
- anti-cheat systems that distinguish CFrame from physics rotation.

The two current modes are sufficient for field testing. Body movers or additional rotation modes should not be added speculatively.
