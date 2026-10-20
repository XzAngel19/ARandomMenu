#!/usr/bin/env python3
"""Actual knife aim: blade-sized probe, upward ladder over a rail, button trigger.

The blade is a physical projectile with a real cross-section. A rail that
covers the chest has to push the aim upward instead of cancelling the throw,
and the packet has to be built from CFrames so a tap and a click behave the
same.
"""
import os, subprocess, tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
K = (ROOT / 'src/games/MM2/Blatant/KnifeThrow.lua').read_text()

script = PRELUDE + r'''
local lastKnifePrediction=nil
local lastKnifeError=nil
local lastKnifeAimName=nil
local lastKnifeAimHeight=nil
local lastKnifeRadius=nil
local targetPlayer={Character={}}
local handleSize=Vector3.new(0.2,0.4,1.2)
local ready=true
local function getReadyKnife()
    if not ready then return nil end
    return {GetAttribute=function() return nil end,
        FindFirstChild=function(_,name) 
            if name=="Handle" then
                return {IsA=function(_,c) return c=="BasePart" end, Size=handleSize}
            end
            return nil
        end}
end
local endpoint=Vector3.new(20,4,0)
local info={capturedPosition=Vector3.new(18,4,0),endpoint=endpoint,velocity=Vector3.new(16,0,0),
    model='kinematic-v51',leadSeconds=.12,flightSeconds=.2,sampleAge=0,samples=4,motionSource='fit'}
local aimResult=endpoint
local aimReason=nil
local function readKnifeSpeed(knife) return 96 end
local prediction={knifeAim=function(target,origin,speed)
    assert(target==targetPlayer)
    return aimResult,(aimResult and info or nil),aimReason
end}
local LocalPlayer={Character={}}
-- The module checks typeof(hit.Instance)=="Instance"; in this harness a part
-- is a plain table, so the tag stands in for the Roblox type.
typeof=function(value)
    if type(value)=="table" and value.__instance then return "Instance" end
    return type(value)
end
local CollectionService={GetTagged=function() return {} end}
local Enum={RaycastFilterType={Exclude="Exclude"}}
local RaycastParams={new=function() return {} end}
local chestPart={__instance=true,IsDescendantOf=function(_,c) return c==targetPlayer.Character end}
local headPart={__instance=true,IsDescendantOf=function(_,c) return c==targetPlayer.Character end}
local railPart={__instance=true,IsDescendantOf=function() return false end}
-- The scenario decides what a body of this radius meets when thrown at `aim`.
local sphereHit=nil
local sphereCalls=0
local rayCalls=0
local ringHit=nil
local workspace={}
workspace.Spherecast=function(_,origin,radius,delta,params)
    sphereCalls+=1
    if type(sphereHit)=="function" then return sphereHit(origin+delta,radius) end
    return sphereHit
end
workspace.Raycast=function(_,origin,delta,params)
    rayCalls+=1
    local aim=origin+delta
    if ringHit and math.abs(origin.Y-aim.Y)<0.001 and origin.Y~=aim.Y then return nil end
    if type(ringHit)=="function" and math.abs((aim.OriginY or -999))>0 then return nil end
    if ringHit and origin.X~=0 then return ringHit(origin,delta) end
    return {Instance=chestPart,Position=aim}
end
''' + section(K, '    local MIN_KNIFE_RADIUS', '    type ThrowJoint') + r'''
local function reset()
    sphereCalls=0
    rayCalls=0
    ringHit=nil
    sphereHit=nil
end

-- 1. Chest clear: the first rung wins and one probe is enough.
reset()
sphereHit={Instance=chestPart,Position=endpoint}
local aim=resolveKnifeAim(targetPlayer,Vector3.zero)
assert(aim and (aim-endpoint).Magnitude<1e-9,"the chest is the default aim")
assert(lastKnifeAimName=="chest" and lastKnifeAimHeight==0)
assert(sphereCalls==1,"a clear chest costs one probe: "..sphereCalls)
assert(lastKnifeError==nil)
pass("knife aim: a clear chest is the first rung and costs one probe")

-- 2. A rail covers the chest: the aim climbs until the blade reaches a body
--    part. Body extents are used, not a fixed ray.
reset()
sphereHit=function(aimPoint,radius)
    if aimPoint.Y>=4.9 then return {Instance=headPart,Position=aimPoint} end
    return {Instance=railPart,Position=Vector3.new(aimPoint.X,4.5,aimPoint.Z)}
end
aim=resolveKnifeAim(targetPlayer,Vector3.zero)
assert(aim,"a covered chest must not cancel the throw when the head is free")
near(aim.Y,5.05,1e-6)
assert(lastKnifeAimName=="head",lastKnifeAimName)
assert(sphereCalls==3,"chest and upper chest reject, head wins: "..sphereCalls)
assert(lastKnifeAimHeight and lastKnifeAimHeight>1)
pass("knife aim: a rail over the chest moves the blade to the head")

-- 3. The radius is the blade's own cross-section, not a constant.
reset()
sphereHit={Instance=chestPart,Position=endpoint}
resolveKnifeAim(targetPlayer,Vector3.zero)
-- 0.2 x 0.4 x 1.2 -> half extents 0.1/0.2/0.6 -> middle 0.2
near(lastKnifeRadius,0.2,1e-9)
handleSize=Vector3.new(0.05,0.05,0.05)
resolveKnifeAim(targetPlayer,Vector3.zero)
near(lastKnifeRadius,0.12,1e-9)
handleSize=Vector3.new(4,4,4)
resolveKnifeAim(targetPlayer,Vector3.zero)
near(lastKnifeRadius,0.6,1e-9)
handleSize=Vector3.new(0.2,0.4,1.2)
pass("knife aim: blade radius is the middle half-extent, bounded")

-- 4. Every rung refused: fail closed as cover, never a blind throw.
reset()
sphereHit={Instance=railPart,Position=Vector3.new(10,2,0)}
assert(resolveKnifeAim(targetPlayer,Vector3.zero)==nil)
assert(lastKnifeError=="covered",lastKnifeError)
assert(sphereCalls==7,"all seven rungs must be probed: "..sphereCalls)
pass("knife aim: fully covered fails closed after the whole ladder")

-- 5. Engines without Spherecast: a centre ray proves the target, a ring ray
--    closer than it vetoes the throw.
reset()
workspace.Spherecast=function() error("Spherecast is not a valid member") end
local ringBlocked=true
workspace.Raycast=function(_,origin,delta,params)
    rayCalls+=1
    local isCentre=origin.Magnitude<1e-9
    if not isCentre then
        if ringBlocked then
            return {Instance=railPart,Position=Vector3.new(origin.X,2,origin.Z)}
        end
        return nil
    end
    return {Instance=chestPart,Position=Vector3.new(20,4,0)}
end
aim=resolveKnifeAim(targetPlayer,Vector3.zero)
assert(aim==nil and lastKnifeError=="covered",
    "a ring ray closer than the target must veto the throw")
assert(rayCalls==14,"seven rungs, centre plus the first vetoing ring ray: "..rayCalls)
ringBlocked=false
local before=rayCalls
aim=resolveKnifeAim(targetPlayer,Vector3.zero)
assert(aim and (aim-endpoint).Magnitude<1e-9,"a clear ring lets the centre ray decide")
assert(rayCalls-before==5,"the first rung costs centre plus four ring rays")
pass("knife aim: without Spherecast a closer ring ray vetoes the throw")

-- 6. Range and reachability keep their old refusal.
reset()
aimResult=nil;aimReason='unreachable'
assert(resolveKnifeAim(targetPlayer,Vector3.zero)==nil and lastKnifeError=='unreachable')
assert(sphereCalls==0 and rayCalls==0)
aimResult=Vector3.new(500,0,0);aimReason=nil
assert(resolveKnifeAim(targetPlayer,Vector3.zero)==nil and lastKnifeError=='too far')
aimResult=endpoint
ready=false
sphereHit={Instance=chestPart,Position=endpoint}
assert(resolveKnifeAim(targetPlayer,Vector3.zero)~=nil,"no blade size falls back to 0.25")
ready=true
pass("knife aim: unreachable and >400-stud leads are still refused")
'''

assert 'KNIFE_CORRIDOR_RADIUS' not in K, "the fixed 0.5 corridor is gone"
assert 'KNIFE_AIM_LADDER' in K
assert K.count(':FireServer(') == 1, "one throw path, one packet"
assert 'CFrame.new(origin.Position), CFrame.new(aim)' not in K, \
    "the origin must not be an identity-rotation frame again"
assert 'CFrame.lookAt(origin.Position, aim)' in K, \
    "the packet origin looks at the predicted point: coherent for servers that read LookVector"
assert 'remote:FireServer(originCFrame, CFrame.new(aim))' in K, \
    "the aim stays a position: that is where the blade has to end up"
assert 'knife.Activated:Connect' not in K, \
    "the button trigger was removed: throws are automatic only"
assert 'Throw with button' not in K
assert 'lastKnifeAimName' in K and 'knifeRadius = lastKnifeRadius' in K, \
    "the aim rung and the blade size must reach the calibration file"

with tempfile.TemporaryDirectory(prefix='knife-wallcheck-') as tmp:
    p = Path(tmp) / 'test.luau'
    p.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(p)], check=True)
