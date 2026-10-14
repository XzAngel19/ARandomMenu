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
local Enum={Material={Air="Air"},HumanoidStateType={Jumping="Jumping"},
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
playThrowAnimation({GetDescendants=function() return {anim("Equip","0")} end})
assert(destroyed==3 and loaded==3)
stopThrowAnimation(); stopThrowAnimation()
assert(destroyed==3)
knifeThrowSettings.animation=false
playThrowAnimation(other)
assert(loaded==3)
pass("actual animation lifecycle: not Equip; cache by knife/id; cleanup even if Stop errors; OFF")
end
''']
    chunks += ["do\nlocal mm2Settings={predictionRtt=0.08,autoTuneLead=false,gunLeadBias=0}\nlocal Stats={FindFirstChild=function() return nil end}\n",
               section(BASE, "local lastLatencyReadAt:", "local function getGunOriginCFrame"), r'''
    local baseline=getGunHorizonSeconds()
    near(baseline,0.2+1/40+1/120)
    local calls=0
    trajectoryCalibration={getEstimates=function() calls+=1; return {gunAcceptanceMs=1624,confirmedShots=62} end}
    near(getGunHorizonSeconds(),baseline)
    assert(calls==1,"forward local controller must be captured")
    trajectoryCalibration.getEstimates=function() return {liveGunAcceptanceMs=100,liveGunSamples=6} end
    near(getGunHorizonSeconds(),0.125+1/40+1/120)
    trajectoryCalibration.getEstimates=function() return {liveGunAcceptanceMs=100,liveGunSamples=5} end
    near(getGunHorizonSeconds(),baseline)
    trajectoryCalibration.getEstimates=function() return {liveGunAcceptanceMs=0/0,liveGunSamples=10} end
    near(getGunHorizonSeconds(),baseline)
    trajectoryCalibration.getEstimates=function() error("bad calibration") end
    near(getGunHorizonSeconds(),baseline)
    pass("gun controller capture; ignore old aggregate/NaN/small batches; bounded fresh calibration")
end
''']
    chunks += [r'''
do
local runtime={events={{kind="stab",distance=28,hitTarget=false}},freshGunLatency={},gunAcceptance={count=62,mean=200.0177},knifeSpeed={count=162,mean=96}}
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
    near(aim.X,root.Position.X+velocity.X*(0.1+t))
end
speed=0/0
assert(predictAim(target,Vector3.zero)~=nil,"invalid learned speed must use 96")
velocity=Vector3.new(110,0,0)
assert(predictAim(target,Vector3.zero)==nil)
pass("actual Knife predictor: RTT/2 plus intercept in Normal and near-target Silent")
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
pass("actual Shoot solver: known-good linear lead; torso/root offset; jump; stale respawn sample")
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
local function playThrowAnimation()
    animations+=1
    assert(notes==sends,"telemetry must be queued before cosmetic work")
    near(lastThrow,now)
    error("unavailable animator")
end
local stops=0
local function stopThrowAnimation() stops+=1 end
local trajectoryCalibration={noteAuthoredShot=function() notes+=1 end}
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
assert(payloads[#payloads].schema==3)
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
    with tempfile.TemporaryDirectory(prefix="mm2-precision-") as directory:
        script = Path(directory) / "regressions.luau"
        script.write_text(build())
        subprocess.run([os.environ.get("LUAU", "luau"), str(script)], check=True)


if __name__ == "__main__":
    main()
