#!/usr/bin/env python3
"""Execute on-foot Speed: all modes, seated safety, ownership and teardown."""
import os
import subprocess
import tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE
ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT/'src/games/universal/Movement/Speed.lua').read_text()
script = PRELUDE + r'''
Enum.HumanoidStateType={Running='Running',Jumping='Jumping',Climbing='Climbing',Swimming='Swimming',Physics='Physics',PlatformStanding='PlatformStanding'}
local paramCount=0
local RaycastParams={new=function() paramCount+=1;return {} end}
local cfMt={__add=function(a,v) return CFrame.new(a.Position+v) end}
CFrame.new=function(p) return setmetatable({Position=p or Vector3.zero,LookVector=Vector3.new(0,0,-1)},cfMt) end
local function signal()
 local s={listeners={}}
 function s:Connect(fn)
  self.listeners[fn]=true
  return {Disconnect=function() self.listeners[fn]=nil end}
 end
 function s:Fire(...) for fn in pairs(self.listeners) do fn(...) end end
 function s:Count() local n=0;for _ in pairs(self.listeners) do n+=1 end;return n end
 return s
end
local function newHumanoid()
 local h=setmetatable({Parent=true,Health=100,_walk=16,writes=0,MoveDirection=Vector3.new(1,0,0),FloorMaterial='Air',state='Running',Sit=false,changes=0},{
  __index=function(self,key) if key=='WalkSpeed' then return self._walk end end,
  __newindex=function(self,key,value) if key=='WalkSpeed' then self._walk=value;self.writes+=1 else rawset(self,key,value) end end})
 function h:GetState() return self.state end
 function h:ChangeState(s) self.state=s;self.changes+=1 end
 return h
end
local h=newHumanoid()
local root={Parent=true,Anchored=false,CollisionGroup='Default',Size=Vector3.new(2,2,1),Position=Vector3.zero,CFrame=CFrame.new(),AssemblyMass=2,AssemblyLinearVelocity=Vector3.new(2,5,3)}
function root:ApplyImpulse(v) self.AssemblyLinearVelocity+=v/self.AssemblyMass end
local character={FindFirstChildOfClass=function() return h end,FindFirstChild=function() return root end}
local player={Character=character}
local fly={Enabled=false}
local blockDistance,casts,lastParams=nil,0,nil
local world={Blockcast=function(_,cf,size,delta,params)
 lastParams=params;casts+=1;assert(params.RespectCanCollide and params.CollisionGroup==root.CollisionGroup and params.FilterDescendantsInstances[1]==character)
 return blockDistance and {Distance=blockDistance} or nil
end}
local run={PreSimulation=signal()}
local module,handler
local function option(self,d)
 local o={Value=d.List and d.List[d.Index or 1] or d.Default,definition=d}
 function o:Set(v) self.Value=v;if d.Function then d.Function(v) end end
 self.Options[d.Name]=o;return o
end
local framework={Categories={Exploits={CreateModule=function(_,d)
 handler=d.Function;module={Options={},Enabled=false,cleanups={}}
 module.CreateDropdown=option;module.CreateSlider=option;module.CreateToggle=option
 function module:SetStatus() end
 function module:RefreshVisibility() end
 function module:Clean(item) table.insert(self.cleanups,item) end
 function module:Toggle(v)
  self.Enabled=v
  if not v then for _,item in ipairs(self.cleanups) do if type(item)=='function' then item() else item:Disconnect() end end;table.clear(self.cleanups) end
  handler(v)
 end
 return module
end}},GetModule=function(_,name) return name=='Fly' and fly or nil end}
local function tick(dt) run.PreSimulation:Fire(dt or 1/60) end
local function set(name,value) module.Options[name]:Set(value) end
''' + '\nlocal Module=(function()\n' + SOURCE + '\nend)()\n' + r'''
Module.init({host={LocalPlayer=player,workspace=world,RunService=run},framework=framework})
assert(module.Options.Mode.Value=='Velocity', 'new configurations start in Velocity mode')
module:Toggle(true);tick();near(h.WalkSpeed,16);near(root.AssemblyLinearVelocity.X,32)
assert(run.PreSimulation:Count()==1)
set('Mode','WalkSpeed');tick();near(h.WalkSpeed,32)
for _,value in ipairs({1000,5000,1e12}) do set('Speed',value);tick();near(h.WalkSpeed,value) end
set('Speed',32);tick();near(h.WalkSpeed,32)
local walkWrites=h.writes
for _=1,120 do tick() end
assert(h.writes==walkWrites,'unchanged WalkSpeed should not be written every physics frame')
module:Toggle(false);near(h.WalkSpeed,16);assert(run.PreSimulation:Count()==0)
module:Toggle(true);tick();h.WalkSpeed=24;tick();near(h.WalkSpeed,32);module:Toggle(false);near(h.WalkSpeed,24)
h.WalkSpeed=16;module:Toggle(true);tick();h.WalkSpeed=70;module:Toggle(false);near(h.WalkSpeed,70)
h.WalkSpeed=16;module:Toggle(true);tick();local old=h;h=newHumanoid();h.WalkSpeed=22;tick();near(old.WalkSpeed,16)
module:Toggle(false);near(h.WalkSpeed,22);h.WalkSpeed=16
module:Toggle(true);set('Mode','Velocity');h.MoveDirection=Vector3.new(.5,0,0);tick();near(root.AssemblyLinearVelocity.X,16);near(root.AssemblyLinearVelocity.Y,5)
h.MoveDirection=Vector3.zero;tick();near(root.AssemblyLinearVelocity.Magnitude,5)
set('Mode','Impulse');h.MoveDirection=Vector3.new(.25,0,0);tick();near(root.AssemblyLinearVelocity.X,8);near(root.AssemblyLinearVelocity.Y,5)
h.MoveDirection=Vector3.zero;tick();near(root.AssemblyLinearVelocity.X,0)
set('Mode','CFrame');h.MoveDirection=Vector3.new(1,0,0);root.CFrame=CFrame.new();tick(.1);near(root.CFrame.Position.X,1.6)
root.CFrame=CFrame.new();tick(50);near(root.CFrame.Position.X,1.6)
blockDistance=.3;root.CFrame=CFrame.new();tick(.1);near(root.CFrame.Position.X,.2);blockDistance=nil
for _=1,120 do tick(1/60) end
assert(paramCount==1, 'wall checks reuse one RaycastParams')
character={FindFirstChildOfClass=function() return h end,FindFirstChild=function() return root end}
player.Character=character;root.CollisionGroup='NewGroup';tick()
assert(paramCount==1 and lastParams.FilterDescendantsInstances[1]==character and lastParams.CollisionGroup=='NewGroup',
    'respawn and collision-group changes refresh the existing parameters')
set('Mode','Teleport');root.CFrame=CFrame.new();tick(.1);near(root.CFrame.Position.X,0);tick(.1);near(root.CFrame.Position.X,3.2)
h.MoveDirection=Vector3.zero;tick(.1);h.MoveDirection=Vector3.new(1,0,0);tick(.1);near(root.CFrame.Position.X,3.2)
tick(.1);near(root.CFrame.Position.X,6.4)
set('Mode','WalkSpeed');tick();near(h.WalkSpeed,32)
set('Speed',-32);h.MoveDirection=Vector3.new(1,0,0);tick();near(h.WalkSpeed,-32);near(root.AssemblyLinearVelocity.X,-32)
set('Mode','CFrame');root.CFrame=CFrame.new();tick(.1);near(root.CFrame.Position.X,-4.8)
set('Mode','WalkSpeed');set('Speed',32);tick();near(h.WalkSpeed,32)
for _,state in ipairs({'Climbing','Swimming','Physics','PlatformStanding'}) do h.state=state;tick();near(h.WalkSpeed,16) end
h.state='Running';root.Anchored=true;tick();near(h.WalkSpeed,16);root.Anchored=false;fly.Enabled=true;tick();near(h.WalkSpeed,16);fly.Enabled=false
module:Toggle(false);assert(#lastParams.FilterDescendantsInstances==0, 'OFF releases the cached character filter')
set('Auto jump',true);h.FloorMaterial='Ground';local changes=h.changes
module.SetSprintHeld(true);near(h.WalkSpeed,30);assert(h.changes==changes,'Sprint OFF must not activate Auto jump')
module.SetSprintHeld(false);near(h.WalkSpeed,16);set('Auto jump',false)
pass('foot: all five modes, analog input, zero-input braking, Y preserved, wall volume, hitch/burst timing, external WalkSpeed, respawn, Fly/state skips and Sprint OFF')
assert(not module.Options['Vehicle speed'] and not module.Options['Vehicle mode']
    and not module.Options['Vehicle multiplier'] and not module.Options['Vehicle speed value']
    and not module.Options['Motor torque'], 'all vehicle controls must be removed')
local seat={MaxSpeed=40,Torque=10}
module:Toggle(true);set('Mode','WalkSpeed');tick();near(h.WalkSpeed,32)
local initialVelocity=root.AssemblyLinearVelocity
h.Sit=true;h.SeatPart=seat
for _,mode in ipairs({'WalkSpeed','Velocity','Impulse','CFrame','Teleport'}) do
 set('Mode',mode);tick();near(h.WalkSpeed,16)
 assert(seat.MaxSpeed==40 and seat.Torque==10 and root.AssemblyLinearVelocity==initialVelocity,
    'seated Speed must not alter the seat or character velocity')
end
h.SeatPart=nil;h.Sit=false;set('Mode','WalkSpeed');tick();near(h.WalkSpeed,32)
Module.destroy();near(h.WalkSpeed,16);assert(run.PreSimulation:Count()==0)
pass('vehicle controls removed; on-foot Speed stays inactive while seated and resumes on exit')
'''
with tempfile.TemporaryDirectory(prefix='speed-') as d:
    path=Path(d)/'speed.luau';path.write_text(script)
    subprocess.run([os.environ.get('LUAU','luau'),str(path)],check=True)
