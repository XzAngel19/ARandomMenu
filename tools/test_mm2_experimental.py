#!/usr/bin/env python3
"""Experimental Auto Shoot chooses one route; mocks do not prove hits."""
from pathlib import Path
import os
import subprocess
import tempfile
from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
SHOOT = (ROOT / 'src/games/MM2/Blatant/Shoot.lua').read_text()
AUTO = (ROOT / 'src/games/MM2/Combat/AutoShoot.lua').read_text()
MANIFEST = (ROOT / 'src/libraries/Manifest.lua').read_text()
for path in ('src/games/universal/Movement/SafeWalk.lua',
             'src/games/universal/Combat/TargetStrafe.lua',
             'src/games/universal/Combat/TriggerBot.lua'):
    assert not (ROOT / path).exists() and path not in MANIFEST, path

code = PRELUDE + r'''
local root = {Position = Vector3.new(40, 0, 0), AssemblyLinearVelocity = Vector3.zero}
local character = {FindFirstChild = function(_, name) return name == 'HumanoidRootPart' and root or nil end}
local target = {Character = character}
''' + section(SHOOT, '    local function chooseExperimentalGunMode(', '    -- How long an authored request owns the gun.') + r'''
assert(chooseExperimentalGunMode(target, Vector3.zero) == 'Bullet')
root.AssemblyLinearVelocity = Vector3.new(8, 0, 0)
assert(chooseExperimentalGunMode(target, Vector3.zero) == 'CFrame')
root.Position = Vector3.new(12, 0, 0)
assert(chooseExperimentalGunMode(target, Vector3.zero) == 'Bullet')
root.Position = Vector3.new(40, 0, 0)
assert(chooseExperimentalGunMode(nil, Vector3.zero) == 'Bullet')

local settings = {mode = 'Experimental', wallCheck = true, proximity = false}
local autoShootActive = true
local localRoot = {CFrame = CFrame.new(Vector3.zero)}
local gun = {}
local localCharacter, humanoid = {}, {}
local function findLocalGun() return gun, localCharacter, humanoid, localRoot end
local proximitySeen = nil
local function resolveMurdererTarget(_, proximity)
    proximitySeen = proximity
    return target, root
end
local function ensureGunEquipped() return true end
local lastShotSentAt = 0
local AUTO_SHOT_PACE_SECONDS = 0.22
local legacyCalls, calls, result = 0, {}, true
local function fireCFrameShotImmediate() legacyCalls += 1 end
local function fireBulletShotImmediate() legacyCalls += 1 end
local status = nil
local AutoShootFeature = {SetStatus = function(_, text) status = text end}
local function getGunOriginCFrame() return CFrame.new(Vector3.zero) end
local state = {mm2ChooseExperimentalAim = chooseExperimentalGunMode}
state.mm2FireGunShot = function(player, opts)
    table.insert(calls, {player=player, opts=opts})
    return result
end
''' + section(AUTO, '    local function autoShootTick()', '    local function watchToolContainer(') + r'''
now = 1
root.AssemblyLinearVelocity = Vector3.zero
autoShootTick()
assert(#calls == 1 and calls[1].player == target and calls[1].opts.silent == false
    and calls[1].opts.wallCheck == true and calls[1].opts.continuous == true
    and string.find(status, 'Bullet · request sent', 1, true) and legacyCalls == 0)
autoShootTick()
assert(#calls == 1, 'local pacing must not dispatch twice')
now = 2
settings.proximity, settings.wallCheck = true, false
root.AssemblyLinearVelocity = Vector3.new(12, 0, 0)
autoShootTick()
assert(#calls == 2 and calls[2].opts.silent == true and calls[2].opts.wallCheck == false
    and proximitySeen == true and string.find(status, 'CFrame · request sent', 1, true)
    and legacyCalls == 0)
now = 3
result = false
autoShootTick()
assert(#calls == 3 and legacyCalls == 0 and string.find(status, 'not sent', 1, true),
    'a rejected/uncertain request must not trigger another transport')
autoShootActive = false
now = 4
autoShootTick()
assert(#calls == 3, 'OFF must not dispatch')
print('PASS experimental Auto Shoot: policy, independent options, one route, rejection and OFF')
'''

with tempfile.TemporaryDirectory(prefix='mm2-experimental-') as directory:
    script = Path(directory) / 'test.luau'
    script.write_text(code)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(script)], check=True)
