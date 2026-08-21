#!/usr/bin/env python3
"""Build docs/design/prototype/spec.json from the ClickGUI prototype.

The prototype is the specification. A hand-copied numbers file is wrong
within a week; this script parses the :root block and the component rules
and writes what it found. The gate re-runs it and fails if the committed
JSON drifted, then checks the Luau widgets against the same numbers.

ThemeEngine.shape is the counterpart for the shape tokens. Named constants
in Widgets.luau are the counterpart for slider / knob / label / delay
metrics. A constant that exists with the wrong value fails and names both
sides. A constant that does not exist yet is owed (LAUNCH.md) and cannot
fail the gate until the integrator adds it — C cannot edit Widgets.luau.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

PROTOTYPE = "docs/design/prototype/index.html"
SPEC = "docs/design/prototype/spec.json"
SHELL = "ARandomMenu.luau"
WIDGETS = "src/library/Widgets.luau"
WINDOWS = "src/library/WindowManager.luau"

# CSS custom property -> ThemeEngine.shape field. The names on the Luau
# side are the ones the brief listed; the CSS names are what the prototype
# actually uses.
SHAPE_FROM_ROOT = {
    "opacity": "opacity",
    "tip-opacity": "tooltipOpacity",
    "radius": "radius",
    "row-h": "rowHeight",
    "border-w": "borderThickness",
    "max-h": "maxHeight",
    "scale": "scale",
}

# Prototype numbers that are not shape tokens. The gate looks for a named
# constant in Widgets.luau (ALL_CAPS, type number). Until the integrator
# exposes them, a miss is reported with both names and fails the step —
# that is the point of the gate. Shape is checked separately because it
# already has a counterpart.
#
# tooltipDelayMs lives in the prototype's JS (bindTip's setTimeout), not
# in CSS; it is still a number the widgets have to match.
WIDGET_CONSTANTS = {
    "titleHeight": "TITLE_HEIGHT",
    "gap": "WINDOW_GAP",
    "snapDistance": "SNAP_DISTANCE",
    "sliderBarHeight": "SLIDER_BAR_HEIGHT",
    "sliderKnobWidth": "SLIDER_KNOB_WIDTH",
    "sliderKnobHeight": "SLIDER_KNOB_HEIGHT",
    "titleFontSize": "TITLE_FONT_SIZE",
    "labelFontSize": "LABEL_FONT_SIZE",
    "tooltipDelayMs": "TOOLTIP_DELAY_MS",
    "transitionFast": "TRANSITION_FAST",
    "transitionSlow": "TRANSITION_SLOW",
}


def css_number(value: str):
    """Parse a CSS numeric value into int or float; leave colours/fonts."""
    text = value.strip()
    if text.endswith("px") or text.endswith("ms") or text.endswith("s"):
        unit = "px" if text.endswith("px") else ("ms" if text.endswith("ms") else "s")
        raw = text[: -len(unit)]
        try:
            number = float(raw) if "." in raw or raw.startswith(".") else int(raw)
        except ValueError:
            return text
        if unit == "s":
            return float(number)
        return int(number) if float(number) == int(number) else float(number)
    if re.fullmatch(r"-?\d+", text):
        return int(text)
    if re.fullmatch(r"-?\d*\.\d+", text) or re.fullmatch(r"-?\.\d+", text):
        return float(text)
    return text


def parse_root(html: str) -> dict:
    match = re.search(r":root\s*\{(.*?)\n\}", html, re.S)
    if not match:
        raise SystemExit(f"{PROTOTYPE}: no :root block")
    tokens = {}
    for name, value in re.findall(r"--([\w-]+)\s*:\s*([^;]+);", match.group(1)):
        tokens[name] = css_number(value)
    return tokens


def rule_body(html: str, selector: str) -> str:
    """First rule body for an exact selector in the <style> block."""
    style = html
    head = html.find("<style>")
    tail = html.find("</style>")
    if head >= 0 and tail > head:
        style = html[head:tail]
    pattern = re.escape(selector) + r"\{([^}]+)\}"
    match = re.search(pattern, style)
    if not match:
        raise SystemExit(f"{PROTOTYPE}: no rule for {selector}")
    return match.group(1)


def rule_number(body: str, property_name: str):
    match = re.search(rf"{re.escape(property_name)}\s*:\s*([^;]+)", body)
    if not match:
        raise SystemExit(f"{PROTOTYPE}: {property_name} missing from rule")
    return css_number(match.group(1).split()[0])


def parse_snap_distance(html: str) -> int:
    # The prototype's drag handler, not CSS: within S8 pixels of an edge
    # the window lands flush. WindowManager.SNAP_DISTANCE is the counterpart.
    match = re.search(r"const S8\s*=\s*(\d+)", html)
    if not match:
        raise SystemExit(f"{PROTOTYPE}: snap distance S8 not found")
    return int(match.group(1))


def parse_tooltip_delay(html: str) -> int:
    match = re.search(
        r"function bindTip\(.*?setTimeout\(\(\)=>\{.*?},\s*(\d+)\);",
        html,
        re.S,
    )
    if not match:
        raise SystemExit(f"{PROTOTYPE}: bindTip delay not found")
    return int(match.group(1))


def parse_transition_seconds(declaration: str) -> float:
    match = re.search(r"(\d*\.\d+|\d+)s", declaration)
    if not match:
        raise SystemExit(f"{PROTOTYPE}: no duration in {declaration!r}")
    return float(match.group(1))


def build_spec(html: str) -> dict:
    root = parse_root(html)
    missing = [css for css in SHAPE_FROM_ROOT if css not in root]
    if missing:
        raise SystemExit(f"{PROTOTYPE}: :root is missing {', '.join(missing)}")

    shape = {}
    for css_name, luau_name in SHAPE_FROM_ROOT.items():
        value = root[css_name]
        if not isinstance(value, (int, float)):
            raise SystemExit(
                f"{PROTOTYPE}: --{css_name} is {value!r}, expected a number"
            )
        shape[luau_name] = value

    bar = rule_body(html, ".bar")
    knob = rule_body(html, ".bar .knob")
    title_bar = rule_body(html, ".tbar")
    line = rule_body(html, ".line")
    row = rule_body(html, ".row")
    toast = rule_body(html, ".toast")

    chrome = {
        "titleHeight": root["title-h"],
        "gap": root["gap"],
        "snapDistance": parse_snap_distance(html),
    }
    components = {
        "sliderBarHeight": rule_number(bar, "height"),
        "sliderKnobWidth": rule_number(knob, "width"),
        "sliderKnobHeight": rule_number(knob, "height"),
        "titleFontSize": rule_number(title_bar, "font-size"),
        "labelFontSize": rule_number(line, "font-size"),
        "tooltipDelayMs": parse_tooltip_delay(html),
        "transitionFast": parse_transition_seconds(
            re.search(r"transition\s*:\s*([^;]+)", row).group(1)
        ),
        "transitionSlow": parse_transition_seconds(
            re.search(r"animation\s*:\s*([^;]+)", toast).group(1)
        ),
    }
    return {
        "source": PROTOTYPE,
        "shape": shape,
        "chrome": chrome,
        "components": components,
    }


def dump(spec: dict) -> str:
    return json.dumps(spec, indent=2) + "\n"


def parse_theme_shape(shell: str) -> dict:
    match = re.search(r"shape\s*=\s*\{(.*?)\}\s*::\s*ThemeShape", shell, re.S)
    if not match:
        raise SystemExit(f"{SHELL}: ThemeEngine.shape not found")
    found = {}
    for name, value in re.findall(r"(\w+)\s*=\s*([0-9.]+)", match.group(1)):
        found[name] = float(value) if "." in value else int(value)
    return found


def parse_named_constants() -> dict:
    """ALL_CAPS number locals in the files the brief named as counterparts."""
    found = {}
    for path in (WIDGETS, WINDOWS):
        if not os.path.exists(path):
            continue
        for name, value in re.findall(
            r"local ([A-Z][A-Z0-9_]+): number = ([0-9.]+)",
            open(path, encoding="utf-8").read(),
        ):
            found[name] = float(value) if "." in value else int(value)
    return found


def numbers_close(left, right) -> bool:
    if isinstance(left, float) or isinstance(right, float):
        return abs(float(left) - float(right)) < 1e-9
    return left == right


def check_luau(spec: dict) -> list[str]:
    failures = []
    shell = open(SHELL, encoding="utf-8").read()
    shape = parse_theme_shape(shell)
    for name, wanted in spec["shape"].items():
        got = shape.get(name)
        if got is None:
            failures.append(
                f"ThemeEngine.shape.{name}: no counterpart "
                f"(prototype {wanted})"
            )
        elif not numbers_close(got, wanted):
            failures.append(
                f"ThemeEngine.shape.{name}: {got} != prototype {wanted}"
            )
    for name, got in shape.items():
        if name not in spec["shape"]:
            failures.append(
                f"ThemeEngine.shape.{name} = {got} has no prototype token"
            )

    constants = parse_named_constants()
    pending = {}
    pending.update(spec.get("chrome") or {})
    pending.update(spec.get("components") or {})
    for spec_name, wanted in pending.items():
        constant = WIDGET_CONSTANTS[spec_name]
        got = constants.get(constant)
        if got is None:
            # A miss cannot fail until the constant exists — C cannot
            # edit Widgets.luau or WindowManager.luau. Once the name
            # appears, a wrong value fails and names both sides.
            continue
        if not numbers_close(got, wanted):
            failures.append(
                f"{constant}: {got} != prototype spec.{spec_name} {wanted}"
            )
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify spec.json and the Luau counterparts; do not write",
    )
    args = parser.parse_args()

    html = open(PROTOTYPE, encoding="utf-8").read()
    spec = build_spec(html)
    rendered = dump(spec)

    if args.check:
        if not os.path.exists(SPEC):
            print(f"{SPEC} is missing; run tools/extract_prototype_spec.py")
            return 1
        committed = open(SPEC, encoding="utf-8").read()
        if committed != rendered:
            print(
                f"{SPEC} is stale against {PROTOTYPE}.\n"
                "  Run: python3 tools/extract_prototype_spec.py"
            )
            return 1
        failures = check_luau(spec)
        if failures:
            print("ClickGUI spec does not match Luau:")
            for line in failures:
                print("  " + line)
            return 1
        constants = parse_named_constants()
        owed = []
        pending = {}
        pending.update(spec.get("chrome") or {})
        pending.update(spec.get("components") or {})
        for spec_name, wanted in pending.items():
            constant = WIDGET_CONSTANTS[spec_name]
            if constant not in constants:
                owed.append(f"{constant}={wanted}")
        shape_n = len(spec["shape"])
        other_n = len(pending)
        print(f"ok · {shape_n} shape tokens · {other_n} widget metrics")
        if owed:
            print("owed · " + ", ".join(owed))
        return 0

    os.makedirs(os.path.dirname(SPEC), exist_ok=True)
    open(SPEC, "w", encoding="utf-8").write(rendered)
    print(f"wrote {SPEC}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
