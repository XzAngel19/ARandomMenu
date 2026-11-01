#!/usr/bin/env python3
"""Auto Farm dispatches the real Silent constructor with its own WallCheck OFF.

This combines the real farm helper, Gun wrapper and shot constructor against a
mocked wall; no claim is made about Roblox server acceptance or damage.
"""
from pathlib import Path
import os
import subprocess
import tempfile
from test_mm2_precision import section
from test_gun_silent_constructor import code as gun_code

ROOT = Path(__file__).resolve().parents[1]
FARM = (ROOT / 'src/games/MM2/Other/AutoFarm.lua').read_text()
helper = section(FARM, '    local lastShotAt: number = -math.huge', '    local function toggleAutoFarm(')
code = gun_code + r'''
local farmStatus = nil
local function setStatus(value) farmStatus=value end
''' + helper + r'''
now=40
aimFor(12)
local wall = part(Vector3.new(6, 0, 0), Vector3.new(0.5, 8, 8), nil)
table.insert(scene, wall)
assert(mm2Settings.shootWallCheck == true, 'Gun Aimbot WallCheck is ON')
assert(not isWeaponPathClear(muzzlePosition, aimInfo.endpoint, MURDERER.Character), 'the wall is real in the mock')
local authored
trajectoryCalibration.noteAuthoredShot = function(_, info) authored=info end
assert(shootMurderer(MURDERER), 'farm must send its Silent shot even with Gun WallCheck ON')
assert(remote.sends == 1 and authored and authored.silent == true and authored.settings.wallCheck == false,
    'one Silent packet must carry the farm override')
assert(not shootMurderer(MURDERER) and remote.sends==1, 'farm must pace repeated attempts')
now+=1
local attempts=0
state.mm2FireSilentShot=function(_, opts)
    attempts+=1
    assert(opts.continuous==true and opts.wallCheck==false and opts.quiet==true)
    return false
end
assert(not shootMurderer(MURDERER) and attempts==1 and remote.sends==1,
    'a refusal must not fall back to a Bullet or second send')
now+=1
state.mm2FireSilentShot=function() attempts+=1; error('send may already have happened') end
assert(not shootMurderer(MURDERER) and attempts==2 and remote.sends==1)
assert(not shootMurderer(MURDERER) and attempts==2, 'uncertain sends must be paced')
state.mm2FireSilentShot=nil; now+=1
assert(not shootMurderer(MURDERER) and farmStatus=='Silent shot unavailable' and remote.sends==1,
    'missing Silent path must not silently fall back to Bullet')
print('PASS Auto Farm: real Silent constructor, independent WallCheck OFF, pacing, refusal/error and missing path')
'''

with tempfile.TemporaryDirectory(prefix='mm2-farm-silent-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(code)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
