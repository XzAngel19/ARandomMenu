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
git fetch origin arena/01a01c6e-arandommenu
git reset --hard FETCH_HEAD
git push --force-with-lease origin HEAD
```

The probe commit is thrown away by that reset, which is fine — it already proved
what it was for. To pick up later integration work, `git fetch origin
arena/01a01c6e-arandommenu && git merge FETCH_HEAD`.

Both messages below start with this.

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
> git fetch origin arena/01a01c6e-arandommenu
> git reset --hard FETCH_HEAD
> git push --force-with-lease origin HEAD
> ```
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
> git fetch origin arena/01a01c6e-arandommenu
> git reset --hard FETCH_HEAD
> git push --force-with-lease origin HEAD
> ```
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
