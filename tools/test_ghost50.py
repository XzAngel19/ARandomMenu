#!/usr/bin/env python3
"""Actual Invisibility controller (v189 logic, v190 name): parked real body, native walk, velocity fly.

Verifies the failures reported live against v188 are structurally impossible:
  * the real body is ANCHORED, non-collidable and re-placed at 10 Hz at most
    (v188 rewrote it every frame on a live collidable body -> jitter/teleport);
  * the clone spawns ABOVE the real body, never inside it;
  * Fly is velocity on an UNANCHORED rig (v188 anchored the root, so velocity
    was ignored and Fly did nothing);
  * no Void guard, no Sprint multiplier, no Outline options remain;
  * Void depth defaults to 5 and old profiles migrate to 5.
Does not simulate Roblox's collision solver; verifies the module's own writes.
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
local Color3={fromRGB=function(r,g,b) return {r=r,g=g,b=b} end}
local function signal()
 local s={listeners={}}
 function s:Connect(fn) local c={Connected=true,fn=fn};table.insert(self.listeners,c);function c:Disconnect() self.Connected=false end;return c end
 function s:Fire(...) for _,c in ipairs(table.clone(self.listeners)) do if c.Connected then c.fn(...) end end end
 function s:Count() local n=0;for _,c in ipairs(self.listeners) do if c.Connected then n+=1 end end;return n end
 return s
end
local makeCharacter
local loads=0
local cloneFails=false
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
 function methods:ChangeState(s) props.state=s end
 function methods:GetAttribute(n) return props[n] end
 function methods:SetAttribute(n,v) props[n]=v end
 function methods:FindFirstAncestorOfClass() return nil end
 function methods:PivotTo(frame) self:FindFirstChild('HumanoidRootPart').CFrame=frame end
 function methods:Clone() if cloneFails then error('clone failed') end;return makeCharacter(self:FindFirstChild('HumanoidRootPart').CFrame.Position) end
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
 for _,name in ipairs({'Head','Torso'}) do local p=object('Part',{Name=name,CanCollide=true});p.Parent=model end
 local h=object('Humanoid',{Name='Humanoid',Health=100,WalkSpeed=16,MoveDirection=Vector3.new(1,0,0),FloorMaterial='Ground',RigType='R6'});h.Parent=model
 return model,h,root
end
local Instance={new=function(class) return object(class) end}
local character,h,root=makeCharacter(Vector3.new(0,20,0))
local player={Character=character}
local world=object('Workspace',{CurrentCamera={CameraSubject=h,CFrame=CFrame.new(0,20,0)},FallenPartsDestroyHeight=-500,
 Raycast=function() return nil end})
RaycastParams={new=function() return {FilterDescendantsInstances={}} end}
local pressed={};local focused=false;local movementForward,movementRight=0,0;local jumpHeld=false
local input={JumpRequest=signal(),GetFocusedTextBox=function() return focused end,
 IsKeyDown=function(_,k) return pressed[k] end,KeyboardEnabled=true}
local pre=signal()
-- The controller throttles the parked-body sync with os.clock; the shared
-- PRELUDE freezes that clock, so it advances with each simulated frame here.
local clock=0
os.clock=function() return clock end
local rawFire=pre.Fire
function pre:Fire(dt) clock=clock+(dt or 0);rawFire(self,dt) end
local flags={};local free=false;local spec=false
local services={activity={set=function(n,v) flags[n]=v end},freeCam={IsActive=function() return free end},
 spectate={IsActive=function() return spec end},
 movementInput={getVector=function() return movementForward,movementRight end,
 isJumpHeld=function() return jumpHeld end}}
local card
local framework={Categories={Utilities={CreateModule=function(_,d)
 card={Options={}}
 local function option(self,o)
  local saved=configData and configData.values["Universal.Ghost."..tostring(o.Name):gsub("%W","")]
  local initial=tonumber(saved) or o.Default
  local field={Value=initial,Metadata={min=o.Min,max=o.Max,default=o.Default}}
  function field:Set(v) self.Value=v;if o.Function then o.Function(v) end end
  self.Options[o.Name]=field;if o.Function then o.Function(initial) end;return field
 end
 card.CreateToggle=option;card.CreateSlider=option
 function card:Toggle(v) if self.Enabled~=v then self.Enabled=v;d.Function(v) end end
 card.Feature={enabled=false}
 function card.Feature.activate()
  local wanted=not card.Feature.enabled
  local ok,err=pcall(function() card:Toggle(wanted) end)
  card.Feature.enabled=ok and wanted or false
  if not ok then card:Toggle(false) end
  return ok,err
 end
 function card:Notify(s) self.lastNotice=s end
 return card
end}}}
'''+ '\nlocal savedMarker=nil\nconfigData={values={}}\nqueueConfigSave=function() savedMarker=true end\nlocal Ghost=(function()\n'+(ROOT/'src/games/universal/Blatant/Invisible.lua').read_text()+'\nend)()\n'+r'''
local function reinit()
 Ghost.init({host={LocalPlayer=player,UserInputService=input,RunService={PreSimulation=pre},workspace=world},framework=framework,services=services})
end
reinit()
-- Menu surface: four options, and none of the removed ones. Void depth 5.
assert(card.Options['Fly'].Value==false and not card.Options['Fly speed'].Visible)
assert(not card.Options['Sprint multiplier'] and not card.Options['Void guard'] and not card.Options.Outline,
 'v189 removed Sprint multiplier, Void guard and Outline')
assert(card.Options['Void depth'].Value==5 and card.Options['Void depth'].Metadata.min==5
 and card.Options['Void depth'].Metadata.max==350,'Void depth defaults to the minimum, now 5')
local count=0;for _ in pairs(card.Options) do count+=1 end
assert(count==5,'Invisibility keeps exactly Fly, Fly speed, Void depth, WalkSpeed, Transparency (5 options)')

card:Toggle(true)
assert(flags.ghost and not character.Archivable and pre:Count()==1)
local clone=world:FindFirstChild('Wurst_Ghost')
local gh=clone:FindFirstChildOfClass('Humanoid')
local gr=clone:FindFirstChild('HumanoidRootPart')
-- The real body is parked: anchored, non-collidable, and NOT respawned on top
-- of the clone.
assert(root.Anchored and not root.CanCollide and not character:FindFirstChild('Torso').CanCollide,
 'the real body must be anchored and non-collidable while Ghost is on')
assert(h.PlatformStand and h.WalkSpeed==0)
-- The clone spawns ABOVE the body, three studs up from where the body stands.
near(gr.Position.Y,23)
-- No blue outline, and the disguise keeps it out of NPC ESP/Entity.
assert(not clone:FindFirstChild('GhostHighlight'),'ghost must never draw a Highlight')
assert(clone:GetAttribute('WurstDisguise')==true)
assert(gr.AssemblyLinearVelocity.Magnitude==0 and not gr.Anchored and clone:FindFirstChild('Torso').CanCollide)

-- Walk: the clone moves through the movement service, never by CFrame.
local writes=gr.frameWrites;local animationLoads=loads
for _=1,20 do pre:Fire(.02) end
assert(gr.frameWrites==writes and loads==animationLoads,'Walk must not position-lock or reload animations every frame')
movementForward=1;pre:Fire(.02)
near(gh.MoveDirection.Z,-1);near(gh.MoveDirection.X,0)
assert(gh.WalkSpeed==16)
card.Options['WalkSpeed']:Set(40);pre:Fire(.02);assert(gh.WalkSpeed==40)
card.Options['WalkSpeed']:Set(16)
focused=true;movementForward=0;pre:Fire(.02);assert(gh.MoveDirection.Magnitude==0);focused=false
input.JumpRequest:Fire();assert(gh.Jump)
gh.Jump=false;gh.FloorMaterial='Air';gh.state='Freefall';input.JumpRequest:Fire();assert(not gh.Jump)
gh.FloorMaterial='Ground';gh.state='Running'

-- The body sync is throttled to 10 Hz, not per frame.
local bodyWrites=root.frameWrites
for _=1,5 do pre:Fire(.01) end
assert(root.frameWrites-bodyWrites<=1,'the parked body is re-placed at most once per 0.1 s')
for _=1,10 do pre:Fire(.01) end
assert(root.frameWrites-bodyWrites>=1,'the parked body still follows the clone')
near(root.Position.Y,gr.Position.Y-5)

-- Fly: velocity on an UNANCHORED rig. v188 anchored the root and then set
-- velocity, which the engine ignores.
card.Options['Fly']:Set(true)
assert(not gr.Anchored and gh.PlatformStand and not clone:FindFirstChild('Torso').CanCollide,
 'Fly must leave the rig unanchored; anchored parts ignore velocity')
movementForward=0;pressed.W=true;pre:Fire(.1)
assert(gr.AssemblyLinearVelocity.Magnitude==0,'Fly ignores raw WASD; the movement service is the source')
pressed.W=false
movementForward=1;writes=gr.frameWrites;pre:Fire(.1)
assert(gr.frameWrites==writes,'Fly must never write the clone CFrame')
near(gr.AssemblyLinearVelocity.Z,-55)
movementForward=0;movementRight=1;pre:Fire(.1);near(gr.AssemblyLinearVelocity.X,55)
movementRight=0;pressed.Space=true;pre:Fire(.1);near(gr.AssemblyLinearVelocity.Y,55)
pressed.Space=false;pressed.LeftControl=true;pre:Fire(.1);near(gr.AssemblyLinearVelocity.Y,-55)
pressed.LeftControl=false;pre:Fire(.1)
assert(gr.AssemblyLinearVelocity.Magnitude==0,'no input means no drift')
pressed.Space=false;jumpHeld=true;pre:Fire(.1);near(gr.AssemblyLinearVelocity.Y,55)
jumpHeld=false;pre:Fire(.1)
card.Options['Fly']:Set(false)
assert(not gh.PlatformStand and clone:FindFirstChild('Torso').CanCollide)

-- Ghost does not steal a camera from FreeCam or Spectate.
free=true;local external={};world.CurrentCamera={CameraSubject=external,CFrame=CFrame.new(0,0,0)};pre:Fire(.02)
assert(world.CurrentCamera.CameraSubject==external);free=false
pre:Fire(.02);assert(world.CurrentCamera.CameraSubject==gh)

-- Respawn rebuilds the puppet and re-parks the new body.
local newCharacter,newH,newRoot=makeCharacter(Vector3.new(100,40,0));player.Character=newCharacter
pre:Fire(.02);assert(clone.destroyed and not newCharacter.Archivable and newRoot.Anchored)
clone=world:FindFirstChild('Wurst_Ghost');gr=clone:FindFirstChild('HumanoidRootPart');near(gr.Position.X,100)
near(gr.Position.Y,43)

-- Turning Ghost OFF hands the body back where the puppet was.
gr.CFrame=CFrame.new(110,35,0)
card:Toggle(false)
near(newRoot.Position.X,110);near(newRoot.Position.Y,35)
assert(not newRoot.Anchored and newRoot.CanCollide and not newH.PlatformStand,
 'OFF must restore collisions and unanchor the real body')
assert(clone.destroyed and not flags.ghost and world.CurrentCamera.CameraSubject==newH and pre:Count()==0
 and input.JumpRequest:Count()==0)

-- Direct unload is the same contract as OFF.
assert(card.Feature.activate());assert(card.Enabled and card.Feature.enabled and flags.ghost and pre:Count()==1)
Ghost.destroy()
assert(not card.Enabled and not card.Feature.enabled and not flags.ghost and pre:Count()==0
 and input.JumpRequest:Count()==0 and not newRoot.Anchored,
 'direct unload must turn everything OFF and hand the body back')

-- A failed clone leaves the card OFF and the body untouched.
reinit()
cloneFails=true
local ok=card.Feature.activate()
assert(not ok and not card.Enabled and not card.Feature.enabled and not flags.ghost and pre:Count()==0
 and not newRoot.Anchored and newRoot.CanCollide,
 'failed spawn must report failure, leave the card OFF and not park the body')
cloneFails=false

-- Losing the active ghost switches the visible feature OFF and frees the body.
assert(card.Feature.activate() and card.Enabled and card.Feature.enabled and flags.ghost)
clone=world:FindFirstChild('Wurst_Ghost');clone:Destroy();pre:Fire(.02)
assert(not card.Enabled and not card.Feature.enabled and not flags.ghost)
assert(not newRoot.Anchored and newRoot.CanCollide,'losing the ghost must not leave the body parked')
Ghost.destroy()

-- Migration: the v187 default (120) and the v188 minimum (1) both become 5,
-- while a depth the player actually picked survives.
configData.values["Universal.Ghost.Voiddepth"]=120
configData.values["UI.GhostDepthDefault"]=nil
savedMarker=nil
reinit()
assert(savedMarker==true and configData.values["Universal.Ghost.Voiddepth"]==5
 and configData.values["UI.GhostDepthDefault"]==2,'the legacy 120 default must migrate to 5')
assert(card.Options['Void depth'].Value==5)
Ghost.destroy()
configData.values["Universal.Ghost.Voiddepth"]=1
configData.values["UI.GhostDepthDefault"]=nil
reinit()
assert(configData.values["Universal.Ghost.Voiddepth"]==5 and card.Options['Void depth'].Value==5,
 'a below-minimum value from v188 must rise to the new minimum')
Ghost.destroy()
for _,kept in ipairs({200,42}) do
 configData.values["Universal.Ghost.Voiddepth"]=kept
 configData.values["UI.GhostDepthDefault"]=nil
 reinit()
 assert(configData.values["Universal.Ghost.Voiddepth"]==kept and card.Options['Void depth'].Value==kept,
  'a depth the player picked must survive the migration')
 Ghost.destroy()
end
configData=nil
pass('actual Ghost v189: parked anchored body at 10 Hz, clone spawned above it, native walk, velocity fly, no guard/outline/sprint, depth 5 and migration')
'''
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp)/'ghost.luau';p.write_text(script);subprocess.run([os.environ.get('LUAU','luau'),str(p)],check=True)
