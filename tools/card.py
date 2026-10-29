#!/usr/bin/env python3
"""Add, remove, rename or re-window a card without touching five files by hand.

v138.9 moved the whole catalog into one file, src/libraries/Manifest.lua, and
removed the duplicated fallbackManifest from Wurst.lua. This tool is the front
door to that catalog:

    python3 tools/card.py list
    python3 tools/card.py list --category Combat

    # register an existing module file (universal section)
    python3 tools/card.py add "Combat Logger" --category Combat \\
        --path src/games/universal/Combat/CombatLogger.lua

    # same, and write a compilable module skeleton first
    python3 tools/card.py add "Combat Logger" --category Combat --stub

    # MM2 / any other game section
    python3 tools/card.py add "Auto Thing" --game MM2 --category Utilities \\
        --path src/games/MM2/Other/AutoThing.lua --stub

    # which window a card shows up in (only needed when the card does not pass
    # categoryName itself)
    python3 tools/card.py window "Coin ESP" Render

    # remove it again
    python3 tools/card.py remove "Combat Logger" --delete-file

Every command rewrites the catalog in a canonical, alphabetically sorted form,
so two people adding cards never produce a merge conflict in the middle of the
list. Run tools/validate.sh afterwards; tools/test_registry.py checks that the
catalog and the disk agree.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "src" / "libraries" / "Manifest.lua"

MODULES_OPEN = "        -- <arandommenu:modules> managed by tools/card.py\n"
MODULES_CLOSE = "        -- </arandommenu:modules>\n"
CARDS_OPEN = "        -- <arandommenu:cards> managed by tools/card.py\n"
CARDS_CLOSE = "        -- </arandommenu:cards>\n"

ENTRY = re.compile(r'\{path = "([^"]+)", name = "([^"]+)", category = "([^"]+)"\}')
MULTILINE = re.compile(
    r'\{\s*path = "([^"]+)",\s*name = "([^"]+)",\s*category = "([^"]+)",?\s*\}'
)
CARD = re.compile(r'\["([^"]+)"\] = "([^"]+)"')
GAME_BLOCK = re.compile(r'(\n        (\w+) = \{\n)(.*?)(\n        \},)', re.S)


def read() -> str:
    return MANIFEST.read_text(encoding="utf-8")


def write(text: str) -> None:
    MANIFEST.write_text(text, encoding="utf-8")


def catalog_categories(text: str) -> tuple[list[str], dict[str, str]]:
    block = text[text.index("categories = {"): text.index("cards = {")]
    order = re.findall(r'^\s{12}"([^"]+)",\s*$', block, re.M)
    aliases = dict(re.findall(r'\["([^"]+)"\] = "([^"]+)",', block))
    return order, aliases


def normalize(category: str, order: list[str], aliases: dict[str, str]) -> str:
    if category in order:
        return category
    if category in aliases:
        return aliases[category]
    raise SystemExit(
        f"unknown category {category!r}; pick one of {', '.join(order)}"
    )


def parse_modules(text: str) -> tuple[list[tuple[str, str, str]], str]:
    """Return the universal entries, the game entries and the game block text."""
    start = text.index(MODULES_OPEN)
    end = text.index(MODULES_CLOSE)
    body = text[start:end]
    entries = [(m.group(1), m.group(2), m.group(3)) for m in MULTILINE.finditer(body)]
    # game sections inside the same table: "        MM2 = { ... },"
    game_start = text.index("    gameModules = {")
    game_block = text[game_start: text.index("\n    },\n}", game_start)]
    return entries, game_block


def rewrite_modules(text: str, entries: list[tuple[str, str, str]]) -> str:
    start = text.index(MODULES_OPEN) + len(MODULES_OPEN)
    end = text.index(MODULES_CLOSE)
    entries = sorted(entries, key=lambda item: (item[1].lower(), item[0]))
    lines = []
    for path, name, category in entries:
        lines.append(
            f'        {{path = "{path}", name = "{name}", category = "{category}"}},\n'
        )
    return text[:start] + "".join(lines) + text[end:]


def rewrite_cards(text: str, cards: dict[str, str]) -> str:
    start = text.index(CARDS_OPEN) + len(CARDS_OPEN)
    end = text.index(CARDS_CLOSE)
    lines = [f'        ["{key}"] = "{cards[key]}",\n' for key in sorted(cards)]
    return text[:start] + "".join(lines) + text[end:]


def card_map(text: str) -> dict[str, str]:
    start = text.index(CARDS_OPEN)
    end = text.index(CARDS_CLOSE)
    return dict(CARD.findall(text[start:end]))


def game_paths(text: str, game: str) -> list[str]:
    match = re.search(rf"\n        {game} = \{{\n(.*?)\n        \}},", text, re.S)
    if not match:
        raise SystemExit(f"no game section named {game!r} in the catalog")
    return re.findall(r'"([^"]+)"', match.group(1))


def write_game_section(text: str, game: str, paths: list[str]) -> str:
    match = re.search(rf"(\n        {game} = \{{\n)(.*?)(\n        \}},)", text, re.S)
    assert match, game
    body = "".join(f'            "{path}",\n' for path in sorted(paths))
    return text[: match.start(2)] + body.rstrip("\n") + text[match.end(2):]


def module_name_of(path: str) -> str:
    return Path(path).stem


STUB = """local Module = {
    Name = "%(name)s",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: any): any
    local host: any = context.host
    local createUniversalFeature: any = host.createUniversalFeature

    local enabled: boolean = false

    local feature: any = createUniversalFeature(
        "%(name)s",
        "TODO: describe this card.",
        60,
        function(value: boolean): ()
            enabled = value == true
        end,
        {categoryName = "%(category)s"}
    )

    activeCleanup = function(): ()
        enabled = false
    end
    Module.Initialized = true
    return feature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
"""


def cmd_list(args: argparse.Namespace) -> int:
    text = read()
    entries, _ = parse_modules(text)
    cards = card_map(text)
    rows = []
    for path, name, category in sorted(entries, key=lambda item: item[1].lower()):
        if args.category and category != args.category:
            continue
        rows.append((category, name, path))
    for category, name, path in rows:
        print(f"{category:<10} {name:<28} {path}")
    print(f"\n{len(rows)} modules, {len(cards)} card windows")
    return 0


def cmd_add(args: argparse.Namespace) -> int:
    text = read()
    order, aliases = catalog_categories(text)
    category = normalize(args.category, order, aliases)
    path = args.path
    if args.game:
        paths = game_paths(text, args.game)
        if path is None:
            path = f"src/games/{args.game}/Other/{args.stub_name}.lua"
        if path in paths:
            raise SystemExit(f"{path} is already registered in {args.game}")
        target = ROOT / path
        if not target.is_file():
            if not args.stub:
                raise SystemExit(f"{path} does not exist (pass --stub to create it)")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(
                STUB % {"name": args.stub_name, "category": category}, encoding="utf-8"
            )
            print(f"created {path}")
        text = write_game_section(text, args.game, paths + [path])
        write(text)
        print(f"registered {path} in game section {args.game}")
        return 0

    entries, _ = parse_modules(text)
    if path is None:
        path = f"src/games/universal/{category}/{args.stub_name}.lua"
    if any(entry[0] == path for entry in entries):
        raise SystemExit(f"{path} is already in the catalog")
    target = ROOT / path
    exists = target.is_file()
    if not exists and not args.stub:
        raise SystemExit(f"{path} does not exist (pass --stub to create it)")
    if not exists:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(
            STUB % {"name": args.stub_name, "category": category}, encoding="utf-8"
        )
        print(f"created {path}")
    entries.append((path, args.stub_name, category))
    text = rewrite_modules(text, entries)
    cards = card_map(text)
    cards[args.stub_name] = category
    text = rewrite_cards(text, cards)
    write(text)
    print(f"registered {args.stub_name} in {category} ({path})")
    print("next: implement the module, then run bash tools/validate.sh")
    return 0


def cmd_remove(args: argparse.Namespace) -> int:
    text = read()
    removed = False
    entries, _ = parse_modules(text)
    kept = [entry for entry in entries if entry[1] != args.name]
    if len(kept) != len(entries):
        text = rewrite_modules(text, kept)
        removed = True
    for game in ("MM2", "VD", "BedFight", "X2Duels", "TRS", "BedWars", "MVSD"):
        try:
            paths = game_paths(text, game)
        except SystemExit:
            continue
        matching = [p for p in paths if module_name_of(p).lower() == args.name.lower()
                    or p == args.path]
        if matching:
            text = write_game_section(text, game, [p for p in paths if p not in matching])
            removed = True
            print(f"removed {', '.join(matching)} from {game}")
    cards = card_map(text)
    if args.name in cards:
        del cards[args.name]
        text = rewrite_cards(text, cards)
        removed = True
    if not removed:
        raise SystemExit(f"no module or card named {args.name!r} in the catalog")
    write(text)
    if args.delete_file:
        for entry in entries:
            if entry[1] == args.name:
                target = ROOT / entry[0]
                if target.is_file():
                    target.unlink()
                    print(f"deleted {entry[0]}")
    print(f"removed {args.name}")
    return 0


def cmd_window(args: argparse.Namespace) -> int:
    text = read()
    order, aliases = catalog_categories(text)
    category = normalize(args.category, order, aliases)
    cards = card_map(text)
    cards[args.name] = category
    write(rewrite_cards(text, cards))
    print(f"{args.name} now shows up in {category}")
    return 0


def cmd_check(args: argparse.Namespace) -> int:
    text = read()
    order, aliases = catalog_categories(text)
    entries, _ = parse_modules(text)
    problems = []
    seen = {}
    for path, name, category in entries:
        if path in seen:
            problems.append(f"duplicate path {path}")
        seen[path] = name
        if not (ROOT / path).is_file():
            problems.append(f"missing file {path}")
        if category not in order:
            problems.append(f"{name}: category {category} is not in categories.order")
    cards = card_map(text)
    for name, category in cards.items():
        if category not in order and category not in aliases:
            problems.append(f"card {name}: unknown window {category}")
    for game in ("MM2", "VD", "BedFight", "X2Duels", "TRS", "BedWars", "MVSD"):
        try:
            paths = game_paths(text, game)
        except SystemExit:
            continue
        for path in paths:
            if not (ROOT / path).is_file():
                problems.append(f"{game}: missing file {path}")
    if problems:
        print("catalog problems:")
        for problem in problems:
            print("  -", problem)
        return 1
    print(f"catalog OK: {len(entries)} universal modules, {len(cards)} card windows")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    listing = sub.add_parser("list", help="show every registered module")
    listing.add_argument("--category")
    listing.set_defaults(func=cmd_list)

    add = sub.add_parser("add", help="register a module (and optionally a card)")
    add.add_argument("name")
    add.add_argument("--category", required=True)
    add.add_argument("--path")
    add.add_argument("--game", help="MM2, VD, BedFight, X2Duels, TRS, ...")
    add.add_argument("--stub", action="store_true", help="create a module skeleton")
    add.set_defaults(func=cmd_add)

    remove = sub.add_parser("remove", help="unregister a module/card")
    remove.add_argument("name")
    remove.add_argument("--path")
    remove.add_argument("--delete-file", action="store_true")
    remove.set_defaults(func=cmd_remove)

    window = sub.add_parser("window", help="set the window a card shows up in")
    window.add_argument("name")
    window.add_argument("category")
    window.set_defaults(func=cmd_window)

    check = sub.add_parser("check", help="verify the catalog against the disk")
    check.set_defaults(func=cmd_check)

    args = parser.parse_args(argv)
    if hasattr(args, "name") and args.command == "add":
        args.stub_name = args.name
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
