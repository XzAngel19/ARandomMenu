#!/usr/bin/env python3
"""Execute v17 control/calibration regressions with actual source and deterministic mocks.
LUAU=/path/to/luau python3 tools/test_mm2_v17.py
No network/game connection, no server acceptance or FPS claim.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
sys.dont_write_bytecode = True
from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
BASE = (ROOT / 'src/games/MM2/base.lua').read_text()
AURA = (ROOT / 'src/games/MM2/Blatant/KnifeAura.lua').read_text()
THROW = (ROOT / 'src/games/MM2/Blatant/KnifeThrow.lua').read_text()
SHOOT = (ROOT / 'src/games/MM2/Blatant/Shoot.lua').read_text()
WIDGETS = (ROOT / 'src/guis/Wurst/Code/Widgets.lua').read_text()
LOADER = (ROOT / 'src/Wurst.lua').read_text()


def build():
    chunks = [PRELUDE, section(BASE, 'local predictionMath = {}', 'type MotionSample')]
    chunks += [r'''
do
local state={mm2Core={predictionMath=predictionMath,trajectoryCalibration={},
    knifeControl=predictionMath.newKnifeControl(),setWeaponStatus=setWeaponStatus,weaponStatus=weaponStatus}}
local featureConnections={}
local mm2Features,MM2Scroll={},{}
local LocalPlayer={CharacterAdded={Connect=function() return {Disconnect=function() end} end}}
local TaskManager={Connect=function(_,fn) return {Connected=true,Disconnect=function(self) self.Connected=false end,fn=fn} end}
local function disconnectFeatureConnection(key)
    if featureConnections[key] then featureConnections[key]:Disconnect() end
    featureConnections[key]=nil
end
local toggles,numbers,actions={},{},{}
local function createUniversalFeature(name,description,order,onToggle)
    return {configKey="MM2."..name,onToggle=onToggle}
end
local function addToggleOption(feature,label,default,callback)
    local c={value=default}
    function c:click() self.value=not self.value; callback(self.value) end
    toggles[label]=c; callback(default)
end
local function addNumberOption(feature,label,default,lo,hi,callback)
    table.insert(numbers,{key=feature.configKey.."."..label:gsub("%W",""),value=default})
    callback(math.clamp(default,lo,hi))
end
local function addCycleOption(feature,label,values,index,callback) callback(values[index]) end
local function addActionOption(feature,label,callback) actions[label]=callback end
local Aura=(function()
''', AURA, r'''
end)()
local Throw=(function()
''', THROW, r'''
end)()
Aura.init({}); Throw.init({})
local card=state.mm2KnifeFeature
-- Wanted settings can be restored before the master without starting anything.
toggles["Knife Throw"]:click()
assert(toggles["Knife Throw"].value and featureConnections.MM2KnifeThrow==nil)
card.onToggle(true)
assert(featureConnections.MM2KnifeThrow and featureConnections.MM2KnifeThrow.Connected)
local previous=featureConnections.MM2KnifeThrow
card.onToggle(false)
assert(not previous.Connected and featureConnections.MM2KnifeThrow==nil)
assert(toggles["Knife Throw"].value)
card.onToggle(true)
assert(featureConnections.MM2KnifeThrow and featureConnections.MM2KnifeThrow~=previous)
toggles["Knife Aura"]:click()
assert(featureConnections.MM2KnifeController~=nil)
card.onToggle(false)
assert(featureConnections.MM2KnifeThrow==nil and featureConnections.MM2KnifeController==nil)
card.onToggle(true)
assert(featureConnections.MM2KnifeThrow and featureConnections.MM2KnifeController)
local keys={}
for _,row in ipairs(numbers) do assert(not keys[row.key],row.key); keys[row.key]=row.value end
assert(keys["MM2.Knife.AuraRange"]==14 and keys["MM2.Knife.ThrowRange"]==120)
assert(actions["Knife status"] and actions["Throw prediction status"])
Throw.destroy(); Aura.destroy()
assert(featureConnections.MM2KnifeThrow==nil and featureConnections.MM2KnifeController==nil)
pass("full Knife modules: restore, master OFF/ON, both sub-options, independent ranges, destroy")
end

do
local configData={values={["MM2.Knife.Range"]=250}}
local saved=0
local function queueConfigSave() saved+=1 end
local function migrate()
''', section(LOADER, 'if configData.values["MM2.Knife.RangeMigration"]', 'local function findExistingGui()'), r'''
end
migrate()
assert(configData.values["MM2.Knife.LegacyRange"]==250)
assert(configData.values["MM2.Knife.AuraRange"]==14 and configData.values["MM2.Knife.ThrowRange"]==120)
configData.values["MM2.Knife.ThrowRange"]=180
migrate(); assert(configData.values["MM2.Knife.ThrowRange"]==180 and saved==1)
pass("range migration preserves ambiguous legacy value; new defaults; idempotent")
end

do
local minimum,maximum,step,precisionFactor=0.2,3,0.1,10
local value,editing=1,false
local fill,knob,valueInput={},{},{}
local UDim2={fromScale=function(x,y) return {x,y} end}
local formatCompactNumber=tostring
local configData={values={}}
local optionKey="delay"
local function queueConfigSave() end
local function isFiniteNumber(v) return predictionMath.finite(v) end
local applied=nil
local function callback(v) applied=v end
''', section(WIDGETS, '        local function quantize(raw:', '        local function updateFromScreenX('), r'''
setValue(-1,true,false); near(applied,0.2); near(configData.values.delay,0.2)
setValue(999,false,false); near(applied,3)
setValue(0/0,true,false); near(applied,3)
setValue(-1,true,true); near(applied,0.2)
pass("actual numeric widget clamps typed, restored and slider values; rejects NaN")
end

do
''', section(BASE, 'local GUN_LEAD = {', 'local autoLeadCorrection:'),
        section(BASE, 'local function getGunTurnRate(', 'local function getGunTurnDiscount('),
        section(BASE, 'local motionSamples:', 'local lastLatencyReadAt:'), r'''
local hum={FloorMaterial="Ground",GetState=function() return "Running" end}
local player={Character={FindFirstChildOfClass=function() return hum end}}
for _,hz in ipairs({20,60,120}) do
    local root={Position=Vector3.zero,AssemblyLinearVelocity=Vector3.new(16,0,0)}
    motionSamples[player]=nil; now=0; getFilteredVelocity(player,root)
    now=1/hz
    local theta=math.pi/hz
    root.AssemblyLinearVelocity=Vector3.new(16*math.cos(theta),0,16*math.sin(theta))
    getFilteredVelocity(player,root)
    local m=motionSamples[player]; near(getGunTurnRate(m.stability,m.sampleInterval),math.pi)
end
-- Repeated reads at 120Hz, actual heading updated only every 50ms.
motionSamples[player]=nil; now=0
local root={Position=Vector3.zero,AssemblyLinearVelocity=Vector3.new(16,0,0)}
getFilteredVelocity(player,root)
for i=1,18 do
    now=i/120
    local theta=math.floor(i/6)*math.pi/20
    root.AssemblyLinearVelocity=Vector3.new(16*math.cos(theta),0,16*math.sin(theta))
    getFilteredVelocity(player,root)
    if i>=6 then local m=motionSamples[player]; near(getGunTurnRate(m.stability,m.sampleInterval),math.pi) end
end
pass("turn estimator is time-normalized at 20/60/120Hz and ignores repeated replicated headings")
end

do
local mm2Settings={predictionRtt=0.08,gunLeadBias=0,autoTuneLead=false,adaptiveGunTiming=false}
local Stats={FindFirstChild=function() return nil end}
''', section(BASE, 'local lastLatencyReadAt:', 'local function getGunOriginCFrame'), r'''
local original=getGunHorizonSeconds()
trajectoryCalibration={getEstimates=function() return {liveGunAcceptanceMs=100,liveGunSamples=10} end}
near(getGunHorizonSeconds(),original)
mm2Settings.adaptiveGunTiming=true
near(getGunHorizonSeconds(),0.125+1/40+1/120)
mm2Settings.adaptiveGunTiming=false
near(getGunHorizonSeconds(),original)
pass("recording timing never adjusts aim unless Adaptive gun timing is explicitly ON")
end

do
local velocity=Vector3.new(16,0,0)
local root={Position=Vector3.new(96,0,0)}
local target={Character={FindFirstChild=function() return root end}}
local core={mm2Settings={useKnifeSpeedCalibration=false}}
local knifeThrowSettings={latencyModel="Packet RTT/2",leadBias=0}
local lastPrediction
local trajectoryCalibration={getEstimates=function() return {knifeSpeed=120,liveKnifeSpeed=120,liveKnifeSamples=3} end}
local function getFilteredVelocity() return velocity end
local function getEstimatedLatency() return 0.2 end
''', section(THROW, '    local function predictAim', '    local throwTrack:'), r'''
local half=predictAim(target,Vector3.zero)
near(lastPrediction.networkLead,0.1); near(lastPrediction.speed,96)
knifeThrowSettings.latencyModel="Replica RTT"
local full=predictAim(target,Vector3.zero)
near(lastPrediction.networkLead,0.2); assert(full.X>half.X)
core.mm2Settings.useKnifeSpeedCalibration=true
predictAim(target,Vector3.zero); near(lastPrediction.speed,120)
pass("Knife A/B exposes half/full RTT; flight solved separately; learned speed opt-in")
end

do
local runtime={active=true,pendingGuns={},freshGunLatency={},gunAcceptance={},sessionGunConfirmed=0,
    ambiguousGunSignals=0,duplicateGunSignals=0,unmatchedGunSignals=0}
local tool={}
local first={shotId="A",tool=tool,activatedAt=0,origin=Vector3.zero,requestedAim=Vector3.new(10,0,0),authored=true}
local second={shotId="B",tool=tool,activatedAt=0.2,origin=Vector3.new(100,0,0),requestedAim=Vector3.new(110,0,0),authored=true}
local estimatesAt=0
local function compactPending() end
local function normalizeGun(x) return x end
local function worldPosition(x) return x end
local function addSample() end
local function ensureTrajectorySampler() end
local LocalPlayer={Character={}}
local emitted=nil
local function emitShot(_,info) emitted=info end
runtime.pendingGuns={first,second}
''', section(BASE, '    local function handleGunFired(', '    local finishKnifeTrack:'), r'''
now=0.3
handleGunFired(tool,Vector3.zero,Vector3.new(5,0,0),nil)
assert(first.confirmedAt==0.3 and second.confirmedAt==nil)
assert(emitted.shotId=="A"); near(runtime.freshGunLatency[1].ms,300)
handleGunFired(tool,Vector3.zero,Vector3.new(5,0,0),nil)
assert(runtime.duplicateGunSignals==1 and runtime.sessionGunConfirmed==1)
first.confirmedAt=nil
second.origin=Vector3.zero; second.requestedAim=Vector3.new(10,0,0)
handleGunFired(tool,Vector3.zero,Vector3.new(5,0,0),nil)
assert(runtime.ambiguousGunSignals==1 and runtime.sessionGunConfirmed==1 and #runtime.freshGunLatency==1)
assert(predictionMath.matchAttempt({first},nil,nil,Vector3.new(1,0,0),now)==nil)
assert(predictionMath.matchAttempt({first},{},Vector3.zero,Vector3.new(1,0,0),now)==nil)
assert(predictionMath.matchAttempt({first},tool,Vector3.zero,Vector3.new(-1,0,0),now)==nil)
first.authored=false; runtime.pendingGuns={first}
handleGunFired(tool,Vector3.zero,Vector3.new(5,0,0),nil)
assert(runtime.sessionGunConfirmed==2 and #runtime.freshGunLatency==1)
pass("actual Gun observer: oldest matching geometry, duplicate/ambiguity refusal, no native activation latency training")
end

do
local mm2Settings={calibrationDetails=false}
local function getTargetRoot() error("OFF must not capture target") end
local function getTargetHumanoid() error("OFF must not capture target") end
''', section(BASE, '    local function captureTrajectoryPoint(', '    local function findKnifeAnalysisTarget('), r'''
assert(captureTrajectoryPoint({},0,100)==nil)
local runtime={events={},sessionId="session",buildStamp="v17",revision=0,dirty=false,saveScheduled=false,active=true}
local MAX_EVENTS=2
local scheduled,saveCount=0,0
local queued
local task={delay=function(_,fn) scheduled+=1; queued=fn end}
local function saveSnapshot() saveCount+=1 end
''', section(BASE, '    local function appendEvent(', '    local function trackConnection('), r'''
appendEvent({kind="gun"}); assert(runtime.dirty and scheduled==0)
mm2Settings.calibrationAutosave=true
appendEvent({kind="gun"}); appendEvent({kind="knife"})
assert(scheduled==1 and #runtime.events==2)
mm2Settings.calibrationAutosave=false; queued(); assert(saveCount==0)
pass("lightweight capture performs no trajectory reads; bounded events; autosave opt-in and cancellable")
end

do
local state={mm2ShotFeedback={spawnStats={Through={shots=1,hits=0,confirmed=0,unconfirmed=0}},hide=function() end}}
local trained=0
local function tuneFromConfirmedShot() trained+=1 end
''', section(BASE, 'state.mm2ShotFeedback.resolve = function(', 'state.mm2ShotFeedback.handleGunFired = function('), r'''
local c={target={Parent=nil},silentSpawn="Through"}
state.mm2ShotFeedback.resolve(c,false,false)
local s=state.mm2ShotFeedback.spawnStats.Through
assert(s.hits==0 and s.unconfirmed==1 and s.confirmed==0 and trained==0)
state.mm2ShotFeedback.resolve(c,true,true); assert(s.hits==0) -- final/duplicate protection
state.mm2ShotFeedback.resolve({silentSpawn="Through"},false,true)
assert(s.confirmed==1 and s.hits==0)
state.mm2ShotFeedback.resolve({silentSpawn="Through"},true,true)
assert(s.confirmed==2 and s.hits==1 and trained==1)
pass("Spawn A/B distinguishes unknown, observed and hit-part; disconnect cannot become hit; idempotent")
end
''']
    chunks += [r'''

do
local runtime={active=true,sessionId="s",pendingKnives={},tracks={},observedProjectiles={},
    freshKnifeSpeed={},knifeSpeed={},knifeSpawnDelay={},sessionKnifeAttempts=1,
    sessionKnifeConfirmed=0,ambiguousKnifeSignals=0}
local mm2Settings={calibrationDetails=false}
local estimatesAt=0
local events,emitted={},{}
local function appendEvent(record) table.insert(events,record) end
local function emitShot(kind,record) table.insert(emitted,{kind=kind,record=record}) end
local function addSample(stats,value) stats.last=value end
local function compactPending() end
local function analyzeTargetTrajectory() return {} end
local function median(values) return values[1] end
local function projectilePosition() return Vector3.zero end
local function disconnectFeatureConnection() end
local workspace={GetServerTimeNow=function() return now end}
local callbacks={}
local featureConnections={}
local TaskManager={Connect=function(_,fn) table.insert(callbacks,fn); return {Disconnect=function() end} end}
local task={spawn=function(fn) fn() end,wait=function() error("unexpected wait") end}
local tool={Name="Knife"}
local handle={IsDescendantOf=function(_,value) return value==tool end}
tool.FindFirstChild=function() return handle end
local function projectile(speed)
    return {Parent={},FindFirstChild=function() return {IsA=function() return true end,Value=handle} end,
        GetAttribute=function() return speed end,Destroying={Connect=function() return {Disconnect=function() end} end}}
end
local function pending(id,classified)
    return {shotId=id,tool=tool,activatedAt=0,pingMs=200,attemptCounted=classified,targetTrajectory={}}
end

''', section(BASE, '    local finishKnifeTrack:', '    local function isGun('), r'''
now=0.2
runtime.pendingKnives={pending("one",true)}
local p=projectile(96)
resolveKnifeProjectile(p)
assert(runtime.sessionKnifeConfirmed==1 and #runtime.pendingKnives==0)
assert(events[1].phase=="projectile-observed" and events[1].speedEvidence=="ThrowSpeed attribute")
assert(events[1].impactMeaning:find("unknown") and #callbacks==0)
assert(#runtime.freshKnifeSpeed==1 and runtime.freshKnifeSpeed[1].speed==96)
resolveKnifeProjectile(p); assert(runtime.sessionKnifeConfirmed==1)
runtime.pendingKnives={pending("a",true),pending("b",true)}
resolveKnifeProjectile(projectile(96))
assert(runtime.ambiguousKnifeSignals==1 and #runtime.pendingKnives==2 and #events==1)
runtime.pendingKnives={pending("native",false)}
resolveKnifeProjectile(projectile(96))
assert(runtime.sessionKnifeAttempts==2 and runtime.sessionKnifeConfirmed==2)
runtime.pendingKnives={pending("invalid-attribute",true)}
local bad=projectile(0/0)
resolveKnifeProjectile(bad)
assert(runtime.tracks[bad].rawSpeed==nil and #callbacks==1)
finishKnifeTrack(bad,"destroyed")
assert(runtime.sessionKnifeConfirmed==2 and #runtime.freshKnifeSpeed==2)
pass("actual Knife observer: unique/ambiguous/native/duplicate, attribute-only low cost, NaN rejection, no invented hit")
end

do
local runtime={timedOutAttempts=0}
local MAX_PENDING_AGE=2.5
local records={}
local function appendEvent(e) table.insert(records,e) end
local finalized=0
local function finalizeGunCapture() finalized+=1 end
local workspace={GetServerTimeNow=function() return now end}
local compactPending
''', section(BASE, '    compactPending = function(', '    local function vectorFromArray('), r'''
now=3
local queue={{kind="knife",activatedAt=0,attemptCounted=true,shotId="k",pingMs=100},
    {kind="gun",activatedAt=0,attemptCounted=true,confirmedAt=0.2},
    {kind="knife",activatedAt=0,attemptCounted=false}}
compactPending(queue,now)
assert(#queue==0 and runtime.timedOutAttempts==1 and #records==1 and finalized==1)
assert(records[1].kind=="knife" and records[1].phase=="unconfirmed")
pass("expired observations preserve unknown vs confirmed vs unclassified activation")
end
''']
    generic = (ROOT / 'src/games/universal/Render/ProjectileCalibration.lua').read_text()
    learning = (ROOT / 'src/games/universal/Other/GameLearning.lua').read_text()
    chunks += [r'''
do
local runtime={enabled=false,historyLoaded=false,connections={},tracks={},pending={},observedTools={},observedCandidates={}}
local reads,disconnections=0,0
local executorEnvironment={readfile=function() reads+=1; return "{}" end}
local outputPath="test"
local controller={}
local signal={Connect=function() return {Disconnect=function() disconnections+=1 end} end}
local LocalPlayer={Character={},CharacterAdded=signal,FindFirstChildOfClass=function() return {} end}
local workspace={DescendantAdded=signal}
local function observeContainer() end
local function considerCandidate() end
''', section(generic, '        local function disconnectAll():', '        local function compactPending('),
        section(generic, '        local function loadSavedAnalytics():', '        controller = {}'),
        section(generic, '        function controller:setEnabled(', '        function controller:save('), r'''
controller:setEnabled(true); assert(reads==1 and #runtime.connections==2)
controller:setEnabled(true); assert(reads==1 and #runtime.connections==2)
controller:setEnabled(false); assert(#runtime.connections==0 and disconnections==2)
controller:setEnabled(true); assert(reads==1 and #runtime.connections==2)
controller:setEnabled(false)
local toggles={}
local function addToggleOption(feature,label,default,callback)
    assert(default==false)
    toggles[label]=callback; callback(default)
end
local calibration=controller
local ProjectileCalibrationFeature={}
local GameLearningFeature={}
local gameLearning={setEnabled=function(self,value) self.enabled=value end}
''', section(generic, '    addToggleOption(ProjectileCalibrationFeature, "Projectile observer"', '    tuning ='),
        section(learning, '    addToggleOption(GameLearningFeature, "Game learning observer"', '    addToggleOption(\n'), r'''
assert(not runtime.enabled and gameLearning.enabled==false)
toggles["Projectile observer"](true); assert(runtime.enabled)
toggles["Game learning observer"](true); assert(gameLearning.enabled)
toggles["Projectile observer"](false); assert(not runtime.enabled)
pass("optional generic observers default OFF; UI controls wired; projectile off/on disconnects without reimporting history")
end
print("v17 regression groups passed:",passed)
''']
    return '\n'.join(chunks)


def main():
    assert 'autoSettings.maxError = math.clamp(value, MINIMUM_ERROR_RADIUS, 1)' in SHOOT
    assert 'silent = autoSettings.mode == "Silent"' in SHOOT
    assert 'v18-20261014-mm2-evidence-motion' in LOADER
    assert 'arena/d83a806d-arandommenu' in LOADER
    with tempfile.TemporaryDirectory(prefix='mm2-v17-') as directory:
        file = Path(directory) / 'test.luau'
        file.write_text(build())
        subprocess.run([os.environ.get('LUAU', 'luau'), str(file)], check=True)


if __name__ == '__main__':
    main()
