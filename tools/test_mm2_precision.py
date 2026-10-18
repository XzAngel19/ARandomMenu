#!/usr/bin/env python3
"""Run the live MM2 kinematic predictor in Luau with deterministic mocks.

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
PREDICTION = (ROOT / "src/games/MM2/Prediction.lua").read_text()


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
    if k=="Cross" then return function(a,b)
        return Vector3.new(a.Y*b.Z-a.Z*b.Y,a.Z*b.X-a.X*b.Z,a.X*b.Y-a.Y*b.X)
    end end
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
    chunks = [PRELUDE, section(BASE, "local predictionMath = {}", "local lastLatencyReadAt")]
    chunks.append(r'''
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
    assert(not predictionMath.finite(0/0) and not predictionMath.finite(math.huge))
    pass("blade intercept: stationary, lateral, approach, retreat, vertical, linear limit, unreachable")
end
''')
    chunks.append(r'''
do
    local workspace={Gravity=196.2}
    local LocalPlayer={Character={}}
    local humanoid={Health=100,GetState=function() return "Running" end}
    local root={Position=Vector3.zero,AssemblyLinearVelocity=Vector3.zero}
    local torso={Position=Vector3.new(0,1,0),IsA=function() return true end}
    local character={FindFirstChild=function(_,name)
        if name=="HumanoidRootPart" then return root end
        if name=="UpperTorso" then return torso end
        return nil
    end,FindFirstChildOfClass=function() return humanoid end}
    local target={Character=character}
    local Players={GetPlayers=function() return {LocalPlayer,target} end}
    local state={mm2Core={predictionMath=predictionMath,getEstimatedLatency=function() return 0.12 end}}
    local featureConnections={}
    local function disconnectFeatureConnection(key)
        if featureConnections[key] then featureConnections[key]:Disconnect();featureConnections[key]=nil end
    end
    local sampleTick=nil
    local TaskManager={Connect=function(_,callback)
        sampleTick=callback
        return {Disconnect=function() sampleTick=nil end}
    end}
    local function loadPrediction()
''')
    chunks.append(PREDICTION)
    chunks.append(r'''
    end
    local Module=loadPrediction()
    Module.init({})
    local prediction=state.mm2Prediction
    assert(type(prediction)=="table","module must publish state.mm2Prediction")
    now=0
    for i=1,30 do
        now=i/60
        root.Position=Vector3.new(16*now,0,0)
        torso.Position=Vector3.new(16*now,1,0)
        root.AssemblyLinearVelocity=Vector3.new(16,0,0)
        sampleTick(1/60)
    end
    local endpoint,info,reason=prediction.gunAim(target,Vector3.new(0,0,-30))
    assert(endpoint,reason)
    near(info.velocity.X,16,0.25)
    assert(info.leadSeconds>=0.14 and info.leadSeconds<=0.15,info.leadSeconds)
    near(endpoint.X,16*now+16*info.leadSeconds,0.2)
    near(endpoint.Y,1,1e-6)
    assert(info.model=="kinematic-v51")
    assert(info.samples>=3 and info.sampleAge<0.02)
    local aim,knife=prediction.knifeAim(target,Vector3.zero,96)
    assert(aim)
    near(aim.Magnitude,96*knife.flightSeconds,1e-3)
    near(aim.X-16*now,16*(knife.leadSeconds+knife.flightSeconds),1e-3)
    for _=1,5 do prediction.noteEcho(0,0.18) end
    assert(prediction.getEchoDelay()==nil,"five echoes are not a median")
    assert(prediction.status(target):find("auto lead %(ping%)"),
        "with few echoes the lead must fall back to ping")
    prediction.noteEcho(0,0.04)
    assert(prediction.getEchoDelay()==nil,"an impossible 40 ms echo is a mismatch")
    prediction.noteEcho(0,0.18)
    local _,echoed=prediction.gunAim(target,Vector3.new(0,0,-30))
    near(echoed.echoDelay,0.18,1e-9)
    near(echoed.leadSeconds,0.205,1e-6)
    prediction.noteEcho(0,0.001)
    prediction.noteEcho(0,2)
    near(prediction.getEchoDelay(),0.18,1e-9)
    prediction.settings.extraLead=0.05
    local _,automatic=prediction.gunAim(target,Vector3.new(0,0,-30))
    near(automatic.leadSeconds,0.205,1e-6)
    local autoText=prediction.status(target)
    assert(autoText:find("auto lead %(echo%)"),autoText)
    assert(autoText:find("interp 25 ms"),autoText)
    prediction.settings.autoLead=false
    local _,manual=prediction.gunAim(target,Vector3.new(0,0,-30))
    near(manual.leadSeconds,0.255,1e-6)
    local statusText=prediction.status(target)
    assert(statusText:find("manual %+50 ms"),statusText)
    assert(not statusText:find("auto lead"),statusText)
    prediction.settings.extraLead=0.6
    local _,capped=prediction.gunAim(target,Vector3.new(0,0,-30))
    near(capped.leadSeconds,0.805,1e-6)
    assert(prediction.status(target):find("manual %+600 ms"))
    prediction.settings.extraLead=1.5
    local _,clamped=prediction.gunAim(target,Vector3.new(0,0,-30))
    near(clamped.leadSeconds,1.0,1e-6)
    prediction.settings.extraLead=0
    prediction.settings.autoLead=true
    now=now+1
    assert(prediction.gunAim(target,Vector3.new(0,0,-30))==nil,"stale pose must fail closed")
    prediction.reset()
    now=0
    for i=1,10 do
        now=i/60
        root.Position=Vector3.zero
        torso.Position=Vector3.new(0,1,0)
        root.AssemblyLinearVelocity=Vector3.zero
        sampleTick(1/60)
    end
    root.Position=Vector3.new(200,0,0)
    torso.Position=Vector3.new(200,1,0)
    now=now+1/60
    sampleTick(1/60)
    local teleported=prediction.getMotion(target)
    assert(teleported and teleported.samples==1,"teleport must not seed a velocity fit")
    prediction.reset()
    root.Position=Vector3.new(0,20,0)
    torso.Position=Vector3.new(0,21,0)
    humanoid.GetState=function() return "Freefall" end
    for i=1,20 do
        now=now+0.05
        root.Position=Vector3.new(0,20-0.5*i,0)
        torso.Position=Vector3.new(0,21-0.5*i,0)
        root.AssemblyLinearVelocity=Vector3.new(0,-10,0)
        sampleTick(1/60)
    end
    local falling,fell=prediction.gunAim(target,Vector3.new(0,0,-30))
    assert(falling and falling.Y<root.Position.Y and falling.Y>root.Position.Y-10,fell)
    local blade,bladeInfo=prediction.knifeAim(target,Vector3.new(0,0,-30),96)
    assert(blade and bladeInfo.flightSeconds)
    assert(blade.Y<falling.Y,"airborne blade aims at the projected impact, not a straight Y")
    pass("live predictor: weighted fit, echo median, freshness, teleport reset, gravity")

    -- Turn: the chord over the horizon must beat the straight tangent.
    humanoid.GetState=function() return "Running" end
    prediction.reset()
    now=0
    local radius,omega=20,2.0
    local function circle(t)
        local theta=omega*t
        return Vector3.new(radius*math.sin(theta),0,radius-radius*math.cos(theta)),
               Vector3.new(radius*omega*math.cos(theta),0,radius*omega*math.sin(theta))
    end
    for i=1,30 do
        now=i/60
        local position,velocity=circle(now)
        root.Position=position
        torso.Position=position+Vector3.new(0,1,0)
        root.AssemblyLinearVelocity=velocity
        sampleTick(1/60)
    end
    local turnEndpoint,turnInfo=prediction.gunAim(target,Vector3.new(0,0,-30))
    assert(turnEndpoint,"a turning target must stay aimable")
    local turnMotion=prediction.getMotion(target)
    assert(turnMotion and turnMotion.turnRate<-0.5,
        "counter-clockwise turn must measure a negative rate: "
            .. tostring(turnMotion and turnMotion.turnRate))
    local futurePosition=circle(now+turnInfo.leadSeconds)
    local futureX,futureZ=futurePosition.X,futurePosition.Z
    local linearX=root.Position.X+turnMotion.horizontal.X*turnInfo.leadSeconds
    local linearZ=root.Position.Z+turnMotion.horizontal.Z*turnInfo.leadSeconds
    local linearError=math.sqrt((linearX-futureX)^2+(linearZ-futureZ)^2)
    local turnError=math.sqrt((turnEndpoint.X-futureX)^2+(turnEndpoint.Z-futureZ)^2)
    assert(linearError>0.4,"the straight lead must actually be wrong in this setup: "
        .. tostring(linearError))
    assert(turnError<linearError*0.5,
        string.format("chord %.3f must beat tangent %.3f",turnError,linearError))
    pass("turn correction: measured rate, chord closer than the straight tangent")

    -- Braking: the measured deceleration must remove the overshoot.
    prediction.reset()
    now=0
    local startSpeed,deceleration=32,64
    local function braking(t)
        local span=math.min(t,startSpeed/deceleration)
        return Vector3.new(startSpeed*span-0.5*deceleration*span*span,0,0),
               Vector3.new(math.max(0,startSpeed-deceleration*t),0,0)
    end
    for i=1,18 do
        now=i/60
        local position,velocity=braking(now)
        root.Position=position
        torso.Position=position+Vector3.new(0,1,0)
        root.AssemblyLinearVelocity=velocity
        sampleTick(1/60)
    end
    local brakeEndpoint,brakeInfo=prediction.gunAim(target,Vector3.new(0,0,-30))
    assert(brakeEndpoint,"a braking target must stay aimable")
    local brakeMotion=prediction.getMotion(target)
    assert(brakeMotion and brakeMotion.longitudinalAccel<-20,
        "braking must be measured: "
            .. tostring(brakeMotion and brakeMotion.longitudinalAccel))
    local truePosition=braking(now+brakeInfo.leadSeconds)
    local trueX=truePosition.X
    local brakeLinear=root.Position.X
        + brakeMotion.horizontal.X*brakeInfo.leadSeconds
    local brakeLinearError=math.abs(brakeLinear-trueX)
    local brakeError=math.abs(brakeEndpoint.X-trueX)
    assert(brakeLinearError>0.5,"the straight lead must overshoot a braking target: "
        .. tostring(brakeLinearError))
    assert(brakeError<brakeLinearError*0.5,
        string.format("brake %.3f must beat linear %.3f",brakeError,brakeLinearError))
    pass("stop-time: measured deceleration, lead closer than constant speed")
    Module.destroy()
    assert(state.mm2Prediction==nil and sampleTick==nil)
end
''')
    chunks.append(r"""
do
    local mm2Settings={predictionRtt=0.08}
    local directSeconds=0.075
    local pingMilliseconds=120
    local LocalPlayer={GetNetworkPing=function() return directSeconds end}
    local Stats={FindFirstChild=function(_,name)
        if name~="Network" then return nil end
        return {FindFirstChild=function(_,child)
            if child~="ServerStatsItem" then return nil end
            return {FindFirstChild=function(_,leaf)
                if leaf~="Data Ping" then return nil end
                return {GetValue=function() return pingMilliseconds end}
            end}
        end}
    end}
""")
    chunks.append(section(BASE, "local lastLatencyReadAt:", "local function getGunOriginCFrame"))
    chunks.append(r"""
    now=100
    local first=getEstimatedLatency()
    now=101
    local second=getEstimatedLatency()
    assert(first>0.075 and first<0.076,first)
    assert(second>0.075 and second<0.0761,second)
    directSeconds=0
    now=102
    getEstimatedLatency()
    now=103
    near(getEstimatedLatency(),0.12,0.001)
    directSeconds=5
    now=104
    getEstimatedLatency()
    now=105
    near(getEstimatedLatency(),0.12,0.001)
    LocalPlayer.GetNetworkPing=function() error("unavailable") end
    now=106
    getEstimatedLatency()
    now=107
    near(getEstimatedLatency(),0.12,0.001)
    pingMilliseconds=1500
    now=108
    getEstimatedLatency()
    now=109
    assert(getEstimatedLatency()<=0.6)
    pass("latency: engine GetNetworkPing preferred, invalid values fall back to Data Ping, hard cap")
end
""")
    # Execute the real writer with an in-memory encoder/IO sink. Detect accidental
    # disk rereads, double accumulation, failed-write loss, and migration drift.
    chunks += [r'''
do
local state={}
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
    assert "state.mm2Prediction" in SHOOT and "prediction.gunAim" in SHOOT
    assert "state.mm2Prediction" in KNIFE and "prediction.knifeAim" in KNIFE
    assert "validateGunShot" in SHOOT and "isWeaponPathClear" in BASE
    assert "WeaponPassthrough" in BASE
    assert "computeGunAim" not in SHOOT and "predictionMath.sampleDue" not in BASE
    assert "predictionMath.closestCrossing" not in BASE and "GUN_LEAD" not in BASE
    assert "bodyHalfWidth" not in SHOOT and "WurstHitbox" not in BASE
    assert "TaskManager:Connect(autoShootTick)" in SHOOT
    assert "task.delay(10, function()" in BASE
    assert "candidate.silentSpawn" in BASE and "candidate.ambiguous" in BASE
    assert "GUN_PIERCE_STUDS" not in SHOOT
    assert "GUN_SERVER_COOLDOWN" not in SHOOT and "lastGunFireServer" not in SHOOT
    assert "autoSettings.fireDelay" not in SHOOT
    with tempfile.TemporaryDirectory(prefix="mm2-precision-") as directory:
        script = Path(directory) / "regressions.luau"
        script.write_text(build())
        subprocess.run([os.environ.get("LUAU", "luau"), str(script)], check=True)


if __name__ == "__main__":
    main()
