# D options audit — Wurst 7.19

Authority: `Wurst-Imperium/Wurst7` at `4a22e53d774b9a28e395874834f099e779685998`.
Settings were compared against the Java declaration order, not the wiki. “Adapted” means the same purpose needs Roblox-specific controls; no Minecraft-only row was added.

| Module | Wurst Java | Kept / renamed / removed / reordered |
|---|---|---|
| Killaura | `KillauraHack.java` | Kept Roblox weapon/target/contact controls. Removed presentation-only **Show advanced** and the private pixel-built **Show target** panel; target count remains in HackList status. No Java-only SwingHand/container/entity-filter rows added. |
| TriggerBot | `TriggerBotHack.java` | Kept Roblox activation, reaction, target-part, range/team/wall controls. No Minecraft blocking/mouse simulation rows added. |
| Auto Clicker | — | Roblox-only; kept one CPS range, activation, click target and capture controls. |
| Hitboxes | — | Roblox-only; kept part/expand/filter/reveal/collision controls. |
| Projectile Calibration | `TrajectoriesHack.java` | Adapted analytics rather than trajectory colours; kept existing analysis controls and actions. |
| PlayerESP | `PlayerEspHack.java` | Adapted: kept Roblox boxes, rigs, names, health, tracers, chams, roles and filters. No sleeping/invisible Minecraft filters added. |
| ItemESP | `ItemEspHack.java` | Adapted object registry; kept object list, capture, distance/outline/text/colour. |
| X-Ray | `XRayHack.java` | Adapted fixed local geometry fade; no ore list, exposed-only or opacity rows added. |
| Fullbright | `FullbrightHack.java` | Adapted Lighting path; kept Brightness and Clock time. No Gamma/Night Vision/Fade rows added. |
| FOV | — | Roblox-only; kept one Field of view value. |
| Zoom | — (`Zoom` keybind feature) | Adapted Roblox camera distance; kept max/min/unlock-first-person. |
| Flight | `FlightHack.java` | Adapted movement engines. Removed presentation-only **Advanced settings** and its gates; kept real method/float/speed/safety/internal-control rows. No anti-kick Minecraft rows added. |
| SpeedHack | `SpeedHackHack.java` | Adapted multi-engine Roblox movement; kept one numeric Speed plus mode/safety controls. |
| HighJump | `HighJumpHack.java` | Adapted Height to Roblox jump velocity; kept one value. |
| Jump Power | `HighJumpHack.java` | Roblox split of HighJump; kept one Power value. |
| Infinite Jump | — | Roblox-only; kept mode and mode-owned power/rise/interval controls. |
| Noclip | `NoclipHack.java` | Exact setting surface: no options. |
| Spider | `SpiderHack.java` | Adapted Roblox engines; kept mode/speed/climb-state. |
| Phase Dash | — | Roblox-only; kept mode-owned dash controls. |
| Click Teleport | — | Roblox-only; kept destination and travel controls/actions. |
| Vehicle Speed | `BoatFlyHack.java` (related only) | Roblox-only speed adaptation; kept four routes, multiplier and motor torque. |
| Freeze Movements | `BlinkHack.java` (related only) | Roblox-only local freeze; kept one mode. |
| NoFall | `NoFallHack.java` | Adapted Roblox impact/state model; kept mode, safe speed, record reset and scan. No Elytra/mace rows added. |
| SafeWalk | `SafeWalkHack.java` | Adapted edge look-ahead; no Minecraft sneak toggle added. |
| Anti-Void | — | Roblox-only; no options. |
| Anti-Fling | `AntiKnockbackHack.java` / `AntiEntityPushHack.java` | Adapted fling guard; kept one velocity threshold. |
| AntiAFK | `AntiAfkHack.java` | Adapted to Roblox Idle response; no AI/path/range/wait rows added. |
| Gravity | — | Roblox-only; kept one gravity value. |
| Fling | — | Roblox-only action; kept target/duration/power/return. |
| Lag Switch | `BlinkHack.java` (related) | Adapted incoming replication lag; kept one value. |
| Improve FPS | — | Roblox-only; kept four reversible optimisations. |
| Interact Extender | `ReachHack.java` | Adapted prompts/click detectors; kept distance and target-kind toggles. |
| Rejoin Server | `AutoReconnectHack.java` (related) | Wurst Options action; no module settings row. |
| Remote Logger | — | Roblox-only; kept capture filter/limit/resampling and output actions. |
| Friend List | — | Roblox-only shared protection; kept names/friend/team controls and actions. |
| Disguise | — | Roblox-only; kept user/apply/respawn/animation/emote controls. |
| Animation Changer | — | Roblox-only; kept pack search/apply/reset controls. |
| Emote Player | — | Roblox-only; kept source/search/playback/actions. |

## Result

- 38 modules before and after.
- No options added.
- Removed three presentation rows: `Killaura.Show advanced`, `Killaura.Show target`, `Flight.Advanced settings`.
- Existing module `configKey`s are unchanged.
- All remaining rows correspond to observable Roblox behaviour or a canonical action.
