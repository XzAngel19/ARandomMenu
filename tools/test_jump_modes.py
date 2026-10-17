#!/usr/bin/env python3
"""Whole Jump: real state enablement/Freefall impulses, no animation overrides, PC/touch and cleanup."""
import os,subprocess,tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE
ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'src/games/universal/Movement/Jump.lua').read_text()
script=PRELUDE+r'''
Enum.Material={Air='Air',Ground='Ground'}
Enum.HumanoidStateType={Jumping='Jumping',Freefall='Freefall',Running='Running',Landed='Landed',Seated='Seated',Swimming='Swimming',Climbing='Climbing',Physics='Physics',PlatformStanding='PlatformStanding',Ragdoll='Ragdoll',FallingDown='FallingDown',Dead='Dead'}
local function humanoid()
 local h={Parent=true,Health=100,JumpPower=50,UseJumpPower=true,Jump=false,MoveDirection=Vector3.new(1,0,0),FloorMaterial='Air',current='Running',states={Jumping=true,Freefall=true},changes=0}
 function h:GetStateEnabled(s) return self.states[s]~=false end
 function h:SetStateEnabled(s,v) self.states[s]=v end
 function h:GetState() return self.current end
 function h:ForceState(s)
  if s==self.current then return end
  self.changes+=1;local old=self.current;self.current=s
  if self.listener then self.listener(old,s) end
 end
 function h:ChangeState(s) if self:GetStateEnabled(s) then self:ForceState(s) end end
 h.StateChanged={Connect=function(_,fn) h.listener=fn;return {Disconnect=function() h.listener=nil end} end}
 function h:FindFirstChildOfClass() error('no Animator manipulation is allowed') end
 return h
end
local h=humanoid()
local root={AssemblyLinearVelocity=Vector3.new(3,20,4),AssemblyMass=2}
local character={FindFirstChildOfClass=function() return h end,FindFirstChild=function() return root end}
local LocalPlayer={Character=character}
local inputRequest,held,loop,handler,jump
local movement={onJumpRequest=function(fn) inputRequest=fn;return {Disconnect=function() inputRequest=nil end} end,isJumpHeld=function() return held end}
local run={PreSimulation={Connect=function(_,fn) loop=fn;return {Disconnect=function() loop=nil end} end}}
local function option(self,d)
 local o={Value=d.List and d.List[d.Index or 1] or d.Default,definition=d}
 function o:Set(v) self.Value=v;if d.Function then d.Function(v) end end
 self.Options[d.Name]=o;return o
end
local framework={Categories={Exploits={CreateModule=function(_,d)
 handler=d.Function;jump={Options={},Enabled=false,cleanups={}}
 jump.CreateToggle=option;jump.CreateSlider=option;jump.CreateDropdown=option;jump.CreateButton=option
 function jump:SetStatus() end
 function jump:Clean(fn) table.insert(self.cleanups,fn) end
 function jump:Toggle(v)
  self.Enabled=v
  if not v then for _,item in ipairs(self.cleanups) do if type(item)=='function' then item() else item:Disconnect() end end;table.clear(self.cleanups) end
  handler(v)
 end
 return jump
end}}}
'''+'\nlocal Module=(function()\n'+SOURCE+'\nend)()\n'+r'''
Module.init({host={LocalPlayer=LocalPlayer,UserInputService={TouchEnabled=true,KeyboardEnabled=false},RunService=run},framework=framework,services={movementInput=movement}})
jump.Options['Infinite jump']:Set(true);jump:Toggle(true)
inputRequest();assert(h.current=='Jumping' and root.AssemblyLinearVelocity.Y==50)
now+=1;jump.Options['Infinite jump mode']:Set('Fall')
assert(not h:GetStateEnabled('Jumping') and h:GetStateEnabled('Freefall') and h.current=='Freefall','state lock must apply immediately, not on the next animation/frame')
root.AssemblyLinearVelocity=Vector3.new(3,20,4);inputRequest()
assert(h.current=='Freefall' and root.AssemblyLinearVelocity.Y==50)
assert(root.AssemblyLinearVelocity.X==3 and root.AssemblyLinearVelocity.Z==4)
local changes=h.changes
for _=1,60 do loop() end
assert(h.changes==changes,'do not spam ChangeState when already in Freefall')
h:ChangeState('Landed');assert(h.current=='Landed','Fall does not force the standing/walking state into midair')
h.Jump=true;h:ChangeState('Jumping');loop();assert(h.current=='Landed' and not h.Jump,'native Jumping is disabled, not merely hidden by a fall clip')
now+=1;inputRequest();assert(h.current=='Freefall' and root.AssemblyLinearVelocity.Y==50)
h:ForceState('Jumping');assert(h.current=='Freefall','redirect a forced Jumping transition without an animation workaround')
jump.Options['Jump interval']:Set(.05);now+=.06;root.AssemblyLinearVelocity=Vector3.new(3,-5,4);inputRequest();assert(root.AssemblyLinearVelocity.Y==50,'mobile respects configured interval')
for _,state in ipairs({'Seated','Swimming','Climbing','Physics','PlatformStanding','Ragdoll','FallingDown'}) do
 h:ForceState(state);assert(h:GetStateEnabled('Jumping') and not h.listener,'release state ownership in incompatible states')
 now+=1;root.AssemblyLinearVelocity=Vector3.new(3,-5,4);inputRequest();loop()
 assert(root.AssemblyLinearVelocity.Y==-5 and h.current==state,'no airborne impulse or forced Fall while seated/swimming/ragdolled')
 h:ForceState('Running');loop();assert(not h:GetStateEnabled('Jumping'))
end
root.Anchored=true;loop();assert(h:GetStateEnabled('Jumping'))
now+=1;inputRequest();assert(root.AssemblyLinearVelocity.Y==-5)
root.Anchored=false;loop();assert(not h:GetStateEnabled('Jumping'))
jump.Options['Infinite jump mode']:Set('Normal');assert(h:GetStateEnabled('Jumping') and not h.listener)
now+=1;inputRequest();assert(h.current=='Jumping')
jump.Options['Infinite jump mode']:Set('Rise');held=true;loop();assert(h.current=='Freefall' and root.AssemblyLinearVelocity.Y==75)
held=false;root.AssemblyLinearVelocity=Vector3.new(3,-5,4);loop();assert(root.AssemblyLinearVelocity.Y==-5)
h:SetStateEnabled('Jumping',false);h:SetStateEnabled('Freefall',false)
jump.Options['Infinite jump mode']:Set('Fall');assert(h:GetStateEnabled('Freefall') and not h:GetStateEnabled('Jumping'))
jump.Options['Infinite jump']:Set(false);assert(not h:GetStateEnabled('Freefall') and not h:GetStateEnabled('Jumping'),'restore initially disabled states too')
h:SetStateEnabled('Jumping',true);h:SetStateEnabled('Freefall',true);jump.Options['Infinite jump']:Set(true)
local old=h;h=humanoid();loop();assert(old:GetStateEnabled('Jumping') and not old.listener and not h:GetStateEnabled('Jumping'))
Module.destroy();assert(not jump.Enabled and not loop and not inputRequest and not h.listener and h:GetStateEnabled('Jumping'))
local nativeRequest
Module.init({host={LocalPlayer=LocalPlayer,UserInputService={JumpRequest={Connect=function(_,fn) nativeRequest=fn;return {Disconnect=function() nativeRequest=nil end} end}},RunService=run},framework=framework,services={}})
jump.Options['Infinite jump']:Set(true);jump.Options['Infinite jump mode']:Set('Fall');jump:Toggle(true)
assert(nativeRequest);nativeRequest();assert(h.current=='Freefall' and root.AssemblyLinearVelocity.Y==50)
Module.destroy();assert(not nativeRequest and not loop and h:GetStateEnabled('Jumping'))
print('PASS Jump actual source: state lock before physics, positive-Y Freefall, no animation spam, landing, force-state correction, touch timing, Normal/Rise, respawn and exact flag restoration')
'''
assert 'LoadAnimation' not in SOURCE and ':Play(' not in SOURCE
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'jump.luau';p.write_text(script);subprocess.run([os.environ.get('LUAU','luau'),str(p)],check=True)
