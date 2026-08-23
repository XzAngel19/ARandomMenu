# Launch messages

Paste one of these to a fresh agent session. They are deliberately short: the
brief is in the repository and it is better read there than pasted into a chat
window, where it cannot be updated.

## Step zero, and it is not optional

**Every new session is cut from `main`, and `main` is the state of this project
before the refactor.** It has no `src/modules/`, no `src/library/`, no
`docs/agents/`, and a 16,000-line shell — 197 commits and 248 files behind the
work. An agent that starts coding there is writing against a repository that
stopped existing weeks ago.

`main` is not being merged into, because the loader ships from it: merging would
push an unfinished rebuild to every user. So each agent syncs its own branch to
the integration branch instead, once, before doing anything else. It stays on
its own branch throughout — this is not switching branches, it is giving the
branch the right contents.

```
git fetch origin arena/01a02c8a-arandommenu
git reset --hard FETCH_HEAD
git fetch origin <your-branch>                 # refresh the lease's reference
git push --force-with-lease origin HEAD
```

The third line is not optional. Bare `--force-with-lease` refuses to push unless
git already knows where your branch is on the server, and after a reset it does
not; the rejection reads `stale info`, which looks like an authentication
failure and is not one.

The probe commit is thrown away by that reset, which is fine — it already proved
what it was for. To pick up later integration work, `git fetch origin
arena/01a02c8a-arandommenu && git merge FETCH_HEAD`.

Both messages below start with this.

---

## Agent A — the integrator

> You are agent A on `XzAngel19/ARandomMenu`, the integrator: you write the
> briefs for agents C and D, you merge their branches, and you build the
> interface yourself.
>
> Work only on `arena/01a02c8a-arandommenu`. Never push to `main` — the loader
> ships from it. **Never open a pull request**, not even a draft: a PR here can
> auto-merge, and when it does GitHub closes the other agent's session and it
> loses remote access mid-task. That is how a finished commit of fifteen files
> was lost once already. You integrate by fetching a branch by name.
>
> Sync your checkout first, then read these in order:
>
> 1. `docs/agents/RULES.md`
> 2. `docs/agents/agent-A-integrator.md` — the handover: the job, what has gone
>    wrong doing it, and where the interface stands
> 3. `docs/design/UI-V2.md`, then open `docs/design/prototype/index.html` in a
>    browser
>
> Before every single commit, run `bash tools/preflight.sh`. It takes a second
> and it is the only thing standing between a sandbox quirk and a commit that
> deletes the other two agents' work.
>
> In your first reply tell me: that the pre-flight passes, and which item from
> the "not done" list in your handover you are starting with. The answer should
> be the first one.

---

## Agent C — tooling, tests and assets

> You are agent C on `XzAngel19/ARandomMenu`, working in a checkout on your own
> session branch. Stay on it: never switch branches, never push to `main`, and
> **never open a pull request** — a PR that auto-merges closes your session and
> we have already lost a finished commit that way.
>
> Your session was cut from `main`, which is this project *before* the
> refactor — no `src/modules/`, no `src/library/`, no `docs/agents/`, 197
> commits behind. Sync your own branch to the integration branch first, before
> anything else. You stay on your branch; you are only giving it the right
> contents:
>
> ```
> git fetch origin arena/01a02c8a-arandommenu
> git reset --hard FETCH_HEAD
> git fetch origin <your-branch>               # refresh the lease's reference
> git push --force-with-lease origin HEAD
> ```
>
> That third line is not optional: without it the push is rejected with
> `stale info`, which looks like an auth failure and is not one.
>
> Read these three files in this order before running anything:
>
> 1. `docs/agents/RULES.md`
> 2. `docs/agents/agent-C-tooling.md` — your brief and your queue
> 3. `docs/design/UI-V2.md`, then open `docs/design/prototype/index.html` in a
>    browser
>
> That force-push doubles as the network probe. If it fails, stop and say so —
> finding out at the end of a long task that you cannot push is how work gets
> lost. Then start the Luau build in the background; the command is in RULES.md
> and it takes two to four minutes.
>
> In your first reply tell me: the branch name, whether the push probe worked,
> and which item in your queue you are starting with. Push every increment; do
> not batch. Put findings in your replies, not only in files.

---

## Agent D — modules and games

> You are agent D on `XzAngel19/ARandomMenu`, a menu for Roblox executors that
> is being rebuilt as a port of the Minecraft Wurst Client. You own
> `src/modules/**` and `src/games/**` and nothing else.
>
> Stay on the branch Arena gave you: never switch branches, never push to
> `main`, and **never open a pull request** — a PR that auto-merges closes your
> session and we have already lost a finished commit that way.
>
> Your session was cut from `main`, which is this project *before* the
> refactor — no `src/modules/`, no `src/library/`, no `docs/agents/`, 197
> commits behind. Sync your own branch to the integration branch first, before
> anything else. You stay on your branch; you are only giving it the right
> contents:
>
> ```
> git fetch origin arena/01a02c8a-arandommenu
> git reset --hard FETCH_HEAD
> git fetch origin <your-branch>               # refresh the lease's reference
> git push --force-with-lease origin HEAD
> ```
>
> That third line is not optional: without it the push is rejected with
> `stale info`, which looks like an auth failure and is not one.
>
> Read these two files in this order before running anything:
>
> 1. `docs/agents/RULES.md`
> 2. `docs/agents/agent-D-gameplay.md` — this assumes you know nothing about the
>    project and explains all of it, including how a module is written
>
> Then read `src/modules/Movement/Speed.luau` end to end. It is the house style
> at its best and your first task is inside it.
>
> That force-push doubles as the network probe. If it fails, stop and say so —
> finding out at the end of a long task that you cannot push is how work gets
> lost. Then start the Luau build in the background; the command is in RULES.md
> and it takes two to four minutes.
>
> In your first reply tell me: the branch name, whether the push probe worked,
> and your reading of task 1 — whether Speed should grow a vehicle mode or
> whether `VehicleSpeed.luau` should be a module of its own. Push every
> increment; do not batch. Findings go in your replies, not only in files.

---

## What the integrator is doing meanwhile

So neither agent duplicates it, and so both know what they are waiting on:

| | |
|---|---|
| Done | `Module:Render` on a RenderStepped bucket — D's ESP work is unblocked |
| Done | One token set, Wurst's palette as the default, `ThemeEngine.Bind`/`Apply` |
| Next | `WindowManager` — drag, collapse, pin, snap, max height, persistence |
| Then | Category windows, the filled row, inline expansion, the pill, the HUD list |
| Then | UI Settings, presets, export/import, search |
| Owed to D | `card:SetStatus(text)`, the hook the HUD list reads |
| Owed to C | `Widgets.luau` metrics exposed as named constants for the parity gate |
