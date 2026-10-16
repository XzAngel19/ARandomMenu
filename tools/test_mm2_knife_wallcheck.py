#!/usr/bin/env python3
"""Actual Knife visibility resolution and nearest-target selection, without changing prediction."""
import os, subprocess, tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE, section
ROOT=Path(__file__).resolve().parents[1]
K=(ROOT/'src/games/MM2/Blatant/KnifeThrow.lua').read_text()
script=PRELUDE+r'''
local knifeThrowSettings={wallCheck=true}
local resolveKnifeAim
local function body(p)
 return {Position=p,Size=Vector3.new(2,2,1),CFrame={RightVector=Vector3.new(0,0,1),UpVector=Vector3.new(0,1,0)},IsA=function(_,c) return c=='BasePart' end}
end
local function character(x)
 local parts={HumanoidRootPart=body(Vector3.new(x,0,0)),UpperTorso=body(Vector3.new(x,2,0)),Head=body(Vector3.new(x,4,0))}
 return {FindFirstChild=function(_,n) return parts[n] end}
end
local nearTarget={Character=character(10)}
local farTarget={Character=character(25)}
local LocalPlayer={Character=character(0)}
local Players={GetPlayers=function() return {nearTarget,farTarget} end}
local function isValidTarget() return true end
local lead=Vector3.new(10,0,0)
local function predictAim(t) return t.Character:FindFirstChild('HumanoidRootPart').Position+lead end
local visibility='head'
local calls=0
local function isWeaponPathClear(_,point,target,strict,opts)
 assert(strict==nil and (opts.ignoreTarget or opts.requireTarget))
 calls+=1
 if target==farTarget.Character then return true end
 if visibility=='head' then return point.Y>3 end
 if visibility=='torso' then return point.Y>1 and point.Y<3 and point.Z>.5 end
 return false
end
''' + section(K, '    local KNIFE_VISIBILITY_PARTS', '    type ThrowJoint') + section(K, '    local function findNearestTarget', '    local function getReadyKnife') + r'''
local origin=Vector3.zero
local aim=resolveKnifeAim(nearTarget,origin)
near(aim.X,20);near(aim.Y,4)
assert(findNearestTarget(origin)==nearTarget,'partially visible target must not be rejected by a center-only prefilter')
visibility='torso';aim=resolveKnifeAim(nearTarget,origin)
near(aim.X,20);near(aim.Y,2);near(aim.Z,.55)
visibility='blocked';calls=0
assert(resolveKnifeAim(nearTarget,origin)==nil and calls<=60,'fully blocked fails closed with bounded probes')
assert(findNearestTarget(origin)==farTarget,'blocked nearest player must not starve visible farther player')
print('PASS Knife WallCheck: predicted head/torso rescue, preserved projectile lead, full obstruction, bounded probes, visible-target selection, always-on LOS')
'''
with tempfile.TemporaryDirectory(prefix='knife-wallcheck-') as tmp:
 p=Path(tmp)/'test.luau';p.write_text(script)
 subprocess.run([os.environ.get('LUAU','luau'),str(p)],check=True)
