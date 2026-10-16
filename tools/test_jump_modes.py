#!/usr/bin/env python3
"""Whole Jump module: distinct Normal/Rise/Fall, native fall clip and lifecycle."""
import os
import subprocess
import tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE
ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'src/games/universal/Movement/Jump.lua').read_text()
script=PRELUDE+r'''
Enum.Material={Air='Air',Ground='Ground'}
Enum.HumanoidStateType={Jumping='Jumping',Freefall='Freefall',Running='Running',Landed='Landed'}
Enum.AnimationPriority={Movement='Movement'}
local nativeJump={AnimationId='actual-rig-jump',IsA=function() return true end}
local nativeFall={AnimationId='actual-rig-fall',IsA=function() return true end}
local jumpTrack={IsPlaying=true,Animation=nativeJump,stops=0}
function jumpTrack:Stop() self.IsPlaying=false;self.stops+=1 end
local emote={IsPlaying=true,Animation={AnimationId='emote-do-not-stop'},Stop=function() error('must not stop unrelated emotes') end}
local fallTrack,loadCount
loadCount=0
local animator={}
function animator:GetPlayingAnimationTracks()
 local tracks={emote}
 if jumpTrack.IsPlaying then table.insert(tracks,jumpTrack) end
 if fallTrack and fallTrack.IsPlaying then table.insert(tracks,fallTrack) end
 return tracks
end
function animator:LoadAnimation(animation)
 assert(animation==nativeFall,'use the rig clip, no guessed ID')
 loadCount+=1
 fallTrack={IsPlaying=false,Animation=animation,plays=0}
 function fallTrack:Play() self.IsPlaying=true;self.plays+=1 end
 function fallTrack:Stop() self.IsPlaying=false end
 function fallTrack:Destroy() self.destroyed=true end
 return fallTrack
end
local jumpFolder={GetChildren=function() return {nativeJump} end}
local fallFolder={FindFirstChildOfClass=function() return nativeFall end}
local animate={FindFirstChild=function(_,n) return n=='fall' and fallFolder or jumpFolder end}
local listener
local humanoid={Parent=true,Health=100,JumpPower=50,UseJumpPower=true,MoveDirection=Vector3.new(1,0,0),FloorMaterial='Air',current='Running'}
humanoid.StateChanged={Connect=function(_,fn) listener=fn;return {Disconnect=function() listener=nil end} end}
function humanoid:FindFirstChildOfClass(c) assert(c=='Animator');return animator end
function humanoid:GetState() return self.current end
function humanoid:ChangeState(s)
 if s==self.current then return end
 local old=self.current;self.current=s;if listener then listener(old,s) end
end
local root={AssemblyLinearVelocity=Vector3.new(3,20,4),AssemblyMass=2}
local character={FindFirstChildOfClass=function() return humanoid end,
 FindFirstChild=function(_,n) return n=='Animate' and animate or root end}
local LocalPlayer={Character=character}
local inputRequest,held,loop,handler,jump
local movement={onJumpRequest=function(fn) inputRequest=fn;return {Disconnect=function() inputRequest=nil end} end,isJumpHeld=function() return held end}
local function option(self,d)
 local value=d.List and d.List[d.Index or 1] or d.Default
 self.Options[d.Name]={Value=value,definition=d};return self.Options[d.Name]
end
local framework={Categories={Exploits={CreateModule=function(_,d)
 handler=d.Function;jump={Options={},Enabled=false,cleanups={}}
 jump.CreateToggle=option;jump.CreateSlider=option;jump.CreateDropdown=option;jump.CreateButton=option
 function jump:SetStatus() end
 function jump:Clean(fn) table.insert(self.cleanups,fn) end
 function jump:Loop(fn) loop=fn end
 function jump:Toggle(v)
  self.Enabled=v
  if not v then
   for _,item in ipairs(self.cleanups) do
    if type(item)=='function' then item() else item:Disconnect() end
   end
   table.clear(self.cleanups);loop=nil
  end
  handler(v)
 end
 return jump
end}}}
'''+'\nlocal Module=(function()\n'+SOURCE+'\nend)()\n'+r'''
Module.init({host={LocalPlayer=LocalPlayer,UserInputService={}},framework=framework,services={movementInput=movement}})
local modes=jump.Options['Infinite jump mode'].definition.List
assert(#modes==3 and modes[1]=='Normal' and modes[2]=='Rise' and modes[3]=='Fall')
jump.Options['Infinite jump'].Value=true;jump:Toggle(true)
inputRequest();assert(humanoid.current=='Jumping' and root.AssemblyLinearVelocity.Y==50 and not fallTrack)
assert(root.AssemblyLinearVelocity.X==3 and root.AssemblyLinearVelocity.Z==4)
now+=1;jump.Options['Infinite jump mode'].Value='Fall';loop()
jumpTrack.IsPlaying=true;root.AssemblyLinearVelocity=Vector3.new(3,20,4)
inputRequest()
assert(humanoid.current=='Freefall' and root.AssemblyLinearVelocity.Y==50,'Fall must jump even while Y>0, not brake descent')
assert(fallTrack and fallTrack.IsPlaying and fallTrack.Priority=='Movement' and fallTrack.Looped)
assert(jumpTrack.stops>0 and emote.IsPlaying and loadCount==1)
loop();assert(loadCount==1,'do not reload the clip every frame')
humanoid:ChangeState('Landed');assert(not fallTrack.IsPlaying,'release fall pose on landing')
jumpTrack.IsPlaying=true;root.AssemblyLinearVelocity=Vector3.new(3,0,4);humanoid:ChangeState('Jumping')
assert(humanoid.current=='Freefall' and root.AssemblyLinearVelocity.Y==50 and fallTrack.IsPlaying and not jumpTrack.IsPlaying,'native/Auto Jump transitions must use falling without cancelling takeoff')
jump.Options['Infinite jump mode'].Value='Normal';loop()
assert(not listener and fallTrack.destroyed)
now+=1;inputRequest();assert(humanoid.current=='Jumping')
jump.Options['Infinite jump mode'].Value='Rise';held=true;loop()
assert(humanoid.current=='Freefall' and root.AssemblyLinearVelocity.Y==75)
held=false;root.AssemblyLinearVelocity=Vector3.new(3,-5,4);loop();assert(root.AssemblyLinearVelocity.Y==-5)
jump.Options['Infinite jump mode'].Value='Fall';loop();assert(listener)
local oldTrack=fallTrack
local oldHumanoid=humanoid;humanoid=table.clone(humanoid);oldHumanoid.Parent=nil
loop();assert(oldTrack.destroyed and listener,'release old rig controller on respawn')
Module.destroy();assert(not jump.Enabled and not loop and not inputRequest and not listener and fallTrack.destroyed)
print('PASS Jump: Normal/Rise/Fall, upward Fall jumps + native clip, no emote stop, native jump transition, landing/mode/destroy cleanup')
'''
with tempfile.TemporaryDirectory(prefix='jump-modes-') as tmp:
    path=Path(tmp)/'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU','luau'),str(path)],check=True)
