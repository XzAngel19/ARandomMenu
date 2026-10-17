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
local ended,focused
local input={InputEnded={Connect=function(_,fn) ended=fn;return {Disconnect=function() ended=nil end} end},
 WindowFocusReleased={Connect=function(_,fn) focused=fn;return {Disconnect=function() focused=nil end} end}}
Enum.KeyCode={Space='Space',ButtonA='ButtonA'};Enum.UserInputType={Touch='Touch',Keyboard='Keyboard'}
local function release(touch) ended({KeyCode=touch and 'Unknown' or 'Space',UserInputType=touch and 'Touch' or 'Keyboard'}) end
Module.init({host={LocalPlayer=LocalPlayer,UserInputService=input,RunService=run},framework=framework,services={movementInput=movement}})
jump.Options['Infinite jump']:Set(true);jump.Options['Infinite jump mode']:Set('Fall');jump:Toggle(true)
h.FloorMaterial='Ground';root.AssemblyLinearVelocity=Vector3.new(3,0,4)
inputRequest();assert(h.current=='Running' and root.AssemblyLinearVelocity.Y==0 and h:GetStateEnabled('Jumping'),'first ground press is left to Roblox, not a synthetic Fall')
h:ChangeState('Jumping');h.FloorMaterial='Air';root.AssemblyLinearVelocity=Vector3.new(3,50,4);loop()
assert(h.current=='Jumping' and h:GetStateEnabled('Jumping'),'ordinary first jump keeps its normal state/animation')
root.AssemblyLinearVelocity=Vector3.new(3,-5,4)
for _=1,60 do now+=.02;inputRequest();loop() end
assert(root.AssemblyLinearVelocity.Y==-5 and h.current=='Jumping','holding Space must not create extra jumps')
release();inputRequest();assert(h.current=='Freefall' and root.AssemblyLinearVelocity.Y==50 and not h:GetStateEnabled('Jumping'))
assert(root.AssemblyLinearVelocity.X==3 and root.AssemblyLinearVelocity.Z==4)
local changes=h.changes;root.AssemblyLinearVelocity=Vector3.new(3,-9,4)
for _=1,60 do now+=.02;inputRequest();loop() end
assert(h.changes==changes and root.AssemblyLinearVelocity.Y==-9,'no state/animation or impulse spam while held')
h:ForceState('Jumping');assert(h.current=='Freefall','forced Jumping is corrected only after an extra Fall jump')
jump.Options['Jump interval']:Set(.05);now+=.06;release(true);inputRequest();assert(root.AssemblyLinearVelocity.Y==50,'touch release rearms one jump at configured interval')
input.TouchEnabled=true
local jumpFinger={UserInputType='Touch',Position=Vector3.new(100,100,0)}
input.GetTouches=function() return {jumpFinger} end
release();now+=1;inputRequest();root.AssemblyLinearVelocity=Vector3.new(3,-9,4)
ended({UserInputType='Touch'});now+=1;inputRequest();assert(root.AssemblyLinearVelocity.Y==-9,'unrelated finger release must not rearm a held jump')
ended(jumpFinger);inputRequest();assert(root.AssemblyLinearVelocity.Y==50)
input.TouchEnabled=false
h.FloorMaterial='Ground';h:ChangeState('Landed');loop()
assert(h:GetStateEnabled('Jumping') and not h.listener,'landing restores native ground jumps')
release();h:ChangeState('Running');root.AssemblyLinearVelocity=Vector3.new(3,0,4);inputRequest();assert(root.AssemblyLinearVelocity.Y==0)
h.FloorMaterial='Air';h:ChangeState('Jumping');release();now+=1;inputRequest();assert(h.current=='Freefall')
for _,state in ipairs({'Seated','Swimming','Climbing','Physics','PlatformStanding','Ragdoll','FallingDown'}) do
 h:ForceState(state);assert(h:GetStateEnabled('Jumping') and not h.listener)
 release();now+=1;root.AssemblyLinearVelocity=Vector3.new(3,-5,4);inputRequest();loop()
 assert(root.AssemblyLinearVelocity.Y==-5 and h.current==state,'no boost in incompatible states')
 h:ForceState('Freefall');release();now+=1;inputRequest();assert(not h:GetStateEnabled('Jumping'))
end
root.Anchored=true;loop();assert(h:GetStateEnabled('Jumping'));release();now+=1;inputRequest();assert(root.AssemblyLinearVelocity.Y==50)
root.Anchored=false;jump.Options['Infinite jump mode']:Set('Normal');assert(h:GetStateEnabled('Jumping') and not h.listener)
release();now+=1;inputRequest();assert(h.current=='Jumping')
jump.Options['Infinite jump mode']:Set('Rise');held=true;loop();assert(h.current=='Freefall' and root.AssemblyLinearVelocity.Y==75)
held=false;root.AssemblyLinearVelocity=Vector3.new(3,-5,4);loop();assert(root.AssemblyLinearVelocity.Y==-5)
h:SetStateEnabled('Jumping',false);h:SetStateEnabled('Freefall',false)
jump.Options['Infinite jump mode']:Set('Fall');release();now+=1;inputRequest();assert(h:GetStateEnabled('Freefall'))
jump.Options['Infinite jump']:Set(false);assert(not h:GetStateEnabled('Freefall') and not h:GetStateEnabled('Jumping'),'restore initially false flags')
h:SetStateEnabled('Jumping',true);h:SetStateEnabled('Freefall',true);jump.Options['Infinite jump']:Set(true)
release();now+=1;inputRequest();local old=h;h=humanoid();loop();assert(old:GetStateEnabled('Jumping') and not old.listener and h:GetStateEnabled('Jumping'),'new character starts with ordinary native jumps')
Module.destroy();assert(not jump.Enabled and not loop and not inputRequest and not ended and not focused)
local nativeRequest
input.JumpRequest={Connect=function(_,fn) nativeRequest=fn;return {Disconnect=function() nativeRequest=nil end} end}
Module.init({host={LocalPlayer=LocalPlayer,UserInputService=input,RunService=run},framework=framework,services={}})
jump.Options['Infinite jump']:Set(true);jump.Options['Infinite jump mode']:Set('Fall');jump:Toggle(true)
assert(nativeRequest);nativeRequest();assert(h.current=='Freefall' and root.AssemblyLinearVelocity.Y==50)
Module.destroy();assert(not nativeRequest and not loop and not ended and h:GetStateEnabled('Jumping'))
print('PASS Jump actual source: native first ground jump, one boost per release/press, upward Freefall, no animation/state spam, landing, PC/touch, Normal/Rise, incompatible states, respawn and exact flag cleanup')
'''
assert 'LoadAnimation' not in SOURCE and ':Play(' not in SOURCE
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'jump.luau';p.write_text(script);subprocess.run([os.environ.get('LUAU','luau'),str(p)],check=True)
