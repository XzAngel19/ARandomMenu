#!/usr/bin/env python3
"""Execute v19 UI, migration, animation and cadence source with service mocks."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
sys.dont_write_bytecode = True
from test_mm2_precision import PRELUDE, section
R = Path(__file__).resolve().parents[1]
BASE = (R/'src/games/MM2/base.lua').read_text()
SHOOT = (R/'src/games/MM2/Blatant/Shoot.lua').read_text()
KNIFE = (R/'src/games/MM2/Blatant/KnifeThrow.lua').read_text()
WIDGETS = (R/'src/guis/Wurst/Code/Widgets.lua').read_text()
LOADER = (R/'src/Wurst.lua').read_text()

def build():
    return '\n'.join([PRELUDE, section(BASE,'local predictionMath = {}','type MotionSample'),r'''
do
local configData={values={},states={}}
local writes=0
local function queueConfigSave() writes+=1 end
local function migrate()
''',section(LOADER,'-- v19 separates','local function findExistingGui()'),r'''
end
for _,target in ipairs({"Manual","Custom"}) do
 for _,silent in ipairs({false,true}) do
    writes=0
    configData={values={["MM2.Shoot.Mode"]=target,["MM2.Shoot.Targetplayer"]="kept",["MM2.AutoShoot.Mode"]="Silent"},states={["MM2.Shoot.SilentAIM"]=silent}}
    migrate();migrate()
    assert(writes==1)
    assert(configData.values["MM2.Shoot.Mode"]==(silent and "Silent AIM" or "Prediction"))
    assert(configData.values["MM2.Shoot.Target"]==(target=="Custom" and "Custom" or "Murder"))
    assert(configData.values["MM2.Shoot.Targetplayer"]=="kept")
    assert(configData.values["MM2.AutoShoot.Mode"]=="Silent AIM")
 end
end
configData={values={["MM2.Shoot.Mode"]="Prediction",["MM2.Shoot.Target"]="Custom"},states={["MM2.Shoot.SilentAIM"]=true}}
migrate();assert(configData.values["MM2.Shoot.Mode"]=="Prediction" and configData.values["MM2.Shoot.Target"]=="Custom")
pass("old Mode/SilentAIM migration preserves target text, new preferences and Auto Mode; idempotent")
end

do
local settings={shootMode="Murder",silentAim=false,shootWallCheck=true,silentSweep=.5,silentSpawn="Through",gunLeadBias=0,motionSampleHz=60,gunMotionModel="Classic 66d",gunTimingModel="RTT"}
local state={mm2Core={mm2Settings=settings,predictionMath=predictionMath,resetAutoLeadCorrection=function() end}}
local featureConnections={}
local cards,callbacks,choices={},{},{}
local saved={["Shoot.Mode"]="Silent AIM",["Shoot.Target"]="Custom"}
local function createUniversalFeature(name,_,_,callback)
 local card={name=name,optionRows={},updateExpandedSize=function() end}
 cards[name]=card;return card
end
local function row(card,label)
 local r={Name="Option_"..label:gsub("%W",""),Visible=true,LayoutOrder=#card.optionRows+1}
 table.insert(card.optionRows,r);return r
end
local function addCycleOption(card,label,values,index,callback)
 row(card,label);callbacks[card.name.."."..label]=callback;choices[card.name.."."..label]=values
 callback(saved[card.name.."."..label] or values[index])
end
local function addToggleOption(card,label,default,callback) row(card,label);callbacks[card.name.."."..label]=callback;callback(default) end
local function addNumberOption(card,label,default,lo,hi,callback) row(card,label);callback(default) end
local function addTextOption(card,label,default,callback) row(card,label);callbacks[card.name.."."..label]=callback;callback(default) end
local function addActionOption(card,label,callback) row(card,label) end
local Module=(function()
''',SHOOT,r'''
end)()
Module.init({})
local card=cards.Shoot
local function visible(label)
 for _,r in ipairs(card.optionRows) do if r.Name=="Option_"..label:gsub("%W","") then return r.Visible end end
 error("missing "..label)
end
assert(choices["Shoot.Mode"][1]=="Prediction" and choices["Shoot.Mode"][2]=="Silent AIM")
assert(choices["Shoot.Target"][1]=="Murder" and choices["Shoot.Target"][2]=="Custom")
assert(card.optionRows[1].Name=="Option_Mode" and card.optionRows[2].Name=="Option_Target")
callbacks["Shoot.Advanced"](true)
assert(visible("Silent sweep") and not visible("Motion model") and visible("Target player"))
callbacks["Shoot.Target player"]("kept")
callbacks["Shoot.Advanced"](true)
for _,mode in ipairs({"Prediction","Silent AIM"}) do
 for _,target in ipairs({"Murder","Custom"}) do
    callbacks["Shoot.Mode"](mode);callbacks["Shoot.Target"](target)
    assert(visible("Silent spawn")== (mode=="Silent AIM"))
    assert(visible("Spawn A/B status")== (mode=="Silent AIM"))
    assert(visible("Motion model")== (mode=="Prediction"))
    assert(visible("Auto tune lead")== (mode=="Prediction"))
    assert(visible("WallCheck")== (mode=="Prediction"))
    assert(visible("Target player")== (target=="Custom"))
    assert(visible("Mode") and visible("Target") and visible("Shoot status"))
    assert(settings.shootTarget=="kept")
 end
end
assert(callbacks["Shoot.SilentAIM"]==nil)
callbacks["Auto Shoot.Mode"]("Silent AIM") -- native internal naming remains tested by v17/v18
pass("actual full Shoot UI restores modes; all four Mode/Target combinations; only matching rows visible")
end

do
local state={}
local game={PlaceId=142823291}
local callback,modeCount
local stored="Game learning"
local destroyedSelectors=0
local function addCycleOption(feature,label,values,index,fn)
 modeCount+=1;callback=fn
 local r={Name="Mode",Visible=true,Destroy=function() destroyedSelectors+=1 end}
 table.insert(feature.optionRows,r)
 fn(table.find(values,stored) and stored or values[index])
 return {Parent=r}
end
''',section(WIDGETS,'    state.beginMetricsPanel =','    local function addKeyOption('),r'''
for _,order in ipairs({{"Calibration","Game learning","Projectiles"},{"Projectiles","Calibration","Game learning"},{"Game learning","Projectiles","Calibration"}}) do
 local feature={optionRows={},updateExpandedSize=function() end};modeCount=0
 for _,name in ipairs(order) do
    local finish=state.beginMetricsPanel(feature,name)
    table.insert(feature.optionRows,{Name=name,Visible=true})
    finish()
 end
 assert(modeCount==1 and #feature.optionRows==4)
 for _,selected in ipairs(order) do
    callback(selected)
    for i,r in ipairs(feature.optionRows) do assert(r.Visible==(i==1 or r.Name==selected)) end
 end
end
game.PlaceId=636649648;stored="Calibration";modeCount=0
local late={optionRows={},updateExpandedSize=function() end}
local finish=state.beginMetricsPanel(late,"Game learning")
table.insert(late.optionRows,{Name="Game learning",Visible=true});finish()
state.activeGameName="MM2"
finish=state.beginMetricsPanel(late,"Calibration")
table.insert(late.optionRows,{Name="Calibration",Visible=true});finish()
assert(modeCount==2 and destroyedSelectors==1 and #late.optionRows==3)
assert(late.metricsPanels.selected=="Calibration")
assert(not late.metricsPanels.groups["Game learning"][1].Visible)
assert(late.metricsPanels.groups.Calibration[1].Visible)
pass("actual Metrics panel helper: one selector, restored selection, producer order and late structural MM2 detection")
end

do
local children,guiChildren={},{}
local char={GetAttribute=function() return nil end,GetChildren=function() return children end,FindFirstChild=function() return nil end}
local gui={GetChildren=function() return guiChildren end}
local LocalPlayer={Character=char,GetAttribute=function() return nil end,FindFirstChild=function() return nil end,FindFirstChildOfClass=function() return gui end}
local CollectionService={HasTag=function(_,obj,tag) return obj.tag==tag end}
local mm2RoundData={}
local function playerFromRoundKey() return LocalPlayer end
''',section(BASE,'local function getPlayerPerk(','local function registerMM2Roles('),r'''
assert(getPlayerPerk(LocalPlayer)==nil)
children={{Name="Sleight",tag="Perk"}};assert(getPlayerPerk(LocalPlayer)=="Sleight")
children={};guiChildren={{Name="Sleight",tag="Perk"}};assert(getPlayerPerk(LocalPlayer)=="Sleight")
guiChildren={};mm2RoundData={{Perk="Haste"}};assert(getPlayerPerk(LocalPlayer)=="Haste")
local d,s=predictionMath.knifeCadence("Auto",1,nil,false);near(d,.5)
d=predictionMath.knifeCadence("Auto",1,nil,true);near(d,.25)
d=predictionMath.knifeCadence("Auto",1,.4,true);near(d,.4) -- do not halve an already adjusted attribute
for _,bad in ipairs({0,-1,0/0,math.huge,"0.1"}) do near(predictionMath.knifeCadence("Auto",1,bad,true),.25) end
near(predictionMath.knifeCadence("Manual",1,.2,true),1)
pass("actual perk detection in character/PlayerGui; safe cadence fallbacks and attribute/manual precedence")
end

do
local knifeThrowSettings={enabled=false,mode="Normal",cadence="Auto",fireDelay=1,range=120,throwHz=60}
local perk=nil
local LocalPlayer={}
local core={getPlayerPerk=function(p) assert(p==LocalPlayer);return perk end}
''',section(KNIFE,'    local function getThrowCadence(','    local throwTrack:'),r'''
local lastThrow=-math.huge
local lastPrediction={}
local setWeaponStatus=function() end
local root={Position=Vector3.new(30,0,0)}
local target={Name="target",Character={FindFirstChild=function() return root end}}
LocalPlayer.Character={FindFirstChild=function() return {Position=Vector3.zero} end}
local sends,notes=0,{}
local cooldown=nil
local remote={IsA=function() return true end,FireServer=function() sends+=1 end}
local knife={Name="Knife",GetAttribute=function() return cooldown end,FindFirstChild=function() return {FindFirstChild=function() return remote end} end}
local function getPlayerWeapon() return knife end
local function getReadyKnife() return knife end
local function findNearestTarget() return target end
local function predictAim() return root.Position end
local function isWeaponPathClear() return true end
local trajectoryCalibration={noteAuthoredShot=function(_,info) table.insert(notes,info) end}
local function playThrowAnimation() error("cosmetic unavailable") end
local function stopThrowAnimation() end
local callbacks={}
local featureConnections={}
local TaskManager={Connect=function(_,cb) callbacks[1]=cb;return {Connected=true,Disconnect=function() callbacks[1]=nil end} end}
local function disconnectFeatureConnection(key) if featureConnections[key] then featureConnections[key]:Disconnect();featureConnections[key]=nil end end
local knifeControl={register=function() end}
''',section(KNIFE,'    local function throwKnife():','    local KnifeThrowFeature:'),r'''
for _,hz in ipairs({30,60,120}) do
 for _,fast in ipairs({false,true}) do
    perk=fast and "Sleight" or nil;now=0;sends=0;notes={}
    knifeThrowSettings.throwHz=hz;toggleKnifeThrow(true)
    for i=1,1200 do now=i/120;callbacks[1](1/120) end
    assert(sends>=(fast and 35 or 18) and sends<=(fast and 40 or 20))
    near(notes[1].settings.fireDelay,fast and .25 or .5)
    assert(notes[1].settings.sleight==fast)
    local before=sends;now+=5;callbacks[1](5);assert(sends==before+1)
    toggleKnifeThrow(false);assert(callbacks[1]==nil)
 end
end
pass("actual Throw scheduler: normal/Sleight at 30/60/120Hz; one request after stall; cosmetic errors cannot block send")
end

do
Enum.AnimationPriority={Action="Action"}
local knifeThrowSettings={animation=true}
local timers={}
local task={delay=function(t,fn) table.insert(timers,fn) end}
local function signal()
 local s={}
 function s:Connect(fn) self.fn=fn;return {Disconnect=function() self.fn=nil end} end
 return s
end
local tracks,playing={},{}
local animator={GetPlayingAnimationTracks=function() return playing end,LoadAnimation=function(_,anim)
 local t={Animation=anim,Length=1,IsPlaying=false,stops=0,plays=0,destroyed=false}
 function t:Play(_,_,speed) self.IsPlaying=true;self.plays+=1;self.speed=speed end
 function t:Stop() self.stops+=1;self.IsPlaying=false end
 function t:Destroy() self.destroyed=true end
 table.insert(tracks,t);return t
end}
local humanoid={RigType="R15",Died=signal(),FindFirstChildOfClass=function() return animator end}
local LocalPlayer={Character={FindFirstChildOfClass=function() return humanoid end}}
local function anim(name,id) return {Name=name,AnimationId=id,IsA=function() return true end} end
local release=anim("ThrowRelease","r15")
local scans=0
local knife={Parent=LocalPlayer.Character,Unequipped=signal(),DescendantAdded=signal(),GetDescendants=function()
 scans+=1;return {anim("ThrowCharge","charge"),anim("ThrowIdle","idle"),anim("ThrowR6","r6"),release}
end}
''',section(KNIFE,'    local throwTrack:','    local function throwKnife():'),r'''
playThrowAnimation(knife,.25,true)
assert(#tracks==1 and tracks[1].Animation==release and tracks[1].speed>=2)
playThrowAnimation(knife,.25,true);assert(#tracks==1 and scans==1)
local t=tracks[1];local stops=t.stops
timers[1]();assert(t.stops==stops) -- old callback must not interrupt newer release
timers[2]();assert(t.stops==stops+1)
local native={Animation=release,IsPlaying=true}
playing={native};playThrowAnimation(knife,.25,true)
assert(t.plays==2 and native.IsPlaying)
playing={};playThrowAnimation(knife,.5,false)
knife.Unequipped.fn();assert(t.destroyed and throwTrack==nil)
local stopped=t.stops;timers[#timers]();assert(t.stops==stopped)
playThrowAnimation(knife,.5,false);humanoid.Died.fn();assert(tracks[2].destroyed)
knifeThrowSettings.animation=false;playThrowAnimation(knife,.5,false);assert(#tracks==2)
pass("actual animation: release/rig selection, cache, stale-timer cancellation, native de-dup, unequip/death/OFF cleanup")
end
do
local game={PlaceId=636649648}
local state={}
''',section((R/'src/games/universal/Other/GameLearning.lua').read_text(),'    local function isMM2():','    local gameBridge:'),r'''
assert(not isMM2())
state.activeGameName="MM2";assert(isMM2())
state.activeGameName=nil;state.mm2Core={};assert(isMM2())
state.mm2Core=nil;game.PlaceId=142823291;assert(isMM2())
pass("actual learning detector follows MM2 structural loading, not only the main PlaceId")
end
print("v19 regression groups passed:",passed)
'''])

def main():
    with tempfile.TemporaryDirectory(prefix='mm2-v19-') as folder:
        p=Path(folder)/'test.luau';p.write_text(build())
        subprocess.run([os.environ.get('LUAU','luau'),str(p)],check=True)

if __name__=='__main__':main()
