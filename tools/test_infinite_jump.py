#!/usr/bin/env python3
"""Run the standalone Infinite Jump lifecycle against PC/mobile input mocks."""
import os
import subprocess
import tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'src/games/universal/Movement/InfiniteJump.lua').read_text()
code = PRELUDE + r'''
Enum.Material={Air='Air',Ground='Ground'}
Enum.HumanoidStateType={Jumping='Jumping',Freefall='Freefall',Running='Running',Seated='Seated',Swimming='Swimming',Climbing='Climbing',Physics='Physics',PlatformStanding='PlatformStanding',Ragdoll='Ragdoll',Dead='Dead'}
Enum.KeyCode={Space='Space',ButtonA='ButtonA',Unknown='Unknown'}
Enum.UserInputType={Touch='Touch',Keyboard='Keyboard'}
local function signal()
 local s={listeners={}}
 function s:Connect(fn)
  local c={};self.listeners[c]=fn
  function c:Disconnect() s.listeners[self]=nil end
  return c
 end
 function s:Fire(...) for _,fn in pairs(table.clone(self.listeners)) do fn(...) end end
 function s:Count() local n=0;for _ in pairs(self.listeners) do n+=1 end;return n end
 return s
end
local button={AbsolutePosition={X=100,Y=100},AbsoluteSize={X=60,Y=60}}
local touchGui={FindFirstChild=function(_,name) return name=='JumpButton' and button end}
local playerGui={FindFirstChild=function(_,name) return name=='TouchGui' and touchGui end}
local root={Anchored=false,AssemblyLinearVelocity=Vector3.new(3,0,4)}
local humanoid={Parent=true,Health=100,FloorMaterial='Ground',current='Running',changes=0}
function humanoid:GetState() return self.current end
function humanoid:ChangeState(v) self.current=v;self.changes+=1 end
local character={FindFirstChildOfClass=function() return humanoid end,FindFirstChild=function(_,n) return n=='HumanoidRootPart' and root end}
local player={Character=character,FindFirstChildOfClass=function(_,name) return name=='PlayerGui' and playerGui end}
local input={TouchEnabled=true,InputBegan=signal(),InputEnded=signal(),WindowFocusReleased=signal(),JumpRequest=signal(),touches={}}
function input:GetTouches() return self.touches end
local run={PreSimulation=signal()}
local move={onJumpRequest=function(fn) return input.JumpRequest:Connect(fn) end}
local card
local framework={Categories={Exploits={CreateModule=function(_,d)
 card={Enabled=false,Options={},cleanups={}}
 function card:CreateSlider(o) self.Options[o.Name]={Value=o.Default} end
 function card:SetStatus(v) self.status=v end
 function card:Clean(item) table.insert(self.cleanups,item) end
 function card:Toggle(v)
  if self.Enabled==v then return end
  self.Enabled=v
  if not v then for _,item in ipairs(self.cleanups) do item:Disconnect() end;table.clear(self.cleanups) end
  d.Function(v)
 end
 return card
end}}}
''' + '\nlocal Module=(function()\n' + SOURCE + '\nend)()\n' + r'''
Module.init({host={LocalPlayer=player,UserInputService=input,RunService=run},services={movementInput=move},framework=framework})
assert(input.InputBegan:Count()==0 and input.JumpRequest:Count()==0,'must be inert until ON')
card:Toggle(true)
assert(input.InputBegan:Count()==1 and input.JumpRequest:Count()==1 and run.PreSimulation:Count()==1)
local finger={UserInputType='Touch',KeyCode='Unknown',Position=Vector3.new(110,110,0)}
input.touches={finger}
input.InputBegan:Fire(finger,true)
assert(root.AssemblyLinearVelocity.Y==0 and humanoid.current=='Running',
    'first positive ground jump must stay native on mobile too')
input.InputEnded:Fire(finger)
humanoid.FloorMaterial='Air';now=1
input.InputBegan:Fire(finger,true);input.JumpRequest:Fire()
assert(root.AssemblyLinearVelocity.Y==50 and humanoid.changes==1,'one mobile tap adds one air jump')
root.AssemblyLinearVelocity=Vector3.new(3,-5,4)
input.InputEnded:Fire({UserInputType='Touch',KeyCode='Unknown'})
input.JumpRequest:Fire();assert(root.AssemblyLinearVelocity.Y==-5,'another finger cannot rearm the held jump')
input.InputEnded:Fire(finger);now+=1;input.JumpRequest:Fire()
assert(root.AssemblyLinearVelocity.Y==50 and humanoid.changes==2,'release and tap rearm mobile air jump')
input.InputEnded:Fire(finger)
input.TouchEnabled=false;now+=1
local space={UserInputType='Keyboard',KeyCode='Space'}
root.AssemblyLinearVelocity=Vector3.new(3,-2,4)
input.InputBegan:Fire(space,false);input.JumpRequest:Fire()
assert(root.AssemblyLinearVelocity.Y==50 and humanoid.changes==3,'PC key and JumpRequest cannot double boost')
input.InputEnded:Fire(space);humanoid.current='Seated';now+=1
root.AssemblyLinearVelocity=Vector3.new(3,-2,4);input.InputBegan:Fire(space,false)
assert(root.AssemblyLinearVelocity.Y==-2,'seated characters cannot boost')
input.InputEnded:Fire(space);humanoid.current='Running';humanoid.FloorMaterial='Ground'
card.Options['Jump Power'].Value=-20;now+=1;input.InputBegan:Fire(space,false)
assert(root.AssemblyLinearVelocity.Y==-20 and humanoid.current=='Freefall','negative power inverts ground jump physics')
Module.destroy()
assert(not card.Enabled and input.InputBegan:Count()==0 and input.InputEnded:Count()==0
 and input.JumpRequest:Count()==0 and run.PreSimulation:Count()==0,'unload must detach all listeners')
print('PASS Infinite Jump: native mobile ground takeoff, PC/touch air boosts, deduplication, negative physics and cleanup')
'''
with tempfile.TemporaryDirectory(prefix='infinite-jump-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(code)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
