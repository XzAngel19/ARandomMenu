# Rules for agents working on this repository

Read this first, in full, before touching anything. These rules exist because
each one of them has already cost us work.

## 0. What "done" means here

> **Code slop** is low-quality, AI-generated code that compiles and passes basic
> tests, but is architecturally thoughtless, bloated, and hard to maintain. Like
> text-based AI spam, it looks polished on the surface but quietly rots a
> project from the inside.

That is the thing we are removing. A change that adds a file, adds a contract,
adds an abstraction and does not delete anything is usually slop. A green gate
proves nothing ran, not that it worked — we have shipped five dead modules, 110
tests nobody executed and 186 unreachable lines, all green.

## 1. Never open a pull request. Ever.

Not a draft, not "just to show the diff". A PR on this repository can
auto-merge, and when it does, GitHub closes the agent's session and the agent
loses all remote access mid-task. This is exactly how agent B lost a finished
commit — 15 files, +1210/−37 — that never left its sandbox.

Push to your branch. The integrator pulls your branch by name. CI runs on every
branch (`on: push: branches: ["**"]`), so pushing is enough to be checked.

## 2. Probe the network in your first minute

Before writing a line of code:

```
git commit --allow-empty -m "wip: probe" && git push origin HEAD
```

If that fails, stop and report it. Finding out at the end of a four-hour task
that you cannot push is how work gets lost.

## 3. Push every increment

One file finished is one push. Never batch a session's work into a final push.
Your sandbox can die at any moment; the remote is the only thing that persists.

## 4. Stay in your lane

Every agent owns a disjoint set of files, listed in its brief. Do not edit a
file you do not own, even to fix an obvious bug — two agents editing one file is
a merge conflict in generated output that nobody can resolve safely.

If you need a change in someone else's file: append the request to
`docs/requests/<your-letter>.md`, **say it in your chat reply as well**, and
keep working around it.

Nobody edits `runtime/bundle.luau`. It is generated. The integrator regenerates
it. If it conflicts, take neither side — regenerate.

## 5. Findings go in the chat reply, not only in a file

Your sandbox dies with your session; the chat log does not. Anything you learned
that the next person needs — a remote's real name, a game's clamp, a mock gap —
goes in the reply you write to the user, in prose. Writing it only into
`docs/` has already lost us a full analysis once.

## 6. Run the gate before every push

```
LUAU_DIR=/tmp/luau-src/build bash tools/validate.sh
```

It must print `All checks passed.` `/tmp` does not survive between turns, so
you will have to rebuild Luau roughly every session — start it in the
background first thing, it takes 2-4 minutes:

```
export PATH="$HOME/.local/bin:$PATH"
command -v cmake >/dev/null || pip3 install --quiet --break-system-packages cmake
rm -rf /tmp/luau-src && git clone --depth 1 -b 0.732 https://github.com/luau-lang/luau.git /tmp/luau-src
cd /tmp/luau-src && cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --target Luau.Compile.CLI Luau.Repl.CLI Luau.Analyze.CLI -j4
```

## 7. A refactor does not change behaviour

If you move code, the menu does exactly what it did before, and you say so. If
you change behaviour, that is a separate commit with a separate message saying
what changed and why. A commit that does both is a commit nobody can review.

## 8. House style

- `--!strict` Luau, 4-space indent, explicit types on locals and parameters.
- Comments explain **why**, not what, and read as if the code always looked that
  way. A short "it used to do X, which broke Y" is the right voice; a comment
  restating the line below it is noise.
- Prose in English in code and docs. The user writes Spanish; reply in Spanish.
- Commit with `git commit -F` and a file or heredoc. Inline `-m` has broken on
  parentheses and quotes in this sandbox.

## 9. If something goes wrong

Stop coding. Print everything unpushed — full file contents, `git diff`,
`sha256sum` of each file — **before** diagnosing. Diagnosis is worthless if the
work evaporates while you do it. Then report what happened.

## 10. Known sandbox traps

- Git HEAD silently resets to the session's base commit while your working files
  stay on disk. Fix: `git fetch origin <your-branch> && git reset --soft
  FETCH_HEAD && git reset -q`. Anything pushed is safe.
- Directory names `dist/`, `build/`, `out/`, `node_modules/` are excluded from
  workspace snapshots. Generated output lives in `runtime/`.
- `luau-analyze` reports every free global as unknown, including `Enum`. That is
  expected; the global contract compensates by reading `env.d.luau`.
- `curl` to raw.githubusercontent is SSL-blocked. `gh api` works.
- Downloading CI logs is blocked. Verify CI by job step name and conclusion.

## 11. The licence, now that this is a Wurst port

Wurst7 is GPL-3.0 and its README says so in bold: the code may only be used in
open-source clients released under the same licence. Anything taken from
`Wurst-Imperium/Wurst7` — an asset, a string, an algorithm — carries that with
it. Do not vendor anything from it until `LICENSE` and `NOTICE.md` exist at the
repository root, and when you do vendor something, record where it came from and
at which upstream commit.

## 12. Sync to the integration branch before you read anything

Your session is cut from `main`, and `main` is this project before the refactor:
no `src/modules/`, no `src/library/`, no `docs/agents/`, a 16,000-line shell,
197 commits behind. Every file this brief tells you to read is missing there,
and every file you are asked to change has moved.

`main` is deliberately not being merged into — the loader ships from it, so
merging would push an unfinished rebuild to every user. Sync your own branch
instead, once, before doing anything else:

```
git fetch origin arena/01a01c6e-arandommenu
git reset --hard FETCH_HEAD
git fetch origin <your-branch>                 # refresh the lease's reference
git push --force-with-lease origin HEAD
```

The third line is not optional and its absence is not obvious. Bare
`--force-with-lease` refuses the push unless git already knows where your branch
is on the server, and after a reset it does not — the probe commit was created
before that knowledge existed, so the push is rejected with `stale info`, which
reads like an authentication problem and is not one.

You are staying on your own branch; you are giving it the right contents. Later,
to pick up integration work: `git fetch origin arena/01a01c6e-arandommenu &&
git merge FETCH_HEAD`.
