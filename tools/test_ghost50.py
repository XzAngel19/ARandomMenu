#!/usr/bin/env python3
"""Actual Ghost controller: native walking ownership, sprint, jumping, Fly transitions and cleanup.

v188 additions exercised here: the walk speed slider, the sprint multiplier, the
minimum default Void depth, the Outline toggle (blue Highlight gone by default),
the disguise attribute for other menu indexes, and the walking void guard.
Does not simulate Roblox's collision solver; verifies Walk never writes the
ghost's CFrame except through the bounded void guard.
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
 for _,name in ipairs({'Head','Torso'}) do local p=object('Part',{Name=name});p.Parent=model end
 local h=object('Humanoid',{Name='Humanoid',Health=100,WalkSpeed=16,MoveDirection=Vector3.new(1,0,0),FloorMaterial='Ground',RigType='R6'});h.Parent=model
 return model,h,root
end
local Instance={new=function(class) return object(class) end}
local character,h,root=makeCharacter(Vector3.new(0,20,0))
local player={Character=character}
local world=object('Workspace',{CurrentCamera={CameraSubject=h,CFrame=CFrame.new(0,20,0)},FallenPartsDestroyHeight=-500,Raycast=function() return nil end})
local pressed={};local focused=false;local movementForward,movementRight=0,0;local jumpHeld=false
RaycastParams={new=function() return {FilterDescendantsInstances={}} end}
local input={JumpRequest=signal(),GetFocusedTextBox=function() return focused end,IsKeyDown=function(_,k) return pressed[k] end,
 KeyboardEnabled=true}
local pre=signal()
local flags={};local free=false;local spec=false
local services={activity={set=function(n,v) flags[n]=v end},freeCam={IsActive=function() return free end},spectate={IsActive=function() return spec end},movementInput={getVector=function() return movementForward,movementRight end,isJumpHeld=function() return jumpHeld end}}
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
Ghost.init({host={LocalPlayer=player,UserInputService=input,RunService={PreSimulation=pre},workspace=world},framework=framework,services=services})
assert(not card.Options['Ghost Fly'].Value)
assert(card.Options['Void depth'].Value==1 and card.Options['Void depth'].Metadata.min==1
    and card.Options['Void depth'].Value==card.Options['Void depth'].Metadata.min,
    'Void depth must default to its minimum')
card:Toggle(true);assert(flags.ghost and not character.Archivable and pre:Count()==1)
local clone=world:FindFirstChild('Wurst_Ghost');local gh=clone:FindFirstChildOfClass('Humanoid');local gr=clone:FindFirstChild('HumanoidRootPart')
assert(not gr.Anchored and clone:FindFirstChild('Torso').CanCollide and not gr.CanCollide)
-- v188: walking input comes from the shared movement service (mobile
-- sticks and custom keybinds), not from raw WASD or the real humanoid.
movementForward=1;pre:Fire(.02)
assert(world.CurrentCamera.CameraSubject==gh and gh.WalkSpeed==16)
near(gh.MoveDirection.Z,-1)
near(gh.MoveDirection.X,0)
-- v188: no blue outline by default, and the puppet is disguised from the
-- other menu indexes (Entity/NPCESP reject WurstDisguise models).
assert(not clone:FindFirstChild('GhostHighlight'),'ghost must not draw a Highlight by default')
assert(clone:GetAttribute('WurstDisguise')==true,'ghost clone must carry the disguise attribute')
card.Options.Outline:Set(true)
local outline=clone:FindFirstChild('GhostHighlight')
assert(outline and outline.OutlineTransparency==0.15 and outline.DepthMode=='Occluded',
 'opt-in outline is occluded, never through walls')
card.Options.Outline:Set(false);assert(not clone:FindFirstChild('GhostHighlight'))
card.Options['Ghost transparency']:Set(0.8)
assert(clone:FindFirstChild('Torso').Transparency==0.8,'transparency slider applies live')
card.Options['Ghost transparency']:Set(0.5)
local writes=gr.frameWrites;local count=loads
for _=1,20 do pre:Fire(.02) end
assert(gr.frameWrites==writes and loads==count,'Walk must not position-lock or reload animation every frame')
pressed.LeftShift=true;pre:Fire(.02);assert(gh.WalkSpeed==32)
pressed.LeftShift=false;pre:Fire(.02);assert(gh.WalkSpeed==16)
-- v188: Ghost WalkSpeed is a real option and the sprint is a multiplier.
card.Options['Ghost WalkSpeed']:Set(40);pre:Fire(.02);assert(gh.WalkSpeed==40)
pressed.LeftShift=true;pre:Fire(.02);assert(gh.WalkSpeed==80)
pressed.LeftShift=false;card.Options['Sprint multiplier']:Set(1);pre:Fire(.02)
assert(gh.WalkSpeed==40,'multiplier 1 disables sprinting')
card.Options['Sprint multiplier']:Set(2);card.Options['Ghost WalkSpeed']:Set(16);pre:Fire(.02)
assert(gh.WalkSpeed==16)
input.JumpRequest:Fire();assert(gh.Jump)
gh.Jump=false;gh.FloorMaterial='Air';gh.state='Freefall';input.JumpRequest:Fire();assert(not gh.Jump)
gr.CFrame=CFrame.new(10,-20,0);gr.AssemblyLinearVelocity=Vector3.new(0,-100,0);writes=gr.frameWrites
pre:Fire(.02);assert(gr.frameWrites==writes);near(gr.Position.Y,-20);near(gr.AssemblyLinearVelocity.Y,-100)
-- v188: the void guard is bounded, not a flight plane: only under the last
-- known height minus the margin, and only while walking.
gr.CFrame=CFrame.new(10,-400,0);writes=gr.frameWrites;pre:Fire(.02)
assert(gr.frameWrites==writes+1,'void guard re-seats a ghost that fell past the map floor')
near(gr.Position.Y,-236)
gr.CFrame=CFrame.new(10,-20,0)
card.Options['Void guard']:Set(false);gr.CFrame=CFrame.new(10,-400,0);writes=gr.frameWrites;pre:Fire(.02)
assert(gr.frameWrites==writes,'Void guard OFF leaves native falling alone')
card.Options['Void guard']:Set(true);gr.CFrame=CFrame.new(10,20,0)
-- No ground ray or fixed-height fallback: native physics is free to keep falling.
focused=true;pressed.LeftShift=true;pre:Fire(.02);assert(gh.WalkSpeed==16 and gh.MoveDirection.Magnitude==0);focused=false
movementForward=0
card.Options['Ghost Fly']:Set(true);pre:Fire(.1)
assert(gr.Anchored and gh.PlatformStand and not clone:FindFirstChild('Torso').CanCollide)
-- v188: Fly is velocity driven, so it comes from the shared movement service
-- (mobile sticks, custom keybinds) instead of raw WASD keys, and raw keys are
-- not read at all any more.
pressed.W=true;writes=gr.frameWrites;pre:Fire(.1)
assert(gr.AssemblyLinearVelocity.Magnitude==0,'Fly ignores raw WASD; the service is the source')
pressed.W=false;movementForward=1;writes=gr.frameWrites;pre:Fire(.1)
assert(gr.frameWrites==writes,'Fly must not write the ghost CFrame')
near(gr.AssemblyLinearVelocity.Z,-55)
movementForward=0;movementRight=1;pre:Fire(.1);near(gr.AssemblyLinearVelocity.X,55)
movementRight=0;movementForward=0;pressed.Space=true;pre:Fire(.1)
near(gr.AssemblyLinearVelocity.Y,55)
pressed.Space=false;pressed.LeftControl=true;pre:Fire(.1)
near(gr.AssemblyLinearVelocity.Y,-55)
pressed.LeftControl=false;pre:Fire(.1)
assert(gr.AssemblyLinearVelocity.Magnitude==0,'no input means no drift')
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
assert(card.Feature.activate());assert(card.Enabled and card.Feature.enabled and flags.ghost and pre:Count()==1)
Ghost.destroy()
assert(not card.Enabled and not card.Feature.enabled and not flags.ghost and pre:Count()==0 and input.JumpRequest:Count()==0,
 'direct unload must also turn the feature/card OFF and detach its listeners')
-- A failed clone must not leave the card visually ON or persist its ON state.
Ghost.init({host={LocalPlayer=player,UserInputService=input,RunService={PreSimulation=pre},workspace=world},framework=framework,services=services})
cloneFails=true
local ok=card.Feature.activate()
assert(not ok and not card.Enabled and not card.Feature.enabled and not flags.ghost and pre:Count()==0,
 'failed spawn must report failure and leave both feature and card OFF')
cloneFails=false
assert(card.Feature.activate() and card.Enabled and card.Feature.enabled and flags.ghost)
-- v188: the legacy 120-stud default migrates to the new minimum once, and a
-- depth the player actually chose is preserved.
local function reinit()
 Ghost.init({host={LocalPlayer=player,UserInputService=input,RunService={PreSimulation=pre},workspace=world},framework=framework,services=services})
end
configData.values["Universal.Ghost.Voiddepth"]=120
configData.values["UI.GhostDepthDefault"]=nil
savedMarker=nil
reinit()
assert(savedMarker==true and configData.values["Universal.Ghost.Voiddepth"]==1
 and configData.values["UI.GhostDepthDefault"]==1,
 'the legacy 120 default must migrate to the minimum')
assert(card.Options['Void depth'].Value==1,'the migrated value must reach the slider')
Ghost.destroy()
configData.values["Universal.Ghost.Voiddepth"]=200
configData.values["UI.GhostDepthDefault"]=nil
savedMarker=nil
reinit()
assert(configData.values["Universal.Ghost.Voiddepth"]==200 and card.Options['Void depth'].Value==200,
 'a depth the player picked must survive the migration')
Ghost.destroy()
configData.values["Universal.Ghost.Voiddepth"]=nil
configData.values["UI.GhostDepthDefault"]=nil
reinit()
configData=nil -- back to a profile-less session for the remaining assertions
assert(card.Feature.activate() and card.Enabled and card.Feature.enabled and flags.ghost)
clone=world:FindFirstChild('Wurst_Ghost');clone:Destroy();pre:Fire(.02)
assert(not card.Enabled and not card.Feature.enabled and not flags.ghost,
 'losing the active ghost must also switch the visible feature OFF')
-- pre:Count() is the frame listener count, kept separate from the state check
-- because the mock connection set also holds listeners from earlier inits.
assert(pre:Count()==1,'the lost-ghost path runs once and detaches its listener')
Ghost.destroy()
pass('actual Ghost: native Walk, sprint/jump, Fly, camera and respawn; failed spawn, lost ghost and unload keep feature/card/listeners OFF')
'''
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp)/'ghost.luau';p.write_text(script);subprocess.run([os.environ.get('LUAU','luau'),str(p)],check=True)
