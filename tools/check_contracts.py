#!/usr/bin/env python3
"""Contracts between the shell and the modules it loads.

Three failures that a compiler cannot see, because every one of them is a table
lookup that returns nil at runtime and takes the module down with it:

  1. A module reads ``Options["X"]`` for a row it never created — which is what
     happens when a control is renamed and one call site is missed.
  2. A module reads ``state.x`` that nothing in the repository ever assigns.
  3. A game module calls a builder (``addToggleOption`` and friends) that the
     shell does not put in ``createGameModuleEnvironment``. A missing builder
     kills the module halfway through building its panel, which is how Kill
     Aura once rendered a "Weapon" heading with nothing underneath it.

Run from the repository root; prints every violation and exits non-zero.
"""

import glob
import math
import re
import sys

SHELL = "ARandomMenu.luau"
OPTION_BUILDERS = (
    "Toggle|Slider|TwoSlider|Dropdown|Bind|TextBox|Color|List|Button|Section"
)


def option_contract(sources: list, failures: list) -> None:
    for path in sources:
        text = open(path).read()
        created = set(
            re.findall(
                r"Create(?:" + OPTION_BUILDERS + r")"
                r"\(\{\s*\n?\s*Name\s*=\s*\"([^\"]+)\"",
                text,
            )
        )
        # Rows built for whatever a game registered are named at runtime, so
        # this file's reads cannot be resolved statically.
        dynamic = (
            "Name = extra.Name" in text
            or "Name = roleName" in text
            or "rowName" in text
        )
        if dynamic:
            continue
        # `options` is the local alias almost every module uses for
        # `module.Options`, so both spellings count as a read.
        for name in sorted(
            set(re.findall(r"[Oo]ptions\[\s*\"([^\"]+)\"\s*\]", text))
        ):
            if name not in created:
                failures.append(
                    f'{path}: reads Options["{name}"] but never creates that row'
                )


def dead_option_contract(sources: list, failures: list) -> None:
    """An option nobody reads and that does nothing is decoration.

    A menu grows into a wall of switches one plausible-looking option at a
    time, so an option has to earn its row: either the module reads it
    (`Options["Name"]`) or it carries a `Function` that does something when it
    changes. Anything else is a control that lies about having an effect.
    """
    builder = re.compile(
        r"Create(?:" + OPTION_BUILDERS + r")\(\{(.*?)\n(\s*)\}\)",
        re.S,
    )
    for path in sources:
        text = open(path).read()
        reads = set(re.findall(r"[Oo]ptions\[\s*\"([^\"]+)\"\s*\]", text))
        # A gate is read by the rows that depend on it, not by the module.
        reads |= set(re.findall(r"Option\s*=\s*\"([^\"]+)\"", text))
        if "rowName" in text or "extra.Name" in text or "roleName" in text:
            # Rows this module builds for whatever a game registered.
            continue
        for body in builder.findall(text):
            block = body[0]
            name_match = re.search(r"Name\s*=\s*\"([^\"]+)\"", block)
            if not name_match:
                continue
            name = name_match.group(1)
            if name in reads or "Function" in block:
                continue
            failures.append(
                f"{path}: option \"{name}\" is never read and has no Function — "
                "it does nothing"
            )


def state_contract(shell: str, sources: list, failures: list) -> None:
    writes = set(re.findall(r"\bstate\.(\w+)\s*=[^=]", shell))
    # Fields of the `state` table literal itself.
    writes |= set(re.findall(r"^\s{4}(\w+)\s*=", shell, re.M))
    for path in sources:
        text = open(path).read()
        writes |= set(re.findall(r"\bstate\.(\w+)\s*=[^=]", text))
        writes |= set(re.findall(r"host\.state\.(\w+)\s*=[^=]", text))

    first_read = {}
    for path in sources:
        text = open(path).read()
        for name in re.findall(r"\bstate\.(\w+)", text):
            first_read.setdefault(name, path)
    for name, path in sorted(first_read.items()):
        if name not in writes:
            failures.append(
                f"{path}: reads state.{name}, which nothing in the repository assigns"
            )


def environment_keys(shell: str) -> set:
    """Everything a downloaded file can reach through `host.` or as a global.

    Two sources, because the shell no longer owns all of it: the table
    `createGameModuleEnvironment` builds, plus the builders the widget library
    returns and the shell copies in by name. A builder renamed on one side and
    not the other reads as nil in every module at once.
    """
    environment = shell[
        shell.index("local function createGameModuleEnvironment") : shell.index(
            "local function loadGameModule"
        )
    ]
    exposed = set(re.findall(r"^\s{8}(\w+)\s*=", environment, re.M))
    widgets = open("src/library/Widgets.luau").read()
    returned = widgets[widgets.rindex("    return {") : widgets.rindex("\nend")]
    exposed |= set(re.findall(r"^\s{8}(\w+)\s*=", returned, re.M))
    # Anything else the loader folds into that same table after a library has
    # arrived — the card factory does this, because it is a library too and
    # lands after the environment was built.
    exposed |= set(re.findall(r"widgetBuilders\.(\w+)\s*=", shell))
    return exposed


def host_contract(shell: str, sources: list, failures: list) -> None:
    """Every `host.x` a downloaded file reads has to be something the shell puts there.

    Every file under src/ takes the same environment, and reads it by field
    rather than as a global, so a name the shell never published is nil the
    first time it is touched.

    This check used to look only at src/library/ and src/core/, and the hole
    cost a week: Spider, Anti-Void, Noclip, Anti-AFK and Fling all called
    `host.addFeatureTooltip` while building their card, got nil, and died
    mid-init. Five cards were absent from every client and the only trace was
    one warn each. Rejoin Server reads `host.cloneReference` inside its button
    handler, so it loaded fine and broke on the click instead — which is worse,
    because it looks present.
    """
    exposed = environment_keys(shell)
    for path in sources:
        if not path.startswith("src/"):
            continue
        for name in sorted(set(re.findall(r"host\.(\w+)", open(path).read()))):
            if name not in exposed:
                failures.append(
                    f"{path}: reads host.{name}, which the shell never publishes"
                )


def builder_contract(shell: str, failures: list) -> None:
    exposed = environment_keys(shell)

    used = set()
    declared = set()
    for path in glob.glob("src/games/*.luau"):
        text = open(path).read()
        used |= set(
            re.findall(r"(?<![\w.:])((?:add|create|register|make)\w+)\s*\(", text)
        )
        used |= set(re.findall(r"host\.((?:add|create|register|make)\w+)", text))
        declared |= set(re.findall(r"local\s+function\s+(\w+)", text))
        declared |= set(re.findall(r"local\s+(\w+)\s*[:=]", text))
    for name in sorted(used - exposed - declared):
        failures.append(
            f"src/games: calls {name}(), which neither "
            "createGameModuleEnvironment nor the widget library exposes"
        )


def state_index_contract(sources: list, failures: list) -> None:
    """Every key of the shared table is named and explained in state.d.luau.

    `state` is how everything reaches everything else, and its cost is not the
    number of keys but not knowing what is in it: two different things once
    ended up under `activeGameModule` and one of them silently won. Declaring a
    key means naming it beside everyone else's, which is the only thing that
    stops a shared table drifting back into a bag.

    It fails both ways round. An undeclared key is a value nobody can look up;
    a declared key nothing assigns is documentation describing a menu that does
    not exist.
    """
    index = open("state.d.luau").read()
    declared = set(re.findall(r"^    (\w+):", index, re.M))

    assigned = set()
    for path in ["ARandomMenu.luau"] + [p for p in sources if p.startswith("src/")]:
        assigned |= set(re.findall(r"\bstate\.(\w+)\s*=[^=]", open(path).read()))

    for name in sorted(assigned - declared):
        failures.append(
            f"state.{name} is assigned but not declared in state.d.luau — "
            "add a line saying what it is for"
        )
    for name in sorted(declared - assigned):
        failures.append(
            f"state.d.luau declares {name}, which nothing assigns any more — "
            "delete the line"
        )


def state_index_comment_contract(failures: list) -> None:
    """A declared key has to come with a reason, not a restatement of its name.

    Grouping is allowed: a run of keys under one comment (the per-game
    boards, the teardown hooks) share the line that introduced them. A key
    after a blank line with no comment of its own is a hole. A comment that
    is just the key again, or shorter than a short sentence, is padding.
    """
    text = open("state.d.luau").read()
    start = text.find("export type MenuState")
    end = text.find("\n}\n", start)
    if start < 0 or end < 0:
        failures.append("state.d.luau: MenuState type is missing")
        return
    body = text[start:end]
    last_commented = False
    for line in body.splitlines():
        match = re.match(r"^    (\w+):", line)
        if not match:
            if line.strip() == "":
                last_commented = False
            continue
        name = match.group(1)
        comment_match = re.search(r"--\s*(.*)$", line)
        if comment_match:
            comment = comment_match.group(1).strip()
            last_commented = True
            if len(comment) < 8:
                failures.append(
                    f"state.d.luau: state.{name} has a comment too short to "
                    f"explain it: {comment!r}"
                )
                continue
            normalised = re.sub(r"[^a-z0-9]", "", comment.lower())
            if normalised == name.lower():
                failures.append(
                    f"state.d.luau: state.{name} restates its own name "
                    "instead of saying what it is for"
                )
            continue
        if not last_commented:
            failures.append(
                f"state.d.luau: state.{name} has no comment and is not "
                "grouped under the previous one"
            )


def show_rule_contract(sources: list, failures: list) -> None:
    """A row that declares when it belongs on screen has to name a real option.

    `Show = {Option = "Mode", Values = {...}}` is how a row folds itself away
    under the mode that does not use it. The kernel resolves the name at
    refresh time, so a typo does not error — the rule never matches and the row
    is simply never visible again. It is the least visible way to lose a
    control: the card still says it has the setting.

    A name starting with `__` is the deliberate opposite: an always-false rule,
    used to retire a row so that no later refresh can bring it back.
    """
    for path in sources:
        if not (path.startswith("src/modules/") or path.startswith("src/games/")):
            continue
        text = open(path).read()
        declared = set(re.findall(r'Name\s*=\s*"([^"]+)"', text))
        for match in re.finditer(r'Option\s*=\s*"([^"]+)"', text):
            name = match.group(1)
            if name.startswith("__") or name in declared:
                continue
            line = text.count("\n", 0, match.start()) + 1
            failures.append(
                f'{path}:{line}: a Show rule names the option "{name}", '
                "which this file never creates"
            )


def connection_contract(shell: str, sources: list, failures: list) -> None:
    """Every named per-frame connection has to be disconnected somewhere.

    `featureConnections.X = TaskManager:Connect(...)` with no matching
    `disconnectFeatureConnection("X")` is a callback that survives its own
    module being switched off — the exact shape of every "it is still running
    after I turned it off" report.
    """
    for path in [SHELL] + sources:
        text = open(path).read()
        opened = set(re.findall(r"featureConnections\.(\w+)\s*=[^=]", text))
        closed = set(re.findall(r'disconnectFeatureConnection\("(\w+)"\)', text))
        # Modules that tear down a list of names in a loop mention each one as
        # a plain string instead.
        if "disconnectFeatureConnection(connectionName)" in text:
            closed |= set(re.findall(r'"(\w+)"', text))
        for name in sorted(opened - closed):
            failures.append(
                f"{path}: featureConnections.{name} is never disconnected"
            )


def card_name_contract(shell: str, failures: list) -> None:
    """Two cards with the same name would be two identical rows on one board.

    Only one game module is ever loaded at a time, so a game's names are
    checked against the shell's and the framework's, not against each other's.
    """
    pattern = r'createUniversalFeature\(\s*\n\s*"([^"]+)"'
    shell_cards = set(re.findall(pattern, shell))
    framework_cards = set()
    for path in glob.glob("src/modules/**/*.luau", recursive=True):
        framework_cards |= set(
            re.findall(
                r'CreateModule\(\{\s*\n\s*Name\s*=\s*"([^"]+)"',
                open(path).read(),
            )
        )
    universal = shell_cards | framework_cards
    for path in glob.glob("src/games/*.luau"):
        names = re.findall(pattern, open(path).read())
        for name in sorted(set(names) & universal):
            failures.append(
                f'{path}: card "{name}" already exists in the universal set'
            )
        for name in sorted({n for n in names if names.count(n) > 1}):
            failures.append(f'{path}: card "{name}" is registered twice')


def text_fits_contract(failures: list) -> None:
    """A label shorter than its own line box loses its descenders.

    Every label the helpers build clips to its frame, and `TextSize` is
    `normalSize * 1.35 * textScale`, so a 13-point label renders at 18px and
    needs about 22 pixels of room. The page header was 20 and the tail of the
    "g" in "Settings" was shaved off. The runtime caps the font size to the box
    as a safety net; this keeps the boxes honest so the net is never needed.
    """
    multiplier, line_box = 1.35, 1.2

    def needed(normal: int) -> int:
        return math.ceil(round(normal * multiplier) * line_box) + 1

    builder = re.compile(
        r"\b(?:host\.)?(?:makeTextLabel|makeButton)\(\s*[^,]+,.*?,\s*(\d+)\s*\)"
    )
    for path in ["ARandomMenu.luau"] + sorted(
        glob.glob("src/**/*.luau", recursive=True)
    ):
        lines = open(path).read().split("\n")
        for index, line in enumerate(lines):
            call = builder.search(line)
            if not call:
                continue
            name = None
            for probe in (line, lines[index - 1] if index else ""):
                found = re.search(r"local\s+(\w+)\s*[:=]", probe)
                if found:
                    name = found.group(1)
                    break
            if not name:
                continue
            want = needed(int(call.group(1)))
            window = "\n".join(lines[index : index + 16])
            # `UDim2.new` is often written across five lines, so the height
            # search has to read through newlines.
            heights = re.findall(
                re.escape(name)
                + r"\.Size\s*=\s*UDim2\.fromOffset\(\s*[^,]+?,\s*(\d+)\s*\)",
                window,
                re.S,
            )
            heights += re.findall(
                re.escape(name)
                + r"\.Size\s*=\s*UDim2\.new\(.*?,\s*0\s*,\s*(\d+)\s*\)",
                window,
                re.S,
            )
            for height in heights:
                if int(height) < want:
                    failures.append(
                        f"{path}:{index + 1}: {name} is {height}px tall but its "
                        f"text needs {want}px, so it will be clipped"
                    )


def loader_contract(shell: str, failures: list) -> None:
    """The 10-second boot is a contract, not a vibe.

    GUID cache-busting, a blocking fingerprint wait and a missing disk write
    are the three things that made a second launch as expensive as the first.
    """
    if "GenerateGUID" in shell:
        failures.append("ARandomMenu.luau: still cache-busts with GenerateGUID")
    if "?nocache=" in shell:
        failures.append("ARandomMenu.luau: still uses ?nocache=")
    if "while not detected and attempts < 6 do" in shell:
        failures.append(
            "ARandomMenu.luau: fingerprint still blocks bootstrap for 3s"
        )
    if "fetchRepositorySource" not in shell or "runtime/bundle.luau" not in shell:
        failures.append("ARandomMenu.luau: bundle fetch path is missing")
    if "writeCachedSource" not in shell:
        failures.append("ARandomMenu.luau: disk cache is never written")
    if "[RTM:Timing]" not in shell:
        failures.append("ARandomMenu.luau: bootstrap timing summary is missing")


def main() -> int:
    shell = open(SHELL).read()
    sources = sorted(glob.glob("src/**/*.luau", recursive=True))
    failures: list = []

    option_contract(sources, failures)
    dead_option_contract(sources, failures)
    state_contract(shell, sources, failures)
    builder_contract(shell, failures)
    host_contract(shell, sources, failures)
    state_index_contract(sources, failures)
    show_rule_contract(sources, failures)
    connection_contract(shell, sources, failures)
    card_name_contract(shell, failures)
    text_fits_contract(failures)
    loader_contract(shell, failures)

    if failures:
        for line in failures:
            print("  " + line)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
