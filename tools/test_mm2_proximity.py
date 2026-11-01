#!/usr/bin/env python3
"""Exercise Auto Shoot's real proximity filter and the real visibility helper.

The GUI is mocked; these checks do not simulate a Roblox server or damage.
"""
import os
import subprocess
import tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
AUTO = (ROOT / 'src/games/MM2/Combat/AutoShoot.lua').read_text()
WIDGETS = (ROOT / 'src/guis/Wurst/Code/Widgets.lua').read_text()

code = PRELUDE + r'''
local settings = {mode='Bullet', proximity=false, aura=25, wallCheck=true}
local localRoot = {Position=Vector3.zero, CFrame=CFrame.new(Vector3.zero)}
local targetRoot = {Position=Vector3.new(80, 0, 0), AssemblyLinearVelocity=Vector3.zero}
local targetChar = {FindFirstChild=function(_, n) return n=='HumanoidRootPart' and targetRoot end}
local target = {Character=targetChar}
local LocalPlayer = {}
local function findMurderer() return target end
local function getPlayerRole() return 'Murderer' end
local function getPlayerWeapon() return nil end
local function isPlayerAlive() return true end
local function isProtectedTarget() return false end
''' + section(AUTO, '    local function resolveMurdererTarget(', '    local function computeTargetEndpoint(') + r'''
assert(resolveMurdererTarget(localRoot, false)==target, 'OFF must not impose the Aura radius')
assert(resolveMurdererTarget(localRoot, true)==nil, 'ON must reject a target outside the radius')
targetRoot.Position=Vector3.new(20, 0, 0)
assert(resolveMurdererTarget(localRoot, true)==target, 'ON must allow a target inside the radius')
targetRoot.Position=Vector3.new(80, 0, 0)

local gun, character, humanoid = {}, {}, {}
local function findLocalGun() return gun, character, humanoid, localRoot end
local function ensureGunEquipped() return true end
local autoShootActive = true
local lastShotSentAt = 0
local AUTO_SHOT_PACE_SECONDS = 0.22
local sends = {}
local function fireBulletShotImmediate() table.insert(sends, 'Bullet'); return true end
local function fireCFrameShotImmediate() table.insert(sends, 'CFrame'); return true end
local state = {mm2FireGunShot=function(_, opts) table.insert(sends, opts.silent and 'CFrame' or 'Bullet'); return true end}
local function getGunOriginCFrame() return CFrame.new(Vector3.zero) end
local AutoShootFeature = {enabled=true, SetStatus=function() end, updateExpandedSize=function() end}
''' + section(AUTO, '    local function autoShootTick()', '    local function watchToolContainer(') + r'''
for _, mode in ipairs({'Bullet','CFrame','Experimental'}) do
    settings.mode=mode; settings.proximity=false; now+=1
    local count=#sends; autoShootTick()
    assert(#sends==count+1, mode..' must not filter far targets when Proximity is OFF')
    settings.proximity=true; now+=1
    count=#sends; autoShootTick()
    assert(#sends==count, mode..' must respect radius when Proximity is ON')
    targetRoot.Position=Vector3.new(20,0,0); now+=1; autoShootTick()
    assert(#sends==count+1, mode..' must shoot an in-range target')
    targetRoot.Position=Vector3.new(80,0,0)
end
local options = {Visible=true}
local auraSlider = {Visible=true, Parent=options}
local updates = 0
AutoShootFeature.updateExpandedSize = function() updates+=1 end
local function updateStatus() end
''' + section(WIDGETS, '    local function setOptionVisible(', '    local function addToggleOption(') + section(AUTO, '    local function refreshProximityOption()', '    local function syncMode()') + r'''
settings.proximity=false; refreshProximityOption()
assert(options.Visible and not auraSlider.Visible, 'OFF must hide only the Aura row, not the options container')
settings.proximity=true; refreshProximityOption()
assert(options.Visible and auraSlider.Visible, 'ON must show Aura without hiding the other options')
settings.proximity=false; refreshProximityOption()
assert(options.Visible and not auraSlider.Visible and updates==3, 'repeat toggles must preserve the settings window')
print('PASS Auto Shoot: Proximity gates radius only when ON; Aura row alone is hidden and restored')
'''

with tempfile.TemporaryDirectory(prefix='mm2-proximity-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(code)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
