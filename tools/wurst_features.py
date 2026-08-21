#!/usr/bin/env python3
"""Official Wurst 7 UI-setting defaults, as the parity gate reads them.

The numbers and names come from Wurst7 at
4a22e53d774b9a28e395874834f099e779685998 (ClickGuiHack, HackListOtf,
WurstLogoOtf, TabGuiOtf, KeybindList, TacoCmd). docs/wurst-features.md
is the prose inventory; this module is the machine-readable half so
spec.json is generated, not hand-copied.

A counterpart that exists with the wrong value fails the gate and names
both sides. A counterpart that does not exist yet is owed — C cannot
edit the shell or the widgets.
"""

from __future__ import annotations

# Each row is one setting the UI Settings window (or the feature it
# opens) ships. `luau` is the name the gate looks for. Theme.* tokens
# already exist. ALL_CAPS names are owed until the window is built.
SETTINGS: list[dict] = [
    {
        "window": "ClickGUI",
        "name": "Background",
        "type": "color",
        "default": "#404040",
        "description": "Background color",
        "luau": "Theme.surface",
    },
    {
        "window": "ClickGUI",
        "name": "Accent",
        "type": "color",
        "default": "#101010",
        "description": "Accent color",
        "luau": "Theme.accent",
    },
    {
        "window": "ClickGUI",
        "name": "Text",
        "type": "color",
        "default": "#F0F0F0",
        "description": "Text color",
        "luau": "Theme.text",
    },
    {
        "window": "ClickGUI",
        "name": "Opacity",
        "type": "slider",
        "default": 0.5,
        "min": 0.15,
        "max": 0.85,
        "step": 0.01,
        "description": "",
        "luau": "OPACITY",
    },
    {
        "window": "ClickGUI",
        "name": "Tooltip opacity",
        "type": "slider",
        "default": 0.75,
        "min": 0.15,
        "max": 1,
        "step": 0.01,
        "description": "",
        "luau": "TOOLTIP_OPACITY",
    },
    {
        "window": "ClickGUI",
        "name": "Max height",
        "type": "slider",
        "default": 200,
        "min": 0,
        "max": 1000,
        "step": 50,
        "description": "Maximum window height\n0 = no limit",
        "luau": "MAX_HEIGHT",
    },
    {
        "window": "ClickGUI",
        "name": "Max settings height",
        "type": "slider",
        "default": 200,
        "min": 0,
        "max": 1000,
        "step": 50,
        "description": "Maximum height for settings windows\n0 = no limit",
        "luau": "MAX_SETTINGS_HEIGHT",
    },
    {
        "window": "HackList",
        "name": "Mode",
        "type": "enum",
        "default": "Auto",
        "values": ["Auto", "Count", "Hidden"],
        "description": (
            "Auto mode renders the whole list if it fits onto the screen.\n"
            "Count mode only renders the number of active hacks.\n"
            "Hidden mode renders nothing."
        ),
        "luau": "HACKLIST_MODE",
    },
    {
        "window": "HackList",
        "name": "Position",
        "type": "enum",
        "default": "Left",
        # Wurst hangs the list under the logo. The prototype gives that
        # corner to the wordmark and the stats, so this port's default is
        # Right. The gate holds the port default, not upstream's.
        "portDefault": "Right",
        "values": ["Left", "Right"],
        "description": (
            "Which side of the screen the HackList should be shown on.\n"
            "Change this to Right when using TabGUI."
        ),
        "luau": "HACKLIST_POSITION",
    },
    {
        "window": "HackList",
        "name": "Color",
        "type": "color",
        "default": "#FFFFFF",
        "description": (
            "Color of the HackList text.\n"
            "Only visible when RainbowUI is disabled."
        ),
        "luau": "HACKLIST_COLOR",
    },
    {
        "window": "HackList",
        "name": "Sort by",
        "type": "enum",
        "default": "Name",
        "values": ["Name", "Width"],
        "description": (
            "Determines how the HackList entries are sorted.\n"
            "Only visible when Mode is set to Auto."
        ),
        "luau": "HACKLIST_SORT_BY",
    },
    {
        "window": "HackList",
        "name": "Reverse sorting",
        "type": "checkbox",
        "default": False,
        "description": "",
        "luau": "HACKLIST_REVERSE",
    },
    {
        "window": "HackList",
        "name": "Animations",
        "type": "checkbox",
        "default": True,
        "description": (
            "When enabled, entries slide into and out of the HackList "
            "as hacks are enabled and disabled."
        ),
        "luau": "HACKLIST_ANIMATIONS",
    },
    {
        "window": "WurstLogo",
        "name": "Background",
        "type": "color",
        "default": "#FFFFFF",
        "description": (
            "Background color.\nOnly visible when RainbowUI is disabled."
        ),
        "luau": "WURSTLOGO_BACKGROUND",
    },
    {
        "window": "WurstLogo",
        "name": "Text",
        "type": "color",
        "default": "#000000",
        "description": "Text color.",
        "luau": "WURSTLOGO_TEXT",
    },
    {
        "window": "WurstLogo",
        "name": "Visibility",
        "type": "enum",
        "default": "Always",
        "values": ["Always", "Only when outdated"],
        "description": "",
        "luau": "WURSTLOGO_VISIBILITY",
    },
    {
        "window": "TabGUI",
        "name": "Status",
        "type": "enum",
        "default": "Disabled",
        "values": ["Enabled", "Disabled"],
        "description": "",
        "luau": "TABGUI_STATUS",
    },
    {
        "window": "Taco",
        "name": "Enabled",
        "type": "checkbox",
        "default": False,
        "description": (
            'Spawns a dancing taco on your hotbar.\n'
            '"I love that little guy. So cute!" -WiZARD'
        ),
        "luau": "TACO_ENABLED",
    },
]

# Stored form, from KeybindList.createDefaultKeybinds. The wiki's Title
# Case is display; the file is lowercase.
KEYBINDS: list[dict] = [
    {"key": "key.keyboard.b", "commands": "fastplace;fastbreak"},
    {"key": "key.keyboard.c", "commands": "fullbright"},
    {"key": "key.keyboard.g", "commands": "flight"},
    {"key": "key.keyboard.semicolon", "commands": "speednuker"},
    {"key": "key.keyboard.h", "commands": "say /home"},
    {"key": "key.keyboard.j", "commands": "jesus"},
    {"key": "key.keyboard.k", "commands": "multiaura"},
    {"key": "key.keyboard.n", "commands": "nuker"},
    {"key": "key.keyboard.r", "commands": "killaura"},
    {"key": "key.keyboard.right.shift", "commands": "navigator"},
    {"key": "key.keyboard.right.control", "commands": "clickgui"},
    {"key": "key.keyboard.u", "commands": "freecam"},
    {"key": "key.keyboard.x", "commands": "x-ray"},
    {"key": "key.keyboard.y", "commands": "sneak"},
]

# UI Settings is a window, not a feature. It hosts these buttons and
# then every ClickGUI setting, in this order.
UI_SETTINGS_HOSTS: list[str] = [
    "WurstLogo",
    "HackList",
    "Keybinds",
    "WurstOptions",
    "ClickGUI",
]

# Named in the brief, missing from official Wurst 7. Recording them
# here is what stops a later port from inventing them.
ABSENT: list[str] = [
    "GlobalToggle",
    "Isolate windows",
]

# Minecraft GUI-scale-1 pixels, from Wurst7 at the pinned commit
# (Window.java height = inner + 13, FeatureButton.getDefaultHeight
# 11, WurstLogo blit 72x18 at (0, 3), chip fill y=6..17,
# HackListHUD posY += 9). Window width is packed to the title and
# the widest child, not a constant.
CHROME: dict = {
    "titleHeight": 13,
    "rowHeight": 11,
    "settingsArrow": 11,
    "logoWidth": 72,
    "logoHeight": 18,
    "logoX": 0,
    "logoY": 3,
    "logoChipTop": 6,
    "logoChipBottom": 17,
    "hackListLine": 9,
    "hackListMargin": 2,
    "hackListSlide": 5,
    "windowWidth": None,
}

# ref-wurst-719.jpg is 1600x900: a 1920x1080 framebuffer at GUI
# scale 2, scaled by 5/6. One GUI-scale-1 pixel is 10/6 screenshot
# pixels, so the Java blit 72x18 becomes 120x30 and a HackList
# line of 9 becomes 15. Measuring the sausage's orange pixels
# gives 124x27 (JPEG fringe); HackList clusters land every 17.
# Those two measured numbers confirm the Java, they do not replace
# it. ref-wurst-cyan.jpg is a fork (Isolate / GlobalToggle) and is
# not a source for chrome.
SCREENSHOT: dict = {
    "file": "docs/design/reference/ref-wurst-719.jpg",
    "width": 1600,
    "height": 900,
    "guiScale": 2,
    "framebufferWidth": 1920,
    "framebufferHeight": 1080,
    "pixelsPerGui": 1.6667,
    "logoBlit": [124, 27],
    "hackListLine": 17,
}

# Wurst draws every label with WurstClient.MC.font — Minecraft's
# default bitmap renderer, not a font Wurst ships. There is no
# TTF/OTF in the Wurst7 tree. Glyphs come from vanilla's bitmap
# providers (historically ascii.png, 8 px tall in a 16x16 grid);
# Font.lineHeight is 9, which is why the HackList advances 9.
# Typical Latin advance is 5–6 px plus one of spacing. The closest
# face this repository already vendors is Monocraft (minecraftFont),
# an OTF that imitates that bitmap. Furniture today still paints
# the chip fallback with TITLE_FONT (BuilderSans) and the stats
# with RobotoMono.
FONT: dict = {
    "source": "Minecraft default bitmap (MC.font)",
    "file": None,
    "glyphHeight": 8,
    "lineHeight": 9,
    "typicalAdvance": 6,
    "closestVendored": "minecraftFont / Monocraft.otf",
    "portToday": "BuilderSans / RobotoMono",
}


def spec_section() -> dict:
    """The block extract_prototype_spec.py folds into spec.json."""
    settings = []
    for row in SETTINGS:
        entry = {
            "window": row["window"],
            "name": row["name"],
            "type": row["type"],
            "default": row["default"],
            "description": row["description"],
            "luau": row["luau"],
        }
        for extra in ("min", "max", "step", "values", "portDefault"):
            if extra in row:
                entry[extra] = row[extra]
        settings.append(entry)
    return {
        "source": (
            "Wurst7 4a22e53d774b9a28e395874834f099e779685998"
        ),
        "uiSettingsHosts": list(UI_SETTINGS_HOSTS),
        "absent": list(ABSENT),
        "settings": settings,
        "keybinds": [dict(row) for row in KEYBINDS],
        "chrome": dict(CHROME),
        "screenshot": dict(SCREENSHOT),
        "font": dict(FONT),
    }
