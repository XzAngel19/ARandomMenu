#!/usr/bin/env python3
"""Execute actual Spider mode paths and settings visibility."""
import os, subprocess, tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE
ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'src/games/universal/Blatant/Spider.lua').read_text()
script=PRELUDE+r'''
Enum.Material={Air='Air'}
Enum.HumanoidStateType={Running='Running',Climbing='Climbing'}
Enum.RaycastFilterType={Exclude='Exclude'}
local RaycastParams={new=function() return {} end}
local cfMt={}
cfMt.__add=function(a,v) return CFrame.new(a.Position+v) end
cfMt.__index={Lerp=function(a,b,t) return CFrame.new(a.Position+(b.Position-a.Position)*t) end}
CFrame.new=function(p) return setmetatable({Position=p or Vector3.zero,UpVector=Vector3.new(0,1,0),LookVector=Vector3.new(0,0,-1),RightVector=Vector3.new(1,0,0)},cfMt) end
CFrame.lookAt=function(p) return CFrame.new(p) end
local character={}
local humanoid={HipHeight=2,MoveDirection=Vector3.new(0,0,-1),FloorMaterial='Air',ChangeState=function(self,s) self.state=s end}
local impulses=0
local root={Position=Vector3.new(0,10,0),CFrame=CFrame.new(Vector3.new(0,10,0)),AssemblyMass=2,AssemblyLinearVelocity=Vector3.zero}
function root:ApplyImpulse(v) impulses+=1;self.AssemblyLinearVelocity+=v/self.AssemblyMass end
local surface={IsA=function() return true end}
local wall={Instance=surface,Normal=Vector3.new(0,0,1),Position=Vector3.new(0,10,-1)}
local ceiling={Instance=surface,Normal=Vector3.new(0,-1,0),Position=Vector3.new(0,13,0)}
local ceilingOnly=false
local world={CurrentCamera={CFrame=CFrame.new()},Raycast=function(_,p,d)
    if d.Y>0 then return ceiling end
    if d.Z<-.1 and not ceilingOnly then return wall end
end}
local tick,handler,feature,mode
local options,rows={},{}
local connections={}
local host={workspace=world,Players={GetPlayers=function() return {} end},LocalPlayer={},
    getCharacterParts=function() return character,humanoid,root end,
    TaskManager={Connect=function(_,fn) tick=fn;return {Disconnect=function() tick=nil end} end},
    featureConnections=connections,
    disconnectFeatureConnection=function(key) if connections[key] then connections[key]:Disconnect();connections[key]=nil end end,
    createUniversalFeature=function(_,_,_,fn) handler=fn;feature={enabled=false,SetStatus=function() end};return feature end,
    addCycleOption=function(_,_,values,_,fn) mode=fn;assert(#values==4);fn(values[1]) end,
    addNumberOption=function(_,name,_,_,_,fn) options[name]=fn;local r={Visible=true};rows[name]=r;return r end,
    addToggleOption=function(_,name,_,fn) options[name]=fn;local r={Parent={Visible=true}};rows[name]=r.Parent;return r end,
    addFeatureTooltip=function() end,
}
'''+'\nlocal Module=(function()\n'+SOURCE+'\nend)()\n'+r'''
Module.init({host=host})
assert(rows['Ceiling Walk'].Visible and not rows['Climb state'].Visible and not rows['Impulse interval'].Visible)
feature.enabled=true;handler(true);tick(1/60)
assert(root.AssemblyLinearVelocity.Z<0,'Spiderman must adhere/move on the surface, not just boost Y')
mode('Velocity');root.AssemblyLinearVelocity=Vector3.new(3,-5,4);tick(1/60)
assert(root.AssemblyLinearVelocity.Y==30 and root.AssemblyLinearVelocity.X==3)
assert(not rows['Ceiling Walk'].Visible and rows['Climb state'].Visible)
mode('Impulse');root.AssemblyLinearVelocity=Vector3.zero;tick(1/60)
assert(impulses==1 and root.AssemblyLinearVelocity.Y==30 and rows['Impulse interval'].Visible)
root.AssemblyLinearVelocity=Vector3.new(0,-10,0);tick(1/60)
assert(impulses==1 and root.AssemblyLinearVelocity.Y==-10,'Impulse must pulse, not write every frame')
tick(.2);assert(impulses==2 and root.AssemblyLinearVelocity.Y==30)
for i=1,120 do tick(1/120);assert(root.AssemblyLinearVelocity.Y<=30) end
mode('CFrame');root.CFrame=CFrame.new(root.Position);root.AssemblyLinearVelocity=Vector3.new(3,9,4);tick(.1)
assert(root.CFrame.Position.Y==13 and root.AssemblyLinearVelocity.Y==0,'CFrame must move by speed*dt')
mode('Spiderman');ceilingOnly=true
root.CFrame.LookVector=Vector3.new(0,-1,0)
tick(.1)
assert(root.AssemblyLinearVelocity.Magnitude==root.AssemblyLinearVelocity.Magnitude,'parallel ceiling look must not normalize zero')
Module.destroy();assert(not tick)
print('PASS Spider: four actual mode paths, bounded timed impulses, per-mode settings, transition/destroy cleanup, ceiling finite guard')
'''
with tempfile.TemporaryDirectory(prefix='spider-') as tmp:
 p=Path(tmp)/'test.luau';p.write_text(script)
 subprocess.run([os.environ.get('LUAU','luau'),str(p)],check=True)
