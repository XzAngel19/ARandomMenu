#!/usr/bin/env python3
"""Whole preset module: actual targeting, predictor, animation and repeat loop."""
import os
import subprocess
import tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE
ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'src/games/MM2/Blatant/KnifeThrow.lua').read_text()
script=PRELUDE+r'''
local cf={}
CFrame.new=function(p) return setmetatable({Position=p or Vector3.zero,RightVector=Vector3.new(1,0,0),UpVector=Vector3.new(0,1,0)},cf) end
CFrame.Angles=function() return CFrame.new() end
cf.__mul=function(a,b) return CFrame.new(a.Position+b.Position) end
cf.__sub=function(a,b) return CFrame.new(a.Position-b) end
cf.__index={Lerp=function(a,b,t) return t>=1 and b or a end}
local function body(x) return {Position=Vector3.new(x,0,0),Size=Vector3.new(2,2,1),CFrame=CFrame.new(Vector3.new(x,0,0)),IsA=function(_,c) return c=='BasePart' end} end
local joint={Parent=true,C0=CFrame.new(),Transform=CFrame.new(),IsA=function(_,c) return c=='Motor6D' end}
local character={FindFirstChild=function(_,n)
 if n=='Torso' then return {FindFirstChild=function(_,j) return j=='Right Shoulder' and joint or nil end} end
 if n=='HumanoidRootPart' then return body(0) end
end}
local charAdded
local LocalPlayer={Character=character,CharacterAdded={Connect=function(_,fn) charAdded=fn;return {Disconnect=function() charAdded=nil end} end}}
local function target(x)
 local root=body(x)
 return {Character={FindFirstChild=function(_,n) return n=='HumanoidRootPart' and root or nil end},visible=true}
end
local close,far=target(20),target(300)
local Players={GetPlayers=function() return {LocalPlayer,far,close} end}
local sends,notes=0,0
local lastAim,lastTarget
local remote={IsA=function() return true end,FireServer=function(_,origin,aim) sends+=1;lastAim=aim.Position end}
local handle=body(0)
local knife={Name='Knife',Parent=character,Enabled=true,GetAttribute=function() return nil end,FindFirstChild=function(_,n)
 if n=='Handle' then return handle end
 if n=='Events' then return {FindFirstChild=function() return remote end} end
end}
local loops,featureConnections={},{}
local TaskManager={Connect=function(_,fn,phase)
 local key=phase or 'heartbeat';loops[key]=fn;return {Disconnect=function() loops[key]=nil end}
end}
-- The packet gate reads a wall clock. Simulated time only exists in the pose
-- loop's dt, so the two are tied together: one animation cycle of dt is one
-- animation cycle of clock, and the anti-spam window can be exercised.
local simulatedClock=0
os.clock=function() return simulatedClock end
local rawConnect=TaskManager.Connect
TaskManager.Connect=function(self,fn,phase)
 local callback=fn
 if phase=='render' then
  callback=function(dt) simulatedClock+=dt or 0; fn(dt) end
 end
 return rawConnect(self,callback,phase)
end
local function disconnectFeatureConnection(k)
 if featureConnections[k] then featureConnections[k]:Disconnect();featureConnections[k]=nil end
end
local state={mm2SilentAimEnabled=true,mm2SilentAimFeature={},mm2KnifeRuntime={masterEnabled=false}}
state.mm2Prediction={knifeAim=function(target)
 local root=target.Character:FindFirstChild('HumanoidRootPart')
 return root.Position,{capturedPosition=root.Position,endpoint=root.Position,velocity=Vector3.zero,
  model='kinematic-v51',leadSeconds=.1,flightSeconds=.1,sampleAge=0,samples=3,motionSource='fit'}
end}
local configData={states={},values={}}
-- The blade is probed with a swept sphere, so the scene answers for the body
-- that would be hit: the visible target's part, or a wall in front of it.
local function targetPart(owner)
  return {__instance=true,IsDescendantOf=function(_,c) return c==owner.Character end}
end
local closePart,farPart=targetPart(close),targetPart(far)
local wallPart={__instance=true,IsDescendantOf=function() return false end}
typeof=function(v) if type(v)=='table' and v.__instance then return 'Instance' end return type(v) end
local CollectionService={GetTagged=function() return {} end}
local RaycastParams={new=function() return {FilterDescendantsInstances={}} end}
local spheres=0
local workspace={Spherecast=function(_,origin,radius,delta,params)
  spheres+=1
  local aim=origin+delta
  if aim.X>=250 then
    if far.visible then return {Instance=farPart,Position=aim} end
    return {Instance=wallPart,Position=Vector3.new(150,0,0)}
  end
  if close.visible then return {Instance=closePart,Position=aim} end
  return {Instance=wallPart,Position=Vector3.new(10,0,0)}
end}
local function addInformationOption() end
state.mm2Core={findMurderer=function() return LocalPlayer end,getPlayerRole=function() return 'Innocent' end,
 getPlayerWeapon=function(_,_,held) assert(held);return knife end,isPlayerAlive=function() return true end,
 isProtectedTarget=function() return false end,getFilteredVelocity=function() return Vector3.zero end,
 getEstimatedLatency=function() return 0 end,predictionMath={finite=function(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end},
 isWeaponPathClear=function(_,_,char,_,opts)
   if opts==nil then return char==close.Character and close.visible
     or char==far.Character and far.visible end
   assert(opts.ignoreTarget)
   return char==close.Character and close.visible or char==far.Character and far.visible
 end,
 trajectoryCalibration={noteAuthoredShot=function(_,shot)
   notes+=1;lastTarget=shot.target;assert(not shot.silent and shot.settings.animation and shot.settings.wallCheck)
 end}}
local toggle
state.mm2KnifeAuraModule={CreateToggle=function(_,d) assert(d.Name=='Knife Throw' and d.Bindable);toggle=d.Function end}
local toggles={}
local function addToggleOption(_,name,_,fn,_,bindable)
  assert(bindable and name=='Knife Throw',name)
  toggles[name]=fn
  if name=='Knife Throw' then toggle=fn end
end
local function addActionOption() error('No redundant action allowed') end
local function addNumberOption() error('No numeric settings allowed') end
local function addCycleOption() error('No mode settings allowed') end
'''+'\nlocal Module=(function()\n'+SOURCE+'\nend)()\n'+r'''
Module.init({});assert(toggle)
toggle(true);loops.heartbeat();assert(loops.render and sends==0)
local render=loops.render
render(.2);loops.heartbeat();assert(loops.render==render,'do not restart windup')
close.visible=false;render(.101)
assert(sends==1 and notes==1 and lastTarget==far and lastAim.X==300,'retarget at release; no 120-stud cap inside the 400-stud blade limit')
loops.heartbeat();assert(loops.render==render,'recovery must finish instead of being interrupted by spam')
render(.26);assert(not loops.render)
loops.heartbeat();assert(loops.render and sends==1,'next cycle starts without extra Fire delay')
toggle(false);assert(not loops.render and not loops.heartbeat)
toggle(true);knife.Enabled=false;loops.heartbeat();assert(not loops.render and sends==1)
knife.Enabled=true;state.mm2SilentAimEnabled=false;state.mm2KnifeThrowRefresh()
assert(not loops.heartbeat and not loops.render and state.mm2KnifeRuntime.throwWanted,'master stops but retains selection')
state.mm2SilentAimEnabled=true;state.mm2KnifeThrowRefresh()
assert(loops.heartbeat,'master ON resumes selected Throw')
far.visible=false;loops.heartbeat();assert(not loops.render,'fully hidden targets are not selected')
close.visible=true;loops.heartbeat();assert(loops.render)
charAdded();assert(not loops.render,'respawn cancels pose and packet')
Module.destroy();assert(not loops.heartbeat and not charAdded)
print('PASS Knife preset: single toggle, actual whole module, nearest visible/retarget at 300 studs, always animation/LOS, complete recovery, repeat, readiness/master/OFF/respawn, blade probe')
'''
with tempfile.TemporaryDirectory(prefix='knife-presets-') as tmp:
    path=Path(tmp)/'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU','luau'),str(path)],check=True)
