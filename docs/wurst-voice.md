# Wurst's own words

Source: `assets/wurst/translations/en_us.json` at Wurst7
`4a22e53d774b9a28e395874834f099e779685998`. 158 hack descriptions, 177
setting descriptions, written in one voice over eleven years.

This is a naming and tone reference for the people rewriting our
tooltips (agent D). It is not a phrasebook. Their sentences are about
Minecraft. A tooltip that mentions bedrock, ores, elytra or NoCheat+
in a Roblox menu is worse than a plain one. Copy the *shape* of a
sentence, never the Minecraft in it.

## How a hack is named

Wurst concatenates. The ClickGUI says `KillAura`, `PlayerESP`,
`HighJump`, `SafeWalk`, `NoFall`, `AntiAFK`, `X-Ray`. Two exceptions
keep a separator because the words smash: `X-Ray`, `TP-Aura`.

Our cards are spaced Title Case (`Kill Aura`, `Player ESP`, `High
Jump`). That is the 5% Roblox in the layout and it stays. Do not
rename a card to match Wurst's concatenation. Do match the *words*:
we already say Fly where they say Flight, Speed where they say
SpeedHack, TriggerBot where they say TriggerBot.

A hack name is a thing you do, not a description of a thing you do.
`Flight`, not `AllowsFlight`. `Fullbright`, not `SeeInTheDark`.

## How a setting is named

Settings are Title Case with every content word capitalised, including
short ones: `Field Of View`, `Check Line Of Sight`, `Horizontal Speed`.
Toggle labels are the effect, not a question: `Team check` on our side
is the same idea as their `Check Line Of Sight` — a noun phrase, no
`Enable …`, no trailing `?`.

A setting description talks about the control, often restating the
hack so the row still makes sense if you read it alone:

> Determines how far AnchorAura will reach to place, charge and
> detonate anchors.

Toggles get a when-enabled / when-disabled pair when both states do
something different. A slider description is the quantity, not the
widget.

## How a description is written

The first sentence *is* the tooltip. Median eight words, forty-four
characters. It starts with a verb:

| Verb | Use |
|---|---|
| Allows you to … | you could not do this before |
| Automatically … | it acts without a click |
| Prevents / Protects you from … | it stops a thing happening to you |
| Makes you … | it changes how you move |
| Highlights / Shows … | it draws |
| Blocks / Disables / Removes … | it takes a vanilla effect away |
| Helps you … | it assists, it does not replace you |

Examples of the shape, Minecraft stripped out:

- “Automatically attacks entities around you.”
- “Allows you to fly.”
- “Prevents you from falling off edges.”
- “Highlights nearby players.”
- “Protects you from fall damage.”
- “Allows you to see in the dark.”

A second sentence is optional and does one of three jobs: a
constraint (“A block must fall on your head to activate it.”), a
pointer to a sister hack (“Tip: This works with Killaura.”), or a
joke. The jokes are named (`Jesus`, `MileyCyrus`, `Derp`) and they
are part of what the client *is* — they are not a licence to put a
pun on Speed.

Do not start with “This module …” or “This hack …”. The card already
has the name.

## When a description warns rather than explains

A warning is its own paragraph, after a blank line, prefixed
`WARNING:`. Wurst uses it when the hack can hurt you, get you
detected, or throw something away — not when the hack is merely
strong.

Recurring pattern: every flight-like hack that still lets you hit the
ground (`Flight`, `HighJump`, `Glide`, `Jetpack`, `CreativeFlight`)
ends with “You will take fall damage if you don't use NoFall.” That
is the voice for a sibling dependency: name the other card, say what
happens without it.

Other warnings in the file: ClickAura looks more suspicious than
Killaura; Noclip damages you inside blocks; AntiHunger has been
reported to add fall damage; throwing a trident with Yeet Mode on
can lose the trident. The trigger is “this can go wrong in a way the
name does not say”. Detection notes belong here, not in the first
sentence.

Do not import their anti-cheat names (NoCheat+, Paper, Vanilla). A
Roblox warning names the thing that actually happens here: you fall,
the shot misses, the remote does not exist.

## Sentence length and capitalisation, compressed

- First sentence: one clause, present tense, second person (“you”).
- Hack IDs: concatenated PascalCase. Display with us: spaced.
- Settings: Title Case labels, sentence-case descriptions.
- American spelling in their file (`Color`, `Armor`). We already
  write `Colour` in the widgets; do not flip the whole menu to match.
- `FOV` expands to `Field Of View` in a label, stays `FOV` in a
  short readout.

## Counterpart table

Only hacks that have a counterpart in *this* menu. Wurst has 158; we
have 45 universal cards plus the per-game ones. A blank Wurst column
means there is no counterpart — write a plain tooltip, do not invent
one from a neighbour.

| Our card | Wurst | Wurst's first sentence | Do not import |
|---|---|---|---|
| Kill Aura | Killaura | Automatically attacks entities around you. | MultiAura / ClickAura / TP-Aura are other cards. ClickAura's “looks suspicious” warning is about click-to-attack, not about us. |
| TriggerBot | TriggerBot | Automatically attacks the entity you're looking at. | |
| Auto Clicker | — | | ClickAura is not an auto clicker. |
| Hitboxes | — | | Reach is reach distance, not part size. |
| Projectile Calibration | Trajectories | Predicts the flight path of arrows and throwable items. | Arrows, bows, crossbows. |
| Player ESP | PlayerESP | Highlights nearby players. | “ESP boxes of friends will appear in blue” is their friend colour, not a role. |
| Item Render | ItemESP | Highlights nearby items. | |
| X-Ray | X-Ray | Allows you to see ores through walls. | Ores. |
| Fullbright | Fullbright | Allows you to see in the dark. | |
| FOV | — | | CameraDistance is third-person distance. |
| Zoom Unlocker | Zoom (keybind) | | A key, not a hack description. |
| Fly | Flight | Allows you to fly. | The NoFall warning is the right *shape* for a sibling dependency. |
| Speed | SpeedHack | Allows you to run ~2.5x faster than you would by sprinting and jumping. | The 2.5×, the NoCheat+ patch note. |
| High Jump | HighJump | Allows you to jump higher. | Same NoFall warning as Flight. |
| Jump Power | HighJump | (same hack) | We split jump height from jump power; they did not. |
| Infinite Jump | — | | BunnyHop jumps for you. That is not infinite jump. |
| Noclip | Noclip | Allows you to freely move through blocks. | Sand falling on your head; damage inside blocks. |
| Spider | Spider | Allows you to climb up walls like a spider. | |
| Phase Dash | — | | |
| Click Teleport | — | | |
| Vehicle Speed | BoatFly | Allows you to fly with boats and other vehicles. | Related, not the same module. BoatFly is flight; ours is speed. |
| Freeze Movements | — | | Blink suspends *packets*, not the character. |
| No Fall | NoFall | Protects you from fall damage. | Elytra / mace pauses. |
| Safe Walk | SafeWalk | Prevents you from falling off edges. | Parkour is the opposite (jumps at the edge). |
| Anti-Void | — | | |
| Anti-Fling | AntiKnockback, AntiEntityPush | Prevents you from taking knockback / getting pushed. | Closest pair, not a fling-specific hack. |
| Anti-AFK | AntiAFK | Walks around randomly to hide you from AFK detectors. | Pathfinding AI, wait-time randomisation. |
| Gravity | — | | Timer changes the world's step rate. |
| Fling | — | | Throw uses an item many times. |
| Lag Switch | Blink | Suspends all motion updates while enabled. | Related, not identical. |
| Improve FPS | — | | |
| Interact Extender | Reach | Allows you to reach further. | |
| Rejoin Server | AutoReconnect | Automatically reconnects when you get kicked from the server. | Related: they rejoin on kick, we rejoin on demand. |
| Remote Logger | — | | |
| Friend List | — | | PlayerESP mentions friends; NameProtect hides names. Neither is a list. |
| Disguise | — | | NameProtect hides names. It does not wear someone else's avatar. |
| Animation Changer | — | | Derp / Tired / HeadRoll / MileyCyrus are jokes. Do not copy them onto a serious card. |
| Emote Player | — | | |

Game modules that have a Wurst cousin: BedFight's Scaffold is
ScaffoldWalk (“Automatically places blocks below your feet.”). MM2's
Sprint is AutoSprint (“Makes you sprint automatically.”) only in the
name — theirs is always-on, ours is a hold key.

## What this file is not

It is not a rewrite of our tooltips. D does that, card by card, using
the first-sentence shape and the warning rule, against the actual
behaviour of the Roblox module. If a Wurst sentence names a Minecraft
block, a mob, a server plugin or a keybind we do not have, leave it
in this file.
