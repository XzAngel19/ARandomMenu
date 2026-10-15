#!/usr/bin/env python3
"""Actual-source profile, legacy-budget and target-ballistics regressions.
No Roblox connection or assertion of server acceptance/real-world hit rate.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
sys.dont_write_bytecode = True
from test_mm2_precision import PRELUDE, section
from test_mm2_v18 import build as v18
from test_mm2_v19 import build as v19
R = Path(__file__).resolve().parents[1]
B = (R/'src/games/MM2/base.lua').read_text()
S = (R/'src/games/MM2/Blatant/Shoot.lua').read_text()
K = (R/'src/games/MM2/Blatant/KnifeThrow.lua').read_text()


def build():
    ui = section(v19(), 'local settings={shootMode=', 'assert(choices["Shoot.Mode"]')
    ui = ui.replace('local saved={', 'local saved={["Shoot.Prediction profile"]=initialProfile,', 1)
    ui = ui.replace('row(card,label);callback(default)', 'row(card,label);callbacks[card.name.."."..label]=callback;callback(default)')
    scene = section(v18(), 'do\nlocal workspace={Gravity=', 'for _,similarity')
    return '\n'.join([PRELUDE, section(B, 'local predictionMath = {}', 'type MotionSample'),
        'do\nlocal function checkUI(initialProfile)\n', ui, r'''
assert(settings.predictionProfile==initialProfile)
assert(not visible("Prediction profile") and not visible("Hitbox") and not visible("Burst"))
callbacks["Shoot.Mode"]("Prediction")
assert(visible("Prediction profile"))
callbacks["Shoot.Advanced"](true)
for _,profile in ipairs({"Old","Actual","Experimental"}) do
    callbacks["Shoot.Prediction profile"](profile)
    assert(visible("Hitbox")==(profile=="Old"))
    assert(visible("Burst")==(profile=="Old"))
    assert(visible("Motion model")==(profile=="Actual"))
    callbacks["Shoot.Hitbox"](true)
    assert(visible("Hitbox size")==(profile=="Old"))
    callbacks["Shoot.Hitbox"](false);assert(not visible("Hitbox size"))
    callbacks["Shoot.Mode"]("Silent AIM")
    assert(not visible("Prediction profile") and not visible("Hitbox") and not visible("Burst"))
    callbacks["Shoot.Mode"]("Prediction")
end
end
for _,profile in ipairs({"Old","Actual","Experimental"}) do checkUI(profile) end
pass("full Shoot UI: restored profiles, Old-only controls, hidden size and Silent isolation")
end

do
local made,removed=0,0
local Instance={new=function()
    made+=1
    return {Destroy=function(self) removed+=1;self.Parent=nil end}
end}
local mm2Settings={predictionProfile="Old",oldHitbox=true,oldHitboxSize=8}
''', section(S, '    local legacyGeneration =', '    local diagnostics ='), r'''
local function target()
    local root={CFrame=CFrame.new(Vector3.zero)}
    return {Character={FindFirstChild=function() return root end}}
end
local a,b=target(),target()
syncLegacyHitbox(a);local first=legacyBox
for _=1,100 do syncLegacyHitbox(a) end
assert(made==1 and removed==0 and legacyBox.Size.X==8)
assert(legacyBox.CanTouch and legacyBox.CanQuery and not legacyBox.CanCollide)
syncLegacyHitbox(b);assert(made==2 and removed==1 and first.Parent==nil)
b.Character=target().Character;syncLegacyHitbox(b);assert(made==3 and removed==2)
syncLegacyHitbox(nil);assert(removed==3 and legacyBox==nil)
mm2Settings.predictionProfile="Actual";syncLegacyHitbox(a);assert(made==3)
mm2Settings.predictionProfile="Old";mm2Settings.oldHitbox=false;syncLegacyHitbox(a);assert(made==3)
clearLegacyHitbox();clearLegacyHitbox();assert(removed==3)
pass("one local legacy volume: original query/touch, reuse, target/respawn cleanup and profile isolation")
end

do
for _,delay in ipairs({0,.08,.3,.6}) do
    local o=Vector3.new(30,0,0);local v=Vector3.new(16,0,0)
    local point,t=predictionMath.verticalIntercept(o,v,96,delay,196.2,true,nil)
    local linear=predictionMath.interceptTime(o+v*delay,v,96)
    near(t,linear,1e-6);near(point.Magnitude,96*t,1e-4)
end
for _,v in ipairs({Vector3.new(16,30,0),Vector3.new(10,-8,5)}) do
    local o=Vector3.new(20,10,0)
    local point,t=predictionMath.verticalIntercept(o,v,96,.1,196.2,false,nil)
    assert(point and t)
    near(point.Y,o.Y+v.Y*(t+.1)-.5*196.2*(t+.1)^2,1e-6)
    near(point.Magnitude,96*t,1e-4)
end
local point,t=predictionMath.verticalIntercept(Vector3.new(60,15,0),Vector3.new(16,-8,0),96,.2,196.2,false,-15)
assert(point and t);near(point.Y,0);near(point.Magnitude,96*t,1e-4)
assert(predictionMath.verticalIntercept(Vector3.new(30,0,0),Vector3.new(200,0,0),96,.2,196.2,true,nil)==nil)
assert(predictionMath.verticalIntercept(Vector3.new(0/0,0,0),Vector3.zero,96,.2,196.2,true,nil)==nil)
pass("bounded target-ballistics solver: walking, jumps, falling, floor contact, unreachable and NaN")
end
''', scene, r'''
velocity=Vector3.new(36,0,0);sample.classicStability=.8;sample.stability=.8
mm2Settings.gunLeadBias=.1;mm2Settings.gunTimingModel="RTT";mm2Settings.gunMotionModel="V17"
mm2Settings.predictionProfile="Old";mm2Settings.oldHitbox=false
assert(computeGunAim(target,origin)==nil) -- Old restores its error gate
mm2Settings.oldHitbox=true;mm2Settings.oldHitboxSize=8
local _,old=computeGunAim(target,origin)
assert(old and old.snapshot.model=="Classic 66d" and old.snapshot.allowedErrorBudget==4)
assert(old.errorRadius>1 and old.errorRadius<4)
mm2Settings.predictionProfile="Actual"
local _,actual=computeGunAim(target,origin)
assert(actual and actual.snapshot.model=="V17" and actual.snapshot.allowedErrorBudget==1)
mm2Settings.predictionProfile="Experimental"
local _,experimental=computeGunAim(target,origin)
assert(experimental and experimental.snapshot.model=="Projection selector")
mm2Settings.predictionProfile="Old"
local _,silent=computeGunAim(target,origin,{ignoreVisibility=true})
assert(silent.snapshot.profile=="Actual" and silent.snapshot.model=="V17" and silent.snapshot.allowedErrorBudget==1.75)
pass("real solver: 66d error budget restored only in Old, Actual preserved, Experimental fixed, Silent separate")

-- Real dispatcher, real solver and real send/telemetry path together.
local diagnostics={checks=0,sentNormal=0,sentSilent=0,burstGroups=0,rejected={}}
local state={mm2ShotFeedback={queue=function() end}}
local notify=function() end
local function setWeaponStatus() end
local legacyGeneration=0
local activeLegacyGroupId=nil
local function syncLegacyHitbox() error("cosmetic failure must not stop send") end
local LocalPlayer={FindFirstChildOfClass=function() return nil end}
local sends,notes,macros,attempts=0,{},0,0
local remote={IsA=function() return true end,FireServer=function() sends+=1;attempts+=1 end}
local gun={Name="Gun",Parent=character,Enabled=true,GetAttribute=function() return nil end,FindFirstChild=function() return remote end}
local function getCharacterParts() return character,humanoid end
local function getPlayerWeapon() return gun end
local function getGunOriginCFrame() return origin end
local function buildSilentShot() return origin,CFrame.new(Vector3.new(20,0,20)),0 end
local trajectoryCalibration={noteAuthoredShot=function(_,info) table.insert(notes,info) end}
local function macroUnequip() macros+=1 end
local onWait=function() end
local task={wait=function() onWait() end}
''', section(S, '    local lastRejectReason:', '    local shootFeatureActive:'), r'''
velocity=Vector3.new(16,0,0);sample.classicStability=1;sample.stability=1
mm2Settings.gunMotionModel="Classic 66d";mm2Settings.oldBurst=4;mm2Settings.gunLeadBias=0
assert(fireGunBurst(target));assert(sends==4 and #notes==4 and macros==1)
for i,info in ipairs(notes) do
    assert(info.settings.burst.index==i and info.settings.burst.count==4)
    assert(info.settings.prediction.burstCount==4 and info.settings.prediction.profile=="Old")
    near(info.settings.horizon,math.clamp(getGunHorizonSeconds()+info.settings.burst.bias,.03,.6))
end
local base=getGunHorizonSeconds()
near(notes[1].settings.burst.bias,0);near(notes[2].settings.burst.bias,base*.5)
near(notes[3].settings.burst.bias,-base*.5);near(notes[4].settings.burst.bias,base)
now+=.1;assert(not fireGunBurst(target));assert(sends==4)
now+=5;assert(fireGunBurst(target));assert(sends==8 and macros==2)
now+=.5;assert(not fireGunBurst(target,{maxError=.1}));assert(sends==8)
now+=.5;local epoch=legacyGeneration;legacyGeneration+=1
assert(not fireGunAtTarget(target,{generation=epoch}));assert(sends==8)
activeLegacyGroupId="new"
assert(not fireGunAtTarget(target,{burst={groupId="superseded"}}));assert(sends==8)
mm2Settings.predictionProfile="Actual";assert(fireGunBurst(target));assert(sends==9 and not notes[9].settings.legacyHitbox)
mm2Settings.predictionProfile="Old";assert(fireGunBurst(target,{silent=true}));assert(sends==10)
assert(notes[10].settings.prediction.profile=="Actual" and notes[10].settings.burst==nil)
now+=.5;remote.FireServer=function() attempts+=1;error("transport") end
local before=attempts;assert(not fireGunBurst(target));assert(attempts==before+1 and macros==4)
-- Cancellation while the equip call yields must also prevent the old batch.
now+=.5
local backpack={};LocalPlayer.FindFirstChildOfClass=function() return backpack end
gun.Parent=backpack
humanoid.IsA=function() return true end
humanoid.EquipTool=function() gun.Parent=character end
onWait=function() legacyGeneration+=1 end
assert(not fireGunBurst(target));assert(sends==10 and macros==4)
now+=.5
remote.FireServer=function() sends+=1;attempts+=1 end
getGunHorizonSeconds=function() return .45 end
assert(fireGunBurst(target));assert(sends==13 and macros==5) -- two capped horizons collapse to one
assert(notes[#notes].settings.burst.index==3)
pass("real Old dispatch: four distinct candidates, 0.5s shared cap, no catch-up, Auto gate, cancellation, one macro and send-error stop")
end

do
local mm2Settings={autoTuneLead=true,predictionEpoch=3}
local autoLeadCorrection=0
local GUN_LEAD={maximumAutoCorrection=.1}
''', section(B, 'local function tuneFromConfirmedShot(', 'state.mm2ShotFeedback.queue ='), r'''
local c={aimPosition=Vector3.new(3.2,0,0),velocity=Vector3.new(16,0,0),leadSeconds=.1,
    leadSensitivity=1,queuedAt=0,predictionEpoch=2,burstCount=1,trajectory={}}
for i=0,6 do table.insert(c.trajectory,{t=i*.05,p=Vector3.new(16*i*.05,0,0)}) end
tuneFromConfirmedShot(c);near(autoLeadCorrection,0)
c.predictionEpoch=3;c.burstCount=4;tuneFromConfirmedShot(c);near(autoLeadCorrection,0)
c.burstCount=1;tuneFromConfirmedShot(c);near(autoLeadCorrection,.025)
pass("actual lead tuner: rejects late prior-profile results and multi-request groups")
end

do
local workspace={Gravity=196.2}
local knifeThrowSettings={latencyModel="Replica RTT",leadBias=0,motionModel="Vertical (experimental)"}
local lastPrediction=nil
local velocity=Vector3.new(16,-5,0)
local root={Position=Vector3.new(0,20,0)}
local humanoid={}
local target={Character={FindFirstChild=function() return root end,FindFirstChildOfClass=function() return humanoid end}}
local probes=0
local core={mm2Settings={},isMotionGrounded=function() return false end,
    getLandingRootY=function() probes+=1;return 3 end}
local trajectoryCalibration={getEstimates=function() return {} end}
local function getFilteredVelocity() return velocity end
local function getEstimatedLatency() return .18 end
''', section(K, '    local function predictAim(', '    local function getThrowCadence('), r'''
local origin=Vector3.new(0,3,-30)
local aim=predictAim(target,origin)
assert(aim and probes==2 and lastPrediction.motionModel=="Vertical (experimental)")
near(aim.Y,3);near((aim-origin).Magnitude,lastPrediction.speed*lastPrediction.flightTime,1e-4)
assert(lastPrediction.landingRootY==3 and lastPrediction.targetVelocity[2]==-5)
knifeThrowSettings.motionModel="Linear";probes=0
local linear=predictAim(target,origin)
assert(linear and linear.Y>aim.Y and probes==0 and lastPrediction.motionModel=="Linear")
knifeThrowSettings.motionModel="Vertical (experimental)";velocity=Vector3.new(200,0,0)
assert(predictAim(target,origin)==nil and lastPrediction==nil)
pass("actual Knife integration: two bounded floor probes, corrected landing, baseline preserved, stale result cleared")
end
do
local function typeof(x) return type(x)=="table" and x.instance and "Instance" or type(x) end
local runtime={active=true,pendingGuns={},freshGunLatency={},gunAcceptance={},sessionGunConfirmed=0}
local estimatesAt=0
local recorded={}
local workspace={GetServerTimeNow=function() return now end}
local function getPingMilliseconds() return 200 end
local function vectorArray(p) return {p.X,p.Y,p.Z} end
local function appendEvent(e) table.insert(recorded,e) end
local tool={instance=true,IsA=function() return true end}
local function compactPending() end
local function normalizeGun(x) return x end
local function worldPosition(x) return x end
local function addSample() end
local function ensureTrajectorySampler() end
local function setWeaponStatus() end
local event
local function emitShot(_,info) event=info end
local function pending(burst)
    return {shotId="x",tool=tool,activatedAt=0,origin=Vector3.zero,requestedAim=Vector3.new(20,0,0),
        authored=true,targetCharacter={},settings={burst=burst}}
end
''',section(B,'    local function handleGunFired(', '    local finishKnifeTrack:'),r'''
now=.2
local hit={instance=true,Name="WurstHitbox",IsDescendantOf=function() return true end}
local c=pending(nil);runtime.pendingGuns={c}
handleGunFired(tool,Vector3.zero,Vector3.new(20,0,0),hit)
assert(event.syntheticHit and not event.hitTarget and #runtime.freshGunLatency==0)
c=pending({count=4});runtime.pendingGuns={c};hit.Name="Torso"
handleGunFired(tool,Vector3.zero,Vector3.new(20,0,0),hit)
assert(event.hitTarget and not event.syntheticHit and #runtime.freshGunLatency==0)
c=pending(nil);runtime.pendingGuns={c}
handleGunFired(tool,Vector3.zero,Vector3.new(20,0,0),hit)
assert(event.hitTarget and #runtime.freshGunLatency==1)
local a,b=pending({count=4,groupId="g"}),pending({count=4,groupId="g"})
b.targetCharacter=a.targetCharacter;runtime.pendingGuns={a,b};runtime.ambiguousGunSignals=0
handleGunFired(tool,Vector3.zero,Vector3.new(20,0,0),hit)
assert(#recorded==1 and recorded[1].phase=="burst-signal" and recorded[1].groupId=="g")
assert(recorded[1].targetBodySignal and a.confirmedAt==nil and b.confirmedAt==nil and #runtime.freshGunLatency==1)
b.settings.burst.groupId="other"
handleGunFired(tool,Vector3.zero,Vector3.new(20,0,0),hit)
assert(#recorded==1) -- two possible groups cannot be attributed
b.settings.burst=nil
handleGunFired(tool,Vector3.zero,Vector3.new(20,0,0),hit)
assert(#recorded==1) -- native/single contender also prevents group attribution

local resolved
local state={mm2ShotFeedback={shootActive=true,pendingShots={},toPosition=function(x) return x end,
    resolve=function(_,direct,observed) resolved={direct,observed} end}}
''',section(B,'state.mm2ShotFeedback.handleGunFired = function(', 'type KnifeSettings ='),r'''
state.mm2ShotFeedback.pendingShots={pending(nil)};hit.Name="WurstHitbox"
state.mm2ShotFeedback.handleGunFired(tool,Vector3.zero,Vector3.new(20,0,0),hit)
assert(resolved[1]==false and resolved[2]==true)
pass("real calibration/feedback observers: local-box contact is not a body hit; multi-request groups never train timing")
end
do
local mm2Settings={predictionProfile="Old",oldHitbox=true,silentAim=true,motionSampleHz=60}
local autoSettings={mode="Normal"}
local featureConnections={}
local tick
local TaskManager={Connect=function(_,fn) tick=fn;return {Disconnect=function() tick=nil end} end}
local function disconnectFeatureConnection(key)
    if featureConnections[key] then featureConnections[key]:Disconnect();featureConnections[key]=nil end
end
local state={mm2ShotFeedback={pendingShots={},hide=function() end}}
local function getWeaponServiceModule() return nil end
local function disconnectGunFiredObserver() end
local function getSelectedShootTarget() return {Character={FindFirstChild=function() return {} end}} end
local queries,updates=0,0
local lastBoxTarget=nil
local LocalPlayer={}
local function getPlayerWeapon() queries+=1;return {} end
local function getFilteredVelocity() end
local function syncLegacyHitbox(target) updates+=1;lastBoxTarget=target end
local cleared=0
local function clearLegacyHitbox() cleared+=1 end
local legacyGeneration=0
''',section(S,'    local shootFeatureActive:', '    local lastAutoShot:'),r'''
now=0;autoShootActive=true;refreshShootInfrastructure()
for i=1,100 do now=i/100;tick(.01) end
assert(queries>=7 and queries<=10 and lastBoxTarget~=nil) -- Auto Prediction works even with manual Mode Silent
mm2Settings.predictionProfile="Actual";local before=queries
for i=101,200 do now=i/100;tick(.01) end
assert(queries==before and lastBoxTarget==nil)
mm2Settings.predictionProfile="Old";autoSettings.mode="Silent"
for i=201,300 do now=i/100;tick(.01) end
assert(queries==before and lastBoxTarget==nil) -- neither controller requests Old
shootFeatureActive=true;mm2Settings.silentAim=false
for i=301,400 do now=i/100;tick(.01) end
assert(lastBoxTarget~=nil)
shootFeatureActive=false;autoShootActive=false;refreshShootInfrastructure()
assert(tick==nil and cleared==1 and legacyGeneration==1)
pass("actual tracking lifecycle: 10Hz box budget, no weapon scans in Actual, independent manual/Auto modes and OFF cleanup")
end
print("v20 regression groups passed:",passed)
'''])


def main():
    with tempfile.TemporaryDirectory(prefix='mm2-v20-') as folder:
        p=Path(folder)/'test.luau'
        p.write_text(build())
        subprocess.run([os.environ.get('LUAU','luau'),str(p)],check=True)

if __name__=='__main__':
    main()
