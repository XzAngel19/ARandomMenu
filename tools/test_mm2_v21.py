#!/usr/bin/env python3
"""Execute actual v21 source under variable render/heartbeat rates and mocked UI.
These are correctness/budget tests, not Roblox hit-rate or FPS benchmarks.
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
from test_mm2_v20 import build as v20
R=Path(__file__).resolve().parents[1]
B=(R/'src/games/MM2/base.lua').read_text()
S=(R/'src/games/MM2/Blatant/Shoot.lua').read_text()
W=(R/'src/guis/Wurst/Code/Widgets.lua').read_text()
L=(R/'src/Wurst.lua').read_text()
P=(R/'src/guis/Wurst/Code/SettingsPage.lua').read_text()


def build():
    ui=section(v19(),'local settings={shootMode=','assert(choices["Shoot.Mode"]')
    scene=section(v18(),'do\nlocal workspace={Gravity=','for _,similarity')
    observer=section(v20(),'do\nlocal function typeof(x)', 'now=.2\nlocal hit=')
    observer=observer.replace('local runtime=', 'local netStatus={}\nlocal function getNetworkStatus() return netStatus end\nlocal runtime=',1)
    knife=section(v20(),'do\nlocal workspace={Gravity=196.2}\nlocal knifeThrowSettings=', 'local aim=predictAim(target,origin)')
    knife=knife.replace('local function getEstimatedLatency() return .18 end',
        'local ping=.72; local refreshed=false; local function getEstimatedLatency(force) refreshed=force;return ping end')
    return '\n'.join([PRELUDE,section(B,'local predictionMath = {}','type MotionSample'),r'''
do
local function trial(rates)
 now=0
 local reads=0
 local ping=180
 local pingItem={GetValue=function() reads+=1;return ping end}
 local Stats={FindFirstChild=function() return {FindFirstChild=function() return {FindFirstChild=function() return pingItem end} end} end}
 local mm2Settings={predictionRtt=.08,gunTimingModel="RTT",gunLeadBias=0,autoTuneLead=false}
''',section(B,'local lastLatencyReadAt:','local function getGunOriginCFrame'),r'''
 local tick,render
 local featureConnections={}
 local TaskManager={Connect=function(_,fn,phase)
    if phase=="render" then render=fn else tick=fn end
    return {Disconnect=function() end}
 end}
''',section(B,'featureConnections.MM2FrameMonitor =','state.mm2Core = {'),r'''
 assert(getNetworkStatus().stale)
 near(getEstimatedLatency(),.18)
 for _=1,50 do getEstimatedLatency() end
 assert(reads==1)
 local firstSpike=nil
 local i=0
 while now<8 do
    i+=1
    local dt=math.min(1/rates[1+(i-1)%#rates],8-now)
    now+=dt
    ping=(now>=2 and now<2.4) and 620 or 180
    if now>=6.5 and now<7.5 then ping=0/0 end
    tick(dt);render(dt)
    local n=getNetworkStatus()
    if n.raw==.62 and not firstSpike then
        firstSpike=now;assert(n.spike);near(n.estimate,.62)
    end
    if now>3.6 and now<6 then assert(not n.spike and not n.stale) end
    if now>6.8 and now<7.4 then assert(n.stale) end
    assert(not shouldHoldForNetwork("Best effort"))
 end
 assert(firstSpike and firstSpike-2<.14)
 assert(reads>=75 and reads<85 and #getNetworkStatus(true).history<=40)
 assert(getNetworkStatus().history==nil and not getNetworkStatus().stale)
 assert(networkEstimator.renderSeconds>=1/100 and networkEstimator.renderSeconds<=1/29)
 now+=.02;ping=950
 near(getEstimatedLatency(true),.95)
 assert(shouldHoldForNetwork("Hold spikes"))
 near(getGunHorizonSeconds(),.85) -- explicit, finite forecast limit, not the former RTT cap
 now+=.02;ping=180;near(getEstimatedLatency(true),.18)
 local before=reads;tick(0/0);render(-1);assert(reads==before)
 now+=.02;ping=3000;near(getEstimatedLatency(true),1.2);assert(getNetworkStatus().capped)
 now+=2;assert(getNetworkStatus().stale)
 return firstSpike
end
for _,fps in ipairs({30,40,50,60,70,80,90}) do trial({fps}) end
trial({80,30,70,40,50,90,30})
pass("real shared monitor: variable 30-90 FPS, first-observed spike response, recovery, missing data, forced reads, finite caps and bounded history")
end

do
local rays=0
local LocalPlayer={}
local CollectionService={GetTagged=function() return {} end}
local RaycastParams={new=function() return {} end}
local hit={IsA=function() return true end,Transparency=1}
local workspace={Raycast=function() rays+=1;return {Instance=hit} end}
''',section(B,'local function isWeaponPathClear(', '-- One bounded map probe'),r'''
local budget={remaining=12}
for _=1,3 do assert(not isWeaponPathClear(Vector3.zero,Vector3.new(0,0,20),nil,budget)) end
assert(rays==12 and budget.remaining==0)
rays=0;assert(not isWeaponPathClear(Vector3.zero,Vector3.new(0,0,20),nil));assert(rays==32)
pass("actual transparent-layer LOS: shared 12-ray Experimental cap, no multiplication across three candidates; legacy behavior unchanged")
end

do
local p=Vector3.new(0,3,30);local origin=Vector3.zero
local calls=0
local ranked=predictionMath.rankProjections(origin,p,Vector3.new(16,0,0),Vector3.new(80,0,0),Vector3.new(0,0,1),.3,.03,true,196.2,
    function() calls+=1;return nil end)
assert(#ranked==3 and calls==3)
assert(ranked[1].score<=ranked[2].score and ranked[2].score<=ranked[3].score)
for _,candidate in ipairs(ranked) do
 assert(candidate.worst>=0 and candidate.score>=0 and candidate.point.Y==3)
end
local a=predictionMath.rankProjections(origin,p,Vector3.zero,Vector3.zero,Vector3.new(1,0,0),.2,.01,true,196.2,nil)
local b=predictionMath.rankProjections(origin,p,Vector3.zero,Vector3.zero,Vector3.new(1,0,0),.2,.15,true,196.2,nil)
for i=1,3 do near((a[i].point-p).Magnitude,0);near((b[i].point-p).Magnitude,0) end -- intent cannot move a stopped target
local tight=predictionMath.rankProjections(origin,p,Vector3.new(16,0,0),Vector3.zero,Vector3.zero,.2,.01,true,196.2,nil)
local wide=predictionMath.rankProjections(origin,p,Vector3.new(16,0,0),Vector3.zero,Vector3.zero,.2,.15,true,196.2,nil)
assert(wide[1].worst>tight[1].worst)
local floor=predictionMath.rankProjections(origin,Vector3.new(0,20,30),Vector3.new(10,-10,0),Vector3.zero,Vector3.zero,.5,.1,false,196.2,function() return 3 end)
for _,c in ipairs(floor) do near(c.point.Y,3) end
pass("real fixed projection ranker: three candidates, nine plausible states, deterministic scores, stationary intent and landing")
end
''',scene,r'''
mm2Settings.predictionProfile="Experimental";mm2Settings.oldHitbox=true;mm2Settings.oldBurst=4
mm2Settings.gunLandingGuard=true;mm2Settings.shootWallCheck=true
local paths,bystanders,floors=0,0,0
getLandingRootY=function() floors+=1;return 0 end
local blocked=0
isWeaponPathClear=function() paths+=1;return paths>blocked end
candidateBystanderCheck=function() bystanders+=1;return false end
local _,result=computeGunAim(target,origin)
assert(result and result.snapshot.model=="Projection selector" and result.snapshot.learningEligible==false)
assert(result.snapshot.candidateCount==3 and result.snapshot.hypothesisCount==9)
assert(paths<=3 and bystanders<=3 and floors<=3)
local first=result.endpoint
paths=0;blocked=3
assert(computeGunAim(target,origin)==nil and paths<=3)
paths=0;blocked=0
local no,_,reason=computeGunAim(target,origin,{maxError=.1})
assert(no==nil and reason=="projection uncertain" and paths==0)
velocity=Vector3.new(0/0,0,0);assert(computeGunAim(target,origin)==nil)
velocity=Vector3.new(16,0,0)
local diagnostics={checks=0,sentNormal=0,sentSilent=0,burstGroups=0,rejected={}}
local state={mm2ShotFeedback={queue=function() end}}
local notify=function() end
local function setWeaponStatus() end
local LocalPlayer={FindFirstChildOfClass=function() return nil end}
local sends,notes=0,{}
local remote={IsA=function() return true end,FireServer=function() sends+=1 end}
local gun={Name="Gun",Parent=character,Enabled=true,GetAttribute=function() return nil end,FindFirstChild=function() return remote end}
local function getCharacterParts() return character,humanoid end
local function getPlayerWeapon() return gun end
local function getGunOriginCFrame() return origin end
local function buildSilentShot() return origin,CFrame.new(Vector3.new(20,0,20)),0 end
local trajectoryCalibration={noteAuthoredShot=function(_,info) table.insert(notes,info) end}
local function macroUnequip() end
local function shouldHoldForNetwork(policy) return policy=="Hold spikes" end
local task={wait=function() error("ready shot must not wait") end,delay=function() error("no delayed candidate dispatch") end}
''',section(S,'    local lastRejectReason:', '    local shootFeatureActive:'),r'''
local before=now
assert(fireGunBurst(target))
assert(now==before and sends==1 and #notes==1 and notes[1].settings.burst==nil)
assert(notes[1].settings.prediction.learningEligible==false)
mm2Settings.gunNetworkPolicy="Hold spikes"
assert(not fireGunBurst(target));assert(sends==1)
mm2Settings.gunNetworkPolicy="Best effort"
assert(fireGunBurst(target));assert(sends==2)
pass("real Experimental send path: bounded scene checks, error gate, no waits, exactly one request despite saved Burst=4, explicit network policy")
end

do
local autoShootActive=false
local legacyGeneration=0
local state={}
local featureConnections={}
local tick
local TaskManager={Connect=function(_,fn) tick=fn;return {Disconnect=function() tick=nil end} end}
local function disconnectFeatureConnection() if tick then tick=nil end end
local function refreshShootInfrastructure() end
local lastAutoShot=0
local calls=0
local function autoShootTick() calls+=1 end
''',section(S,'    local function toggleAutoShoot(', '    local ShootFeature ='),r'''
toggleAutoShoot(true)
for _,fps in ipairs({30,80,40,70,50,90}) do
 local before=calls
 for _=1,fps do tick(1/fps) end
 assert(calls-before==fps)
end
local before=calls;tick(.8);assert(calls==before+1)
toggleAutoShoot(false);assert(tick==nil)
pass("actual Auto scheduler: one evaluation per available 30-90 FPS frame, no catch-up burst after a stall")
end

do
''',ui,r'''
assert(not visible("Motion model") and not visible("Shoot diagnostics"))
callbacks["Shoot.Mode"]("Prediction")
assert(visible("Prediction profile") and not visible("Motion model"))
callbacks["Shoot.Advanced"](true);assert(visible("Motion model"))
callbacks["Shoot.Prediction profile"]("Experimental");assert(not visible("Auto tune lead"))
callbacks["Shoot.Prediction profile"]("Actual");assert(visible("Auto tune lead"))
callbacks["Shoot.Advanced"](false);assert(not visible("Motion model"))
assert(visible("Network policy"))
pass("full Shoot UI: Advanced hides tuning without changing settings; profile and network policy remain accessible")
end

''',observer,r'''
now=.2
local hit={instance=true,Name="Torso",IsDescendantOf=function() return true end}
for _,flag in ipairs({"spike","stale","capped"}) do
 netStatus[flag]=true
 runtime.pendingGuns={pending(nil)};handleGunFired(tool,Vector3.zero,Vector3.new(20,0,0),hit)
 assert(#runtime.freshGunLatency==0)
 netStatus[flag]=nil
 local c=pending(nil);c.settings.prediction={network={[flag]=true}}
 runtime.pendingGuns={c};handleGunFired(tool,Vector3.zero,Vector3.new(20,0,0),hit)
 assert(#runtime.freshGunLatency==0)
end
runtime.pendingGuns={pending(nil)};handleGunFired(tool,Vector3.zero,Vector3.new(20,0,0),hit)
assert(#runtime.freshGunLatency==1)
pass("actual event timing: exclude instability at send OR observation, retain stable single requests")
end

do
local mm2Settings={autoTuneLead=true,predictionEpoch=3}
local state={mm2ShotFeedback={}}
local featureConnections={}
local connections,stops=0,0
local tick
local TaskManager={Connect=function(_,fn) connections+=1;tick=fn;return {} end}
local function disconnectFeatureConnection() stops+=1 end
local autoLeadCorrection=0
local GUN_LEAD={maximumAutoCorrection=.1}
''',section(B,'local leadTracking: PendingShot?', 'state.mm2ShotFeedback.queue ='),r'''
local root={Position=Vector3.zero}
local c={targetCharacter={FindFirstChild=function() return root end},learningEligible=false,
    aimPosition=Vector3.new(3.2,0,0),velocity=Vector3.new(16,0,0),leadSeconds=.1,
    leadSensitivity=1,queuedAt=0,predictionEpoch=3,burstCount=1,trajectory={}}
for i=0,6 do table.insert(c.trajectory,{t=i*.05,p=Vector3.new(16*i*.05,0,0)}) end
startLeadTracking(c);assert(connections==0)
tuneFromConfirmedShot(c);near(autoLeadCorrection,0)
c.learningEligible=true;tuneFromConfirmedShot(c);near(autoLeadCorrection,.025)
state.mm2ShotFeedback.pending=c
startLeadTracking(c);assert(connections==1)
local before=stops;mm2Settings.predictionEpoch=4;tick(.03);assert(stops==before+1)
pass("actual scalar learner: ineligible candidates neither start tracking nor train; old tracker stops after profile change")
end
''',knife,r'''
knifeThrowSettings.motionModel="Linear"
assert(predictAim(target,origin) and refreshed);near(lastPrediction.networkLead,.72)
knifeThrowSettings.latencyModel="Packet half"
assert(predictAim(target,origin));near(lastPrediction.networkLead,.36)
knifeThrowSettings.latencyModel="Replica RTT";ping=3
assert(predictAim(target,origin));near(lastPrediction.networkLead,1.2)
pass("actual Knife: forced refresh, full RTT including spikes, independent half-RTT choice and explicit 1.2s packet bound")
end

do
local callback
local uiPanel={optionCount=0,configKey="UI"}
local uiRecord={}
local uiSettingsValues={Rainbow=true}
local configData={values={["UI.Accent"]="custom"}}
local CLICKGUI_BACKGROUND,CLICKGUI_ACCENT,CLICKGUI_TEXT,CLICKGUI_ENABLED="bg","violet","text","violet"
local saved,painted,applied,updates=0,0,0,nil
local host={colorToConfig=function(c) return c end}
local function queueConfigSave() saved+=1 end
local function notify() end
local function paintPalette() painted+=1 end
local function actionRow(_,_,_,fn) callback=fn end
local ThemeEngine={Apply=function() applied+=1 end,SetMany=function(t) updates=t end}
''',section(P,'    local rainbowSince: number = 0', '    addToggleOption(uiPanel, "Rainbow"'),r'''
assert(configData.values["UI.Accent"]=="custom" and applied==0)
callback();assert(applied==0 and saved==0)
uiSettingsValues.Rainbow=false;callback()
assert(saved==1 and painted==4 and applied==1 and configData.values["UI.Accent"]=="violet")
assert(updates.accent==configData.values["UI.Accent"] and updates.outline==updates.accent)
assert(updates.surface==configData.values["UI.Background"])
pass("actual Midnight preset: preserves custom colors until requested, requires Rainbow OFF, saves reload-consistent tokens")
end

-- Minimal instance/signals implementation for the actual new widgets.
do
local allocations=0
local function signal()
 local subscribers={}
 return {Connect=function(_,fn)
    local c={Connected=true,fn=fn};function c:Disconnect() self.Connected=false end
    table.insert(subscribers,c);return c
 end,Fire=function(_,...) for _,c in ipairs(subscribers) do if c.Connected then c.fn(...) end end end}
end
local UDim={new=function(s,o) return {Scale=s,Offset=o} end}
local UDim2={new=function(a,b,c,d) return {X=UDim.new(a,b),Y=UDim.new(c,d)} end,
    fromOffset=function(x,y) return {X=UDim.new(0,x),Y=UDim.new(0,y)} end}
local Vector2={new=function(x,y) return {X=x,Y=y} end}
local Enum={TextTruncate={AtEnd=1},TextXAlignment={Left=1,Right=2}}
local function create(class,props)
 allocations+=1
 local o={ClassName=class,children={},attrs={},Visible=true,Enabled=true,ZIndex=1,
    MouseButton1Click=signal(),Text=""}
 function o:IsA(name) return name==self.ClassName or (name=="GuiObject" and (self.ClassName=="Frame" or self.ClassName=="TextButton" or self.ClassName=="TextLabel")) end
 function o:FindFirstChild(name) for _,c in ipairs(self.children) do if c.Name==name then return c end end end
 function o:SetAttribute(k,v) self.attrs[k]=v end
 function o:GetAttribute(k) return self.attrs[k] end
 function o:Destroy() self.Parent=nil end
 for k,v in pairs(props or {}) do o[k]=v end
 if o.Parent then table.insert(o.Parent.children,o) end
 return o
end
local Theme={text="white",textMuted="muted",accent="violet",accentSoft="soft",surfaceRaised="dark",positive="green",negative="red"}
local ThemeEngine={}
local themeBindings={}
''',section(L,'function ThemeEngine.Bind(', 'function ThemeEngine.OnChange('),r'''
local screen=create("ScreenGui",{})
local container=create("Frame",{Parent=screen})
local feature={configKey="Test",optionCount=0,optionRows={},searchText="",options=container,updateExpandedSize=function() end}
local state={layout={optionRowHeight=26}}
local configData={values={["Test.Mode"]="Silent AIM"}}
local saves=0
local function queueConfigSave() saves+=1 end
local CONTROL_FONT="Font"
local LABEL_FONT_SIZE,CHILD_INSET=16,4
local function trackUiConnection(c) return c end
local dropdowns=0
local function openChoiceList(_,_,_,pick) dropdowns+=1;pick(3) end
local function drawPixelIcon() end
local heartbeat=signal()
local host={ThemeEngine=ThemeEngine,RunService={Heartbeat=heartbeat}}
''',section(W,'    local function createOptionRow(', '    state.addSectionOption ='),
section(W,'    local function addCycleOption(', '    -- Fixed-size graph'),
section(W,'    state.addTelemetryOption =', '    -- One selector shared'),r'''
local selected
local first=addCycleOption(feature,"Mode",{"Prediction","Silent AIM"},1,function(v) selected=v end)
local row=first.Parent
assert(selected=="Silent AIM" and row.Size.Y.Offset==54)
assert(row:FindFirstChild("Segment2"):GetAttribute("Selected"))
first.MouseButton1Click:Fire();assert(selected=="Prediction" and configData.values["Test.Mode"]=="Prediction" and saves==1)
first.MouseButton1Click:Fire();assert(saves==1)
for _=1,20 do row:FindFirstChild("Segment2").MouseButton1Click:Fire();first.MouseButton1Click:Fire() end
assert(#themeBindings[first]==2) -- no repeated property bindings accumulating per click
local long=addCycleOption(feature,"Long",{"A","B","C","D"},1,function(v) selected=v end)
long.MouseButton1Click:Fire();assert(dropdowns==1 and selected=="C")
local reads=0
local panel=state.addTelemetryOption(feature,"Live status",function()
 reads+=1;return {raw=.5,estimate=.45,status="Spike",spike=true,jitter=.12,frameSeconds=1/30,renderSeconds=1/40,history={180,500},weapon="Shoot: sent"}
end)
local built=allocations
for _=1,100 do heartbeat:Fire(.01) end
assert(reads>=3 and reads<=4 and allocations==built)
assert(string.find(panel:FindFirstChild("NetworkState").Text,"40 FPS",1,true))
container.Visible=false;local before=reads
for _=1,100 do heartbeat:Fire(.01) end
assert(reads==before)
container.Visible=true;screen.Enabled=false;heartbeat:Fire(.3);assert(reads==before)
screen.Enabled=true;heartbeat:Fire(.3);assert(reads==before+1)
panel:Destroy();heartbeat:Fire(.3);local after=reads;heartbeat:Fire(1);assert(reads==after)
pass("actual segmented widgets: restore/click/persistence, long-choice fallback, bounded theme bindings; 4Hz HUD allocates nothing on updates and stops when hidden/destroyed")
end
print("v21 regression groups passed:",passed)
'''])


def main():
    with tempfile.TemporaryDirectory(prefix='mm2-v21-') as folder:
        p=Path(folder)/'test.luau';p.write_text(build())
        subprocess.run([os.environ.get('LUAU','luau'),str(p)],check=True)

if __name__=='__main__': main()
