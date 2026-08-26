# Agent A — the integrator

You run the project. You write the briefs for C and D, you merge their branches,
and you build the interface yourself. This document is the handover: what the
job is, what has already gone wrong doing it, and the two checks that stop it
going wrong again.

Read `docs/agents/RULES.md` first — every agent does. Then this. Then
`docs/design/UI-V2.md`, and open `docs/design/prototype/index.html` in a
browser, because that prototype is the specification for everything you are
building.

## The branch, and the two things that destroy work

You work on **`arena/01a03bca-arandommenu`** and push only there. Never `main`:
the loader ships from it, so merging into it would push an unfinished rebuild to
every player.

That name is not permanent and the way it changes is worth knowing before it
surprises you. An Arena session can only push to the branch Arena created for
it, so the integration branch dies with the integrator session that owns it. The
replacement does not adopt the old name — it cannot — it fast-forwards the old
tip into its own branch and that branch becomes the integration branch. This has
happened twice: `arena/01a01c6e` → `arena/01a02c8a` → `arena/01a03bca`. Nothing
is lost, because each name contains the previous one whole; what breaks is every
document that hard-codes a branch, which is why `RULES.md` §2a now says so in one
place and everything else points at it.

### Never open a pull request

Not a draft, not "to show the diff". A PR on this repository can auto-merge, and
when it does GitHub closes the *other* agent's session and it loses remote access
mid-task. That is not a hypothetical — it is how agent B lost a finished commit
of fifteen files that never left its sandbox. You integrate by fetching a branch
by name. CI runs on every branch, so a push is already checked.

### Run the pre-flight before every commit

```
bash tools/preflight.sh
```

The sandbox silently resets HEAD to the session's base commit while your working
files stay on disk. It has happened five times. Nothing is lost when it does —
everything pushed is safe — but if you commit without noticing, you produce a
commit whose diff **deletes every other agent's work**, and the only thing that
stopped that shipping the last time was the remote happening to be ahead, so the
push bounced.

The script answers one question: is what I am about to commit built on what is
actually on the server. Run it before `git commit`, every time. It costs a
second.

## How to integrate an agent's branch

Never through GitHub. Locally, into a namespaced ref so their branch name cannot
collide with yours:

```
git fetch origin arena/<theirs>:refs/remotes/origin/agentD
git merge --no-edit refs/remotes/origin/agentD
```

The only conflicts you will ever see are the generated files —
`runtime/bundle.luau` and the `SOURCE_STAMP` line in `ARandomMenu.luau`. **Take
neither side.** Resolve by regenerating:

```
git checkout --ours ARandomMenu.luau runtime/bundle.luau
git add ARandomMenu.luau runtime/bundle.luau
python3 tools/bundle.py
```

Then the gate, then commit, then push.

## The gate

```
LUAU_DIR=/tmp/luau-src/build bash tools/validate.sh   # must print "All checks passed."
python3 tools/bundle.py                               # if the stamp moved
```

`/tmp` does not survive between turns, so you will rebuild Luau most sessions.
Start it in the background first thing; it takes two to four minutes and the
command is in `RULES.md`. If the gate says `luau-compile not found`, it skipped
compilation and the tests — that is not a pass, and saying it is would be
exactly the kind of green-but-empty result this project keeps finding.

## What the project is

A Roblox executor menu being rebuilt as a deliberate port of the Minecraft
**Wurst Client**, on the same terms `VapeV4ForRoblox` is a port of Vape: the same
windows, the same settings, the same names, the same defaults. Not an
interpretation. The user's instruction is that the previous menu should be
treated as though it does not exist.

Five per cent is Roblox: the floating pill toolbar from the in-game top bar is
the launcher, and the proportions stay small on a phone the way Vape's do,
because a menu that grows to fill a phone covers the game it exists to act on.

The thing the whole project is fighting, in the user's words:

> **Code slop** is low-quality, AI-generated code that compiles and passes basic
> tests, but is architecturally thoughtless, bloated, and hard to maintain.

Concretely, that means: a green gate proves nothing ran, not that it worked —
this repository has shipped five dead modules, 110 tests nobody executed and 186
unreachable lines, all green. When you add something, prove it is reached.

## Where the interface is

Done, and load-bearing:

- **`ThemeEngine`** — 22 tokens, Wurst's own defaults (`#404040` background,
  `#101010` accent, `#F0F0F0` text), `Bind` so a preset switch repaints what is
  already on screen. `accent` paints chrome, `enabled` paints a module that is
  on; two tokens, as Wurst separates them.
- **`WindowManager`** (`state.windows`) — drag, clamp, snap at eight pixels to
  viewport and to other windows, collapse, pin, max height with scrolling,
  persistence per profile. `Create` builds a window, `Adopt` manages a frame
  that already exists. Owns and releases its own connections.
- **`ClickGui`** (`state.clickGui`) — six category windows tiled from the
  top-left, every one of the 45 cards reparented into the right one.
- **The row** — fills with `enabled` when the module is on. 22 px, and nothing
  scales with the viewport any more.
- **`card:SetStatus(text)`** — on the card, so all 45 modules can publish the
  bracketed status the HUD list will read.
- **`Module:Render`** — a second scheduler bucket on RenderStepped, because
  Heartbeat runs after the frame and made every overlay trail the camera.
- **`PRODUCT`** — the name in one place. `guiName`, `blurName` and
  `storageFolder` deliberately keep their old values: the first two are what a
  game can enumerate under CoreGui and Lighting, and the third already holds
  every player's saved configs.

**The demolition is done.** Your predecessor removed `Main`, `centerMain`, the
sidebar, `createTab`, `setTab`, the page host, the search and the card subtitle:
2,454 lines out, the shell down to 5,288, `state.d.luau` cleaned of the 21 keys
that lost their owner. The scroll aliases it left behind (`state.universalScroll
= CardBin` and friends) are deliberate and load-bearing — game modules still
name a parent — and they go when those modules move to `CreateModule`.

Three window bugs from a real session are also fixed: a category window no
longer has a close button (Wurst does not give one; the X belongs to settings
windows, and ours removed a sixth of the menu with nothing to bring it back), a
pinned window now survives the GUI closing, which is the only thing pinning is
for, and the whole layer is on one `UIScale` derived from viewport height
against 1080p, clamped 0.85–1.6, because the interface was measured against
Vape's and Wurst is bigger.

**That three-item queue is finished, and this section used to claim otherwise.**
It was written before the furniture landed and never revised, so a session that
trusted it would have rebuilt three things that already exist and are already
pinned by suites. What is actually on the tip, each with the check that proves
it runs rather than merely compiles:

1. **The furniture** — `src/library/Furniture.luau`. The wordmark draws
   `assets/wurst/wurst_128.png` through the shell's `wurstLogo` asset key on
   Wurst's white chip (`Furniture` suite: the band is the y=6..17 half-alpha
   stripe, packed to logo + gap + version, and it is not `brandLogo` or the old
   `menu-logo.jpg`); the pill is published and survives the GUI closing; the
   HackList draws one line per enabled module from `card:SetStatus` and omits
   disabled ones; tooltips are `TOOLTIP_DELAY_MS = 400`.
   **The stats block is not missing — it was deliberately removed.** The old
   FPS/PING/TIME/PLACE readout is gone because Wurst draws the sausage and the
   version in that corner and nothing else, and there is a standing check named
   `FPS/PING/TIME/PLACE are not on the HUD`. Do not rebuild it from this brief's
   old wording.
2. **Wurst's setting lines** — `src/library/Widgets.luau`, held by the
   `settings-widgets` suite: label left, value right, a rail with a square knob,
   a square checkbox rather than a switch, and a colour row as label + hex + a
   bar of that colour. The numbers are **rail 6 px, knob 16×16**, not the
   "5 px bar with a 7×11 knob" this brief used to say — those were the Java
   values before `docs/wurst-deviations.md` recorded the scale-2 conversion, and
   `spec.json` now holds the Luau constants to 6 / 16 / 16.
3. **The windows** — `src/library/SettingsPage.luau` builds UI Settings,
   HackList, Keybinds, Add Keybind, Wurst Options and Keybind Profiles.
   "Presets" was never a Wurst object: `docs/wurst-features.md` §Presets is
   explicit that Wurst has **Keybind Profiles** and no theme preset, and that
   this repository's `storageFolder/Profiles/Game_<id>.Config` is a different
   thing that must not be renamed to look like one.

So the interface queue is now driven by what the parity gate and the prototype
still disagree about, not by this list. Before starting anything here, diff the
prototype against the code rather than trusting a paragraph: the gate
(`tools/extract_prototype_spec.py --check`) is the only statement of intent that
cannot go stale, because it fails when it does.

## Who builds what, so nobody builds it twice

There are four of us on this and two of us can write interface code, so the
split is explicit:

- **You** build the interface. That used to read "points 2, 3 and 4 of the list
  above — the pill, the wordmark, the stats block, the HUD list, tooltips…",
  which is stale in two ways: those points are built, and the stats block was
  deliberately deleted rather than left undone. The lane is unchanged —
  `src/library/Furniture.luau`, `Widgets.luau`, `SettingsPage.luau`,
  `ClickGui.luau`, `WindowManager.luau`, `Cards.luau` and the shell — but the
  work is whatever the prototype and the parity gate still disagree about.
- **The reviewer** verifies what you push, integrates C's and D's branches, and
  writes their briefs. It does not build interface features while you are
  building them; if it needs to touch one of your files to unblock somebody, it
  says so in its reply.

Both of you push to the same branch, so rule 2c applies: small commits, and a
rejected push is merged, never forced.

## The other two agents

- **C** owns `tools/**` and `docs/**` minus `docs/agents/`, plus the harness and
  the interface suites. Its parity gate reads `docs/design/prototype/spec.json`
  and holds your Luau constants to the prototype's numbers. It has already
  failed you once for narrowing a window in code while the prototype said
  otherwise — when that happens, **change the prototype first and regenerate**,
  never the other way round, or the spec quietly becomes a description of
  whatever the code does.
- **D** owns `src/modules/**`, `src/games/**` and the suites that test them.

Their briefs are `docs/agents/agent-C-tooling.md` and
`docs/agents/agent-D-gameplay.md`; the messages that launch them are in
`docs/agents/LAUNCH.md`. Keep the briefs in the repository rather than in chat,
so you can update them.

Every session, theirs and yours, is cut from `main`, which is the project before
the refactor. Rule 12 in `RULES.md` is the sync recipe, and its third line —
fetching your own branch before the force-push — is not optional; without it the
push is rejected with `stale info`, which reads like an authentication failure
and is not one.

## Why your work is safe even if this session dies

The session before yours was lost — conversation and all — and nothing of its
work went with it, because it pushed to the shared integration branch as it
went. The demolition was on the server before the session ended.

That is the whole reason rule 3 exists. Push every increment; a finished thing
sitting in a sandbox is a thing nobody has.

## How to talk to the user

Spanish. Code and comments in English. Direct, evidence-based, no flattery. When
you are wrong, say so plainly and specifically — that has happened repeatedly
here and it is what the user values most. Do not claim a technique works in a
game nobody has run; nobody in this project can run Roblox, the user is the only
one who plays it.
