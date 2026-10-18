#!/usr/bin/env python3
"""Actual knife corridor: strict multi-ray WallCheck, current-cover rejection."""
import os, subprocess, tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
K = (ROOT / 'src/games/MM2/Blatant/KnifeThrow.lua').read_text()

script = PRELUDE + r'''
local lastKnifePrediction=nil
local lastKnifeError=nil
local targetPlayer={Character={}}
local readySpeed=nil
local ready=true
local function getReadyKnife() return ready and {GetAttribute=function() return readySpeed end} or nil end
local endpoint=Vector3.new(20,4,0)
local info={capturedPosition=Vector3.new(18,4,0),endpoint=endpoint,velocity=Vector3.new(16,0,0),
    model='kinematic-v51',leadSeconds=.12,flightSeconds=.2,sampleAge=0,samples=4,motionSource='fit'}
local aimResult=endpoint
local aimReason=nil
local aimSpeed=nil
local prediction={knifeAim=function(target,origin,speed)
    assert(target==targetPlayer)
    aimSpeed=speed
    return aimResult,(aimResult and info or nil),aimReason
end}
local corridor=true
local visible=true
local corridorRays=0
local coverageRays=0
local function isWeaponPathClear(origin,finish,character,strict,opts)
    assert(strict==true,"the blade must not skip invisible solid parts")
    assert(character==targetPlayer.Character)
    if opts==nil then
        coverageRays+=1
        return visible
    end
    assert(opts.ignoreTarget and opts.requireTarget==nil)
    corridorRays+=1
    return corridor
end
local function reset()
    corridorRays=0
    coverageRays=0
end
''' + section(K, '    local function readKnifeSpeed', '    type ThrowJoint') + r'''
reset()
assert(resolveKnifeAim(targetPlayer,Vector3.zero)==endpoint)
assert(lastKnifePrediction==info and lastKnifeError==nil)
near(aimSpeed,96)
assert(coverageRays==1,coverageRays)
assert(corridorRays==5,corridorRays)
pass("corridor: one current-body ray, then centre + four 0.5-stud rays")

readySpeed=120;resolveKnifeAim(targetPlayer,Vector3.zero);near(aimSpeed,120)
readySpeed=10;resolveKnifeAim(targetPlayer,Vector3.zero);near(aimSpeed,96)
readySpeed=0/0;resolveKnifeAim(targetPlayer,Vector3.zero);near(aimSpeed,96)
pass("speed probe: ThrowSpeed inside 24-300, otherwise 96")

reset();visible=false
assert(resolveKnifeAim(targetPlayer,Vector3.zero)==nil and lastKnifeError=='covered')
assert(coverageRays==1 and corridorRays==0,"cover is rejected before any corridor ray")
visible=true
reset();corridor=false
assert(resolveKnifeAim(targetPlayer,Vector3.zero)==nil and lastKnifeError=='obstructed')
assert(coverageRays==1 and corridorRays==1,"a blocked corridor stops at the first ray")
corridor=true
pass("current cover and blocked corridor both fail closed")

reset();aimResult=nil;aimReason='unreachable'
assert(resolveKnifeAim(targetPlayer,Vector3.zero)==nil and lastKnifeError=='unreachable')
assert(corridorRays==0 and coverageRays==0)
aimResult=Vector3.new(500,0,0);aimReason=nil
assert(resolveKnifeAim(targetPlayer,Vector3.zero)==nil and lastKnifeError=='too far')
assert(corridorRays==0,"an absurd lead is refused before any ray")
aimResult=endpoint
pass("unreachable and >400-stud leads are refused without rays")

reset();local far=Vector3.new(300,4,0);aimResult=far;info.flightSeconds=3.2
assert(resolveKnifeAim(targetPlayer,Vector3.zero)==far,
    "a slow blade over 300 studs is still thrown: no arbitrary range cap")
info.flightSeconds=.2
aimResult=endpoint
reset();targetPlayer.Character=nil
assert(resolveKnifeAim(targetPlayer,Vector3.zero)==nil and lastKnifeError==nil)
targetPlayer.Character={}
ready=false;assert(resolveKnifeAim(targetPlayer,Vector3.zero)==endpoint and aimSpeed==96)
ready=true
pass("long throws stay allowed; missing character and tool fall back safely")
'''
assert 'KNIFE_VISIBILITY_PARTS' not in K
assert 'predictAim' not in K
assert K.count(':FireServer(') == 1
with tempfile.TemporaryDirectory(prefix='knife-wallcheck-') as tmp:
    p = Path(tmp) / 'test.luau'
    p.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(p)], check=True)
