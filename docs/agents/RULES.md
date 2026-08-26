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

## 2b. Run the pre-flight before every commit

```
bash tools/preflight.sh
```

The sandbox silently resets HEAD to the session's base commit while your working
files stay on disk. Committing without noticing produces a commit whose diff
deletes work that is already pushed. The script checks one thing — that HEAD is
built on what is actually on the server — and tells you how to recover if it is
not.

## 2a. The integration branch is `arena/01a03bca-arandommenu`

It used to be `arena/01a02c8a-arandommenu`, and that name is still written in
older briefs and in commit messages. It moved because an Arena session is pinned
to the branch Arena created for it: the integrator session that owned the old
name is gone, and no new session can push to it. The current integrator seeded
its own branch by fast-forwarding the old tip (`24b4c9d`) into
`arena/01a03bca-arandommenu`, so **no history was lost and nothing needs
rebasing** — the old name is a prefix of the new one.

Read it as: wherever an older document says `arena/01a02c8a-arandommenu`, the
branch to fetch, base on and hand work back to is
`arena/01a03bca-arandommenu`. It will move again the next time the integrator
session is replaced; the tip is always whichever `arena/*` branch the integrator
names in its reply, and its contents always contain the previous one.

## 2c. Two people share the integration branch

The integrator and the reviewer both push to `arena/01a03bca-arandommenu`. That
is deliberate — it means the interface work never has to be merged — and it has
one hazard: the branch can move under you between your last fetch and your push.

When a push is rejected with `fetch first`, **never force**. The other person's
commit is not a mistake to overwrite:

```
git fetch origin arena/01a03bca-arandommenu
git merge FETCH_HEAD                 # or: git stash -u; git reset --hard FETCH_HEAD; git stash pop
python3 tools/bundle.py              # the only conflicts are generated; regenerate, never pick a side
bash tools/preflight.sh <your-branch>
LUAU_DIR=/tmp/luau-src bash tools/validate.sh
git push origin HEAD
```

Push small and push often. A five-minute increment merges cleanly; an
afternoon's work in one commit is an afternoon of conflicts in a file neither of
you can read.

## 3. Push every increment

One file finished is one push. Never batch a session's work into a final push.
Your sandbox can die at any moment; the remote is the only thing that persists.

## 4. Stay in your lane

Every agent owns a disjoint set of files, listed in its brief. **A suite that
tests a module belongs to whoever owns the module** — a fix and the test that
proves it have to land in the same green commit, and they cannot if two agents
own the two halves. Do not edit a
file you do not own, even to fix an obvious bug — two agents editing one file is
a merge conflict in generated output that nobody can resolve safely.

If you need a change in someone else's file: append the request to
`docs/requests/<your-letter>.md`, **say it in your chat reply as well**, and
keep working around it.

**Regenerating the bundle is not editing the shell.** `python3 tools/bundle.py`
rewrites `runtime/bundle.luau` and one stamp line in `ARandomMenu.luau`, both of
which are generated from your sources. Run it whenever the gate tells you the
stamp is stale, and commit both files with your change — the alternative is what
happened the first time this was unclear: an agent finished a correct increment
and then sat on it because it read "do not edit the shell" as "do not run the
generator".

Never hand-edit either file, and never resolve a conflict inside them: take
neither side and regenerate.

## 5. Findings go in the chat reply, not only in a file

Your sandbox dies with your session; the chat log does not. Anything you learned
that the next person needs — a remote's real name, a game's clamp, a mock gap —
goes in the reply you write to the user, in prose. Writing it only into
`docs/` has already lost us a full analysis once.

## 6. Run the gate before every push

```
LUAU_DIR=/tmp/luau-src bash tools/validate.sh
```

It must print `All checks passed.` `/tmp` does not survive between turns, so
you will have to rebuild Luau roughly every session — start it in the
background first thing, it takes 2-4 minutes:

```
rm -rf /tmp/luau-src && git clone --depth 1 -b 0.732 https://github.com/luau-lang/luau.git /tmp/luau-src
make -C /tmp/luau-src config=release luau luau-compile luau-analyze -j2
```

Use the Makefile, not CMake. Recent sandboxes ship no `cmake` at all and the
`pip3 install cmake` line this rule used to carry is one more thing that can
fail before the build even starts; upstream's Makefile needs only `g++` and
`make`, which are always present. It leaves the three binaries symlinked at
`/tmp/luau-src/luau*`, so `LUAU_DIR=/tmp/luau-src` — without the `/build`
suffix the old recipe produced. `-j2` matches the two cores the sandbox
actually has; a higher number only oversubscribes them.

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
git fetch origin arena/01a03bca-arandommenu
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
to pick up integration work: `git fetch origin arena/01a03bca-arandommenu &&
git merge FETCH_HEAD`.
