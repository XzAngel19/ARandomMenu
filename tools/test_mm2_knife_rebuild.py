#!/usr/bin/env python3
"""Actual v34 Knife reconstruction: matrix-based R6/R15 poses and release ownership."""
import os
import subprocess
import tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'src/games/MM2/Blatant/KnifeThrow.lua').read_text()
MATRICES = r'''
local cf={}
local function make(p,r) return setmetatable({Position=p,r=r or {1,0,0,0,1,0,0,0,1}},cf) end
local function rotate(a,v)
    local r=a.r
    return Vector3.new(r[1]*v.X+r[2]*v.Y+r[3]*v.Z,r[4]*v.X+r[5]*v.Y+r[6]*v.Z,r[7]*v.X+r[8]*v.Y+r[9]*v.Z)
end
CFrame.new=function(p) return make(p or Vector3.zero) end
cf.__mul=function(a,b)
    local r={}
    for i=0,2 do for j=0,2 do
        local v=0
        for k=0,2 do v+=a.r[i*3+k+1]*b.r[k*3+j+1] end
        r[i*3+j+1]=v
    end end
    return make(a.Position+rotate(a,b.Position),r)
end
cf.__sub=function(a,v) return make(a.Position-v,a.r) end
cf.__index={Lerp=function(a,b,t)
    if t>=1 then return b end
    local r={};for i=1,9 do r[i]=a.r[i]+(b.r[i]-a.r[i])*t end
    return make(a.Position+(b.Position-a.Position)*t,r)
end}
CFrame.Angles=function(x,y,z)
    local c,s=math.cos,math.sin
    return make(Vector3.zero,{1,0,0,0,c(x),-s(x),0,s(x),c(x)})
        *make(Vector3.zero,{c(y),0,s(y),0,1,0,-s(y),0,c(y)})
        *make(Vector3.zero,{c(z),-s(z),0,s(z),c(z),0,0,0,1})
end
'''
script = PRELUDE + MATRICES + r'''
for _,rig in ipairs({'R6','R15'}) do
    local joints={}
    local function joint(name,basis)
        local j={Parent=true,C0=CFrame.new(Vector3.new(1,.5,0))*basis,Transform=CFrame.Angles(.1,0,0),IsA=function(_,c) return c=='Motor6D' end}
        joints[name]=j;return j
    end
    local shoulder=joint('shoulder',rig=='R6' and CFrame.Angles(0,math.pi/2,0) or CFrame.new())
    local elbow=joint('elbow',CFrame.new())
    local wrist=joint('wrist',CFrame.new())
    local parts={}
    local function part(name,key,j) parts[name]={FindFirstChild=function(_,n) return n==key and j or nil end} end
    if rig=='R6' then part('Torso','Right Shoulder',shoulder) else
        part('RightUpperArm','RightShoulder',shoulder)
        part('RightLowerArm','RightElbow',elbow)
        part('RightHand','RightWrist',wrist)
    end
    local character={FindFirstChild=function(_,name) return parts[name] end}
    local LocalPlayer={Character=character}
    local knife={Parent=character}
    local knifeThrowSettings={animation=true}
    local featureConnections={}
    local tick=nil
    local TaskManager={Connect=function(_,fn,phase)
        assert(phase=='render','pose must be applied after animator work')
        tick=fn;return {Disconnect=function() tick=nil end}
    end}
    local function disconnectFeatureConnection(key)
        if featureConnections[key] then featureConnections[key]:Disconnect();featureConnections[key]=nil end
    end
''' + section(SOURCE, '    type ThrowJoint', '    local function throwKnife') + r'''
    local c0,transform=shoulder.C0,shoulder.Transform
    local sends=0
    local function release() sends+=1 end
    playThrowAnimation(knife,release)
    assert(tick and throwPending)
    tick(.2)
    local down=rotate(shoulder.C0,Vector3.new(0,-1,0))
    assert(down.Y>.8,rig..' must lift the arm ABOVE the shoulder, not sideways')
    near((shoulder.C0.Position-c0.Position).Magnitude,0)
    assert(sends==0,'windup must happen before the packet')
    tick(.101)
    down=rotate(shoulder.C0,Vector3.new(0,-1,0))
    assert(down.Z<-.9,rig..' release arm must point forward')
    assert(sends==1 and not throwPending)
    tick(.26)
    assert(sends==1 and not tick and shoulder.C0==c0 and shoulder.Transform==transform)
    for _,j in pairs(joints) do assert(j.Transform~=nil) end
    playThrowAnimation(knife,release);tick(.1);knife.Parent={};tick(.01)
    assert(not tick and sends==1 and shoulder.C0==c0 and shoulder.Transform==transform,'unequip cancels before release')
    knife.Parent=character;playThrowAnimation(knife,release);tick(.1);stopThrowAnimation();stopThrowAnimation()
    assert(not tick and sends==1 and shoulder.C0==c0,'OFF is idempotent and cannot fire pending packet')
    playThrowAnimation(knife,release);tick(.1);LocalPlayer.Character={};tick(.01)
    assert(not tick and sends==1 and shoulder.C0==c0,'respawn cancels')
    LocalPlayer.Character=character;knifeThrowSettings.animation=false
    playThrowAnimation(knife,release);assert(sends==2 and not tick,'animation OFF fires immediately')
    knifeThrowSettings.animation=true
    playThrowAnimation(knife,release);tick(1)
    assert(sends==3 and not tick,'a stalled frame emits at most one packet')
    pass('actual '..rig..' throw: raised arm, forward release, render phase, cancellation, exact restore')
end
'''
script += r'''
do
local knifeThrowSettings={animation=true,mode='Normal',range=120,spawnOffset=5,fireDelay=1,throwHz=60}
local lastThrow=-math.huge
local throwPending=false
local root={Position=Vector3.new(30,0,0)}
local target={Character={FindFirstChild=function() return root end}}
local valid=true
local function isValidTarget() return valid end
local LocalPlayer={Character={FindFirstChild=function() return nil end}}
local sends,notes=0,0
local originalFrame=CFrame.new(Vector3.new(1,2,3))*CFrame.Angles(.4,.8,.2)
local handle={CFrame=originalFrame,IsA=function(_,c) return c=='BasePart' end}
local remote={IsA=function() return true end,FireServer=function(_,origin,aim)
    assert(origin==handle.CFrame,'normal packet must retain oriented handle frame')
    near(aim.Position.X,root.Position.X)
    sends+=1
end}
local events={FindFirstChild=function() return remote end}
local knife={Name='Knife',Parent=LocalPlayer.Character,FindFirstChild=function(_,n) return n=='Handle' and handle or events end}
local function getReadyKnife() return knife.Parent==LocalPlayer.Character and knife or nil end
local function findNearestTarget() return target end
local predictionCalls=0
local function predictAim() predictionCalls+=1;return root.Position end
local visible=true
local function isWeaponPathClear() return visible end
local pending=nil
local function playThrowAnimation(_,fn) pending=fn;throwPending=true end
local function stopThrowAnimation() pending=nil;throwPending=false end
local trajectoryCalibration={noteAuthoredShot=function(_,shot)
    near(shot.aimPos.X,root.Position.X)
    assert(shot.settings.model=='linear-intercept-v34')
    notes+=1
end}
'''+section(SOURCE,'    local function throwKnife','    local function toggleKnifeThrow')+r'''
now=10;throwKnife();assert(pending and sends==0 and predictionCalls==0)
root.Position=Vector3.new(40,0,0)
local release=pending;throwPending=false;pending=nil;release()
assert(sends==1 and notes==1 and predictionCalls==1)
throwKnife();assert(not pending,'server interval starts at release')
now+=2;throwKnife();assert(pending)
valid=false;release=pending;throwPending=false;pending=nil;release();assert(sends==1,'invalidated target cancels release')
valid=true;throwKnife();knife.Parent={};release=pending;throwPending=false;pending=nil;release();assert(sends==1,'unequip cancels packet')
knife.Parent=LocalPlayer.Character;throwKnife();visible=false;release=pending;throwPending=false;pending=nil;release();assert(sends==1,'WallCheck rechecked at release')
pass('actual throw packet: deferred, fresh target prediction, oriented handle frame, cooldown and cancellation')
end
'''
with tempfile.TemporaryDirectory(prefix='knife-rebuild-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
