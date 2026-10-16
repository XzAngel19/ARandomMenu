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
local character={}
local LocalPlayer={Character=character}
local function findMurderer() return LocalPlayer end
local knife={Parent={},GetAttribute=function() return nil end}
local function getPlayerWeapon(_,name,equippedOnly)
    assert(name=='Knife' and equippedOnly==true,'never query backpack for action')
    return knife
end
'''+section(K,'    local function getReadyKnife','    local function predictAim')+r'''
assert(getReadyKnife()==nil)
knife.Parent=character;assert(getReadyKnife()==knife)
knife.Parent={};assert(getReadyKnife()==nil)
pass('actual Knife readiness: only equipped; no forced equip; unequip allowed')
end

do
local lastAutoShot=-math.huge
local autoSettings={mode='Normal',fireDelay=0.1}
local lastAutoReject=nil
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
'''+section(S,'    local function autoShootTick','    local function toggleAutoShoot')+r'''
now=10;autoShootTick();assert(sent==0)
gun.Parent=character;autoShootTick();assert(sent==1)
autoShootTick();assert(sent==1)
now+=0.2;autoShootTick();assert(sent==2)
gun.Parent={};now+=1;autoShootTick();assert(sent==2)
pass('actual Auto Shoot tick: held gun only; no max-error wait; interval; user unequip')
end

do
local character,humanoid={},{}
local LocalPlayer={Character=character}
local gun={Parent={},Enabled=true,GetAttribute=function() return nil end}
local remote={IsA=function() return true end,FireServer=function() end}
function gun:FindFirstChild() return remote end
local function getCharacterParts() return character,humanoid end
local function getPlayerWeapon(_,_,equippedOnly) assert(equippedOnly);return gun end
local function notify() end
local mm2Settings={silentAim=false,shootWallCheck=true,motionSampleHz=60,gunLeadBias=0}
local function getGunOriginCFrame() return CFrame.new(Vector3.new(0,0,-10)) end
local endpoint=Vector3.new(1,1,1)
local prediction={endpoint=endpoint,targetPosition=endpoint,capturedPosition=endpoint,velocity=Vector3.zero,errorRadius=5,leadSeconds=.1}
local function computeGunAim(_,_,options)
    assert(options.allowUncertain and not options.ignoreVisibility)
    return CFrame.new(endpoint),prediction
end
local queued,notes=0,0
local state={mm2ShotFeedback={queue=function() queued+=1 end}}
local trajectoryCalibration={noteAuthoredShot=function() notes+=1 end}
local function macroUnequip() end
local lastGunFireServer=-math.huge
local GUN_SERVER_COOLDOWN=3.1
'''+section(S,'    type FireOptions','    local shootFeatureActive:')+r'''
local target={Character={}}
assert(not fireGunAtTarget(target,{whenReady=true,quiet=true}))
gun.Parent=character
assert(fireGunAtTarget(target,{whenReady=true,quiet=true}))
assert(queued==1 and notes==1)
assert(not fireGunAtTarget(target,{whenReady=true,quiet=true}),'server cooldown retained')
now+=4;gun.Enabled=false
assert(not fireGunAtTarget(target,{whenReady=true,quiet=true}))
pass('actual firing gate: no EquipTool path; high-error auto allowed; cooldown and disabled gun respected')
end

do
local cfMt={}
CFrame.new=function(p) return setmetatable({Position=p or Vector3.zero},cfMt) end
CFrame.Angles=function(a,b,c) return CFrame.new(Vector3.new(a,b,c)) end
cfMt.__mul=function(a,b) return CFrame.new(a.Position+b.Position) end
cfMt.__index={Lerp=function(a,b,t) return CFrame.new(a.Position+(b.Position-a.Position)*t) end}
local joint={Parent=true,C0=CFrame.new(Vector3.new(.2,.3,.4)),Transform=CFrame.new(),IsA=function(_,c) return c=='Motor6D' end}
local torso={FindFirstChild=function(_,name) if name=='Right Shoulder' then return joint end end}
local humanoid={}
local character={FindFirstChildOfClass=function() return humanoid end,FindFirstChild=function(_,name) if name=='Torso' then return torso end end}
local LocalPlayer={Character=character}
local knife={Parent=character,GetDescendants=function() return {} end}
local knifeThrowSettings={animation=true}
local featureConnections={}
local tick=nil
local TaskManager={Connect=function(_,fn) tick=fn;return {Disconnect=function() tick=nil end} end}
local function disconnectFeatureConnection(key)
    if featureConnections[key] then featureConnections[key]:Disconnect();featureConnections[key]=nil end
end
'''+section(K,'    local throwTrack:','    local function throwKnife')+r'''
local base=joint.C0
playThrowAnimation(knife);assert(tick)
tick(.06);assert((joint.C0.Position-base.Position).Magnitude>.1,'wind-up changes real joint')
for i=1,12 do if tick then tick(.04) end end
assert(joint.C0==base and not tick,'recovery restores exact baseline')
playThrowAnimation(knife);tick(.06);knife.Parent={};tick(.02)
assert(joint.C0==base and not tick,'unequip releases reconstruction immediately')
knife.Parent=character;playThrowAnimation(knife);tick(.06)
stopThrowAnimation();stopThrowAnimation()
assert(joint.C0==base and not tick,'disable cleanup idempotent')
pass('actual reconstructed throw: wind-up/release/recovery; no marker or extra remote; unequip and OFF restore pose')
end
'''

assert 'EquipTool' not in K and 'EquipTool' not in S
assert '"Auto Range"' not in A and 'autoRange' not in A
assert '"Throw now"' in K
assert '"Max error"' not in S
assert 'allowUncertain' in S
with tempfile.TemporaryDirectory(prefix='equipped-actions-') as tmp:
    path=Path(tmp)/'actions.luau';path.write_text(script)
    subprocess.run([os.environ.get('LUAU','luau'),str(path)],check=True)
