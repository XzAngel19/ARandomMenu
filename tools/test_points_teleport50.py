#!/usr/bin/env python3
"""Actual Markers + Teleport integration and timed/cancellable Glide. No live Roblox."""
import os, subprocess, tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE
ROOT=Path(__file__).resolve().parents[1]
def module(path): return '(function()\n'+(ROOT/path).read_text()+'\nend)()'
script=PRELUDE+r'''
local Vector2={new=function(x,y) return {X=x,Y=y} end}
local Color3={fromRGB=function() return {} end}
local game={PlaceId=50}
Enum.UserInputType={Touch='Touch',MouseButton1='MouseButton1'};Enum.KeyCode={Escape='Escape'}
local RaycastParams={new=function() return {} end}
local cf={__add=function(a,v) return setmetatable({Position=a.Position+v,rotation=a.rotation},cf) end}
-- Define after the local declaration so the closure uses its metatable.
cf.__add=function(a,v) return setmetatable({Position=a.Position+v,rotation=a.rotation},cf) end
CFrame.new=function(p) return setmetatable({Position=p or Vector3.zero,rotation='original'},cf) end
local function signal()
 local s={listeners={}}
 function s:Connect(fn) local c={Connected=true,fn=fn};table.insert(self.listeners,c);function c:Disconnect() self.Connected=false end;return c end
 function s:Fire(...) for _,c in ipairs(table.clone(self.listeners)) do if c.Connected then c.fn(...) end end end
 function s:Count() local n=0;for _,c in ipairs(self.listeners) do if c.Connected then n+=1 end end;return n end
 return s
end
local input={InputBegan=signal(),GetFocusedTextBox=function() return nil end}
local heartbeat=signal()
local h={Health=100,HipHeight=2}
local rootProps={Parent=true,Position=Vector3.new(10,30,20),CFrame=CFrame.new(Vector3.new(10,30,20)),AssemblyLinearVelocity=Vector3.zero}
local root=setmetatable({}, {__index=rootProps,__newindex=function(_,k,v) rootProps[k]=v;if k=='CFrame' then rootProps.Position=v.Position end end})
local character={FindFirstChild=function(_,name) return name=='HumanoidRootPart' and root or nil end,FindFirstChildOfClass=function() return h end}
local player={Character=character}
local menuVisible=true
local flags={}
local services={menu={isVisible=function() return menuVisible end,setVisible=function(v) menuVisible=v end,isCapturingInput=function() return false end},
 activity={set=function(k,v) flags[k]=v end,isActive=function(k) return flags[k] end}}
local world={CurrentCamera={CFrame={Position=Vector3.new(999,999,999)},ScreenPointToRay=function() return {Origin=Vector3.zero,Direction=Vector3.new(0,0,1)} end},Raycast=function() return {Position=Vector3.new(7,8,9)} end}
local host={LocalPlayer=player,UserInputService=input,RunService={Heartbeat=heartbeat},workspace=world,configData={values={},states={}},queueConfigSave=function() end}
local cards={}
local function createCard(_,d)
 local c={Options={},definition=d,cleanups={},notifications={}}
 local function option(self,o)
  local value=o.List and o.List[o.Index or 1] or o.Default
  local field={Value=value,definition=o}
  function field:Set(v) self.Value=v;if o.Function then o.Function(v) end end
  self.Options[o.Name]=field
  if o.Function and value~=nil then o.Function(value) end
  return field
 end
 c.CreateSlider=option;c.CreateDropdown=option;c.CreateToggle=option;c.CreateTextBox=option;c.CreateButton=option;c.CreateColor=option
 function c:CreateList(o)
  local field={selected={},definition=o}
  for _,n in ipairs(o.Default or {}) do field.selected[n]=true end
  local function publish()
   local names={};for n in pairs(field.selected) do table.insert(names,n) end;table.sort(names)
   if o.Function then o.Function(field.selected,names) end
  end
  function field:Set(n,on) if o.Single and on then table.clear(self.selected) end;self.selected[n]=on or nil;publish() end
  function field:Refresh() self.names=o.Items();publish() end
  function field:IsSelected(n) return self.selected[n]==true end
  self.Options[o.Name]=field;field:Refresh();return field
 end
 function c:SetStatus(s) self.status=s end
 function c:Notify(s) table.insert(self.notifications,s) end
 function c:RefreshVisibility() end
 function c:Clean(fn) table.insert(self.cleanups,fn) end
 function c:Render(fn) self.render=fn end
 function c:Toggle(v) self.Enabled=v;d.Function(v) end
 cards[d.Name]=c;return c
end
local framework={Categories={Render={CreateModule=createCard},Utilities={CreateModule=createCard}}}
local render={Layer=function() return {} end,ReleaseAll=function() end,Release=function() end}
local context={host=host,services=services,framework=framework,render=render}
'''+ '\nlocal Markers='+module('src/games/universal/Render/Markers.lua')+'\nlocal Teleport='+module('src/games/universal/Movement/ClickTeleport.lua')+r'''
local markers=Markers.init(context)
local teleport=Teleport.init(context)
local function press(c,n) c.Options[n].definition.Function() end
assert(not markers.Options.Places and not markers.Options['Remove named place'] and not teleport.Options['Save waypoint'])
press(markers,'Save here')
local p,surface=services.points.Get('Point 1');near((p-root.Position).Magnitude,0);assert(not surface)
assert(teleport.Options.Point.names[1]=='Point 1','new markers must immediately populate Teleport')
root.CFrame=CFrame.new(Vector3.new(50,60,70));markers.Options.Name:Set('Home');press(markers,'Save here')
teleport.Options.Destination:Set('Waypoint');teleport.Options.Point:Set('Point 1',true);press(teleport,'Teleport to point')
near((root.Position-Vector3.new(10,30,20)).Magnitude,0) -- no camera coordinates or duplicate height offset
markers.Options.Name:Set('Wall');press(markers,'Touch');assert(not menuVisible)
input.InputBegan:Fire({UserInputType='MouseButton1',Position=Vector3.zero},false);assert(menuVisible)
teleport.Options.Point:Set('Wall #1',true);press(teleport,'Teleport to point')
near((root.Position-Vector3.new(7,13,9)).Magnitude,0) -- Touch surface + hip height + landing offset
markers.Options.Point.definition.OnRemove('Wall #1')
assert(not services.points.Get('Wall #1') and not next(teleport.Options.Point.selected),'delete clears Teleport selection, too')
teleport.Options.Movement:Set('Glide');teleport.Options['Glide speed']:Set(100)
for _,fps in ipairs({30,60,144}) do
 root.CFrame=CFrame.new(Vector3.zero);local runtime={}
 Teleport.travel(context,teleport,runtime,Vector3.new(100,0,0),false)
 assert(flags.teleport and heartbeat:Count()==1)
 for _=1,fps do heartbeat:Fire(1/fps) end
 near(root.Position.X,100);assert(not runtime.cancelTravel and heartbeat:Count()==0 and not flags.teleport)
 assert(root.CFrame.rotation=='original')
end
local runtime={}
root.CFrame=CFrame.new(Vector3.zero)
Teleport.travel(context,teleport,runtime,Vector3.new(1000,0,0),false);heartbeat:Fire(.05);near(root.Position.X,5)
Teleport.travel(context,teleport,runtime,Vector3.new(20,0,0),false);assert(heartbeat:Count()==1)
for _=1,20 do heartbeat:Fire(.02) end;near(root.Position.X,20);assert(heartbeat:Count()==0)
Teleport.travel(context,teleport,runtime,Vector3.new(1000,0,0),false)
teleport.Options.Movement:Set('Instant');Teleport.travel(context,teleport,runtime,Vector3.new(50,0,0),false)
assert(heartbeat:Count()==0);near(root.Position.X,50)
teleport.Options.Movement:Set('Glide');Teleport.travel(context,teleport,runtime,Vector3.new(1000,0,0),false)
player.Character={};heartbeat:Fire(.05);near(root.Position.X,50);assert(heartbeat:Count()==0)
player.Character=character
teleport.Options.Point:Set('Home',true);press(teleport,'Teleport to point');assert(heartbeat:Count()==1)
markers.Options.Point.definition.OnRemove('Home');assert(heartbeat:Count()==0,'deleting selected destination cancels its trip')
teleport.Options.Point:Set('Point 1',true);press(teleport,'Teleport to point');assert(heartbeat:Count()==1)
Teleport.destroy();assert(heartbeat:Count()==0 and not flags.teleport)
Markers.destroy();assert(input.InputBegan:Count()==0 and not services.points)
pass('actual Markers/Teleport: standing vs surface coordinates, shared live lists, inline deletion, saved-point selection, Glide at 30/60/144 FPS, orientation, replacement, Instant, respawn, removed destination and cleanup')
'''
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp)/'points.luau';p.write_text(script);subprocess.run([os.environ.get('LUAU','luau'),str(p)],check=True)
