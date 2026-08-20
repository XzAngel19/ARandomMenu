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


def builder_contract(shell: str, failures: list) -> None:
    environment = shell[
        shell.index("local function createGameModuleEnvironment") : shell.index(
            "local function loadGameModule"
        )
    ]
    exposed = set(re.findall(r"^\s{8}(\w+)\s*=", environment, re.M))

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
            f"src/games: calls {name}(), which createGameModuleEnvironment "
            "does not expose"
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


def main() -> int:
    shell = open(SHELL).read()
    sources = sorted(glob.glob("src/**/*.luau", recursive=True))
    failures: list = []

    option_contract(sources, failures)
    state_contract(shell, sources, failures)
    builder_contract(shell, failures)
    connection_contract(shell, sources, failures)
    card_name_contract(shell, failures)

    if failures:
        for line in failures:
            print("  " + line)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
