#!/usr/bin/env python3
"""Actual Ghost controller: native walking ownership, sprint, jumping, Fly transitions and cleanup.
Does not simulate Roblox's collision solver; verifies Walk never writes the ghost's CFrame.
"""
import os, subprocess, tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE
ROOT=Path(__file__).resolve().parents[1]
script=PRELUDE+r'''
Vector3.yAxis=Vector3.new(0,1,0)
local cf={}
cf.__add=function(a,v) return CFrame.new(a.Position+v) end
CFrame.new=function(x,y,z)
 local p=type(x)=='table' and x or Vector3.new(x,y,z)
 return setmetatable({Position=p,LookVector=Vector3.new(0,0,-1),RightVector=Vector3.new(1,0,0)},cf)
end
local Enum=setmetatable({}, {__index=function(t,k) local e=setmetatable({}, {__index=function(s,n) rawset(s,n,n);return n end});t[k]=e;return e end})
local Color3={fromRGB=function() return {} end}
local function signal()
 local s={listeners={}}
 function s:Connect(fn) local c={Connected=true,fn=fn};table.insert(self.listeners,c);function c:Disconnect() self.Connected=false end;return c end
 function s:Fire(...) for _,c in ipairs(table.clone(self.listeners)) do if c.Connected then c.fn(...) end end end
 function s:Count() local n=0;for _,c in ipairs(self.listeners) do if c.Connected then n+=1 end end;return n end
 return s
end
local makeCharacter
local loads=0
local function object(class,values)
 local props=values or {};props.Name=props.Name or class
 local children={};local methods={}
 function methods:IsA(c) return c==class or c=='BasePart' and class=='Part' end
 function methods:GetChildren() return table.clone(children) end
 function methods:GetDescendants()
  local out={};for _,c in ipairs(children) do table.insert(out,c);for _,d in ipairs(c:GetDescendants()) do table.insert(out,d) end end;return out
 end
 function methods:FindFirstChild(n) for _,c in ipairs(children) do if c.Name==n and not c.destroyed then return c end end end
 function methods:FindFirstChildOfClass(n) for _,c in ipairs(children) do if c:IsA(n) and not c.destroyed then return c end end end
 function methods:FindFirstChildWhichIsA(n) return self:FindFirstChildOfClass(n) end
 function methods:Destroy() props.destroyed=true;props.Parent=nil end
 function methods:Move(v) props.MoveDirection=v end
 function methods:GetState() return props.state or 'Running' end
 function methods:PivotTo(frame) self:FindFirstChild('HumanoidRootPart').CFrame=frame end
 function methods:Clone() return makeCharacter(self:FindFirstChild('HumanoidRootPart').CFrame.Position) end
 function methods:LoadAnimation()
  loads+=1;return {Play=function(self) self.playing=true end,Stop=function(self) self.playing=false end}
 end
 local node
 node=setmetatable({}, {__index=function(_,k)
  if k=='children' then return children end
  return methods[k] or props[k]
 end,__newindex=function(_,k,v)
  props[k]=v
  if k=='CFrame' then props.Position=v.Position;props.frameWrites=(props.frameWrites or 0)+1 end
  if k=='Parent' and v and v.children then table.insert(v.children,node) end
 end})
 return node
end
makeCharacter=function(position)
 local model=object('Model',{Archivable=false})
 local root=object('Part',{Name='HumanoidRootPart',Position=position,CFrame=CFrame.new(position),AssemblyLinearVelocity=Vector3.zero,AssemblyAngularVelocity=Vector3.zero});root.Parent=model
 for _,name in ipairs({'Head','Torso'}) do local p=object('Part',{Name=name});p.Parent=model end
 local h=object('Humanoid',{Name='Humanoid',Health=100,WalkSpeed=16,MoveDirection=Vector3.new(1,0,0),FloorMaterial='Ground',RigType='R6'});h.Parent=model
 return model,h,root
end
local Instance={new=function(class) return object(class) end}
local character,h,root=makeCharacter(Vector3.new(0,20,0))
local player={Character=character}
local world=object('Workspace',{CurrentCamera={CameraSubject=h,CFrame=CFrame.new(0,20,0)},FallenPartsDestroyHeight=-500})
local pressed={};local focused=false
local input={JumpRequest=signal(),GetFocusedTextBox=function() return focused end,IsKeyDown=function(_,k) return pressed[k] end}
local pre=signal()
local flags={};local free=false;local spec=false
local services={activity={set=function(n,v) flags[n]=v end},freeCam={IsActive=function() return free end},spectate={IsActive=function() return spec end}}
local card
local framework={Categories={Utilities={CreateModule=function(_,d)
 card={Options={}}
 local function option(self,o)
  local field={Value=o.Default}
  function field:Set(v) self.Value=v;if o.Function then o.Function(v) end end
  self.Options[o.Name]=field;if o.Function then o.Function(o.Default) end;return field
 end
 card.CreateToggle=option;card.CreateSlider=option
 function card:Toggle(v) self.Enabled=v;d.Function(v) end
 function card:Notify(s) error(s) end
 return card
end}}}
'''+ '\nlocal Ghost=(function()\n'+(ROOT/'src/games/universal/Blatant/Invisible.lua').read_text()+'\nend)()\n'+r'''
Ghost.init({host={LocalPlayer=player,UserInputService=input,RunService={PreSimulation=pre},workspace=world},framework=framework,services=services})
assert(not card.Options['Ghost Fly'].Value)
card:Toggle(true);assert(flags.ghost and not character.Archivable and pre:Count()==1)
local clone=world:FindFirstChild('Wurst_Ghost');local gh=clone:FindFirstChildOfClass('Humanoid');local gr=clone:FindFirstChild('HumanoidRootPart')
assert(not gr.Anchored and clone:FindFirstChild('Torso').CanCollide and not gr.CanCollide)
assert(world.CurrentCamera.CameraSubject==gh and gh.WalkSpeed==16 and gh.MoveDirection.X==1)
local writes=gr.frameWrites;local count=loads
for _=1,20 do pre:Fire(.02) end
assert(gr.frameWrites==writes and loads==count,'Walk must not position-lock or reload animation every frame')
pressed.LeftShift=true;pre:Fire(.02);assert(gh.WalkSpeed==32)
pressed.LeftShift=false;pre:Fire(.02);assert(gh.WalkSpeed==16)
input.JumpRequest:Fire();assert(gh.Jump)
gh.Jump=false;gh.FloorMaterial='Air';gh.state='Freefall';input.JumpRequest:Fire();assert(not gh.Jump)
gr.CFrame=CFrame.new(10,-20,0);gr.AssemblyLinearVelocity=Vector3.new(0,-100,0);writes=gr.frameWrites
pre:Fire(.02);assert(gr.frameWrites==writes);near(gr.Position.Y,-20);near(gr.AssemblyLinearVelocity.Y,-100)
-- No ground ray or fixed-height fallback: native physics is free to keep falling.
focused=true;pressed.LeftShift=true;pre:Fire(.02);assert(gh.WalkSpeed==16 and gh.MoveDirection.Magnitude==0);focused=false
card.Options['Ghost Fly']:Set(true);pressed.W=true;pre:Fire(.1)
assert(gr.Anchored and gh.PlatformStand and not clone:FindFirstChild('Torso').CanCollide)
near(gr.Position.Z,-5.5)
card.Options['Ghost Fly']:Set(false);pressed.W=false;pressed.LeftShift=false;pre:Fire(.02)
assert(not gr.Anchored and not gh.PlatformStand and clone:FindFirstChild('Torso').CanCollide)
-- Ghost does not steal a camera from FreeCam or Spectate.
free=true;local external={};world.CurrentCamera={CameraSubject=external,CFrame=CFrame.new(0,0,0)};pre:Fire(.02)
assert(world.CurrentCamera.CameraSubject==external);free=false
pre:Fire(.02);assert(world.CurrentCamera.CameraSubject==gh)
local newCharacter,newH,newRoot=makeCharacter(Vector3.new(100,40,0));player.Character=newCharacter
pre:Fire(.02);assert(clone.destroyed and not newCharacter.Archivable)
clone=world:FindFirstChild('Wurst_Ghost');gr=clone:FindFirstChild('HumanoidRootPart');near(gr.Position.X,100)
gr.CFrame=CFrame.new(110,35,0);card:Toggle(false)
near(newRoot.Position.X,110);near(newRoot.Position.Y,35)
assert(clone.destroyed and not flags.ghost and world.CurrentCamera.CameraSubject==newH and pre:Count()==0 and input.JumpRequest:Count()==0)
Ghost.destroy()
pass('actual Ghost: unanchored colliding Walk, no CFrame height lock, gravity left intact, Shift 32/release, jump/air guard, animation cache, Fly transitions, camera ownership, respawn and cleanup')
'''
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp)/'ghost.luau';p.write_text(script);subprocess.run([os.environ.get('LUAU','luau'),str(p)],check=True)
