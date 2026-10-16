#!/usr/bin/env python3
"""Whole Speed + MM2 Sprint integration: one speed owner, no standalone card."""
import os, subprocess, tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE
ROOT=Path(__file__).resolve().parents[1]
S=(ROOT/'src/games/universal/Movement/Speed.lua').read_text()
K=(ROOT/'src/games/MM2/Movement/Sprint.lua').read_text()
script=PRELUDE+r'''
Enum.Material={Air='Air'}
local objects={}
local Instance={new=function(class)
 local o={class=class,Parent=nil,Enabled=false}
 function o:IsA(c) return c==class end
 function o:Destroy() self.Parent=nil;self.destroyed=true end
 table.insert(objects,o);return o
end}
local Color3={fromRGB=function() return {} end}
local ColorSequence={new=function() return {} end}
local NumberSequence={new=function() return {} end}
local NumberSequenceKeypoint={new=function() return {} end}
local humanoid={Parent=true,Health=100,WalkSpeed=16,Sit=false,MoveDirection=Vector3.new(1,0,0),FloorMaterial='Air'}
local function makeRoot()
 local r={Parent=true,Position=Vector3.zero,AssemblyLinearVelocity=Vector3.zero}
 function r:FindFirstChild(name) for _,o in ipairs(objects) do if o.Parent==self and o.Name==name then return o end end end
 return r
end
local root=makeRoot()
local character={FindFirstChildOfClass=function() return humanoid end,FindFirstChild=function() return root end}
local LocalPlayer={Character=character}
local speed,loop,handler
local function option(self,d)
 local value=d.Default
 if d.List then value=d.List[d.Index or 1] end
 if d.Name=='Sprint' then assert(d.Bindable==true) end
 local o={Value=value,fn=d.Function}
 function o:Set(v) self.Value=v;if self.fn then self.fn(v) end end
 self.Options[d.Name]=o;return o
end
local framework={Categories={Exploits={CreateModule=function(_,d)
 handler=d.Function;speed={Options={},Enabled=false}
 speed.CreateDropdown=option;speed.CreateSlider=option;speed.CreateToggle=option
 function speed:SetStatus() end
 function speed:Clean(fn) self.cleanup=fn end
 function speed:Loop(fn) loop=fn end
 function speed:Toggle(v)
  if not v then if self.cleanup then self.cleanup() end;loop=nil end
  self.Enabled=v;handler(v)
 end
 return speed
end}}}
function framework:GetModule(n) assert(n=='Speed');return speed end
local state={framework=framework,mm2Core={}}
local host={LocalPlayer=LocalPlayer,state=state,workspace={}}
local context={framework=framework,host=host,services={movementInput={getVector=function() return 0,0 end}}}
local function getCharacterParts() return character,humanoid,root end
'''+'\nlocal Speed=(function()\n'+S+'\nend)()\nlocal Sprint=(function()\n'+K+'\nend)()\n'+r'''
Speed.init(context);Sprint.init({})
assert(speed.Options.Sprint and speed.SprintFrame)
speed:Toggle(true);loop(1/60);assert(humanoid.WalkSpeed==32)
speed.Options.Sprint:Set(true);loop(1/60)
assert(humanoid.WalkSpeed==30 and root:FindFirstChild('Wurst_SprintTail').Enabled)
local oldHumanoid=humanoid;local oldRoot=root
humanoid={Parent=true,Health=100,WalkSpeed=22,Sit=false,MoveDirection=Vector3.zero,FloorMaterial='Air'};root=makeRoot();loop(1/60)
assert(humanoid.WalkSpeed==30 and not root:FindFirstChild('Wurst_SprintTail').Enabled)
for _,o in ipairs(objects) do assert(o.Parent~=oldRoot,'old trail must be released on respawn') end
speed.Options.Sprint:Set(false);loop(1/60);assert(humanoid.WalkSpeed==32)
for _,o in ipairs(objects) do assert(not o.Parent,'unchecked Sprint releases all trail objects') end
speed.Options.Sprint:Set(true);loop(1/60);speed:Toggle(false)
assert(oldHumanoid.WalkSpeed==16 and humanoid.WalkSpeed==22)
for _,o in ipairs(objects) do assert(not o.Parent) end
Sprint.destroy();Speed.destroy()
assert(not speed.SprintFrame and not speed.ClearSprint)
print('PASS Sprint option: actual Speed owner, 30 speed/trail, idle trail, unchecked/Speed OFF, respawn, cleanup; no standalone feature')
'''
assert 'createUniversalFeature(' not in K
with tempfile.TemporaryDirectory(prefix='sprint-option-') as tmp:
 p=Path(tmp)/'test.luau';p.write_text(script)
 subprocess.run([os.environ.get('LUAU','luau'),str(p)],check=True)
