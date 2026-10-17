#!/usr/bin/env python3
"""Whole Xray source: filters, streamed parts, bounded batches and exact property ownership."""
import os,subprocess,tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE
ROOT=Path(__file__).resolve().parents[1]
S=(ROOT/'src/games/universal/Render/XRay.lua').read_text()
script=PRELUDE+r'''
local function signal()
 local s={listeners={}}
 function s:Connect(fn) self.listeners[fn]=true;return {Disconnect=function() self.listeners[fn]=nil end} end
 function s:Fire(o) for fn in pairs(self.listeners) do fn(o) end end
 return s
end
local world={parts={},DescendantAdded=signal(),CurrentCamera={CFrame={Position=Vector3.zero}}}
function world:GetDescendants() return self.parts end
local function model(class,parent,hasHumanoid)
 return {Parent=parent,IsA=function(_,c) return c==class end,FindFirstChildOfClass=function(_,c) return c=='Humanoid' and hasHumanoid or nil end}
end
local char=model('Model',world,true)
local characterRoot={Position=Vector3.new(0,2,0)}
char.FindFirstChild=function() return characterRoot end
local function part(name,size,position,parent,modifier)
 local p={Name=name,Size=size,Position=position,Parent=parent or world,Anchored=true,CanCollide=true,Transparency=0,LocalTransparencyModifier=modifier or 0}
 function p:IsA(c) return c=='BasePart' end
 function p:IsDescendantOf(a) local node=self.Parent;while node do if node==a then return true end;node=node.Parent end;return false end
 table.insert(world.parts,p);return p
end
local wall=part('Wall',Vector3.new(1,12,20),Vector3.new(10,5,0),nil,.2)
local floor=part('Floor',Vector3.new(100,1,100),Vector3.new(0,-3,0))
local crate=part('Crate',Vector3.new(4,4,4),Vector3.new(5,3,0))
local far=part('Far',Vector3.new(1,12,20),Vector3.new(5000,0,0))
local decor=part('Glass',Vector3.new(1,12,20),Vector3.new(12,0,0));decor.CanCollide=false
local dynamic=part('Moving',Vector3.new(1,12,20),Vector3.new(13,0,0));dynamic.Anchored=false
local head=part('Head',Vector3.new(2,2,2),Vector3.zero,model('Model',char,false))
local grip=part('Handle',Vector3.new(2,2,2),Vector3.zero,model('Tool',world,false))
local rescue=part('Wurst_AntiVoidPlatform',Vector3.new(42,1,42),Vector3.zero)
local own=part('Menu',Vector3.new(2,2,2),Vector3.zero);own.menu=true
local module,handler
local function option(self,d)
 local o={Value=d.List and d.List[d.Index or 1] or d.Default}
 function o:Set(v) self.Value=v;if d.Function then d.Function(v) end end
 self.Options[d.Name]=o;return o
end
local framework={Categories={Render={CreateModule=function(_,d)
 handler=d.Function;module={Options={},Enabled=false,cleanups={}}
 module.CreateSlider=option;module.CreateToggle=option;module.CreateTextBox=option;module.CreateDropdown=option
 function module:SetStatus() end
 function module:Clean(v) table.insert(self.cleanups,v) end
 function module:Loop(fn) self.step=fn end
 function module:Toggle(v)
  self.Enabled=v
  if not v then for _,item in ipairs(self.cleanups) do if type(item)=='function' then item() else item:Disconnect() end end;table.clear(self.cleanups);self.step=nil end
  handler(v)
 end
 return module
end}}}
'''+ '\nlocal Module=(function()\n'+S+'\nend)()\n'+r'''
Module.init({host={LocalPlayer={Character=char},workspace=world,isMenuOwned=function(p) return p.menu end},framework=framework})
near(wall.LocalTransparencyModifier,.2)
module:Toggle(true);near(wall.LocalTransparencyModifier,.5);near(crate.LocalTransparencyModifier,.5)
for _,p in ipairs({floor,far,decor,dynamic,head,grip,rescue,own}) do near(p.LocalTransparencyModifier,0) end
module.Options.Scope:Set('Walls');module.step(.3);near(crate.LocalTransparencyModifier,0);near(wall.LocalTransparencyModifier,.5)
module.Options['Keep visible']:Set(' wall , Crate ');module.step(.3);near(wall.LocalTransparencyModifier,.2)
module.Options['Keep visible']:Set('');module.Options['Part names']:Set('glass,wall');module.Options.Scope:Set('Named parts');module.Options['Collidable only']:Set(false);module.step(.3)
near(decor.LocalTransparencyModifier,.5);near(wall.LocalTransparencyModifier,.5);near(crate.LocalTransparencyModifier,0)
module.Options.Scope:Set('All map');module.Options['Include unanchored']:Set(true);module.Options['Keep floors']:Set(false);module.Options['Limit range']:Set(false);module.step(.3)
near(dynamic.LocalTransparencyModifier,.5);near(far.LocalTransparencyModifier,.5);near(floor.LocalTransparencyModifier,.5)
near(head.LocalTransparencyModifier,0);near(grip.LocalTransparencyModifier,0)
local added=part('New wall',Vector3.new(1,12,20),Vector3.zero);world.DescendantAdded:Fire(added);module.step(.3);near(added.LocalTransparencyModifier,.5)
wall.LocalTransparencyModifier=.8;module.step(.3);module:Toggle(false);near(wall.LocalTransparencyModifier,.8);near(added.LocalTransparencyModifier,0)
module:Toggle(true);crate.LocalTransparencyModifier=.9;module:Toggle(false);near(crate.LocalTransparencyModifier,.9)
module:Toggle(true);added.Parent=nil;module.step(.3);near(added.LocalTransparencyModifier,0)
Module.destroy();assert(next(world.DescendantAdded.listeners)==nil)
pass('Xray: all scopes, kept names, floors, collision/dynamic/range filters, nested characters/tools, streamed/unparented parts, external writes and cleanup')
-- More candidates than a frame's budget: initial activation must remain bounded.
world.parts={};for _=1,600 do part('Wall',Vector3.new(1,12,20),Vector3.zero) end
Module.init({host={LocalPlayer={Character=char},workspace=world},framework=framework});module:Toggle(true)
local count=0;for _,p in ipairs(world.parts) do if p.LocalTransparencyModifier>0 then count+=1 end end
assert(count==200,'one frame processes at most 200 parts')
module.step(1/60);module.step(1/60);for _,p in ipairs(world.parts) do near(p.LocalTransparencyModifier,.5) end
Module.destroy();for _,p in ipairs(world.parts) do near(p.LocalTransparencyModifier,0) end
pass('Xray: bounded 200-part frame batches and complete bulk restoration')
'''
with tempfile.TemporaryDirectory() as t:
 p=Path(t)/'xray.luau';p.write_text(script);subprocess.run([os.environ.get('LUAU','luau'),str(p)],check=True)
