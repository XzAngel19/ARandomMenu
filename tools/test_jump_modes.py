#!/usr/bin/env python3
"""Whole Jump Settings: High jump button, Long jump button, Auto jump, Custom jump power."""
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
local root={AssemblyLinearVelocity=Vector3.new(3,20,4),AssemblyMass=2, Anchored=false, CFrame=CFrame.new()}
function root:ApplyImpulse(v) self.AssemblyLinearVelocity += v/self.AssemblyMass end
local character={FindFirstChildOfClass=function() return h end,FindFirstChild=function() return root end}
local LocalPlayer={Character=character}
local held,loop,handler,jump
local movement={onJumpRequest=function(fn) return {Disconnect=function() end} end,isJumpHeld=function() return held end}
local run={PreSimulation={Connect=function(_,fn) loop=fn;return {Disconnect=function() loop=nil end} end}}
local function option(self,d)
 local o={Value=d.List and d.List[d.Index or 1] or d.Default,definition=d}
 function o:Set(v) self.Value=v;if d.Function then d.Function(v) end end
 self.Options[d.Name]=o;return o
end
local framework={Categories={Exploits={CreateModule=function(_,d)
 handler=d.Function;jump={Options={},Enabled=false,cleanups={}}
 jump.CreateToggle=option;jump.CreateSlider=option;jump.CreateDropdown=option;jump.CreateButton=option
 jump.CreateNote=function() end
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
Module.init({host={LocalPlayer=LocalPlayer,UserInputService=input,RunService=run},framework=framework,services={movementInput=movement}})
-- v197: Jump Settings must not have Infinite jump (moved to Infinite Jump module)
assert(not jump.Options['Infinite jump'] and not jump.Options['Jump interval'], 'Jump Settings must not have Infinite jump or Jump interval (moved to Infinite Jump module)')
assert(jump.Options['Custom jump power'] and jump.Options['Jump power'] and jump.Options['High jump'] and jump.Options['High jump velocity'], 'Jump Settings must have Custom jump power, Jump power, High jump')
assert(jump.Options['Auto jump'] and jump.Options['Long jump'] and jump.Options['Long jump mode'] and jump.Options['Long jump speed'], 'Jump Settings must have Auto jump, Long jump button and its mode/speed')
-- Test High jump button
jump:Toggle(true)
h.FloorMaterial='Ground';h.current='Running';root.AssemblyLinearVelocity=Vector3.new(3,0,4)
jump.Options['High jump velocity'].Value=72
-- Find High jump button function via definition
local highJumpBtn = nil
for _,opt in pairs(jump.Options) do if opt.definition and opt.definition.Name=='High jump' then highJumpBtn=opt.definition.Function end end
assert(highJumpBtn, 'High jump button must exist')
highJumpBtn()
assert(root.AssemblyLinearVelocity.Y==72 and h.current=='Freefall', 'High jump must apply vertical velocity 72')
-- Test Long jump button (like High jump)
local longJumpBtn = nil
for _,opt in pairs(jump.Options) do if opt.definition and opt.definition.Name=='Long jump' then longJumpBtn=opt.definition.Function end end
assert(longJumpBtn, 'Long jump button must exist (like High jump)')
h.FloorMaterial='Ground';h.MoveDirection=Vector3.new(1,0,0);root.AssemblyLinearVelocity=Vector3.new(0,0,0);root.CFrame=CFrame.new()
jump.Options['Long jump speed'].Value=50
jump.Options['Long jump mode'].Value='Velocity'
longJumpBtn()
assert(root.AssemblyLinearVelocity.X==50 and root.AssemblyLinearVelocity.Y==0, 'Long jump Velocity must apply horizontal speed 50, preserve Y')
-- Test Impulse mode
jump.Options['Long jump mode'].Value='Impulse';root.AssemblyLinearVelocity=Vector3.new(0,0,0)
longJumpBtn()
assert(root.AssemblyLinearVelocity.X > 40, 'Long jump Impulse must apply impulse')
-- Test CFrame mode (lenient: just ensure no error and CFrame still valid)
jump.Options['Long jump mode'].Value='CFrame';root.CFrame=CFrame.new(Vector3.new(0,0,0));h.MoveDirection=Vector3.new(1,0,0)
local ok, err = pcall(longJumpBtn)
assert(ok, 'Long jump CFrame must not error: '..tostring(err))
assert(root.CFrame and root.CFrame.Position, 'CFrame must exist after Long jump')
-- Test Auto jump
h.FloorMaterial='Ground';h.MoveDirection=Vector3.new(1,0,0);jump.Options['Auto jump'].Value=true;loop()
assert(h.current=='Jumping' or h.current=='Freefall', 'Auto jump must trigger jump when moving on ground')
-- Test Custom jump power
jump.Options['Custom jump power'].Value=true;jump.Options['Jump power'].Value=100;h.FloorMaterial='Ground';loop()
assert(h.JumpPower==100 and h.UseJumpPower==true, 'Custom jump power must set JumpPower 100')
jump.Options['Custom jump power'].Value=false;loop()
-- On disable, should restore
Module.destroy();assert(not jump.Enabled)
print('PASS Jump Settings: no Infinite jump (moved), High jump button, Long jump button with Velocity/Impulse/CFrame, Auto jump, Custom jump power')
'''
assert 'Infinite jump' not in SOURCE and 'Jump interval' not in SOURCE
# Ensure no infinite jump strings in Jump.lua (except comments) - check via SOURCE
with tempfile.TemporaryDirectory() as d:
 p2=Path(d)/'jump.luau';p2.write_text(script);subprocess.run([os.environ.get('LUAU','luau'),str(p2)],check=True)
