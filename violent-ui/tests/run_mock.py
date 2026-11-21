#!/usr/bin/env python3
"""Execute dist/Violent.lua against tests/mock_roblox.lua and assert the tree.

This is a smoke test: it proves the bundle builds every instance, that the
reference's rows exist in order, and that the view-state bindings (counter,
footer, checkboxes, visibility) respond. It cannot validate rendering.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUNDLE = ROOT / "dist" / "Violent.lua"
MOCK = ROOT / "tests" / "mock_roblox.lua"
LUAU = ROOT.parent / "tools" / "luau" / "bin" / "luau"

TEST = r"""
local failed = 0
local total = 0

local function check(condition, label)
	total += 1
	if not condition then
		failed += 1
		print("FAIL " .. label)
	else
		print("ok   " .. label)
	end
end

local function findClass(parent, className)
	for _, child in ipairs(parent:GetChildren()) do
		if child.ClassName == className then
			return child
		end
	end
	return nil
end

local function descendantsWhere(root, predicate)
	local result = {}
	for _, node in ipairs(root:GetDescendants()) do
		if predicate(node) then
			table.insert(result, node)
		end
	end
	return result
end

local screen = nil
for _, child in ipairs(gethui():GetChildren()) do
	if child.ClassName == "ScreenGui" then
		screen = child
	end
end

check(screen ~= nil, "ScreenGui mounted in gethui()")
if screen == nil then
	print("aborting")
	return
end

local holder = findClass(screen, "Frame")
local windows = {}
for _, child in ipairs(holder:GetChildren()) do
	if child.ClassName == "Frame" and child.Name == "Window" then
		table.insert(windows, child)
	end
end
check(#windows == 1, "one window shell")

local window = windows[1]
check(window.Size.X.Offset == 352 and window.Size.Y.Offset == 588, "window is 352x588")
check(window.BackgroundTransparency > 0, "window body is translucent")

local header = window:FindFirstChild("Header")
check(header ~= nil and header.Size.Y.Offset == 85, "pink header is 85 px")

local logo = header:FindFirstChild("Logo")
local logoText = logo and logo:FindFirstChild("LogoText")
check(logoText ~= nil and logoText.Text == "VIOLENT", "logo reads VIOLENT")

local body = window:FindFirstChild("Body")
local strip = body:FindFirstChild("TabStrip")
local pageName = strip and strip:FindFirstChild("PageName")
local counter = strip and strip:FindFirstChild("Counter")
check(pageName and pageName.Text == "VISUALS / HUD", "page name VISUALS / HUD")
check(counter and counter.Text == "29/51", "counter starts at 29/51")

local scroll = body:FindFirstChild("Content")
check(scroll ~= nil and scroll.ClassName == "ScrollingFrame", "content is a ScrollingFrame")

local rows = {}
for _, child in ipairs(scroll:GetChildren()) do
	if child.ClassName == "TextButton" then
		table.insert(rows, child)
	end
end
check(#rows == 11, "11 interactive rows")

local sections = {}
for _, child in ipairs(scroll:GetChildren()) do
	if child.ClassName == "Frame" and child.Name == "Section" then
		table.insert(sections, child)
	end
end
check(#sections == 3, "3 section headings")

local function labelOf(row)
	local label = row:FindFirstChild("Label")
	return label and label.Text or ""
end

local expected = {
	"Enable Skeleton",
	"Skeleton Thickness",
	"Skeleton Color",
	"Highlight ESP",
	"Highlight Fill",
	"Highlight Outline",
	"Highlight Fill Color",
	"Highlight Outline Color",
	"Show Health Bar",
	"Healt Bar Size",
	"Release, v1.4",
}
local matched = true
for index, text in ipairs(expected) do
	local got = labelOf(rows[index])
	if got ~= text then
		matched = false
		print(("  row %d: expected %q, got %q"):format(index, text, got))
	end
end
check(matched, "row labels match the reference in order")

local sectionText = {}
for _, section in ipairs(sections) do
	for _, child in ipairs(section:GetChildren()) do
		if child.ClassName == "TextLabel" and child.Text ~= "" and child.TextColor3.RGB[1] == 255 then
			table.insert(sectionText, child.Text)
		end
	end
end
check(table.concat(sectionText, "|") == "Highlights|Health bar|text", "section titles match")

-- Toggle row: click flips the checkbox and the counter.
local skeletonRow = rows[1]
local checkbox = skeletonRow:FindFirstChild("Checkbox")
local checkMark = checkbox and checkbox:FindFirstChild("Check")
check(checkMark ~= nil and checkMark.Visible == true, "skeleton toggle starts enabled")
skeletonRow.MouseButton1Click:Fire()
check(counter.Text == "28/51", "counter drops to 28/51 after toggling")
check(checkMark.Visible == false, "checkbox clears after click")
skeletonRow.MouseButton1Click:Fire()
check(counter.Text == "29/51", "counter returns to 29/51")

-- Value row increments and wraps.
local sizeRow = rows[10]
local sizeValue = sizeRow:FindFirstChild("Value")
check(sizeValue and sizeValue.Text == "2.5", "health bar size starts at 2.5")
sizeRow.MouseButton1Click:Fire()
check(sizeValue.Text == "3.0", "health bar size increments to 3.0")

-- Colour row selection and footer text.
local footer = window:FindFirstChild("Footer")
local status = footer and footer:FindFirstChild("Status")
check(status and status.Text == "Set color to: Highlight Outline Color", "footer starts on outline colour")

local outlineRow = rows[8]
outlineRow.MouseButton1Click:Fire()
check(status.Text == "Set color to: Highlight Outline Color", "outline row stays selected")

local fillRow = rows[7]
fillRow.MouseButton1Click:Fire()
check(status.Text == "Set color to: Highlight Fill Color", "selecting fill colour updates footer")
check(fillRow.BackgroundTransparency == 0, "selected colour row is filled pink")
check(outlineRow.BackgroundTransparency == 1, "previous colour row is cleared")

-- Release selector steps without error (stubbed).
rows[11].MouseButton1Click:Fire()

-- Swatch click selects the row and fires the colour-picker stub.
local pickedId = nil
Main.Stubs.ColorPicked = function(id)
	pickedId = id
end
local outlineSwatch = outlineRow:FindFirstChild("Swatch")
outlineSwatch.MouseButton1Click:Fire()
check(pickedId == "highlightOutlineColor", "swatch click reaches the ColorPicked stub")
check(status.Text == "Set color to: Highlight Outline Color", "swatch click selects its row")

-- Header drag moves the window without error.
local dragStart = window.Position.X.Offset
header.InputBegan:Fire({
	UserInputType = Enum.UserInputType.MouseButton1,
	Position = Vector2.new(100, 100),
	Changed = MOCK.newSignal(),
})
UserInputService.InputChanged:Fire({
	UserInputType = Enum.UserInputType.MouseMovement,
	Position = Vector2.new(140, 130),
})
check(math.abs(window.Position.X.Offset - dragStart) > 1, "header drag moves the window")

-- Preview window.
local preview = nil
for _, child in ipairs(holder:GetChildren()) do
	if child.ClassName == "Frame" and child.Name == "EspPreview" then
		preview = child
	end
end
check(preview ~= nil, "ESP preview window exists")
check(preview.Size.X.Offset == 330 and preview.Size.Y.Offset == 340, "preview is 330x340")

local previewTitle = preview:FindFirstChild("Title")
check(previewTitle and previewTitle.Text == "ESP PREVIEW", "preview title")

local description = preview:FindFirstChild("Description")
check(
	description ~= nil
		and description.Text:find("Roblox doesnt support highlights", 1, true) ~= nil
		and description.Text:find("those options.", 1, true) ~= nil,
	"preview copy matches reference"
)

local previewBox = preview:FindFirstChild("PreviewBox")
check(previewBox ~= nil and previewBox.Size.X.Offset == 134, "preview box is 134 wide")
check(preview:FindFirstChild("HealthBar") ~= nil, "health gradient bar exists")

-- Keybind toggles visibility.
UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.RightShift }, false)
check(window.Visible == false and preview.Visible == false, "RightShift hides both windows")
UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.RightShift }, false)
check(window.Visible == true and preview.Visible == true, "RightShift shows both windows")

-- Teardown.
Main.Destroy()
check(screen.Parent == nil, "Destroy unparents the ScreenGui")

print(("%d/%d checks passed"):format(total - failed, total))
if failed > 0 then
	error(("%d checks failed"):format(failed), 0)
end
"""


def main() -> int:
    bundle = BUNDLE.read_text(encoding="utf-8")
    mock = MOCK.read_text(encoding="utf-8")

    harness = (
        "local MOCK = (function()\n"
        + mock
        + "\nend)()\nlocal Main = (function()\n"
        + bundle
        + "\nend)()\n"
        + TEST
    )
    temp = ROOT / "tests" / ".harness.lua"
    temp.write_text(harness, encoding="utf-8")
    try:
        result = subprocess.run([str(LUAU), str(temp)], capture_output=True, text=True)
    finally:
        temp.unlink(missing_ok=True)

    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
