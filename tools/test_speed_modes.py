#!/usr/bin/env python3
"""Execute whole Speed source: native movement, driver-only engines, ownership and teardown."""
import os
import subprocess
import tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE
ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT/'src/games/universal/Movement/Speed.lua').read_text()
script = PRELUDE + r'''
Enum.ActuatorType={Motor='Motor',Servo='Servo'}
Enum.HumanoidStateType={Running='Running',Jumping='Jumping',Climbing='Climbing',Swimming='Swimming',Physics='Physics',PlatformStanding='PlatformStanding'}
local RaycastParams={new=function() return {} end}
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
 local h={Parent=true,Health=100,WalkSpeed=16,MoveDirection=Vector3.new(1,0,0),FloorMaterial='Air',state='Running',Sit=false,changes=0}
 function h:GetState() return self.state end
 function h:ChangeState(s) self.state=s;self.changes+=1 end
 return h
end
local h=newHumanoid()
local root={Parent=true,Anchored=false,CollisionGroup='Default',Size=Vector3.new(2,2,1),Position=Vector3.zero,CFrame=CFrame.new(),AssemblyMass=2,AssemblyLinearVelocity=Vector3.new(2,5,3)}
function root:ApplyImpulse(v) self.AssemblyLinearVelocity+=v/self.AssemblyMass end
local character={FindFirstChildOfClass=function() return h end,FindFirstChild=function() return root end}
local fly={Enabled=false}
local blockDistance,casts=nil,0
local world={Blockcast=function(_,cf,size,delta,params)
 casts+=1;assert(params.RespectCanCollide and params.CollisionGroup=='Default' and params.FilterDescendantsInstances[1]==character)
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
Module.init({host={LocalPlayer={Character=character},workspace=world,RunService=run},framework=framework})
module:Toggle(true);tick();near(h.WalkSpeed,32);assert(run.PreSimulation:Count()==1)
for _=1,120 do tick() end;module:Toggle(false);near(h.WalkSpeed,16);assert(run.PreSimulation:Count()==0)
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
set('Mode','Teleport');root.CFrame=CFrame.new();tick(.1);near(root.CFrame.Position.X,0);tick(.1);near(root.CFrame.Position.X,3.2)
h.MoveDirection=Vector3.zero;tick(.1);h.MoveDirection=Vector3.new(1,0,0);tick(.1);near(root.CFrame.Position.X,3.2)
tick(.1);near(root.CFrame.Position.X,6.4)
set('Mode','WalkSpeed');tick();near(h.WalkSpeed,32)
for _,state in ipairs({'Climbing','Swimming','Physics','PlatformStanding'}) do h.state=state;tick();near(h.WalkSpeed,16) end
h.state='Running';root.Anchored=true;tick();near(h.WalkSpeed,16);root.Anchored=false;fly.Enabled=true;tick();near(h.WalkSpeed,16);fly.Enabled=false
module:Toggle(false);set('Auto jump',true);h.FloorMaterial='Ground';local changes=h.changes
module.SetSprintHeld(true);near(h.WalkSpeed,30);assert(h.changes==changes,'Sprint OFF must not activate Auto jump')
module.SetSprintHeld(false);near(h.WalkSpeed,16);set('Auto jump',false)
pass('foot: all five modes, analog input, zero-input braking, Y preserved, wall volume, hitch/burst timing, external WalkSpeed, respawn, Fly/state skips and Sprint OFF')
local model={Parent=true,motors={},DescendantAdded=signal(),FindFirstAncestorOfClass=function() return nil end}
function model:GetDescendants() return self.motors end
local chassis={Parent=model,Anchored=false,AssemblyLinearVelocity=Vector3.new(4,7,8),IsDescendantOf=function(_,obj) return obj==model end}
local seat={Parent=model,AssemblyRootPart=chassis,Occupant=h,MaxSpeed=40,Torque=10,ThrottleFloat=1,CFrame=CFrame.new(),
 IsA=function(_,class) return class=='VehicleSeat' end,FindFirstAncestorOfClass=function() return model end}
h.Sit=true;h.SeatPart=seat;set('Vehicle speed',true);module:Toggle(true);tick();near(seat.MaxSpeed,80);near(seat.Torque,20);near(h.WalkSpeed,16)
for _=1,120 do tick() end;near(seat.MaxSpeed,80);near(seat.Torque,20)
seat.MaxSpeed=30;seat.Torque=15;tick();near(seat.MaxSpeed,60);near(seat.Torque,30)
set('Vehicle mode','Seat');near(seat.MaxSpeed,30);near(seat.Torque,15);tick();near(seat.MaxSpeed,80)
seat.Occupant={};tick();near(seat.MaxSpeed,30);seat.Occupant=h
set('Vehicle mode','Velocity');seat.ThrottleFloat=-.5;tick();near(chassis.AssemblyLinearVelocity.Z,40);near(chassis.AssemblyLinearVelocity.Y,7)
for _=1,120 do tick() end;near(chassis.AssemblyLinearVelocity.Z,40)
seat.ThrottleFloat=0;tick();near(chassis.AssemblyLinearVelocity.Z,40)
seat.IsA=function() return false end;chassis.AssemblyLinearVelocity=Vector3.new(3,7,4);tick();near(chassis.AssemblyLinearVelocity.X,3);near(chassis.AssemblyLinearVelocity.Z,4)
seat.IsA=function(_,class) return class=='VehicleSeat' end
local function motor(value)
 return {Parent=model,ActuatorType='Motor',AngularVelocity=value,MotorMaxTorque=500,
 IsA=function(_,class) return class=='HingeConstraint' end,IsDescendantOf=function(self,obj) return self.Parent==obj end}
end
local wheel=motor(10);table.insert(model.motors,wheel)
set('Vehicle mode','Motors');seat.ThrottleFloat=1;tick();near(wheel.AngularVelocity,20);near(wheel.MotorMaxTorque,50000);assert(model.DescendantAdded:Count()==1)
for _=1,120 do tick() end;near(wheel.AngularVelocity,20)
wheel.AngularVelocity=-12;seat.ThrottleFloat=-1;tick();near(wheel.AngularVelocity,-24)
seat.ThrottleFloat=0;tick();near(wheel.AngularVelocity,0)
set('Vehicle mode','Seat');near(wheel.AngularVelocity,0);near(wheel.MotorMaxTorque,500);assert(model.DescendantAdded:Count()==0)
wheel.AngularVelocity=13;seat.ThrottleFloat=0;set('Vehicle mode','Motors');tick();near(wheel.AngularVelocity,0)
set('Vehicle mode','Seat');near(wheel.AngularVelocity,0)
wheel.AngularVelocity=10;seat.ThrottleFloat=1;set('Vehicle mode','Motors');tick()
local newWheel=motor(6);model.DescendantAdded:Fire(newWheel);tick();near(newWheel.AngularVelocity,12)
newWheel.Parent={};tick();near(newWheel.AngularVelocity,6);near(newWheel.MotorMaxTorque,500)
set('Vehicle speed',false);near(wheel.AngularVelocity,10);near(wheel.MotorMaxTorque,500);assert(model.DescendantAdded:Count()==0)
set('Vehicle speed',true);set('Vehicle mode','Multiplier');tick();near(seat.MaxSpeed,60)
chassis.Anchored=true;tick();near(seat.MaxSpeed,30);chassis.Anchored=false;tick();near(seat.MaxSpeed,60)
h.SeatPart=nil;h.Sit=false;tick();near(seat.MaxSpeed,30);near(seat.Torque,15)
Module.destroy();near(h.WalkSpeed,16);assert(run.PreSimulation:Count()==0 and model.DescendantAdded:Count()==0)
pass('vehicles: driver/passenger discrimination, four modes, no exponential boost, external engine updates, reverse/coast, motor discovery/removal, zero-throttle restoration, anchored/exit/disable/destroy cleanup')
'''
with tempfile.TemporaryDirectory(prefix='speed-') as d:
    path=Path(d)/'speed.luau';path.write_text(script)
    subprocess.run([os.environ.get('LUAU','luau'),str(path)],check=True)
