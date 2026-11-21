#!/usr/bin/env python3
"""Fallback checks: no gethui(), no Font.new(), no syn table.

The bundle must still mount (PlayerGui fallback) and build with the serif
fallback instead of the Garamond FontFace.
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
local failures = 0

local function check(condition, label)
	if condition then
		print("ok   " .. label)
	else
		failures += 1
		print("FAIL " .. label)
	end
end

local playerGui = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
local coreGui = game:GetService("CoreGui")
local screen = (coreGui and coreGui:FindFirstChild("ViolentUI"))
	or (playerGui and playerGui:FindFirstChild("ViolentUI"))
check(screen ~= nil, "falls back to CoreGui/PlayerGui when gethui is unavailable")

if screen then
	local holder = screen:FindFirstChild("Holder")
	local window = holder and holder:FindFirstChild("Window")
	local logo = window and window:FindFirstChild("Header"):FindFirstChild("Logo")
	local logoText = logo and logo:FindFirstChild("LogoText")
	check(logoText ~= nil and logoText.Text == "VIOLENT", "window still builds without Font.new")

	local selector
	for _, row in ipairs(holder:GetDescendants()) do
		local label = row.ClassName == "TextLabel" and row.Name == "Label" and row
		if label and label.Text == "Release, v1.4" then
			selector = label
		end
	end
	check(selector ~= nil, "italic selector label falls back to a serif Enum.Font")
	check(selector ~= nil and selector.FontFace == nil, "FontFace is not set when Font.new is missing")
end

check(Main ~= nil, "bundle still returns its API")
if Main then
	Main.Destroy()
end

if failures > 0 then
	error(("%d fallback checks failed"):format(failures), 0)
end
print("fallback checks passed")
"""


def main() -> int:
    bundle = BUNDLE.read_text(encoding="utf-8")
    mock = MOCK.read_text(encoding="utf-8")

    harness = (
        "local MOCK = (function()\n"
        + mock
        + "\nend)()\n"
        "gethui = nil\n"
        "Font = nil\n"
        "local Main = (function()\n"
        + bundle
        + "\nend)()\n"
        + TEST
    )
    temp = ROOT / "tests" / ".fallback_harness.lua"
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
