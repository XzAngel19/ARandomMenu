# Writing a module

The menu is easy to add to, and that is the danger: a menu grows into a list of
switches nobody understands one plausible-looking option at a time. These are
the questions to answer before writing any of it, and the rules the answers
have to satisfy. They are the repository's, not a suggestion — the build
enforces the ones that can be enforced.

## 1. Before writing anything

**What is this module, in one sentence?** If the sentence needs an "and", it is
two modules or it is one module with a setting.

**Is there a reference?** Vape's universal build is vendored at
`reference/vape-v4-universal.lua.txt`, the BedFight place dump and captured
remote traffic are next to it. Read the reference first. It is a source of
information, not something to copy: the point is to learn *which facts the
module needs* (which remote, which state, which part of the character), then
write it against this menu's own kernel.

**No reference, and no certainty it can work?** Say so. Look for one — another
menu, a repository, a live capture through Remote Logger. Still nothing? Then
ask for what is missing (a place id, a remote name, a screenshot of the game's
own UI) or say plainly that the module may not work and why. A module that
half-works is worse than an honest "this needs X first", because the person
using it cannot tell the difference between a broken module and a broken game.

## 2. Designing the options

**Does this option help in a way the defaults do not already?** If the answer
is "it lets you turn off something nobody turns off", it is not an option, it
is a default.

**Would two options be one option with a better name?** "Attack colour" and
"Reach colour" were one colour and a dim. "Minimum CPS" and "Maximum CPS" were
one range. "Delay" and "Delay jitter" were one delay that varies, because a
delay that never varies is a signature and nobody wants it.

**Can it be on screen only when it matters?** Then say so, declaratively:

```lua
teleport:CreateTextBox({
    Name = "Player",
    Show = {Option = "Destination", Values = {"Named player"}},
})
```

`Show` accepts one rule, or a list of rules that all have to hold. Omitting
`Values` means "while that option is on", which is how a toggle gates a block.
The kernel hides and reveals the row; the module never calls `SetVisible`
itself and never keeps a list of its own rows.

**Does every option actually do something?** An option that is neither read
(`Options["Name"]`) nor given a `Function` fails the build. That check exists
because decoration is exactly what a menu accumulates.

**Is the technically correct answer the boring one?** Take it. Creativity
belongs in what the module does, not in how many ways it can be configured.

## 3. Changing the design

**Is the design actually wrong, or just unfamiliar?** Look at what good menus
do before redrawing anything: Vape's shell, the menus in this account's other
repositories (`Gurtdeo`, `Reposit`, `mm2testv2` — all variants of the same
YARHM build, worth reading for their spring animations, ripples and `UIScale`
press feedback).

**Can the asset be found rather than invented?** Vape's repository ships its
own art, and the reference dump is already vendored here. Search for images,
animations, fonts and effects before generating them, and keep whatever is
downloaded in `src/gui/Current/Assets` with an entry in the manifest — the
build fails if the manifest points at a file that does not exist, and unused
art gets deleted.

**Does it still perform?** Every drawing path is per-frame code in somebody
else's game. Cache what does not change per frame, reject by distance before
projecting anything, and never scan `workspace:GetDescendants()` on a timer if
an index maintained by `DescendantAdded` will do.

## 4. Before pushing

```
LUAU_DIR=/path/to/luau bash tools/validate.sh
```

That is JSON manifests, source layout, the module contracts, asset existence,
text containment, strict headers, the loader guard, compilation at two
optimisation levels, the scope lints, the register-headroom probe and the
headless tests. All of it, in one command, and the workflow runs the same list.
