#!/usr/bin/env python3
"""Run actual MM2 prediction/control functions in Luau with deterministic mocks.

LUAU=/path/to/luau python3 tools/test_mm2_precision.py
No executor, remote server, third-party code execution or game connection.
Source sections fail closed when renamed; they are not copies of the algorithms.
"""
from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = (ROOT / "src/games/MM2/base.lua").read_text()
SHOOT = (ROOT / "src/games/MM2/Blatant/Shoot.lua").read_text()
KNIFE = (ROOT / "src/games/MM2/Blatant/KnifeThrow.lua").read_text()
AURA = (ROOT / "src/games/MM2/Blatant/KnifeAura.lua").read_text()


def section(text: str, start: str, end: str) -> str:
    assert text.count(start) == 1, start
    return start + text.split(start, 1)[1].split(end, 1)[0]


PRELUDE = r'''
local Vector3 = {}
local mt = {}
function Vector3.new(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0},mt) end
Vector3.zero=Vector3.new(0,0,0)
mt.__add=function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
mt.__sub=function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
mt.__unm=function(a) return a * -1 end
mt.__mul=function(a,b)
    if type(a)=="number" then a,b=b,a end
    return Vector3.new(a.X*b,a.Y*b,a.Z*b)
end
mt.__div=function(a,b) return a*(1/b) end
mt.__index=function(a,k)
    if k=="Magnitude" then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) end
    if k=="Unit" then return a/a.Magnitude end
    if k=="Dot" then return function(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end end
end
local CFrame={new=function(p) return {Position=p} end,lookAt=function(p,q)
    assert((q-p).Magnitude>0.00001,"degenerate CFrame")
    return {Position=p,Endpoint=q}
end}
local Enum={Material={Air="Air"},HumanoidStateType={Jumping="Jumping",Freefall="Freefall"},
    RaycastFilterType={Exclude="Exclude",Include="Include"}}
local now=0
local os={clock=function() return now end}
local function near(a,b,epsilon) assert(math.abs(a-b)<(epsilon or 1e-7),tostring(a).." != "..tostring(b)) end
local passed=0
local function pass(name) passed+=1; print("PASS",name) end
'''


def build() -> str:
    chunks = [PRELUDE, section(BASE, "local predictionMath = {}", "type MotionSample")]
    chunks.append(r'''
do
    for _,fps in ipairs({30,60,120,144,240}) do
        for _,hz in ipairs({20,30,60,120}) do
            local elapsed,count=0,0
            for i=1,fps*10 do
                local due
                due,elapsed=predictionMath.sampleDue(elapsed,1/fps,hz)
                if due then count+=1 end
            end
            assert(count==math.min(fps,hz)*10,`fps={fps}, hz={hz}, actual={count}`)
        end
    end
    local due,left=predictionMath.sampleDue(0,0.5,120)
    assert(due)
    assert(not predictionMath.sampleDue(left,0,120))
    assert(not predictionMath.finite(0/0) and not predictionMath.finite(math.huge))
    pass("20 cadence combinations; one callback maximum after a stall; finite guards")
end

do
    local offset=Vector3.new(120,0,0)
    for _,velocity in ipairs({Vector3.zero,Vector3.new(16,0,0),Vector3.new(-16,0,0),Vector3.new(0,0,16),Vector3.new(0,10,0)}) do
        local t=predictionMath.interceptTime(offset,velocity,96)
        assert(t and t>=0)
        near((offset+velocity*t).Magnitude,96*t)
    end
    assert(predictionMath.interceptTime(offset,Vector3.new(110,0,0),96)==nil)
    near(predictionMath.interceptTime(offset,Vector3.new(-96,0,0),96),0.625)
    assert(predictionMath.interceptTime(offset,Vector3.zero,0/0)==nil)
    assert(predictionMath.interceptTime(Vector3.new(1000,0,0),Vector3.zero,96)==nil)
    near(predictionMath.interceptTime(Vector3.zero,Vector3.zero,96),0)
    pass("knife intercept: stationary, lateral, approach, retreat, vertical, linear limit, unreachable")
end

do
    -- Interpolated crossing should not change when sampling at 30 or 120 Hz.
    for _,hz in ipairs({30,60,120}) do
        local samples={}
        for i=0,hz do table.insert(samples,{t=i/hz,p=Vector3.new(16*i/hz,0,0)}) end
        local time,distance=predictionMath.closestCrossing(samples,Vector3.new(16*0.2337,0,0))
        near(time,0.2337); near(distance,0)
    end
    assert(predictionMath.closestCrossing({},Vector3.zero)==nil)
    pass("lead crossing interpolation at 30/60/120 Hz, without frame quantization")
end

do
    local h={FloorMaterial="Ground",GetState=function() return "Freefall" end}
    assert(isMotionGrounded(h,Vector3.new(0,0.08,0)))
    -- TestingStuff contains a stale grounded=true with upward velocity 16.715.
    assert(not isMotionGrounded(h,Vector3.new(0,16.715,0)))
    h.GetState=function() return "Jumping" end
    assert(not isMotionGrounded(h,Vector3.zero))
    pass("stale grounded flag does not flatten a rising jump")
end
''')
    chunks += [r'''
do
local h={FloorMaterial="Ground",GetState=function() return "Running" end}
local character={FindFirstChildOfClass=function() return h end}
local player={Character=character}
local root={Position=Vector3.zero,AssemblyLinearVelocity=Vector3.new(16,0,0)}
''', section(BASE, "local motionSamples:", "local lastLatencyReadAt:"), r'''
now=0
getFilteredVelocity(player,root)
now=1/120
root.AssemblyLinearVelocity=Vector3.new(17,0,0)
getFilteredVelocity(player,root)
near(motionSamples[player].sampledAt,now)
near(motionSamples[player].acceleration.X,120)
now+=1/120
root.Position=Vector3.new(100,0,0)
getFilteredVelocity(player,root)
near(motionSamples[player].acceleration.Magnitude,0)
player.Character={FindFirstChildOfClass=function() return h end}
now+=1/120
getFilteredVelocity(player,root)
near(motionSamples[player].acceleration.Magnitude,0)
root.AssemblyLinearVelocity=Vector3.new(0/0,0,0)
near(getFilteredVelocity(player,root).Magnitude,0)
assert(motionSamples[player]==nil)
pass("actual motion sampler: 120 Hz supported; teleport/respawn reset; NaN reset")
end
''']
    chunks += [r'''
do
local knifeThrowSettings={animation=true}
local loaded,stopped,destroyed,played=0,0,0,0
local animator={LoadAnimation=function(self,anim)
    loaded+=1
    return {Stop=function() stopped+=1; error("already stopped") end,
        Destroy=function() destroyed+=1 end,Play=function() played+=1 end}
end}
local h={FindFirstChildOfClass=function() return animator end}
local LocalPlayer={Character={FindFirstChildOfClass=function() return h end}}
local function anim(name,id) return {Name=name,AnimationId=id,IsA=function() return true end} end
local throw=anim("Throw","1")
local knife={GetDescendants=function() return {anim("Equip","0"),throw} end}
''', section(KNIFE, "    local throwTrack:", "    local function throwKnife"), r'''
playThrowAnimation(knife); playThrowAnimation(knife)
assert(loaded==1 and played==2)
throw.AnimationId="2"
playThrowAnimation(knife)
assert(loaded==2 and destroyed==1 and stopped==1)
local other={GetDescendants=function() return {anim("Throw","2")} end}
playThrowAnimation(other)
assert(loaded==3 and destroyed==2)
playThrowAnimation({FindFirstChild=function() return {} end,GetDescendants=function() return {anim("Equip","0")} end})
assert(destroyed==3 and loaded==3)
stopThrowAnimation(); stopThrowAnimation()
assert(destroyed==3)
knifeThrowSettings.animation=false
playThrowAnimation(other)
assert(loaded==3)
pass("actual animation lifecycle: not Equip; cache by knife/id; cleanup even if Stop errors; OFF")
end
''']
    chunks += ["do\nlocal mm2Settings={predictionRtt=0.08,autoTuneLead=false,gunLeadBias=0}\n"
               "local GUN_LEAD={replicationRate=20,serverFrame=1/60,minimumHorizon=0,maximumHorizon=0.25,"
               "maximumManualBias=0.15,maximumAutoCorrection=0.1,defaultTurnRate=math.pi*0.5,maxTurnRate=math.pi*1.5}\n"
               "local autoLeadCorrection=0\n"
               "local function getActiveAutoLeadCorrection() return mm2Settings.autoTuneLead and autoLeadCorrection or 0 end\n"
               "local Stats={FindFirstChild=function() return nil end}\n",
               section(BASE, "local lastLatencyReadAt:", "local function getGunOriginCFrame"), r'''
    -- Staleness lead: our view trails the server by ~1 RTT (0.08 -> 0.08).
    -- v26's 0.6xRTT still undershot fast movers ("le da como en el centro"):
    -- the victim replicates victim->server->us, so the full staleness is the
    -- round trip itself.
    near(getGunHorizonSeconds(),0.08)
    mm2Settings.gunLeadBias=0.1
    near(getGunHorizonSeconds(),0.18)
    mm2Settings.gunLeadBias=-0.1
    near(getGunHorizonSeconds(),0)
    mm2Settings.gunLeadBias=0.05
    autoLeadCorrection=0.08
    mm2Settings.autoTuneLead=true
    near(getGunHorizonSeconds(),0.21)
    autoLeadCorrection=0.2
    assert(getGunHorizonSeconds()==0.23,"auto correction is capped at 0.1 on top of staleness+bias")
    mm2Settings.autoTuneLead=false
    assert(getGunHorizonSeconds()==0.13,"auto correction only applies when opted in")
    mm2Settings.gunLeadBias=0
    autoLeadCorrection=0
    -- A huge ping must not blow the lead up: staleness caps at 0.15.
    mm2Settings.predictionRtt=0.6
    near(getGunHorizonSeconds(),0.15)
    mm2Settings.predictionRtt=0.08
    near(getGunHorizonSeconds(),0.08)
    -- Stale calibration data must never push the horizon again.
    trajectoryCalibration={getEstimates=function() return {liveGunAcceptanceMs=400,liveGunSamples=50} end}
    near(getGunHorizonSeconds(),0.08)
    pass("gun horizon: 1.0xRTT staleness lead; auto capped at 0.1; huge ping capped")
end
''']
    chunks += [r'''
do
local runtime={events={{kind="stab",distance=28,hitTarget=false}},freshGunLatency={},gunAcceptance={count=62,mean=200.0177},knifeSpeed={count=162,mean=96},knifeSpawnDelay={count=0,mean=0}}
''', section(BASE, "    local function median(", "    saveSnapshot = function"), r'''
now=10
assert(estimates().maxStabDistance==nil)
for i=1,6 do table.insert(runtime.freshGunLatency,{at=now,ms=100+i*10}) end
now+=1
near(estimates().liveGunAcceptanceMs,135)
near(estimates().knifeSpeed,96)
now+=61
assert(estimates().liveGunAcceptanceMs==nil)
table.insert(runtime.events,{kind="stab",distance=12,hitTarget=true})
now+=1
near(estimates().maxStabDistance,12)
pass("live-only median expires; legacy knife speed survives; unconfirmed stabs cannot train reach")
end
''']
    chunks += [r'''
do
local velocity=Vector3.new(16,0,0)
local root={Position=Vector3.new(120,0,0)}
local target={Character={FindFirstChild=function() return root end}}
local speed=96
local trajectoryCalibration={getEstimates=function() return {knifeSpeed=speed} end}
local function getFilteredVelocity() return velocity end
local function getEstimatedLatency() return 0.2 end
''', section(KNIFE, "    local function predictAim", "    local throwTrack:"), r'''
for _,origin in ipairs({Vector3.zero,Vector3.new(115,0,0)}) do
    local aim=predictAim(target,origin)
    local t=(aim-origin).Magnitude/96
    -- v22+ lead model: the packet window is the full round trip (or the
    -- measured spawn delay once enough throws confirm it), not RTT/2.
    near(aim.X,root.Position.X+velocity.X*(0.2+t))
end
speed=0/0
assert(predictAim(target,Vector3.zero)~=nil,"invalid learned speed must use 96")
velocity=Vector3.new(110,0,0)
assert(predictAim(target,Vector3.zero)==nil)
pass("actual Knife predictor: full-RTT packet window plus intercept; measured spawn delay preferred")
end
''']
    chunks += [r'''
do
local workspace={Gravity=196.2}
local mm2Settings={shootWallCheck=false}
local velocity=Vector3.new(16,0,0)
local humanoid={Health=100,FloorMaterial="Ground",MoveDirection=Vector3.zero,WalkSpeed=16,GetState=function() return "Running" end}
local root={Position=Vector3.zero}
local part={Position=Vector3.new(0,0.8,0),IsA=function() return true end}
local character={FindFirstChild=function(self,name) if name=="HumanoidRootPart" then return root end; return part end,FindFirstChildOfClass=function() return humanoid end}
local target={Character=character}
local sample={character=character,sampledAt=now,acceleration=Vector3.zero,stability=1,grounded=true}
local motionSamples={[target]=sample}
local function getFilteredVelocity() return velocity end
local function getGunHorizonSeconds() return 0.2+1/40+1/120 end
local function getGunTurnDiscount() return 1 end
local function getGunTurnRate() return 0 end
''', section(SHOOT, "    local BODY_HALF_WIDTH:", "    local function getSelectedShootTarget"), r'''
local origin=CFrame.new(Vector3.new(0,0,-20))
local aim,pred=computeGunAim(target,origin)
near(pred.endpoint.X,16*getGunHorizonSeconds())
near(pred.capturedPosition.Y,0.8); near(pred.aimRootOffset.Y,0.8)
near(pred.errorRadius,0.35)
velocity=Vector3.new(16,16.715,0)
local _,air=computeGunAim(target,origin)
near(air.endpoint.Y,0.8+16.715*getGunHorizonSeconds()-0.5*196.2*getGunHorizonSeconds()^2)
sample.character={}; sample.acceleration=Vector3.new(250,0,0)
velocity=Vector3.new(16,0,0)
local _,fresh=computeGunAim(target,origin)
near(fresh.endpoint.X,16*getGunHorizonSeconds())
-- Remote characters often read FloorMaterial=Air on our client. A flat-ground
-- walker must NOT get the free-fall drop (this is exactly the "shot lands
-- several studs below the target" defect).
humanoid.FloorMaterial="Air"
velocity=Vector3.new(16,0,0)
local _,misread=computeGunAim(target,origin)
near(misread.endpoint.Y,0.8)
near(misread.endpoint.X,16*getGunHorizonSeconds())
humanoid.FloorMaterial="Ground"
-- Stop-time damping: a target braking hard is never led past his stop point.
sample.character=character; sample.acceleration=Vector3.new(-250,0,0)
velocity=Vector3.new(16,0,0)
local _,braking=computeGunAim(target,origin)
local stopped=16/250
near(braking.endpoint.X,16*stopped-250*0.25*stopped*stopped)
-- Jump state leads before the replicated physics velocity does.
sample.acceleration=Vector3.zero
humanoid.GetState=function() return "Jumping" end
local _,jumping=computeGunAim(target,origin)
local jumpH=getGunHorizonSeconds()
near(jumping.endpoint.Y,0.8+math.clamp(8*jumpH-0.5*196.2*jumpH*jumpH,-3,3))
humanoid.GetState=function() return "Freefall" end
velocity=Vector3.new(16,0,0)
local _,apex=computeGunAim(target,origin)
near(apex.endpoint.Y,0.8+math.clamp(-0.5*196.2*jumpH*jumpH,-3,3))
humanoid.GetState=function() return "Running" end
pass("actual Shoot solver: linear lead; torso offset; jump; stale sample; no phantom drop; stop damping; jump state")
end
''']
    chunks += [r'''
do
-- Wallcheck rescue: a corner that hides the torso CENTRE must not send the
-- shot to the leg while half the torso box is still exposed.
local workspace={Gravity=196.2}
local mm2Settings={shootWallCheck=true}
local velocity=Vector3.new(16,0,0)
local humanoid={Health=100,FloorMaterial="Ground",MoveDirection=Vector3.zero,WalkSpeed=16,GetState=function() return "Running" end}
local rootCF={RightVector=Vector3.new(0,0,1),UpVector=Vector3.new(0,1,0)}
local root={Position=Vector3.zero,CFrame=rootCF,IsA=function() return true end}
local torso={Position=Vector3.new(0,0.8,0),IsA=function() return true end}
local head={Position=Vector3.new(0,1.6,0),IsA=function() return true end}
local leg={Position=Vector3.new(0,-0.6,0),IsA=function() return true end}
local parts={UpperTorso=torso,HumanoidRootPart=root,Head=head,RightLowerLeg=leg}
local character={FindFirstChild=function(_,name) return parts[name] end,FindFirstChildOfClass=function() return humanoid end}
local target={Character=character}
local sample={character=character,sampledAt=os.clock(),acceleration=Vector3.zero,stability=1,grounded=true}
local motionSamples={[target]=sample}
local function getFilteredVelocity() return velocity end
local function getGunHorizonSeconds() return 0.1 end
local function getGunTurnDiscount() return 1 end
local function getGunTurnRate() return 0 end
local clearList={}
local function markClear(p) table.insert(clearList,p) end
local function isWeaponPathClear(_,to)
    for _,p in ipairs(clearList) do
        if p.X==to.X and p.Y==to.Y and p.Z==to.Z then return true end
    end
    return false
end
''', section(SHOOT, "    local BODY_HALF_WIDTH:", "    local function getSelectedShootTarget"), r'''
local origin=CFrame.new(Vector3.new(0,0,-20))
-- Case 1: only the leg is visible -> the leg is still the correct last resort.
markClear(Vector3.new(1.6,-0.6,0))
local legAim,legPred=computeGunAim(target,origin)
assert(legPred,"leg-only visibility must still produce a shot")
near(legPred.endpoint.X,1.6); near(legPred.endpoint.Y,-0.6)
-- Case 2: the right half of the torso box is exposed -> the probe point must
-- beat the leg (v27: "detectando la pierna cuando no era necesario").
clearList={}
markClear(Vector3.new(1.6,0.8,0.55))
local torsoAim,torsoPred=computeGunAim(target,origin)
assert(torsoPred,"exposed torso probe must produce a shot")
near(torsoPred.endpoint.X,1.6); near(torsoPred.endpoint.Y,0.8); near(torsoPred.endpoint.Z,0.55)
assert(torsoPred.endpoint.Y > 0,"torso probe must outrank the leg")
-- Case 3: nothing visible at all -> clean rejection.
clearList={}
local noneAim,nonePred=computeGunAim(target,origin)
assert(noneAim==nil and nonePred==nil,"fully blocked shot must be rejected")
pass("wallcheck rescue: torso probe beats the leg; leg-only still fires; fully blocked rejects")
end
''']
    chunks += [r'''
do
local mm2Settings={silentSweep=0}
local calls=0
local blocked=false
local function bystanderOnSegment() calls+=1; return blocked end
''', section(SHOOT, "    local SILENT_ORIGIN_STUDS:", "    type FireOptions"), r'''
local p={targetPosition=Vector3.new(4,0,0),capturedPosition=Vector3.zero,velocity=Vector3.new(16,0,0)}
local origin=CFrame.new(Vector3.new(0,0,-20))
local a,b=buildSilentShot({},p,origin,"Through")
assert(a and b and calls==1)
blocked=true; calls=0
assert(buildSilentShot({},p,origin,"Through")==nil)
assert(calls==2,"fallback ray must be checked too")
blocked=false
local vertical=CFrame.new(Vector3.new(4,20,0))
local c,d=buildSilentShot({},p,vertical,"Front")
assert((c.Position-d.Position).Magnitude>0.05)
pass("Silent sweep=0 still checks real segment; fallback rechecked; no zero-length CFrame")
end
''']
    chunks += [r'''
do
local knob={enabled=false,mode="Normal",fireDelay=1,range=120,spawnOffset=5,throwHz=60,animation=true}
local knifeThrowSettings=knob
local lastThrow=-math.huge
local root={Position=Vector3.new(30,0,0)}
local target={Character={FindFirstChild=function() return root end}}
local thrower={Position=Vector3.zero}
local LocalPlayer={Character={FindFirstChild=function() return thrower end}}
local sends,notes,animations=0,0,0
local remote={IsA=function() return true end,FireServer=function() sends+=1 end}
local knife={Name="Knife",FindFirstChild=function() return {FindFirstChild=function() return remote end} end}
local function getReadyKnife() return knife end
local function findNearestTarget() return target end
local function predictAim() return root.Position end
local visibility=true
local function isWeaponPathClear() return visibility end
local function playThrowAnimation()
    animations+=1
    assert(notes==sends,"telemetry must be queued before cosmetic work")
    near(lastThrow,now)
    error("unavailable animator")
end
local stops=0
local function stopThrowAnimation() stops+=1 end
local trajectoryCalibration={noteAuthoredShot=function() notes+=1 end}
local state={mm2KnifeRuntime={}}
local callbacks={}
local featureConnections={}
local TaskManager={Connect=function(self,cb) callbacks[1]=cb; return {Disconnect=function() callbacks[1]=nil end} end}
local function disconnectFeatureConnection(key)
    if featureConnections[key] then featureConnections[key]:Disconnect(); featureConnections[key]=nil end
end
''', section(KNIFE, "    local function throwKnife", "    local KnifeThrowFeature:"), r'''
for _,hz in ipairs({20,60,120}) do
    now=0; sends=0; notes=0
    knob.throwHz=hz
    toggleKnifeThrow(true)
    for i=1,1200 do now=i/120; callbacks[1](1/120) end
    assert(sends==10,`cooldown violation at {hz} Hz: {sends}`)
    assert(notes==10)
    toggleKnifeThrow(false)
    assert(callbacks[1]==nil)
end
assert(stops==3)
visibility=false; sends=0; notes=0; now=100
knob.mode="Normal"; toggleKnifeThrow(true); throwKnife(); assert(sends==0)
knob.mode="Silent"; throwKnife(); assert(sends==1 and notes==1)
toggleKnifeThrow(false)
pass("actual Knife loop: live frequency, 1s cooldown, cosmetic failure isolation, disable cleanup")
end
''']
    chunks += [r'''
do
local knifeSettings={aura=true,autoRange=true,auraRange=14}
local trajectoryCalibration={getEstimates=function() return {maxStabDistance=20} end,noteAuthoredShot=function() end}
''', section(AURA, "    local function getEffectiveRange", "    local function getEquippedWeapon"), r'''
local activated,sent=0,0
local handle={IsA=function() return true end}
local remote={IsA=function() return true end,FireServer=function() sent+=1 end}
local knife={Activate=function() activated+=1 end,FindFirstChild=function(self,name) if name=="Events" then return {FindFirstChild=function() return remote end} end; return handle end}
local localRoot={Position=Vector3.zero}
local targetRoot={Position=Vector3.new(18,0,0)}
local target={Character={FindFirstChild=function() return targetRoot end}}
local function canUseEquippedKnife() return knife,localRoot end
local function findKnifeAuraTarget(root,range) near(range,20); return target end
local function isValidKnifeTarget() return true end
local state={mm2KnifeRuntime={lastAuraSwing=-math.huge}}
local task={delay=function(_,fn) fn() end}
''', section(AURA, "    local function processKnifeAura", "    local function refreshKnifeController"), r'''
processKnifeAura()
assert(activated==1 and sent==1)
processKnifeAura()
assert(activated==1 and sent==1,"cooldown")
pass("actual Aura: auto/manual range disagreement fixed; cooldown before scans")
end
''']
    # Execute the real writer with an in-memory encoder/IO sink. Detect accidental
    # disk rereads, double accumulation, failed-write loss, and migration drift.
    chunks += [r'''
do
local runtime={active=true,dirty=true,revision=0,startedAt=0,events={},motionBuckets={},sessionGunAttempts=1,sessionGunConfirmed=1,sessionKnifeAttempts=2,sessionKnifeConfirmed=1,
    gunAcceptance={count=1,mean=120,m2=0,minimum=120,maximum=120},
    knifeSpeed={count=1,mean=96,m2=0,minimum=96,maximum=96},
    knifeSpawnDelay={count=1,mean=80,m2=0,minimum=80,maximum=80}}
local mm2Settings={}
local payloads={}
local failWrite=false
local appendDuringWrite=false
local reads=0
local environment={writefile=function() if failWrite then error("IO failed") end; if appendDuringWrite then runtime.revision+=1; runtime.dirty=true end end,readfile=function() reads+=1; error("save must not reread") end}
local HttpService={JSONEncode=function(self,payload) table.insert(payloads,payload); return "{}" end}
local DateTime={now=function() return {ToIsoDate=function() return "test" end} end}
local game={PlaceId=142823291}
local OUTPUT_PATH,OUTPUT_ROOT,OUTPUT_FOLDER,trajectoryLogPrefix="test","test","test","test"
local warn=function() end
local saveSnapshot
''', section(BASE, "    local function statsPayload(", "    local function getPingMilliseconds"),
               section(BASE, "    local function restoreMotionBucket(", "    local function loadSavedHistory"),
               section(BASE, "    local function motionModelPayload(", "    local function median("),
               section(BASE, "    saveSnapshot = function", "    local function normalizeGun"), r'''
local MAX_EVENTS=2400
local workspace={GetServerTimeNow=function() return 123 end}
local function getPingMilliseconds() return 80 end
local function typeof(v)
    if getmetatable(v)==mt then return "Vector3" end
    if type(v)=="table" and v.instance then return "Instance" end
    return type(v)
end
local scheduled={}
local task={delay=function(_,fn) table.insert(scheduled,fn) end}
local controller={}
runtime.sessionId="trace-test";runtime.buildStamp="v31"
runtime.pendingGuns={{shotId="shot-1",activatedAt=now,origin=Vector3.zero}}
''', section(BASE, "    local function appendEvent(", "    local function trackConnection"),
section(BASE, "    function controller:noteTracerData(", "    function controller:noteAuthoredShot"), r'''
local targetChar={}
local part={instance=true,GetFullName=function() return "Workspace.Map.Wall" end,
    IsDescendantOf=function(_,c) return c==targetChar end}
controller:noteTracerData({origin=Vector3.zero,endpoint=Vector3.new(10,2,3),hitPart=part,
    target={Character=targetChar,Name="Target",UserId=12},targetPosition=Vector3.new(9,2,3)})
assert(#runtime.events==1 and runtime.events[1].phase=="tracer-data")
assert(runtime.events[1].shotId=="shot-1" and runtime.events[1].hitPartPath=="Workspace.Map.Wall")
near(runtime.events[1].endpointToObservedTarget,1)
controller:noteTracerData({origin=Vector3.zero,endpoint=Vector3.new(0/0,0,0)})
assert(#runtime.events==1,"invalid endpoints must not poison JSON")
local attempts,confirmed=runtime.sessionGunAttempts,runtime.sessionGunConfirmed
assert(saveSnapshot("tracer-feedback"))
local trace=payloads[#payloads].session.events[1]
assert(trace.origin[1]==0 and trace.endpoint[1]==10 and trace.observedTargetPosition[1]==9)
assert(trace.targetPositionScope:find("client%-observed"))
assert(runtime.sessionGunAttempts==attempts and runtime.sessionGunConfirmed==confirmed)
assert(#scheduled==1,"feedback uses existing batched autosave")
pass("Tracer Data survives real calibration writer; finite JSON; scope; correlation; no shot-count inflation")
-- Keep the existing writer test's payload indexing stable.
table.clear(payloads)
local legacy={count=2,meanDurationSeconds=0.2,meanHorizontalLeadSeconds=0.1,meanVerticalLeadSeconds=0.03,meanConstantVelocityResidual={1,2,3},meanModelError={constantVelocity=2,observedAcceleration=3,airborneBallistic=4}}
runtime.motionBuckets.test=restoreMotionBucket(legacy)
assert(saveSnapshot("one")); assert(saveSnapshot("two"))
assert(payloads[1].session.gunAttempts==1 and payloads[2].session.gunAttempts==1)
near(payloads[2].analytics.motionModel.test.meanDurationSeconds,0.2)
local restored=restoreMotionBucket(payloads[2].analytics.motionModel.test)
near(restored.durationSum,0.4); near(restored.horizontalLeadSum,0.2)
assert(restored.count==2 and reads==0)
runtime.sessionGunAttempts+=1; runtime.dirty=true
failWrite=true; assert(not saveSnapshot("failed")); assert(runtime.dirty)
failWrite=false; assert(saveSnapshot("retry")); assert(not runtime.dirty)
assert(payloads[#payloads].session.gunAttempts==2)
assert(payloads[#payloads].schema==4)
appendDuringWrite=true
assert(saveSnapshot("yielding-write") and runtime.dirty)
appendDuringWrite=false
assert(saveSnapshot("next") and not runtime.dirty)
pass("real telemetry writer: idempotent saves, no disk reread, retry preserves counts, legacy migration")
end
''']
    chunks.append('print("MM2 regression groups passed:",passed)\n')
    return "\n".join(chunks)


def main() -> None:
    # Integration contracts not requiring a simulated Roblox scene.
    assert 'silentSpawn = "Through"' in BASE
    assert 'bodyHalfWidth' not in SHOOT and 'WurstHitbox' not in BASE
    assert 'predictionMath.sampleDue(autoElapsed, deltaTime, 60)' in SHOOT
    assert 'predictionMath.sampleDue(elapsed, deltaTime, 30)' in BASE
    assert 'task.delay(10, function()' in BASE
    assert 'if directHit then tuneFromConfirmedShot(candidate) end' in BASE
    assert 'or candidate.silentSpawn then' in BASE
    assert 'candidate.aimRootOffset' in BASE and 'aimRootOffset = part.Position' in SHOOT
    assert 'GUN_PIERCE_STUDS' not in SHOOT, 'v27 pierce removed: the server rejects endpoints past the target (real log evidence)'
    assert 'GUN_SERVER_COOLDOWN' in SHOOT and 'Gun is cooling down' in SHOOT
    # one shared gate before the silent/normal split, and both fire paths
    # stamp lastGunFireServer so AutoShoot + manual share the window
    assert SHOOT.count('lastGunFireServer = os.clock()') == 2, 'both fire paths must stamp the server cooldown'
    assert SHOOT.index('GUN_SERVER_COOLDOWN then') < SHOOT.index('if silent'), 'gate must run before the silent/normal split'
    assert 'probeOffsets' in SHOOT and 'getEstimatedLatency() * 1.0' in BASE
    with tempfile.TemporaryDirectory(prefix="mm2-precision-") as directory:
        script = Path(directory) / "regressions.luau"
        script.write_text(build())
        subprocess.run([os.environ.get("LUAU", "luau"), str(script)], check=True)


if __name__ == "__main__":
    main()
