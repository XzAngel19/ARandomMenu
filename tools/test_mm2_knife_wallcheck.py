#!/usr/bin/env python3
"""Actual knife intercept hand-off and game-filter WallCheck, without visibility rescue."""
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
local clear=true
local clearCalls=0
local function isWeaponPathClear(origin,finish,character,strict,opts)
    clearCalls+=1
    assert(strict==nil and opts and opts.ignoreTarget)
    return clear
end
''' + section(K, '    local function readKnifeSpeed', '    type ThrowJoint') + r'''
assert(resolveKnifeAim(targetPlayer,Vector3.zero)==endpoint)
assert(lastKnifePrediction==info and lastKnifeError==nil)
near(aimSpeed,96)
assert(clearCalls==1)
readySpeed=120;resolveKnifeAim(targetPlayer,Vector3.zero);near(aimSpeed,120)
readySpeed=10;resolveKnifeAim(targetPlayer,Vector3.zero);near(aimSpeed,96)
readySpeed=0/0;resolveKnifeAim(targetPlayer,Vector3.zero);near(aimSpeed,96)
clear=false;clearCalls=0
assert(resolveKnifeAim(targetPlayer,Vector3.zero)==nil and lastKnifeError=='obstructed')
assert(lastKnifePrediction==nil and clearCalls==1,'WallCheck runs on the exact authored segment')
clear=true
aimResult=nil;aimReason='unreachable'
assert(resolveKnifeAim(targetPlayer,Vector3.zero)==nil and lastKnifeError=='unreachable')
assert(clearCalls==1,'an unsolvable intercept is not raycast')
aimResult=endpoint
targetPlayer.Character=nil
assert(resolveKnifeAim(targetPlayer,Vector3.zero)==nil and lastKnifeError==nil)
ready=false;targetPlayer.Character={}
assert(resolveKnifeAim(targetPlayer,Vector3.zero)==endpoint and aimSpeed==96)
pass('actual knife resolve: intercept, speed probe, single game-filter WallCheck, fail-closed obstruction')
'''
assert 'KNIFE_VISIBILITY_PARTS' not in K
assert 'predictAim' not in K
assert K.count(':FireServer(') == 1
with tempfile.TemporaryDirectory(prefix='knife-wallcheck-') as tmp:
    p = Path(tmp) / 'test.luau'
    p.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(p)], check=True)
