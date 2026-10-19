"""Dump the menu the bundle actually builds, instead of grepping for strings.

    python3 tools/audit_menu.py            # Markdown table on stdout
    python3 tools/audit_menu.py --json     # one JSON object per line

The probe reuses the mocked executor environment from gen_full_boot_harness,
boots the real bundle and then walks every feature in `allFeatures`, printing
the section, the category, the card and every row in the order the user sees
them. Static greps cannot answer "is this feature still in the menu?" after a
refactor: a module can compile, ship and never be registered.

Needs LUAU (same variable validate.sh uses) to run the generated harness.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import gen_full_boot_harness as harness

ROOT = harness.ROOT
OUT = ROOT / "build" / "menu_dump.luau"

PROBE = r'''
if not ok then error("[AUDIT] WURST TOP-LEVEL CRASH: " .. tostring(err)) end
local ex = GENV.__expose
assert(ex and type(ex.allFeatures) == "table", "[AUDIT] allFeatures was not exposed")

local function attribute(instance, name)
    local okCall, value = pcall(function() return instance:GetAttribute(name) end)
    if okCall and type(value) == "string" then return value end
    return nil
end

local function rowLabel(row)
    local children = row.children or (row.GetChildren and row:GetChildren()) or {}
    for _, child in ipairs(children) do
        local name = (child.props and child.props.Name) or child.Name
        if name == "OptionLabel" then
            local text = (child.props and child.props.Text) or child.Text
            if type(text) == "string" then return text end
        end
    end
    local name = (row.props and row.props.Name) or row.Name or ""
    return (name:gsub("^Option_", ""))
end

local total = 0
for _, feature in ipairs(ex.allFeatures) do
    print(string.format("[CARD]\t%s\t%s\t%s\t%s\t%s",
        tostring(feature.sectionName), tostring(feature.categoryName),
        tostring(feature.kind), tostring(feature.name), tostring(feature.configKey)))
    for _, row in ipairs(feature.optionRows or {}) do
        local rowName = (row.props and row.props.Name) or row.Name or ""
        if string.sub(rowName, 1, 8) == "Section_" then
            print("[HEAD]\t" .. (attribute(row, "SectionTitle") or rowName:gsub("^Section_", "")))
        else
            local visible = (row.props and row.props.Visible)
            if visible == nil then visible = row.Visible end
            print(string.format("[OPT]\t%s\t%s", rowLabel(row), tostring(visible ~= false)))
            total = total + 1
        end
    end
end
print("[AUDIT] cards\t" .. tostring(#ex.allFeatures) .. "\trows\t" .. tostring(total))
'''


def build() -> Path:
    bundle = (ROOT / "src/libraries/bundle.lua").read_text(encoding="utf-8")
    wurst = (ROOT / "src/Wurst.lua").read_text(encoding="utf-8")

    anchor = "state.frameworkEnvironment = createGameModuleEnvironment(diagnostics)"
    assert wurst.count(anchor) == 1, "framework env anchor missing"
    expose = (
        'do local __g = getgenv() if type(__g) == "table" '
        "then __g.__expose = {ThemeEngine = ThemeEngine, Theme = Theme, "
        "state = state, configData = configData, "
        "allFeatures = allFeatures} end end\n"
    )
    wurst = wurst.replace(anchor, expose + anchor)

    parts = [
        harness.PRELUDE,
        "SOURCES = {\n",
        f'    ["src/libraries/bundle.lua"] = {harness.long_bracket(bundle)},\n',
        "}\n",
        'SOURCES["src/Wurst.lua"] = nil\n',
        "GENV.WURST_DEBUG = true\n",
        "\nlocal ok, err = pcall(function()\n",
        wurst,
        "\nend)\n",
        PROBE,
    ]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("".join(parts), encoding="utf-8")
    return OUT


def run(path: Path) -> str:
    luau = os.environ.get("LUAU", "luau")
    result = subprocess.run([luau, str(path)], capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(
            f"harness failed ({result.returncode})\n{result.stdout}\n{result.stderr}"
        )
    return result.stdout


def parse(output: str):
    cards = []
    for line in output.splitlines():
        if line.startswith("[CARD]\t"):
            _, section, category, kind, name, key = line.split("\t")
            cards.append(
                {"section": section, "category": category, "kind": kind,
                 "name": name, "configKey": key, "rows": []}
            )
        elif line.startswith("[HEAD]\t") and cards:
            cards[-1]["rows"].append({"kind": "head", "label": line.split("\t", 1)[1]})
        elif line.startswith("[OPT]\t") and cards:
            _, label, visible = line.split("\t")
            cards[-1]["rows"].append(
                {"kind": "option", "label": label, "visible": visible == "true"}
            )
    return cards


def as_json(cards) -> None:
    for card in cards:
        print(json.dumps(card, ensure_ascii=False))


def as_markdown(cards) -> None:
    sections = {}
    for card in cards:
        sections.setdefault(card["section"], []).append(card)
    for section in sorted(sections):
        print(f"\n## {section} ({len(sections[section])} cards)\n")
        for card in sections[section]:
            options = [row["label"] for row in card["rows"] if row["kind"] == "option"]
            heads = [row["label"] for row in card["rows"] if row["kind"] == "head"]
            kind = "" if card["kind"] == "toggle" else f" [{card['kind']}]"
            print(f"- **{card['name']}**{kind} — `{card['category']}` — {len(options)} options")
            if heads:
                print(f"  - sections: {', '.join(heads)}")
            if options:
                print(f"  - {', '.join(options)}")


def main() -> None:
    path = build()
    output = run(path)
    cards = parse(output)
    if "--json" in sys.argv:
        as_json(cards)
    else:
        as_markdown(cards)
        print(f"\n{len(cards)} cards total")


if __name__ == "__main__":
    main()
