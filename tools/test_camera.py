#!/usr/bin/env python3
"""Actual camera modules: touch/keyboard input, ownership, reload and restoration (not a live Roblox test)."""
import os, subprocess, tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE
ROOT=Path(__file__).resolve().parents[1]
def module(path):
 return '(function()\n'+(ROOT/path).read_text()+'\nend)()'
script=PRELUDE+r'''
Vector3.yAxis=Vector3.new(0,1,0)
local Vector2={new=function(x,y) return Vector3.new(x,y,0) end,zero=Vector3.zero}
local cf={}
local function frame(p,pitch,yaw) return setmetatable({Position=p,pitch=pitch or 0,yaw=yaw or 0},cf) end
local function rotate(a,v)
 local c,s,cy,sy=math.cos(a.pitch),math.sin(a.pitch),math.cos(a.yaw),math.sin(a.yaw)
 return Vector3.new(cy*v.X+sy*s*v.Y+sy*c*v.Z,c*v.Y-s*v.Z,-sy*v.X+cy*s*v.Y+cy*c*v.Z)
end
cf.__index=function(a,k)
 if k=='LookVector' then return rotate(a,Vector3.new(0,0,-1)) end
 if k=='VectorToWorldSpace' then return rotate end
end
cf.__mul=function(a,b) return frame(a.Position+rotate(a,b.Position),a.pitch+b.pitch,a.yaw+b.yaw) end
CFrame.new=function(x,y,z) return frame(type(x)=='table' and x or Vector3.new(x,y,z)) end
CFrame.fromOrientation=function(p,y) return frame(Vector3.zero,p,y) end
local Enum=setmetatable({}, {__index=function(t,k)
 local e=setmetatable({}, {__index=function(s,n) local v=n
  if n=='Camera' or n=='High' then v={Value=200} end
  rawset(s,n,v);return v end});t[k]=e;return e end})
local UDim2={new=function(xs,xo,ys,yo) return {X={Scale=xs,Offset=xo},Y={Scale=ys,Offset=yo}} end}
function UDim2.fromOffset(x,y) return UDim2.new(0,x,0,y) end
function UDim2.fromScale(x,y) return UDim2.new(x,0,y,0) end
local Color3={new=function() return {} end,fromRGB=function() return {} end}
local signals={}
local function signal()
 local s={listeners={}};table.insert(signals,s)
 function s:Connect(fn) local c={fn=fn,Connected=true};table.insert(self.listeners,c);function c:Disconnect() self.Connected=false end;return c end
 function s:Fire(...) for _,c in ipairs(self.listeners) do if c.Connected then c.fn(...) end end end
 return s
end
local function object(class,props)
 local o=props or {};o.ClassName=class;o.children={};o.Name=o.Name or class
 o.AbsolutePosition=Vector2.zero;o.AbsoluteSize=Vector2.new(104,104)
 function o:FindFirstChild(n) for _,c in ipairs(self.children) do if c.Name==n and not c.destroyed then return c end end end
 function o:FindFirstChildOfClass(n) for _,c in ipairs(self.children) do if c.ClassName==n and not c.destroyed then return c end end end
 function o:Destroy() self.destroyed=true;for _,c in ipairs(self.children) do c:Destroy() end end
 for _,n in ipairs({'InputBegan','InputChanged','InputEnded','WindowFocusReleased','TextBoxFocused','TouchStarted','TouchMoved','TouchEnded','Activated'}) do o[n]=signal() end
 if o.Parent then table.insert(o.Parent.children,o) end
 return o
end
local queued={}
local task={spawn=function(fn) table.insert(queued,fn) end}
local function flush() while #queued>0 do table.remove(queued,1)() end end
local require=function(source) if source.fail then error('restricted') end;return source.exports end
local bindings,steps={},{}
local actions={}
function actions:BindActionAtPriority(name,callback) bindings[name]=callback end
function actions:UnbindAction(name) bindings[name]=nil end
local run={}
function run:BindToRenderStep(name,priority,fn) steps[name]=fn end
function run:UnbindFromRenderStep(name) steps[name]=nil end
local game={GetService=function(_,n) assert(n=='ContextActionService');return actions end}
local function step(dt) now+=dt;for _,fn in pairs(steps) do fn(dt) end end
local function action(name,state,key)
 for n,fn in pairs(bindings) do if string.sub(n,-#name)==name then return fn(n,state,{KeyCode=key or name}) end end
 error('missing action '..name)
end
local player=object('Player')
local scripts=object('PlayerScripts',{Parent=player})
local pg=object('PlayerGui',{Parent=player})
local nativeTouch=object('ScreenGui',{Name='TouchGui',Enabled=true,Parent=pg})
local controls={controlsEnabled=true,Disable=function(self) self.controlsEnabled=false end,Enable=function(self) self.controlsEnabled=true end}
local occlusion={enabled=true,Enable=function(self,v) self.enabled=v end,GetEnabled=function(self) return self.enabled end}
local originalUpdate=function(_,_,frame,focus) return frame,focus,'occluded' end
occlusion.Update=originalUpdate
local cameras={activeOcclusionModule=occlusion}
local source=object('ModuleScript',{Name='PlayerModule',Parent=scripts,exports={GetControls=function() return controls end,GetCameras=function() return cameras end}})
local camera={CameraType='Custom',CFrame=CFrame.new(0,6,0),Focus=CFrame.new(0,6,-16),CameraSubject='subject',FieldOfView=80,ViewportSize=Vector2.new(800,600)}
local world={CurrentCamera=camera}
local character=object('Model');player.Character=character
local humanoid=object('Humanoid',{Parent=character,Move=function(self,v) self.move=v end})
local input=object('UserInputService',{TouchEnabled=true,MouseBehavior='Default',MouseIconEnabled=true})
function input:GetFocusedTextBox() return self.focused end
function input:IsKeyDown(key) return self.shift and key=='LeftShift' end
local host={Players={GetPlayers=function() return {player} end},LocalPlayer=player,UserInputService=input,RunService=run,workspace=world,services={},ScreenGui=object('ScreenGui'),create=object}
local card
local framework={Categories={Visuals={CreateModule=function(_,metadata)
 card={Options={},Enabled=false,cleaners={},Feature={enabled=false},SetStatus=function(self,v) self.status=v end}
 function card:Clean(fn) table.insert(self.cleaners,fn) end
 function card:CreateSlider(def) self.Options[def.Name]={Value=def.Default} end
 function card:CreateList(def) self.Options[def.Name]={Selected={},Set=function() end,IsSelected=function(self,name) return table.find(self.Selected,name)~=nil end} end
 function card:Toggle(v)
  if self.Enabled==v then return end
  self.Enabled=v;self.Feature.enabled=v
  if not v then for _,fn in ipairs(self.cleaners) do fn() end;table.clear(self.cleaners) end
  metadata.Function(v)
 end
 card.Feature.activate=function() card:Toggle(not card.Enabled) end
 return card
end}}}
'''+ '\nlocal CameraAccess='+module('src/libraries/CameraAccess.lua')+'\nlocal access=CameraAccess.init(host)\nlocal FreeCam='+module('src/games/universal/Render/FreeCam.lua')+r'''
local free=FreeCam.init({host=host,services=host.services,framework=framework})
local spectateRoot={Position=Vector3.new(100,20,30)}
local spectateHumanoid={Health=100}
local spectator={Name='Target',Character={FindFirstChild=function() return spectateRoot end,FindFirstChildOfClass=function() return spectateHumanoid end}}
host.Players.GetPlayers=function() return {player,spectator} end
local initialFrame,initialFocus=camera.CFrame,camera.Focus
free:Toggle(true);step(.02);assert(humanoid.move.Magnitude==0 and not nativeTouch.Enabled)
flush();step(.02);assert(not controls.controlsEnabled and camera.CameraType=='Scriptable')
assert(camera.CameraSubject=='subject' and camera.FieldOfView==80)
free.Options['Spectate Player'].Selected={'Target'};step(.02);near((camera.CFrame.Position-spectateRoot.Position).Magnitude,math.sqrt(153))
free.Options['Spectate Player'].Selected={};
action('Forward','Begin','W');local start=camera.CFrame.Position;step(.05);near((camera.CFrame.Position-start).Magnitude,2.4)
action('Right','Begin','D');start=camera.CFrame.Position;step(.05);near((camera.CFrame.Position-start).Magnitude,2.4)
action('Forward','End','W');action('Right','End','D')
action('Up','Begin','E');action('Up','Begin','Space');action('Up','End','E');start=camera.CFrame.Position;step(.05);near(camera.CFrame.Position.Y-start.Y,2.4)
action('Up','End','Space');input.shift=true;action('Forward','Begin','W');start=camera.CFrame.Position;step(.05);near((camera.CFrame.Position-start).Magnitude,7.2)
input.WindowFocusReleased:Fire();input.shift=false;start=camera.CFrame.Position;step(.05);near((camera.CFrame.Position-start).Magnitude,0)
local gui=host.ScreenGui:FindFirstChild('FreeCamControls');local pad=gui:FindFirstChild('Move')
local finger={UserInputType='Touch',Position=Vector3.new(52,52,0),Delta=Vector3.zero}
pad.InputBegan:Fire(finger);finger.Position=Vector3.new(52,10,0);input.TouchMoved:Fire(finger)
local look={UserInputType='Touch',Position=Vector3.new(500,250,0),Delta=Vector3.new(20,10,0)}
input.TouchStarted:Fire(look,false);input.TouchMoved:Fire(look);start=camera.CFrame.Position;step(.05)
near((camera.CFrame.Position-start).Magnitude,2.4);assert(math.abs(camera.CFrame.LookVector.X)>.01)
input.TouchEnded:Fire(finger);input.TouchEnded:Fire(look);start=camera.CFrame.Position;step(.05);near((camera.CFrame.Position-start).Magnitude,0)
local up=gui:FindFirstChild('Up');up.InputBegan:Fire(finger);input.TouchEnded:Fire(finger);start=camera.CFrame.Position;step(.05);near((camera.CFrame.Position-start).Magnitude,0)
input.InputBegan:Fire({UserInputType='MouseButton2'},false);assert(input.MouseBehavior=='LockCurrentPosition' and not input.MouseIconEnabled)
input.TextBoxFocused:Fire();assert(input.MouseBehavior=='Default' and input.MouseIconEnabled)
input.focused={};assert(action('Forward','Begin','W')=='Pass');start=camera.CFrame.Position;step(.05);near((camera.CFrame.Position-start).Magnitude,0);input.focused=nil
local replacement={CameraType='Custom',CFrame=CFrame.new(100,0,0),Focus=CFrame.new(100,0,-16),CameraSubject='respawn',FieldOfView=90,ViewportSize=Vector2.new(800,600)}
world.CurrentCamera=replacement;step(.02);assert(camera.CameraType=='Custom' and camera.CFrame==initialFrame and camera.Focus==initialFocus)
assert(replacement.CameraType=='Scriptable' and replacement.CameraSubject=='respawn' and replacement.FieldOfView==90)
player.Character=object('Model');step(.02)
world.CurrentCamera=nil;step(.02);assert(replacement.CameraType=='Custom');world.CurrentCamera=replacement;step(.02)
gui:FindFirstChild('Exit').Activated:Fire();assert(not free.Enabled and gui.destroyed and controls.controlsEnabled and nativeTouch.Enabled)
assert(not next(bindings) and not next(steps));assert(replacement.CameraType=='Custom')
for _,s in ipairs(signals) do for _,c in ipairs(s.listeners) do assert(not c.Connected,'input leak') end end
controls.controlsEnabled=false;nativeTouch.Enabled=false
for _=1,3 do free:Toggle(true);step(.02);free:Toggle(false) end
assert(not controls.controlsEnabled and not nativeTouch.Enabled,'must not enable previously disabled controls')
assert(access:ThroughWalls(true));local f,focus=access:GetCameras().activeOcclusionModule:Update(.02,initialFrame,initialFocus)
assert(f==initialFrame and focus==initialFocus and occlusion.Update~=originalUpdate and not occlusion.enabled)
assert(not access:ThroughWalls(false));assert(occlusion.Update==originalUpdate and occlusion.enabled)
access:ThroughWalls(true);local other={enabled=false,Update=originalUpdate,GetEnabled=occlusion.GetEnabled,Enable=occlusion.Enable};cameras.activeOcclusionModule=other
assert(access:ThroughWalls(true));assert(occlusion.Update==originalUpdate and occlusion.enabled)
local foreign=function() end;other.Update=foreign;assert(not access:ThroughWalls(true));access:ThroughWalls(false);assert(other.Update==foreign)
cameras.activeOcclusionModule=nil;assert(not access:ThroughWalls(true))
local nativeClass={Update=originalUpdate}
local cameraModule=object('ModuleScript',{Name='CameraModule',Parent=source})
object('ModuleScript',{Name='Poppercam',Parent=cameraModule,exports=nativeClass})
source.exports.GetCameras=function() return {} end
access.playerModule=nil;now+=1;access:GetCameras();flush()
assert(access:ThroughWalls(true),'modern public GetCameras returns {}: must patch the native class instead')
local nativeInstance=setmetatable({focusExtrapolator={Reset=function(self) self.reset=true end}},{__index=nativeClass})
local nf,nfocus=nativeInstance:Update(.02,initialFrame,initialFocus)
assert(nf==initialFrame and nfocus==initialFocus and nativeInstance.focusExtrapolator.reset)
access:ThroughWalls(false);assert(nativeClass.Update==originalUpdate)
access.poppercam=nil
free:Toggle(true);step(.02)
local externalFrame=CFrame.new(7,8,9);replacement.CameraType='Track';replacement.CFrame=externalFrame
free:Toggle(false);assert(replacement.CameraType=='Track' and replacement.CFrame==externalFrame,'must not overwrite a later camera owner')
source.exports.GetCameras=function() return cameras end;cameras.activeOcclusionModule=occlusion
host.featureConnections={}
host.disconnectFeatureConnection=function(name) local c=host.featureConnections[name];if c then c:Disconnect();host.featureConnections[name]=nil end end
host.TaskManager={Connect=function(_,fn) return {fn=fn,Disconnect=function(self) self.disconnected=true end} end}
local zoom,options
host.createUniversalFeature=function(_,_,_,callback)
 options={};zoom={enabled=false,SetStatus=function(self,v) self.status=v end}
 function zoom:Toggle(v) self.enabled=v;callback(v) end
 return zoom
end
host.addNumberOption=function(_,name,_,_,_,callback) options[name]=callback end
host.addToggleOption=function(_,name,_,callback) options[name]=callback end
player.CameraMinZoomDistance,player.CameraMaxZoomDistance,player.CameraMode=60,128,'LockFirstPerson'
local Zoom='''+module('src/games/universal/Render/ZoomUnlocker.lua')+r''' 
Zoom.init({host=host,services=host.services})
zoom:Toggle(true);assert(player.CameraMinZoomDistance==.5 and player.CameraMaxZoomDistance==400 and player.CameraMode=='Classic')
options['Through walls'](true);assert(occlusion.Update~=originalUpdate)
options['Maximum distance'](25);options['Minimum distance'](50)
assert(player.CameraMinZoomDistance==25 and player.CameraMaxZoomDistance==50)
local tick=host.featureConnections.ZoomUnlocker;tick.fn();zoom:Toggle(false)
assert(tick.disconnected and occlusion.Update==originalUpdate and player.CameraMinZoomDistance==60 and player.CameraMaxZoomDistance==128 and player.CameraMode=='LockFirstPerson')
zoom:Toggle(true);options['Through walls'](true);Zoom.destroy();assert(occlusion.Update==originalUpdate and player.CameraMinZoomDistance==60)
source.fail=true;source.exports=nil;access.playerModule=nil;now+=1;assert(access:GetControls()==nil);flush();assert(access:GetControls()==nil)
FreeCam.destroy();CameraAccess.destroy();assert(access.destroyed)
pass('FreeCam real source: PC, diagonal speed, overlapping holds, touch move/look/up/release, focus loss, camera replacement/respawn, exact cleanup; Zoom occlusion identity and unavailable fallback')
'''
with tempfile.TemporaryDirectory() as t:
 p=Path(t)/'camera.luau';p.write_text(script);subprocess.run([os.environ.get('LUAU','luau'),str(p)],check=True)
