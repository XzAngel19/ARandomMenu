#!/usr/bin/env python3
"""Approximate visual preview of dist/Violent.lua.

The bundle is executed against tests/mock_roblox.lua, the resulting instance
tree is dumped to JSON, and a small software renderer draws it. Fonts are
stand-ins (Luckiest Guy for the display face, Roboto Condensed for the body),
so this is a layout/colour check, not a pixel-accurate Roblox render.

Usage:
    python3 violent-ui/tests/render_preview.py [output.png]

Fonts, if present, are read from /tmp/fonts/out (LuckiestGuy.ttf,
RobotoCondensed.ttf, RobotoCondensedBold.ttf); DejaVu is used otherwise.
"""

from __future__ import annotations

import json
import math
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
BUNDLE = ROOT / "dist" / "Violent.lua"
MOCK = ROOT / "tests" / "mock_roblox.lua"
LUAU = ROOT.parent / "tools" / "luau" / "bin" / "luau"
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "docs" / "preview.png"

FONT_DIR = Path("/tmp/fonts/out")
SCALE = 1  # supersample factor (geometry and fonts both follow it)
VIEWPORT = (1180, 820)

DUMP = r"""
local function num(value, default)
	if type(value) == "number" then
		return value
	end
	return default
end

local function encodeColor(color)
	if type(color) ~= "table" then
		return nil
	end
	return {
		r = math.floor(color.R * 255 + 0.5),
		g = math.floor(color.G * 255 + 0.5),
		b = math.floor(color.B * 255 + 0.5),
	}
end

local function encodeUDim2(value)
	if type(value) ~= "table" then
		return nil
	end
	return {
		xs = value.X.Scale,
		xo = value.X.Offset,
		ys = value.Y.Scale,
		yo = value.Y.Offset,
	}
end

local function enumName(value)
	if type(value) == "table" and value.Name ~= nil then
		return value.Name
	end
	return nil
end

local function childOfClass(inst, className)
	for _, child in ipairs(inst._children) do
		if child._className == className then
			return child
		end
	end
	return nil
end

local function describe(inst)
	local props = inst._props
	local node = {
		class = inst._className,
		name = props.Name or "",
		visible = props.Visible ~= false,
		position = encodeUDim2(props.Position),
		size = encodeUDim2(props.Size),
		anchor = props.AnchorPoint and { x = props.AnchorPoint.X, y = props.AnchorPoint.Y } or { x = 0, y = 0 },
		rotation = num(props.Rotation, 0),
		bg = encodeColor(props.BackgroundColor3),
		bgT = num(props.BackgroundTransparency, 0),
		text = props.Text,
		textSize = num(props.TextSize, nil),
		textColor = encodeColor(props.TextColor3),
		textX = enumName(props.TextXAlignment),
		textY = enumName(props.TextYAlignment),
		textT = num(props.TextTransparency, 0),
		font = enumName(props.Font),
		fontFace = props.FontFace and props.FontFace.Family or nil,
		autoX = enumName(props.AutomaticSize),
		layoutOrder = num(props.LayoutOrder, 0),
	}

	local corner = childOfClass(inst, "UICorner")
	if corner then
		node.corner = corner.CornerRadius.Offset
	end

	local stroke = childOfClass(inst, "UIStroke")
	if stroke then
		node.stroke = {
			color = encodeColor(stroke.Color),
			thickness = num(stroke.Thickness, 1),
			transparency = num(stroke.Transparency, 0),
			mode = enumName(stroke.ApplyStrokeMode),
		}
	end

	local gradient = childOfClass(inst, "UIGradient")
	if gradient and gradient.Color then
		local keys = {}
		for _, key in ipairs(gradient.Color.Keypoints) do
			table.insert(keys, { t = key.Time, color = encodeColor(key.Value) })
		end
		node.gradient = { rotation = num(gradient.Rotation, 0), keys = keys }
	end

	local list = childOfClass(inst, "UIListLayout")
	if list then
		node.list = {
			padding = list.Padding and list.Padding.Offset or 0,
			horizontal = enumName(list.HorizontalAlignment),
		}
	end

	local children = {}
	for _, child in ipairs(inst._children) do
		local class = child._className
		if class ~= "UIStroke" and class ~= "UICorner" and class ~= "UIGradient"
			and class ~= "UIListLayout" and class ~= "UIPadding"
		then
			table.insert(children, describe(child))
		end
	end
	node.children = children
	return node
end

local function encode(value)
	local kind = type(value)
	if kind == "nil" then
		return "null"
	elseif kind == "number" then
		return string.format("%.4f", value)
	elseif kind == "boolean" then
		return value and "true" or "false"
	elseif kind == "string" then
		return '"' .. value:gsub('[%z\1-\31\\"]', function(char)
			if char == '"' then
				return '\\"'
			elseif char == "\\" then
				return "\\\\"
			elseif char == "\n" then
				return "\\n"
			end
			return string.format("\\u%04x", char:byte())
		end) .. '"'
	elseif kind == "table" then
		local isArray = true
		local count = 0
		for key in pairs(value) do
			count += 1
			if type(key) ~= "number" or key % 1 ~= 0 then
				isArray = false
			end
		end
		if isArray then
			local parts = {}
			for index = 1, count do
				parts[index] = encode(value[index])
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local parts = {}
		for key, item in pairs(value) do
			table.insert(parts, encode(tostring(key)) .. ":" .. encode(item))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
end

for _, child in ipairs(gethui():GetChildren()) do
	if child._className == "ScreenGui" then
		workspace.CurrentCamera.ViewportSize = Vector2.new(__W__, __H__)
		print("JSON_BEGIN")
		print(encode(describe(child)))
		print("JSON_END")
	end
end
"""


# ---------------------------------------------------------------------------
# Fonts
# ---------------------------------------------------------------------------
DISPLAY_FONT = sys.argv[2] if len(sys.argv) > 2 else "Bangers"


def load_font(name: str, size: int) -> ImageFont.FreeTypeFont:
    candidates = {
        "display": [FONT_DIR / (DISPLAY_FONT + ".ttf"), FONT_DIR / "LuckiestGuy.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"],
        "section": [FONT_DIR / "FredokaOne.ttf", FONT_DIR / "LuckiestGuy.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"],
        "body": [FONT_DIR / "RobotoCondensedMedium.ttf", FONT_DIR / "RobotoCondensed.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed.ttf"],
        "bold": [FONT_DIR / "RobotoCondensedBold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf"],
        "serif": [FONT_DIR / "EBGaramondItalic.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf"],
    }
    for path in candidates[name]:
        if Path(path).is_file():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


FONT_CACHE: dict[tuple[str, int], ImageFont.FreeTypeFont] = {}


DISPLAY_FILES = {"Bangers": "Bangers.ttf", "GothamBlack": "GothamBlack.ttf", "LuckiestGuy": "LuckiestGuy.ttf"}


def font_for(node: dict, size: int) -> ImageFont.FreeTypeFont:
    size = max(1, int(round(size * SCALE)))
    face = (node.get("fontFace") or "")
    name = (node.get("font") or "")
    if "Garamond" in face or "Garamond" in name:
        key = "serif"
    elif "Fredoka" in name:
        key = "section"
    elif "Bangers" in name:
        key = "display"
    elif any(word in name for word in ("Luckiest", "Burbank", "GothamBlack", "Arcade", "Fantasy")):
        key = "display"
    elif "Bold" in name or "Black" in name:
        key = "bold"
    else:
        key = "body"
    if key == "display" and name in DISPLAY_FILES and (FONT_DIR / DISPLAY_FILES[name]).is_file():
        cache_key = (DISPLAY_FILES[name], size)
        if cache_key not in FONT_CACHE:
            FONT_CACHE[cache_key] = ImageFont.truetype(str(FONT_DIR / DISPLAY_FILES[name]), size)
        return FONT_CACHE[cache_key]

    cache_key = (key, size)
    if cache_key not in FONT_CACHE:
        FONT_CACHE[cache_key] = load_font(key, size)
    return FONT_CACHE[cache_key]


# ---------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------
def node_rect(node: dict, parent: tuple[float, float, float, float]) -> tuple[float, float, float, float]:
    px, py, pw, ph = parent
    size = node.get("size") or {}
    width = (size.get("xs", 0) or 0) * pw + (size.get("xo", 0) or 0)
    height = (size.get("ys", 0) or 0) * ph + (size.get("yo", 0) or 0)

    if node.get("autoX") in ("X", "XY") and node.get("text"):
        font = font_for(node, node.get("textSize") or 14)
        width = font.getlength(node["text"])

    pos = node.get("position") or {}
    anchor = node.get("anchor") or {"x": 0, "y": 0}
    x = px + (pos.get("xs", 0) or 0) * pw + (pos.get("xo", 0) or 0) - anchor.get("x", 0) * width
    y = py + (pos.get("ys", 0) or 0) * ph + (pos.get("yo", 0) or 0) - anchor.get("y", 0) * height
    return (x, y, width, height)


def color_tuple(color: dict | None, alpha: float = 1.0) -> tuple[int, int, int, int]:
    if not color:
        return (0, 0, 0, 0)
    return (
        int(color.get("r", 0)),
        int(color.get("g", 0)),
        int(color.get("b", 0)),
        max(0, min(255, int(round(alpha * 255)))),
    )


def lerp_color(a: dict, b: dict, t: float) -> tuple[int, int, int]:
    return tuple(
        int(round(a.get(ch, 0) + (b.get(ch, 0) - a.get(ch, 0)) * t)) for ch in ("r", "g", "b")
    )


def gradient_color(node: dict, fraction: float) -> tuple[int, int, int] | None:
    gradient = node.get("gradient")
    if not gradient or not gradient.get("keys"):
        return None
    keys = gradient["keys"]
    fraction = max(0.0, min(1.0, fraction))
    for index in range(len(keys) - 1):
        left, right = keys[index], keys[index + 1]
        if left["t"] <= fraction <= right["t"]:
            span = right["t"] - left["t"]
            local = 0.0 if span <= 0 else (fraction - left["t"]) / span
            return lerp_color(left["color"], right["color"], local)
    return color_tuple(keys[-1]["color"])[:3]


def rounded_mask(size: tuple[int, int], radius: float) -> Image.Image:
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    if radius > 0:
        draw.rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    else:
        draw.rectangle([0, 0, size[0] - 1, size[1] - 1], fill=255)
    return mask


def paste_rotated(canvas: Image.Image, layer: Image.Image, center: tuple[float, float], angle: float):
    if abs(angle) < 0.01:
        canvas.alpha_composite(layer, (int(round(center[0] - layer.width / 2)), int(round(center[1] - layer.height / 2))))
        return
    rotated = layer.rotate(-angle, resample=Image.BICUBIC, expand=True)
    canvas.alpha_composite(
        rotated,
        (int(round(center[0] - rotated.width / 2)), int(round(center[1] - rotated.height / 2))),
    )


# ---------------------------------------------------------------------------
# Renderer
# ---------------------------------------------------------------------------
def draw_node(canvas: Image.Image, node: dict, rect: tuple[float, float, float, float]):
    if not node.get("visible", True):
        return

    x, y, w, h = rect
    if w <= 0.5 or h <= 0.5:
        return

    width = max(1, int(round(w)))
    height = max(1, int(round(h)))
    angle = node.get("rotation") or 0

    layer = Image.new("RGBA", (width, height), (0, 0, 0, 0))

    fill = node.get("bg")
    transparency = node.get("bgT") or 0
    radius = (node.get("corner") or 0) * SCALE

    if fill and transparency < 0.999:
        mask = rounded_mask((width, height), radius)
        if node.get("gradient"):
            gradient = Image.new("RGBA", (width, height))
            pixels = gradient.load()
            keys = node["gradient"]["keys"]
            for row in range(height):
                fraction = row / max(1, height - 1)
                color = gradient_color(node, fraction) or (0, 0, 0)
                alpha = int(round((1 - transparency) * 255))
                for column in range(width):
                    pixels[column, row] = (*color, alpha)
            layer.paste(gradient, (0, 0), mask)
        else:
            layer.paste(Image.new("RGBA", (width, height), color_tuple(fill, 1 - transparency)), (0, 0), mask)

        if angle:
            # gradient/fill rotation is only used horizontally here
            pass

    stroke = node.get("stroke")
    if stroke and stroke.get("mode") != "Contextual":
        stroke_width = max(1, int(round((stroke.get("thickness") or 1) * SCALE)))
        stroke_color = color_tuple(stroke.get("color"), 1 - (stroke.get("transparency") or 0))
        draw = ImageDraw.Draw(layer)
        draw.rounded_rectangle(
            [stroke_width / 2, stroke_width / 2, width - 1 - stroke_width / 2, height - 1 - stroke_width / 2],
            radius=max(0, radius - stroke_width / 2),
            outline=stroke_color,
            width=stroke_width,
        )

    if angle:
        center = (x + w / 2, y + h / 2)
        paste_rotated(canvas, layer, center, angle)
    else:
        canvas.alpha_composite(layer, (int(round(x)), int(round(y))))

    # Text
    text = node.get("text")
    if text and node.get("textT", 0) < 0.99 and node.get("textColor"):
        font = font_for(node, node.get("textSize") or 14)
        text_color = color_tuple(node["textColor"], 1 - (node.get("textT") or 0))
        anchor_x = (node.get("textX") or "Left")
        anchor_y = (node.get("textY") or "Center")

        pad = int(math.ceil(font.size * 0.6))
        text_layer = Image.new("RGBA", (width + pad * 2, height + pad * 2), (0, 0, 0, 0))
        draw = ImageDraw.Draw(text_layer)

        if anchor_x == "Center":
            tx = pad + width / 2
            horizontal = "m"
        elif anchor_x == "Right":
            tx = pad + width
            horizontal = "r"
        else:
            tx = pad
            horizontal = "l"

        lines = text.split("\n")
        ascent, descent = font.getmetrics()
        line_height = (ascent + descent) * 1.05
        total_height = line_height * len(lines)
        if anchor_y == "Top":
            top = pad
        elif anchor_y == "Bottom":
            top = pad + height - total_height
        else:
            top = pad + height / 2 - total_height / 2

        stroke_info = node.get("stroke")
        stroke_width = 0
        stroke_fill = None
        if stroke_info and stroke_info.get("mode") == "Contextual":
            stroke_width = max(1, int(round((stroke_info.get("thickness") or 1) * SCALE)))
            stroke_fill = color_tuple(stroke_info.get("color"), 1)

        for index, line in enumerate(lines):
            line_center = top + line_height * index + line_height / 2
            draw.text(
                (tx, line_center),
                line,
                font=font,
                fill=text_color,
                anchor=horizontal + "m",
                stroke_width=stroke_width,
                stroke_fill=stroke_fill,
            )

        paste_rotated(canvas, text_layer, (x + w / 2, y + h / 2), angle)

    # Children
    children = node.get("children") or []
    layout = node.get("list")
    if layout:
        ordered = sorted(children, key=lambda child: (child.get("layoutOrder") or 0))
        cursor = 0.0
        for child in ordered:
            child_rect = node_rect(child, (x, y, w, h))
            child_height = child_rect[3]
            if layout.get("horizontal") == "Center":
                child_rect = ((w - child_rect[2]) / 2 + x, y + cursor, child_rect[2], child_rect[3])
            else:
                child_rect = (x, y + cursor, child_rect[2], child_rect[3])
            draw_node(canvas, child, child_rect)
            cursor += child_height + (layout.get("padding") or 0)
        return

    for child in children:
        draw_node(canvas, child, node_rect(child, (x, y, w, h)))


def backdrop(width: int, height: int) -> Image.Image:
    image = Image.new("RGB", (width, height))
    draw = ImageDraw.Draw(image)
    horizon = int(height * 0.58)

    for row in range(horizon):
        t = row / max(1, horizon)
        color = (
            int(110 + 70 * t),
            int(196 + 34 * t),
            int(238 + 12 * t),
        )
        draw.line([(0, row), (width, row)], fill=color)

    draw.rectangle([0, horizon, width, height], fill=(78, 78, 80))
    tile = int(26 * SCALE)
    for row in range(horizon, height, tile):
        for column in range(-tile, width + tile, tile):
            offset = tile // 2 if (row // tile) % 2 else 0
            draw.rectangle(
                [column + offset, row, column + offset + tile - 2, row + tile - 2],
                outline=(96, 96, 98),
                width=1,
            )
    return image


def main() -> int:
    bundle = BUNDLE.read_text(encoding="utf-8")
    mock = MOCK.read_text(encoding="utf-8")
    harness = (
        "local MOCK = (function()\n"
        + mock
        + "\nend)()\nlocal Main = (function()\n"
        + bundle
        + "\nend)()\n"
        + DUMP.replace("__W__", str(VIEWPORT[0])).replace("__H__", str(VIEWPORT[1]))
    )
    temp = ROOT / "tests" / ".render_harness.lua"
    temp.write_text(harness, encoding="utf-8")
    try:
        result = subprocess.run([str(LUAU), str(temp)], capture_output=True, text=True)
    finally:
        temp.unlink(missing_ok=True)

    if result.returncode != 0:
        sys.stderr.write(result.stdout + result.stderr)
        return result.returncode

    payload = result.stdout.split("JSON_BEGIN", 1)[1].split("JSON_END", 1)[0].strip()
    tree = json.loads(payload)

    width, height = VIEWPORT[0] * SCALE, VIEWPORT[1] * SCALE
    canvas = backdrop(width, height).convert("RGBA")

    root_rect = (0.0, 0.0, float(VIEWPORT[0]), float(VIEWPORT[1]))
    # ScreenGui has no explicit size; its Holder child fills it.
    for child in tree.get("children", []):
        draw_node(canvas, child, node_rect(child, root_rect))

    final = canvas.resize(VIEWPORT, Image.LANCZOS).convert("RGB")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    final.save(OUT)
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
