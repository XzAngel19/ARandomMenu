#!/usr/bin/env python3
"""Execute actual equipped-only action gates and reconstructed animation lifecycle."""
import os
from pathlib import Path
import subprocess
import tempfile
from test_mm2_precision import PRELUDE, section
ROOT=Path(__file__).resolve().parents[1]
K=(ROOT/'src/games/MM2/Blatant/KnifeThrow.lua').read_text()
S=(ROOT/'src/games/MM2/Blatant/Shoot.lua').read_text()
A=(ROOT/'src/games/MM2/Blatant/KnifeAura.lua').read_text()

script=PRELUDE+r'''
do
local state={mm2SilentAimEnabled=true}
local character={}
local LocalPlayer={Character=character}
local function findMurderer() return LocalPlayer end
local knife={Parent={},GetAttribute=function() return nil end}
local function getPlayerWeapon(_,name,equippedOnly)
    assert(name=='Knife' and equippedOnly==true,'never query backpack for action')
    return knife
end
'''+section(K,'    local function getReadyKnife','    local function readKnifeSpeed')+r'''
assert(getReadyKnife()==nil)
knife.Parent=character;assert(getReadyKnife()==knife)
knife.Parent={};assert(getReadyKnife()==nil)
pass('actual Knife readiness: only equipped; no forced equip; unequip allowed')
end

do
local shootFeatureActive=true
local autoShootActive=true
local function autoStatus() end
local lastRejectReason=''
local character={}
local LocalPlayer={Character=character}
local gun={Parent={}}
local target={}
local sent=0
local function getPlayerWeapon(_,_,equippedOnly) assert(equippedOnly);return gun end
local function getSelectedShootTarget() return target end
local function fireGunAtTarget(t,opts)
    assert(t==target and opts.whenReady==true and opts.maxError==nil and opts.quiet)
    sent+=1;return true
end
local function notify() end
'''+section(S,'    local function autoShootTick','    updateAutoShootConnection =')+r'''
now=10;autoShootTick();assert(sent==0)
gun.Parent=character;autoShootTick();assert(sent==1)
autoShootTick();assert(sent==2,'no extra fire delay after an attempt')
now+=0.01;autoShootTick();assert(sent==3)
gun.Parent={};now+=1;autoShootTick();assert(sent==3)
gun.Parent=character;shootFeatureActive=false;autoShootTick();assert(sent==3)
pass('actual Auto Shoot tick: current frame attempts, held-only, master OFF, no interval/confidence/distance gate')
end

do
local character,humanoid={},{}
local LocalPlayer={Character=character}
local reloading=false
local gun={Parent={},Enabled=true,GetAttribute=function(_,name) return name=='Reloading' and reloading or nil end}
local remote={IsA=function() return true end,FireServer=function() end}
function gun:FindFirstChild() return remote end
local function getCharacterParts() return character,humanoid end
local function getPlayerWeapon(_,_,equippedOnly) assert(equippedOnly);return gun end
local function notify() end
local mm2Settings={silentAim=false,shootWallCheck=true,silentSpawn='Through',silentSweep=0}
local function getGunOriginCFrame() return CFrame.new(Vector3.new(0,0,-10)) end
local endpoint=Vector3.new(1000,1,1)
local function isPlayerAlive() return true end
local function isProtectedTarget() return false end
local function getPlayerRole() return 'Murderer' end
local function validateGunShot() return true end
local function isWeaponPathClear() return true end
local function buildSilentShot() return CFrame.new(Vector3.zero),CFrame.new(endpoint),2.5 end
local function macroUnequip() end
local info={endpoint=endpoint,targetPosition=endpoint,capturedPosition=endpoint,velocity=Vector3.zero,
    leadSeconds=.1,model='kinematic-v51',sampleAge=0,samples=4,rtt=.1,motionSource='fit'}
local prediction={gunAim=function() return endpoint,info,nil end}
local queued,notes=0,0
local state={mm2ShotFeedback={queue=function() queued+=1 end}}
local trajectoryCalibration={noteAuthoredShot=function() notes+=1 end}
local function macroUnequip() end
'''+section(S,'    type FireOptions','    local shootFeatureActive:')+r'''
local target={Character={}}
assert(not fireGunAtTarget(target,{whenReady=true,quiet=true}))
gun.Parent=character
assert(fireGunAtTarget(target,{whenReady=true,quiet=true}))
assert(queued==1 and notes==1)
assert(fireGunAtTarget(target,{whenReady=true,quiet=true}),'a request must not invent a 3.1s cooldown')
assert(queued==2 and notes==2)
reloading=true;assert(not fireGunAtTarget(target,{whenReady=true,quiet=true}))
reloading=false;gun.Enabled=false
assert(not fireGunAtTarget(target,{whenReady=true,quiet=true}))
gun.Enabled=true;assert(fireGunAtTarget(target,{whenReady=true,quiet=true}),'fires immediately when native readiness returns')
pass('actual firing gate: 1000-stud endpoint, no invented cooldown, no error gate; native reloading/disabled respected')
end

do
local character={}
local gun={Parent={},Enabled=true}
local equips,shots=0,0
local cancel=false
local humanoid={EquipTool=function(_,tool) equips+=1;tool.Parent=character end}
local LocalPlayer={Character=character}
local function getCharacterParts() return character,humanoid end
local function getPlayerWeapon(_,_,equipped) assert(not equipped);return gun end
local RunService={Heartbeat={Wait=function() if cancel then gun.Parent={} end end}}
local function getSelectedShootTarget() return {} end
local function fireGunAtTarget(_,opts) assert(opts.whenReady==true and opts.maxError==nil);shots+=1 end
local shootFeatureActive=true
local function notify() end
'''+section(S,'    local manualShotPending:','    local function toggleShootMurderer')+r'''
triggerManualShot();assert(equips==1 and shots==1)
triggerManualShot();assert(equips==1 and shots==2,'held manual gun must not re-equip')
gun.Parent={};cancel=true;triggerManualShot()
assert(equips==2 and shots==2,'manual action must respect an unequip during the equip frame')
shootFeatureActive=false;triggerManualShot();assert(equips==2)
pass('actual manual Shoot: equips once, fires; respects unequip and OFF; Auto route stays held-only')
end

'''

assert 'EquipTool' not in K
assert 'EquipTool' not in section(S,'    local function fireGunAtTarget','    local shootFeatureActive:')
assert '"Auto Range"' not in A and 'autoRange' not in A
assert '"Throw now"' not in K
assert '"Max error"' not in S
assert 'prediction.gunAim' in S and 'validateGunShot' in S
assert 'computeGunAim' not in S
with tempfile.TemporaryDirectory(prefix='equipped-actions-') as tmp:
    path=Path(tmp)/'actions.luau';path.write_text(script)
    subprocess.run([os.environ.get('LUAU','luau'),str(path)],check=True)
