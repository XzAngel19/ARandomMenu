#!/usr/bin/env python3
"""Character Disguise copies appearance without replacing the local body meshes."""
import os
import subprocess
import tempfile
from pathlib import Path

from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/games/universal/Other/Disguise.lua").read_text()
appearance_item = section(
    SOURCE,
    "    local function isAppearanceItem(",
    "    local function isInsideCharacter(",
)
copy_appearance = section(
    SOURCE,
    "    local function copyCharacterAppearance(",
    "    local function destroyInstance(",
)

script = PRELUDE + appearance_item + r'''
local cloned = {}
local disguisedItems = {}
local rebound = 0
local function rebindAccessory(character, accessory)
    rebound += 1
end

local function object(name, className)
    local value = {Name = name, ClassName = className, Parent = nil}
    function value:IsA(candidate) return candidate == self.ClassName end
    return value
end

local localHead = object("Head", "MeshPart")
localHead.MeshId = "blocky-head"
localHead.TextureID = "blocky-texture"
local localTorso = object("Torso", "Part")
local character = {}
function character:FindFirstChild(name)
    if name == "Head" then return localHead end
    if name == "Torso" then return localTorso end
    return nil
end

local targetHead = object("Head", "MeshPart")
targetHead.MeshId = "r15-target-head"
targetHead.TextureID = "r15-target-texture"
local targetUpperTorso = object("UpperTorso", "MeshPart")
targetUpperTorso.MeshId = "r15-target-torso"
targetUpperTorso.TextureID = "r15-target-torso-texture"
local accessory = object("Hat", "Accessory")
local shirt = object("Shirt", "Shirt")
local pants = object("Pants", "Pants")
local colors = object("Body Colors", "BodyColors")
local graphic = object("Shirt Graphic", "ShirtGraphic")
local face = object("face", "Decal")
local clone = {}
function clone:GetChildren()
    return {targetHead, targetUpperTorso, accessory, shirt, pants, colors, graphic}
end
function clone:FindFirstChild(name, recursive)
    if name == "face" and recursive then return face end
    return nil
end
''' + copy_appearance + r'''
copyCharacterAppearance(character, clone)

assert(localHead.MeshId == "blocky-head", "the target replaced the local head mesh")
assert(localHead.TextureID == "blocky-texture", "the target replaced the local head texture")
assert(localTorso.Parent == nil and targetHead.Parent == nil and targetUpperTorso.Parent == nil,
    "target body parts must not be inserted into the local character")
assert(disguisedItems[targetHead] == nil and disguisedItems[targetUpperTorso] == nil)
assert(rebound == 1, "the accessory must still be rebound to the local rig")
assert(accessory.Parent == character and shirt.Parent == character and pants.Parent == character)
assert(colors.Parent == character and graphic.Parent == character)
assert(face.Parent == localHead, "the target face belongs on the preserved local head")
assert(cloned[accessory] and cloned[shirt] and cloned[pants] and cloned[face])

print("PASS Disguise body: accessories/clothing/face/colors copy; local body meshes stay intact")
'''

assert "MeshId =" not in copy_appearance
assert "TextureID =" not in copy_appearance
assert "rebindAccessory(character, source)" in copy_appearance

with tempfile.TemporaryDirectory(prefix="disguise-body-") as tmp:
    path = Path(tmp) / "test.luau"
    path.write_text(script)
    subprocess.run([os.environ.get("LUAU", "luau"), str(path)], check=True)
