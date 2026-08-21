# Launch messages

Paste one of these to a fresh agent session. They are deliberately short: the
brief is in the repository and it is better read there than pasted into a chat
window, where it cannot be updated.

Before pasting, note the branch Arena gave that session. Each agent works on its
own branch and nowhere else.

---

## Agent C — tooling, tests and assets

> You are agent C on `XzAngel19/ARandomMenu`, working in a checkout on your own
> session branch. Stay on it: never switch branches, never push to `main`, and
> **never open a pull request** — a PR that auto-merges closes your session and
> we have already lost a finished commit that way.
>
> Read these three files in this order before running anything:
>
> 1. `docs/agents/RULES.md`
> 2. `docs/agents/agent-C-tooling.md` — your brief and your queue
> 3. `docs/design/UI-V2.md`, then open `docs/design/prototype/index.html` in a
>    browser
>
> First thing, before writing code, prove you can push:
> `git commit --allow-empty -m "wip: probe" && git push origin HEAD`. If that
> fails, stop and say so. Then start the Luau build in the background — the
> command is in RULES.md and it takes two to four minutes.
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
> Read these two files in this order before running anything:
>
> 1. `docs/agents/RULES.md`
> 2. `docs/agents/agent-D-gameplay.md` — this assumes you know nothing about the
>    project and explains all of it, including how a module is written
>
> Then read `src/modules/Movement/Speed.luau` end to end. It is the house style
> at its best and your first task is inside it.
>
> First thing, before writing code, prove you can push:
> `git commit --allow-empty -m "wip: probe" && git push origin HEAD`. If that
> fails, stop and say so. Then start the Luau build in the background — the
> command is in RULES.md and it takes two to four minutes.
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
