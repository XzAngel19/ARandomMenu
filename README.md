# ARandomMenu

Standalone strict-Luau menu with a remote, PlaceId-driven game-module runtime.

## Runtime architecture

- **Which branch runs in game.** The loader and the bootstrap both point at
  `main`, and the bootstrap downloads its per-game modules from `main` too, so
  an injected menu always runs main's code — work reviewed on a branch looks
  unchanged in game until it is merged. Set `ARANDOMMENU_BRANCH` before loading
  to point the whole runtime (loader, bootstrap and game modules) at a branch:

  ```lua
  getgenv().ARANDOMMENU_BRANCH = "arena/01a01c6e-arandommenu"
  loadstring(game:HttpGet(
      "https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/"
          .. getgenv().ARANDOMMENU_BRANCH .. "/ARandomMenu.luau"))()
  ```

  It defaults to `main`, and the loader still falls back to main and then to
  the known-good snapshot if the branch fails to download.
- `loadstring` downloads the current `ARandomMenu.luau` bootstrap.
- Loader v3 rejects the stale `0/0` runtime, retries a known-good immutable
  snapshot when GitHub's branch CDN has not propagated, and never runs an
  outdated local fallback.
- `ARandomMenu.luau` creates the shared responsive UI, component factory,
  notifications, state and the single-heartbeat `TaskManager`.
- The bootstrap reads `game.PlaceId` and downloads the named game module from
  the repository raw URL. MM2, TRS and VD resolve to their named modules.
- Failed or invalid HTTP responses are logged and may fall back to
  `readfile("ARandomMenu/src/games/<Name>.luau")` when available.
- A game module must return a `Module` table exporting `init(Runtime)`,
  `destroy()`, `Events`, `Name` and `PlaceId`.
- `Runtime.Menu` exposes the live GUI, pages and component API. The module calls
  those shared factories to inject its controls and callbacks into the menu.
- Imported per-frame callbacks use `Runtime.TaskManager`; they are multiplexed
  through one `RunService.Heartbeat` connection and remain alive until cleanup.
- Registered sections initialize asynchronously after the GUI shell appears;
  a staged loading curtain reports progress until they are ready, and opening a
  tab is never used as the condition for constructing content.
- The loading intro is a scripted sequence rather than a spinner that vanishes
  on the last callback: a drifting backdrop glow, the wordmark rising into
  place, a hairline rule drawing out beneath it, then counter-rotating rings
  over a narrated status line and progress bar, and finally a held "Ready"
  before the curtain lifts. Roughly 1.1 s of animation runs before any
  narration, so the intro reads as an intro even when every module loads
  instantly, and a slow load simply keeps the status stage on screen for
  longer — nothing here ever delays a slow load further. The narration yields
  the moment the loader has real `x/y` counts to display, a watchdog lifts the
  curtain if the sequence thread ever dies, and a failed bootstrap keeps the
  curtain up so its error message stays readable.
- **The shell is fixed.** It is anchored at its own centre
  (`AnchorPoint = (0.5, 0.5)`, `Position = fromScale(0.5, 0.5)`) and can never
  be moved: there is no drag strip, no pointer bookkeeping and no persisted
  window geometry. Any `ui.windowPosition` written by an older build is
  dropped when the configuration loads, and a viewport change simply
  re-centres and re-sizes the shell. What *is* movable are the floating tool
  windows (favourites, the overlay manager, the per-overlay settings) and the
  HUD overlays, which keep their own drag handlers and their own saved
  positions in `ui.floatingPositions`.
- The shell itself is a compact, borderless, dark-glass surface: a navigation
  rail, a page header (page name + search) and a scrolling card board. It is
  the only visual theme, so every injection opens the same coherent interface.
- **One window, not a stack of rectangles.** `Main` *is* the shell: the second
  full-size rounded frame that used to sit inside it (painted the same colour,
  with its own radius to keep in sync) and the readability wash that painted
  the background colour over the background are both gone. The navigation rail
  is rounded on the window side and squared off on the content side, because
  `ClipsDescendants` clips to the window's rectangle and not to its rounded
  corner — a square rail filled those corners and read as a block sticking out
  behind the ARM chip. Inside a card, the options panel is a transparent
  container instead of a third surface: an expanded module shows the card and
  its rows, with nothing drawn in between.
- **No faked shadow.** An ambient shadow used to be approximated with stacked
  rounded frames behind the window. `cornerRadius()` caps every radius at
  30 px, so a frame 44 px wider than the shell kept square-ish corners around
  a tightly rounded window and rendered as four grey blocks poking out of the
  corners — the menu looked chipped. A convincing soft shadow needs a 9-slice
  image asset and this runtime downloads none, so the shell has no shadow at
  all. Every full-size surface inside the window (shell, readability layer)
  now also carries the window radius, because `ClipsDescendants` clips to the
  rectangle and not to the rounded corner.
- The interface is deliberately neutral: a single monochrome palette built from
  near-black surfaces, grey outlines and one off-white accent, defined once in
  the `Theme` table. There is no decorative background art, mascot or branded
  watermark, and status colours are reserved for gameplay data (roles, health,
  failures) rather than menu chrome.
- **Design tokens.** `UI_RADIUS` and `UI_MOTION` sit at file scope and are the
  only place radii and animation durations (~0.16 s) are declared. Every square-ish surface still rounds its corners
  through the one `cornerRadius()` helper, so the shell, the tool windows and
  every card share a single, deliberately tight silhouette. Genuine pills and
  circles (switch tracks, knobs, progress bars, radar, blips) keep using
  `UDim.new(1, 0)` and are untouched by the helper.
- **Responsive metrics.** `computeLayoutMetrics(viewport, touch)` returns one
  table — sidebar width, row and control heights, corner radius, card columns,
  touch target size, font sizes, paddings — and `state.layout` is the single
  source of truth for every size in the interface. Three real modes rather
  than one scale factor:
  - *Mobile* (`width < 620` or `height < 430`, so a phone in landscape
    counts): near-fullscreen shell, rail collapsed to monogram chips, finger
    sized controls.
  - *Tablet* (`width < 1100`): reduced rail, one column unless the content
    area is wide.
  - *Desktop*: full rail with labels, two columns whenever the content area
    reaches 560 px, more air between controls.
  Anything that has to react registers through `state.onLayout(listener)`;
  `state.refreshLayout()` recomputes on every viewport change and re-flows the
  rail, header, search, cards, columns, floating windows and the centred
  shell. Game modules never touch it — the shared card and option factories
  size themselves from the table, so a module written once renders correctly
  on every device. `tools/layout-preview.html` renders the same formulas in a
  browser for 360×800, 800×360, 768×1024, 1280×720 and 1920×1080.
- **HUD overlays are chrome-less.** Radar, Target Info, Session Info and the
  Text GUI render their content and nothing else: no panel, no header, no
  close button, so the radar is exactly the circle and the read-outs are bare
  text with their own shadow. They remain movable — the content is the drag
  handle — but they only become an input surface while the menu is open, so a
  transparent overlay can never swallow a click meant for the game, and a
  faint outline appears around them while the menu is open to show they can be
  grabbed. The framed tool windows (favourites, overlay manager, overlay
  settings) keep their compact header and close button.
- Modules are filed under categories (Movement, Combat, Visuals, Protection,
  Utility, and a `General` catch-all that always sorts last). "Player" used to
  hold everything that moved the character, which made it a second General; it
  is **Movement** now. Combat holds only what helps you fight, so **Fling** —
  which does not help you fight, it throws another player around — sits with
  the other one-shot tools in Utility. Every shipped module is filed: nothing
  falls through to `General` and sorted
  alphabetically inside each one. A card publishes its category and sort name
  as attributes; the card grid materialises one **section** per category —
  a header strip plus one or two columns — writes every `LayoutOrder`
  explicitly so the layout never has to break a tie, and hides a section whose
  cards the active search filtered away. Cards are balanced across the columns
  by measured height, so one expanded card cannot leave a column half empty,
  and a category header always spans the full width of its own section, which
  is what lets headers and two-column boards coexist. New cards land in an
  intake column and are redistributed on the next frame, so bootstrap stays
  O(n) instead of re-sorting on every creation.
- Module customisation panels are made of self-contained rows: each setting is
  its own rounded card with a hairline border, a hover highlight and a control
  aligned to a shared right-hand band. Rows are one line — the explanatory
  sentence modules used to pass ("Balanced glides, Direct stops instantly…")
  is ignored by `createOptionRow`, which fixes Fly, Fling, Speed, Hitboxes and
  every game-module panel at once without touching a single call site. Every row in every module shares the same geometry —
  labels end at 48% of the row, controls occupy the exact same 50%→edge
  rectangle whether they are switches, sliders, key slots, text boxes or
  action pairs — so panels with and without keybinds look symmetric. Cycle
  buttons carry an `n/total` counter, numeric fields advertise their accepted
  interval as placeholder text, and long panels can be broken up with section
  headings that fold away together with the controls they label. Fly is the
  reference layout.
- **Device-independent input.** Modules never read WASD, Space or a mouse
  position directly — a phone has none of them, which is precisely why Fly,
  Infinite Jump and CTRL+Click Teleport did nothing on touch. Three shared
  helpers answer the questions a module actually has:
  - `state.getMoveInput()` — steering, read from Roblox's own control module,
    so keyboard, thumbstick and gamepad all work *and* it keeps answering while
    `PlatformStand` is on (which is when `Humanoid.MoveDirection` goes silent
    and flying on a phone froze the character).
  - `state.isJumpHeld()` / `state.onJumpRequest()` — jump from a key, a gamepad
    button or the touch jump button, via `JumpRequest`.
  - `state.getAimRay()` — the mouse on desktop, the centre of the screen on
    touch, because a finger is not a cursor.
  Fly steers through the first, Infinite Jump (including Rise) through the
  second, and **Click Teleport** — renamed, since CTRL+click is only the
  desktop half — through the third: its key slot teleports to whatever is being
  aimed at on any device, and on touch that slot places the button that
  triggers it.
- **Module kinds.** A card's behaviour comes from one declared kind instead of
  a pile of independent booleans, so a new module cannot accidentally inherit
  the wrong keybind semantics:
  - `toggle` (default) — enable/disable state; a click or the key flips it and
    it announces the change.
  - `action` — a button (High Jump, Rejoin, the Fling actions). A click or the
    key runs it once; there is no state to get out of sync. `silentAction`
    suppresses the toast for keys meant to be spammed.
  - `hold` — an always-on system whose effect only applies while its key (or
    its placed mobile button) is held, like a dead-man switch. It can never be
    switched off, never toasts, and clicking the card does nothing so a stray
    click cannot latch the effect. Sprint is the reference implementation:
    `kind = "hold"` plus an `onHold(active)` callback.
  - `group` — an always-on container of options (Knife, FriendList, Teleport…).
    The card expands, and its key slot is deliberately inert: there is nothing
    to activate, so it never captures a key, never places a mobile button and
    does nothing when pressed.
  The legacy `action` / `category` / `holdAction` flags still map onto these
  kinds, and always-on kinds start their runtime once at creation instead of
  waiting for a click that can never come.
- **One keybind per module, always in the card header.** Activation keys are
  no longer buried in the options panel (Phase Dash's "Dash key", MM2's
  "Manual key"…): the header key slot *is* the binding, it starts blank
  instead of reading "KEY", and one shared registry with a single input
  handler dispatches every binding — which is what makes releases reliable.
  Slots come in two shapes:
  - *tap* — the module toggles or the action runs.
  - *hold* — the module is live only while the key is down (Sprint, Fly up and
    down, Speed's sprint), and losing window focus always releases it.
- **Touch parity.** On a phone the same slot is the mobile-button factory: one
  tap opens placement mode (it used to need an undocumented 0.6 s hold), the
  button is dropped anywhere on screen, and it drives the same press/release
  pair — so hold features work with a finger, not just with a keyboard. The
  placed button reads the binding live, so a module that re-points its key
  later re-points the on-screen button too. The three-dot expander is drawn
  on *every* card, including modules with nothing to configure (Anti-AFK,
  Anti-Void, X-Ray): those simply never open — the dots are dimmed and the
  click is ignored, checked at click time because options can be added after a
  card is built.
- **Fling** was rewritten. It reported "stopped after the 5 second safety
  limit" the instant it was triggered: the loop guarded on
  `targetPlayer.Parent == Players`, but `Players` is a `cloneref` handle that
  never compares equal to the service `Parent` returns, so the body never ran.
  It now tests for an actual parent, re-reads the local character every
  iteration (a respawn cannot strand it), alternates `Stepped`/`Heartbeat` so
  the velocity replicates, always restores position, camera and `AutoRotate`,
  and exposes **Duration**, **Power** and **Return to start** instead of
  hiding the timeout in a constant. The same `cloneref` comparison was fixed in
  MM2's shot-confirmation check, where it confirmed every hit including misses.
- **Improve FPS** is a Universal module: stripping textures, particles,
  shadows and materials has nothing to do with Murder Mystery 2 and every game
  benefits. Each change is cached and restored exactly when it is switched off.
- **High Jump** is a one-shot action rather than a state: holding it "enabled"
  made no sense for a feature whose whole job is "press this and jump high".
  It fires from the card, from its key slot or from a placed mobile shortcut,
  and opts out of the per-activation toast so a hotkey can be spammed.
- The reusable `gui.lua` owns its image catalog, executor-safe asset cache,
  settings, draggable shell, tabs and `createModule()` component API. Game
  modules only provide their controls and callbacks.
- Its asset cache verifies PNG/JPEG signatures, interface assets use the real
  files under `Assets`, and text scaling updates a creation-time registry
  instead of walking the complete GUI during every slider movement.
- The Settings page carries only rows that do something. "Menu key" is built
  for keyboards only; the "Mobile menu icon" row (which always read
  ON - REQUIRED and could not be changed) and the "Mobile action buttons"
  reset row are gone, and **Mobile action size** is an exact pixel value —
  type it or drag it — instead of a four-step preset cycle.
- Placed mobile buttons now actually fire their module. Every key slot handed
  the mobile layer a hold descriptor, so *every* placed button was treated as a
  hold button: it engaged on touch-down, and on release took the "stop holding"
  path that never runs the tap callback. Hold state is asked for at press time
  now, so taps tap and holds hold — and hold-to-remove is disabled for hold
  features, because keeping a finger on Sprint is how you sprint, not how you
  delete the button. Long names are kept in full and wrapped at a smaller size
  rather than clipped to six characters ("Infinite Jump", not "INFINI").
- Settings includes calibrated text scale, blur, interface motion,
  cache-busted **Reinject latest**, and an idempotent **Destruct** action
  that disables features and releases every tracked runtime connection. The
  key/action controls blend into the dark glass surface without image frames.
- Every settings row is a single line: its name, vertically centred, and its
  control. The explanatory second line each row used to carry is gone — it
  doubled the height of the page and the names already say what they do.
  `createSettingRow` still accepts the description argument so existing call
  sites keep working; it is simply never rendered.
- **Blur mode** and **Interface motion** have no switch and no ON/OFF caption:
  like a module card, the whole row is the button and the accent stripe plus
  the lit surface are the state.
- The search field keeps its clear button on the leading edge, so the text and
  the control never trade places as the query changes.
- Two scope bugs the teardown depended on were fixed along the way: the
  session-tracking flags and the `Died` connection were block locals that
  `cleanupRuntime` could not see (assigning them created globals and left the
  connection alive), and the per-overlay settings windows were listed by name
  from a scope where those names were `nil`, so they never closed with the
  menu. Both now go through the live registries on `state`.
- **Destruct** tears the runtime down step by step, each step inside its own
  `pcall`. It used to be one unprotected block, so a single failing step (a
  module cleanup, a stale connection, a toolkit that never finished
  initializing) aborted the rest of the teardown *and* the `ScreenGui:Destroy()`
  that followed it, leaving the menu on screen stuck on "REMOVING…". Failures
  are now logged and the teardown continues; the interface is always removed,
  including any leftover shell or blur left behind in `PlayerGui`/`Lighting`.
- **Blur mode** dims the game only while the menu is on screen. A single
  controller owns the `BlurEffect` and is defined next to the shared state, so
  every path that shows or hides the menu (toggle key, mobile button, mobile
  shortcut placement, destruct) goes through it. The effect is switched off —
  not merely resized to `0` — whenever the menu is hidden, so closing the menu
  can never leave the screen blurred.
- **Falling hail** drifts over the blur, from the top edge of the screen down
  past the bottom, on a full-screen layer below the menu window. It is driven
  entirely by the same blur controller through `state.registerBlurDecoration`,
  so it can never outlive the blur: closing the menu, disabling Blur mode or
  destructing all stop it, disconnect its `RenderStepped` loop and hide the
  layer. It also follows the Animations setting, since it is motion, and the
  per-frame step clamps its delta so a backgrounded client does not teleport
  every stone off screen at once.
- Shell dimensions are integer pixels taken from the responsive metrics rather
  than a scaled canvas, which keeps text and strokes crisp; the shell is then
  re-centred (never clamped) whenever the viewport changes.
- Runtime controls use native Builder Sans through `FontFace` for crisp text at
  small sizes. The cached Candy Fruits font is reserved for the large loading
  title, where a decorative OTF can render cleanly without softening controls.
- The permanent shell and tab pages are ordinary `Frame` instances rather than
  nested `CanvasGroup` textures, preventing Roblox from rasterizing interface
  text at a reduced intermediate resolution.
- Universal **Fly** splits flight into two independent engines instead of a
  preset that only changed a smoothing constant. *Method* decides how you move
  sideways — Velocity (direct velocity writes), Constraint (a LinearVelocity
  that survives games resetting velocity every step, and which also drives the
  vertical axis), Impulse (force-based, keeps collisions), CFrame (position
  writes, nothing for a speed cap to clamp), Blink (one hop per interval),
  Pulse (burst and coast) and WalkSpeed (the game's own movement). *Float*
  decides what holds you up — Velocity, Impulse, Hover (an altitude held with
  CFrame writes), Jump (the humanoid's own jump whenever it drops below that
  altitude), Bounce and Floor (an invisible anchored part kept under your
  feet). Horizontal/vertical speed, response, burst interval, wall check,
  PlatformStand, face-camera and the up/down keys stay configurable, grouped
  under Flight / Advanced headings.
  **Speed** provides Adaptive, Smooth, Boost, CFrame, Pulse and Teleport modes
  plus acceleration, burst interval, air control, sprint, momentum retention,
  wall safety, auto-jump and vehicle tuning; its steering reads the shared
  input helper, so it also works while its own PlatformStand option is on and
  on touch clients.
- **Infinite Jump** has Normal (a fixed height every jump), Impulse (the same
  height applied as a force), Stack (each jump adds to the climb, capped),
  Rise (hold jump to climb steadily) and Fall (a mid-air jump cancels the fall
  instead of launching you). A jump-interval floor — raised further on touch,
  where the on-screen button repeats while a finger rests on it — keeps the
  character controllable, and an explicit enabled flag stops queued jump
  events from firing after the module is switched off.
- **Click Teleport** is a hold-then-tap gesture: hold the module's key or its
  placed mobile button, then touch the point you want to reach and the
  character moves to whatever the ray under *that touch* hits. CTRL + click
  still works on desktop. Player ESP, X-Ray, High Jump, Spider, Safe Walk, Zoom Unlocker,
  Interact Extender, a Rejoin action and a rewritten Hitboxes engine extend
  the universal toolkit.
- **Hitboxes** were rewritten around a mode system — Visible (scaled body,
  pinned head), Root (phantom HumanoidRootPart block) and Hybrid — with
  independent head/root sizes, reveal/transparency, collision, mass,
  accessory handling and a tunable refresh interval. Original part states are
  recorded once and restored exactly, and switching modes unwinds the parts
  the new mode no longer targets.
- **Phase Dash** now offers Blink (collision-aware teleport) and Slide
  (velocity burst) modes plus collision padding, flash duration and a
  separate slide speed. Its dash key is the card's own key slot and starts
  blank, like every other module, instead of arriving bound to Q. **Soft Landing** gained Landing / Feather / Auto
  modes, a glide speed and momentum preservation. **Projectile Calibration**
  exposes live-tunable analysis knobs — ping bucket width and ceiling,
  sample window, per-track sample cap, match radius, minimum projectile
  speed — alongside Save / Delete / Show-status actions.
- Universal runtime toolkits initialize inside isolated function scopes so
  older executor compilers stay safely below Luau's 200-register ceiling.

Initialization logs use the `[RTM:Bootstrap]` prefix and include detected
PlaceId, raw download status, downloaded byte count, UI callback count,
TaskManager callback count and errors captured by `pcall`.

## Module architecture

Modules are files, not another thousand lines of `ARandomMenu.luau`. The main
file is the shell — window, cards, option rows, keybind registry — and
everything below the shell is downloaded from the repository at runtime:

```
src/
  core/
    Manifest.luau        ordered list of everything the runtime downloads
    Framework.luau       kernel: categories, modules, options, cleanup
  library/
    Entity.luau          player/character cache, team checks, ray queries
  modules/
    Combat/TriggerBot.luau
    Visuals/PlayerESP.luau
tools/
  test/                  headless Roblox stand-in and the module test suite
```

**The kernel.** `Framework.luau` gives a module file a card and a set of option
builders, and — the part that matters — a cleanup list. Anything a module
allocates through `Module:Loop`, `Module:Event` or `Module:Clean` is disposed of
the moment the module is switched off, so no module carries teardown code and
none of them can leak a connection:

```lua
local ESP
ESP = framework.Categories.Visuals:CreateModule({
    Name = "Player ESP",
    Function = function(enabled: boolean): ()
        if not enabled then
            return
        end
        ESP:Loop(function(deltaTime: number): ()
            -- redrawn every frame; disconnected automatically on disable
        end)
    end,
})
local Boxes = ESP:CreateDropdown({Name = "Boxes", List = {"Corner", "Full", "Off"}})
```

Fly's float engine gained **Bypass**: it holds the altitude but drops you to
the ground for a fraction of a second every few seconds, so a server that
checks whether you ever land sees that you do.

Builders available to a module: `CreateToggle`, `CreateSlider`,
`CreateDropdown`, `CreateList` (a multi-select: same popup, one state mark per
row, stays open while you tick), `CreateBind`, `CreateTextBox`, `CreateColor`,
`CreateButton`, `CreateSection` and `CreateNote`. Each returns an option whose `.Value` stays
current, so a loop reads `Boxes.Value` instead of the module mirroring every
setting into a table of its own.

**The weapon library.** `src/library/Weapons.luau` answers "what can I swing
here", which is not the same question as "what Tool am I holding". The BedFight
dump in `reference/` has no `Tool` instances anywhere: its swords are view
models under `workspace.CurrentCamera.ViewModel`, its inventory is a hotbar of
GuiButtons, and on touch the swing comes from a button the game built at
`PlayerGui.MobileGui.ButtonsFrame.Sword`. The library collects all four shapes —
tools, view models, inventory slots, on-screen buttons — labels each with its
kind, and activates each the right way: a tool is equipped and activated, a
button is pressed by firing the signals a real press raises, in the order the
engine raises them.

A blocklist keeps the picker honest: a hotbar is full of wool, planks, emotes,
capes and kit buttons sitting next to the sword, so anything whose name says
cosmetic, block or emote is dropped, and unnamed buttons are only considered
when they live in the game's touch controls.

**The entity library.** `Entity.luau` answers the three questions every visual
and combat module asks — who is alive, where are their parts, which one is under
the crosshair — in one place, with one team check and one visibility raycast.
`Refresh`, `Get`, `ForEach`, `Rig` (R6 and R15 bone pairs), `VisibleFrom`,
`ClosestToRay` and `ClosestToCursor`.

**The manifest.** `src/core/Manifest.luau` is the file list. Adding a module is
one line there and one file under `src/modules/<Category>/`; nothing in
`ARandomMenu.luau` changes. The runtime keeps an embedded copy as a fallback for
a failed manifest download, and the validation workflow fails if the two drift
apart. Every piece exports the same `init` / `destroy` pair the per-game modules
use, and `destroy` runs from the menu's own teardown step.

### Module kinds

Three kinds of card, and they look like three kinds of card. The marker under
the title is a shape rather than a caption — a word like "TOGGLE" on every card
is noise once you have read it twice, and it eats the width the module name
needs — and the accent stripe carries the matching colour:

The card *is* the control. Nothing is bolted onto it — no switch, no chip, no
marker under the name — because a list of forty modules only stays readable if
each row is one shape whose surface, weight and edge already say what it is and
what it is doing:

| Kind | The card |
| --- | --- |
| toggle | A row that lifts. Off: muted text on near-black, separated by a hairline. On: the surface rises a step, the name goes white and a two-pixel edge lights the left side. |
| action | A slab. A whisper of an outline on all four sides and a name that is always white, because a button has no "off"; the surface flashes once under the press. |
| hold | The same slab, seated a step darker, rising to the lit state for exactly as long as the key is down. |
| group | Not a control at all: no surface, no outline, no hover — a heading with a rule under it and its options below. |

All of it is near-black through grey; the only "colour" in the interface is how
light a grey is. One function, `state.applyCardSkin`, owns every one of those
states, so a restyle, a hover and a toggle cannot disagree about how a card
should look.

Option rows use a **state mark** rather than a switch: a small square that is
empty when off and filled when on. A sliding pill is a phone control — wide,
loud, repeated on every row, and at this size the knob is the only part you can
actually read.

### Choosing between values

Multiple-choice rows open a list under the control instead of cycling one value
per click: pick the value you want directly, in one press, with the current one
marked. The list opens upwards when there is no room below, scrolls past six
entries, and closes on any press outside it or when the menu is hidden.

### Defaults

Nothing is switched on when the menu loads, and every safety rail starts off:
wall checks, team checks, visibility checks, require-tool and friend-skipping
are all opt-in. A module you enable does the blatant thing first and gets
polite only when you ask it to.

### Shipped modules

- **Player ESP** (`Visuals`): corner or full boxes with adjustable thickness,
  R6/R15 skeletons, name tags, a health bar with exact hit points, distance,
  the target's equipped tool, tracers from the bottom, the centre or the cursor,
  and chams as an overlay or an outline. Filters for team, maximum distance and
  visibility, separate colours for enemies, friendlies and targets behind
  geometry, plus text size and a redraw interval. Drawn with ordinary
  GuiObjects rather than the executor `Drawing` API, which several executors
  implement only partially.
- **Kill Aura** (`Combat`): swings the equipped weapon at everyone in reach.
  Swing range and a separate attack range (the distance at which contact
  damage is fired), swings per second with a per-swing random jitter, max
  targets, Multi or Single, target priority by distance, health or threat, a
  field-of-view cone, wall and team checks, rotation off / silent (turned for
  the swing only, then put back) / face, auto-equip, require-tool and target
  **Hits per swing** for games that count each press, **Hit through walls** as
  a decision separate from the wall check (reach and line of sight are not the
  same question),
  a **Show target** readout in the corner — the current target's avatar, name,
  health bar and distance, the way Vape shows it — and highlighting in two
  colours — one for "in swing range", one for "actually
  being hit". Damage is delivered through `Tool:Activate()` **and**
  `firetouchinterest` on the parts inside the target's box, which is what
  melee weapons with limb-only hitboxes need, and **Swing only** turns the
  second half off so the module does nothing a hand could not.

  If nothing is ticked and there is no Tool in your hands, the aura asks the
  weapon library for the best candidate and presses that — without that step it
  found its target, outlined it and then swung nothing at all in every game
  that has no `Tool` instances. Weapon detection does not guess, and it is not
  limited to tools. Everything
  the weapon library finds is listed in a **Weapons** multi-select — tick the
  ones the aura may use, in a game that hands you nine swords, a pickaxe and a
  mobile attack button — and ticked entries are swung through the library, so
  the module works in games with no `Tool` instances at all. With nothing
  ticked it falls back to the tool logic: `FindFirstChildOfClass("Tool")` fails the
  moment a game hands you two tools or names the sword something unexpected, so
  the module *learns*: it watches `Tool.Activated`, and whatever you swing by
  hand becomes the weapon it uses. There is also a *Bind held tool* button and
  a **Weapon name** box (partial match, highest priority), and auto-equip pulls
  that same weapon back out of the backpack after a respawn. Everything past
  the five basic controls is folded away behind one switch.
- **Friend List** (`Utility`, always-on): the one list nothing in the menu
  touches — comma-separated names, Roblox friends, optionally team-mates, an
  "add nearest player" button and a clear button. It used to live inside the
  MM2 module, so the protection disappeared in every other game; MM2 now
  forwards its `isProtectedTarget` question here, and Kill Aura, TriggerBot and
  ESP ask the same list.
- **Click Teleport** (`Movement`, a button card): pick a destination in the
  panel and press the card. Destinations are **Tap point** (arms the module;
  the next tap on the world is where you go), **Nearest player** (friends
  excluded), **Named player** (partial name or display name), **Item** (nearest
  part or model in the workspace whose name contains what you typed, so
  "chest" finds "GoldChest"), **Waypoint** and **Last position** — plus *Save
  waypoint* and *Go back* buttons. Travel is Instant or Glide, with height
  offset, an offset that stops you short of a player instead of inside them,
  search range and an optional keep-momentum. The old version raycast with
  `Camera:ViewportPointToRay(input.Position)` — input positions include the
  36-pixel top bar and viewport points do not, so every teleport landed above
  the finger and on touch it usually hit nothing at all; it uses
  `ScreenPointToRay` now.
- **Auto Clicker** (`Combat`): a clicks-per-second *range* rather than a
  number, so no two intervals match. It can press three different things:
  `Tool` (`Tool:Activate()`, which works on a phone and is what most weapons
  actually listen to), `Mouse` (the executor's `mouse1click`, desktop only) and
  **`Screen button`** — games that build their own on-screen attack button put
  a GuiButton in your PlayerGui, and the clicker presses it exactly as a finger
  does, by firing the signals a tap raises. Press *Learn button*, tap the
  game's button once, and it is bound; the name is remembered so a HUD rebuilt
  between rounds is found again. The menu's own buttons are never eligible.
- **Player ESP** boxes are the projected corners of the character's own
  bounding box, not a height guess with a fixed width ratio. The old box took
  two points and made the width 52% of the height, so an angled camera, a rig
  with its arms out or a target near the screen edge all produced the wrong
  shape — and a corner behind the lens projects to a huge negative coordinate,
  which is where the sudden stretching came from. Targets with any corner
  behind the camera are skipped outright.
- **Player ESP** draws in **team colours** by default, reading each player's
  own `Team.TeamColor`, and puts the name on a dark plate so it stays readable
  over snow or a bright sky. The two-grey scheme is still there for teamless
  games.
- **Item Render** (`Visuals`): object ESP — the name of every listed object,
  drawn above it with its distance, and its silhouette outlined through walls.
  The objects are a **multi-select list**, not a comma string: each one can be
  ticked and unticked on its own. **Touch part** hides the menu, waits for one
  tap on the world, takes the name of whatever was under it (the model's name,
  not the plank's) and adds it to the list already ticked — and from then on
  *every* object with that name is rendered, so one tap on one iron ore lights
  up all of them. Names can also be typed in, and the sweep interval, distance,
  colour, text size and outline are all adjustable.
- **Remote Logger** (`Utility`): records what the game sends to its own
  remotes — the live-only half of reverse engineering, the part no decompiler
  can give you, because it is the *values* a specific action produces. Full
  instance path, method, the type and value of every argument, the call count
  and a ready-to-paste snippet, written as a readable `.txt` and a `.json` to
  `ARandomMenu/RemoteLogs/<place>-<time>`.

  It is built not to interfere. The hook does three things — check a boolean,
  read the namecall method, push references onto a queue — and returns; a normal
  loop drains that queue a frame later and does the describing there. The
  earlier version built the instance path inside the hook, and `GetFullName` is
  itself a namecall, so the logger re-entered itself on every call: enough
  delay on a shop button firing three remotes to make the purchase fail. Now
  nothing inside the hook calls an Instance method or allocates a string,
  `checkcaller` drops the menu's own traffic, and each remote's arguments are
  sampled a few times rather than on every one of sixty calls a second.
- **TriggerBot** (`Combat`): always-on or hold-to-arm, single or automatic,
  reaction delay with a per-acquisition random jitter, minimum time between
  shots, target-part filter (any, head, torso), an aim radius in pixels that
  switches the search from an exact raycast to a screen-space query, maximum
  distance, team check, wall check and a require-tool switch. Firing goes
  through `Tool:Activate()` and `mouse1click()` so a game that ignores one
  still receives the other.

### Performance

Frame time was being spent in four places, and all four are now paid once
instead of repeatedly:

- **The entity list** is built once per frame. ESP, Kill Aura and TriggerBot all
  ask on the same frame; `Refresh` coalesces calls inside a 15 ms window and
  reuses one table per player instead of allocating a fresh one for each,
  which keeps the collector out of the frame budget.
- **Rig bones** are resolved once per character and cached. Fourteen
  `FindFirstChild` pairs per player per frame bought nothing: a rig does not
  change shape between frames.
- **The ESP's visibility raycast** — one ray per player per frame in a full
  server — is cached for a tenth of a second, the redraw interval defaults to
  30 ms rather than every frame, and distance rejection happens before any
  projection or lookup.
- **Item Render** keeps an index of matching objects, built once and maintained
  from `DescendantAdded`/`DescendantRemoving`, instead of walking
  `workspace:GetDescendants()` five times a second — on a real map that is tens
  of thousands of instances per sweep. BedFight's bed and generator sweeps are
  cached the same way, and the weapon scan (which walks the whole PlayerGui) is
  cached for a second, so an aura swinging nine times a second scans once.

The test suite asserts each of these: three refreshes in one frame do one
sweep, a later frame sweeps again, rig tables are identical between calls, and
three weapon scans walk the interface once.

### Tests

`luau tools/test/run.luau` loads the framework, the entity library and every
module file against a stand-in Roblox (`tools/test/Roblox.luau`) and a stand-in
menu host (`tools/test/Host.luau`), switches each module on, drives it for a few
frames and switches it off again. It asserts that options exist with usable
defaults, that loops run, that a delay is actually waited out, that a team-mate
under the crosshair is never shot, and that nothing survives teardown.

`bash tools/validate.sh` is the whole gate in one command: JSON manifests,
source layout, module contracts, manifest/runtime-fallback agreement, strict
headers, the loader guards, compilation at both optimisation levels, the
200-local register headroom probe and the module tests. It picks up
`luau-compile` and `luau` from `LUAU_DIR`, from `PATH` or from `/tmp/luau`:

```bash
LUAU_DIR=/path/to/luau bash tools/validate.sh
```

On a runner (`CI=true`, which GitHub sets, or `REQUIRE_LUAU=1`) a missing
toolchain fails the job instead of skipping the compile and the tests — a
skipped check that reports success is worse than no check. Locally it just says
so and stops.

The GitHub workflow should point a step at this script so the two cannot drift:

```yaml
      - name: Run repository checks
        run: bash tools/validate.sh
```

`LUAU_DIR` is optional there: the script already looks in `PATH` and in
`/tmp/luau`, which is where the workflow's existing compile step unpacks the
Luau release.

## BedFight module

`src/games/BedFight.luau` loads for place `71480482338212` and is built from the
saved place in `reference/`, not from guesswork:

- **Bed ESP** — `Workspace.BedsContainer` and the map's own `Beds` folder, each
  bed labelled with its distance.
- **Generator ESP** — the Diamond and Emerald generator parts, labelled with
  the countdown the game itself renders in `ProgressGui.TimerLabel`, so the
  number on screen is the game's number rather than a second-hand guess.
- **Round Info** — `Status`, `GameMode` and `AllBedsBroken` read live from
  `ReplicatedStorage.GameInfo`, with the number of beds still standing.
- **Auto Swing** — presses the game's own sword button on a timer, because this
  game has no `Tool` to activate.
- **Scaffold** — places the game's own blocks, not a local platform: it equips
  a block from the hotbar, aims down at the gap and presses the game's build
  control, only while there is nothing under your feet. Log `PlaceBlock` with
  the Remote Logger and the button press can become the call itself.
- **Anti Void** — the kill height comes from `GameInfo.DeathBarrierInfo`, so
  the margin is measured against the game's own plane: it remembers where the
  ground last held you, and when you cross the margin with nothing below it
  stops the fall and puts you back there.
- **Bed Nuker** — hits the nearest bed in range with the game's own controls:
  the swing button plus contact events against the bed's hitbox, at a rate you
  set.

What it does not do is fire `SwordHit`, `MineBlock`, `PlaceBlock` or
`PurchaseItemShopItem` directly: their argument shapes are not in the dump, and
a remote called with the wrong arguments is a kick, not a feature. Run the
**Remote Logger**, break one bed and place one block by hand, and the saved log
will contain exactly what those remotes expect — at which point they can be
called properly rather than hopefully.

## MM2 module

- **Clones are recognised.** MM2 is copied constantly ("MMV" and friends): same
  game, different PlaceId, so a PlaceId table alone left every copy with no
  game tab. When the PlaceId is unknown the runtime fingerprints the place
  instead — the `Remotes.Gameplay` round pipeline, `ClientServices.WeaponService`
  with its `GunFired` event, the `MainGUI.Game.Timer` HUD, the `Murderer`
  collision group and the map's coin container. Four of those five must match,
  each is something the game genuinely needs to work, and the check is retried
  briefly while the client is still replicating. `GAME_CHECK.matches()` answers
  for the game a clone is a copy of, so game modules keep working there without
  comparing PlaceIds themselves, and the Settings page reports how the game was
  recognised (`MM2 · fingerprint 5 markers`).

- **Player ESP** was fifteen flat rows (a toggle, a colour and a transparency
  slider per role, plus coins and traps). It is now grouped under Roles /
  Appearance / World headings, each role is a toggle plus its colour, and the
  five per-role sliders collapse into one shared **Player fill**.
- The ESP also *works* now. It used to be gated behind `hasActiveRoundRoles()`,
  which needs the round table to name a Murderer/Sheriff or a player to be
  holding the weapon — but other players' Backpacks never replicate, so at the
  start of a round nothing qualified and the module drew nothing at all. It now
  runs whenever it is on (with an opt-in **Only during rounds** toggle) and
  maintains one Highlight per player instead of destroying and rebuilding every
  highlight twice a second, which also fixes the flicker and the highlights
  lost on respawn.
- **Gun Visuals** is **Gun ESP**, and the in-world markers follow the menu:
  a dark glass plate with a grey hairline and off-white text, with the role
  colour reduced to a slim accent bar instead of a coloured border.
- **Always Show Timer** draws nothing of its own. MM2's HUD decides who sees
  its countdown in exactly one place: the client handler for the `RoundStart`
  remote shows `MainGUI.Game.Timer` for every role except Innocent, and its
  update loop only refreshes that label while your role is not Innocent. The
  module therefore *replays that client event locally* with the local player
  marked as a non-Innocent role, and the game brings up and drives its own
  timer — the display is the game's, not the menu's. The place has exactly one
  listener on that remote, so nothing else reacts to the replay; switching the
  module off replays the real round data to put the HUD back. Executors that
  cannot replay a client event fall back to revealing the label and writing the
  countdown in the game's own `1m 7s` format.
- **Player ESP is instant**: the pass runs every frame (it only walks the
  player list and writes three properties on an existing Highlight) and
  rebuilds immediately on joins, respawns and role changes, so a murderer who
  swaps weapons or dies is recoloured on the next frame.
- **Shoot** and **Knife** are device-independent. Aim is solved locally with
  CFrame maths and a raycast, then the gun's own `Shoot` remote is fired with
  `(origin, aim)`: no mouse, no `hookfunction`, no touch-specific weapon API.
  `gun:Activate()` with the redirect hook is now only used when Redirect mode
  is explicitly selected *and* the hook is installed for this input type. The
  hook itself no longer hard-codes the desktop accessor: it hooks every known
  aim accessor and returns whichever shape the original returned, so touch
  clients redirect too instead of reporting "unavailable".
- **Sprint** is the reference `hold` module. The hard-coded LeftControl watch
  is gone entirely: the module is always running, its key slot starts unbound,
  and the key the player picks is the only thing that makes it run — held means
  sprint, released means stop. It never enables or disables anything and never
  toasts. The speed is re-applied every frame because the game resets
  `WalkSpeed` on respawn, on round start and when a tool is equipped.
- **Improve FPS** moved out of this module into Universal.
- Two lookups were verified against a dump of the live place and fixed:
  `findMM2Map()` required a `CoinContainer` child, but current maps ship
  `CoinAreas` (a live map reads `ResearchFacility > CoinAreas / Interactive /
  Base / Spawns`), so it always returned `nil` and silently disabled Teleport
  to Map, Loop All Interact and the map-scoped sweeps; and the dropped-gun
  search now also accepts the plain `Gun` tool lying in the workspace,
  returning its handle so the pivot and highlight paths keep working.
- The timer work is likewise built on the real hierarchy: `MainGUI.Game.Timer`
  with its `XPText` label, which the game's HUD only refreshes while your role
  is not Innocent — hence the menu writing the countdown itself, in the game's
  own `1m 7s` format, when it would otherwise be frozen.

## Source layout

- `tools/layout-preview.html`: development harness that mirrors
  `computeLayoutMetrics` so the Mobile/Tablet/Desktop shells, the collapsed
  rail, the card columns and the chrome-less overlays can be reviewed in a
  browser at the reference viewports. It is never downloaded by the runtime.
- `src/core/Manifest.luau`: the ordered list of framework, library and module
  files the runtime downloads.
- `src/core/Framework.luau`: the module kernel (categories, options, cleanup).
- `src/library/Entity.luau`: shared player/character queries.
- `src/modules/<Category>/*.luau`: one file per module.
- `tools/test/*.luau`: headless Roblox stand-in and the module test suite.
- `tools/validate.sh`: every repository check in one command.
- `reference/`: third-party sources kept for reading; never loaded or validated.
- `src/gui/Current/Assets/Brand/`: the menu logo and the player-card backdrop.

Artwork that no code referenced (112 files: the blossom animation frames, the
arrow set, the manga-era decorations, particles and frames) and the 24 MB MM2
place dump used while reverse-engineering that game have been removed, along
with their now-dangling entries in the asset catalogue. What remains under
`src/gui/Current/Assets` is either loaded at runtime or pinned by the
validation workflow.
- `src/games/Universal.luau`: the universal/movement module contract only — a
  manifest of feature ids, names and ordering. Every universal implementation
  (Fly, Speed, Infinite Jump, Click Teleport, Noclip …) lives in
  `ARandomMenu.luau`.
- `src/games/MM2.luau`: complete MM2 implementation.
- `src/games/TRS.luau`: complete TRS implementation.
- `src/games/VD.luau`: Violence District survivor, killer and visibility tools.
- `src/gui/Current/gui.lua`: reusable presentation-only GUI controller.
- `src/gui/Current/Images`: optional normal image assets.
- `src/Profile`: compatibility data retained for older loaders.

## Typeface

`Config. → Interface font` lists every face the client ships (read from
`Enum.Font` at runtime rather than hard-coded, so a newer client offers more and
an older one does not lie), plus the three the repository carries:
**Candy Fruits**, **Valve** and **Minecraft (Monocraft)** — a Minecraft-shaped
face under the SIL Open Font License, vendored from
[IdreesInc/Monocraft](https://github.com/IdreesInc/Monocraft) together with its
licence at `src/gui/Current/Assets/Typography/Monocraft-OFL.txt`. That is a
little over fifty options.

Lists longer than eight entries — the typeface picker among them — open with a
filter field at the top, so fifty faces are one search away rather than a long
scroll.

Monocraft is verified as a real OTF: `OTTO`/CFF outlines, 13 tables with every
required one present, 1,698 glyphs, all 95 printable ASCII characters mapped,
family "Monocraft", monospaced, and a single weight (Regular 400). That last
point matters — a Roblox font *family* is a JSON manifest with one file per
weight, while a single-file face has exactly one. Asking such a file for Bold
returns a synthetic smear or nothing, so the picker uses single-file faces at
the one weight they have and lets size carry the hierarchy; only real families
get the bold/semibold/regular treatment.

Choosing one rebuilds the menu's three weights — bold for titles, semibold for
controls, regular for body — from the chosen family and repaints every label
already on screen, each keeping the weight it was designed with, so headings
stay heavier than body text whatever the family. Repository fonts are
downloaded, cached and turned into an asset id through the same path the
decorative fonts already use, off the input thread; the choice is stored in the
config and restored on the next injection.

## Brand, icons and player card

- The intro carries no words. A menu that spells out "loading modules" while it
  loads modules is telling the player something they can already see; what is
  left is the ring and the progress line, and the shell fades up out of it. The
  build stamp moved to the console.
- The drawn icons are transparent PNGs rather than glyphs on a dark plate, so
  the rail's own near-black shows through instead of a grey square.
- The menu's logo (`src/gui/Current/Assets/Brand/menu-logo.jpg`) is drawn on
  both places the menu identifies itself: the floating launcher button and the
  brand mark at the top of the navigation rail. Both keep their lettering as a
  fallback, so an executor without `getcustomasset` loses nothing. The launcher
  only exists while the menu is hidden — it used to sit on top of the open
  window, where it read as a second, broken close button.
- Navigation tabs carry icons instead of two-letter monograms. Game tabs
  (Universal, MM2, TRS, VD, MVSD) show the game's own icon, fetched by asset id
  through `MarketplaceService:GetProductInfo` — `rbxthumb://type=GameIcon` only
  resolves for the place the client is connected to, which is why every tab but
  Universal used to come up blank. Movement gets a walking figure and Config. a
  gear (`src/gui/Current/Assets/Icons/nav-*.png`), and the two floating-window
  launchers get a star and a stacked-windows glyph (`window-*.png`). Monograms
  remain the fallback.
- The brand mark above the tab list closes the menu, and the launcher button —
  now shown on desktop as well, and only while the menu is hidden — opens it
  again.
- The foot of the rail carries a **player card**: the account's avatar
  (`rbxthumb://`, resolved by the engine itself — no download), display name,
  handle, and a line with the date this account first ran the menu, how many
  sessions it has had and how long the current one has been going. The date and
  the counter live in the config file; the session clock restarts with the
  injection. Collapsed rails show the avatar alone.

## Images

The neutral interface draws no decorative artwork, so the runtime resolves only
the two optional display fonts through `AssetManager`. It selects a compatible
executor HTTP alias, validates the font signature, retries failed downloads,
writes versioned files under the cache folder, verifies the result and resolves
local paths with `getcustomasset`/`getsynasset`, falling back to the built-in
Builder Sans face when unavailable. Every stage is logged with the
`[RTM:Assets]` prefix.

The image files under `src/gui/Current` are retained for the standalone
`gui.lua` controller and for older loaders; the current bootstrap does not
download them.
