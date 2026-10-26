#!/usr/bin/env python3
"""Execute Flight's real lifecycle and method transitions against deterministic mocks."""
import os
import subprocess
import tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE
ROOT=Path(__file__).resolve().parents[1]
source=(ROOT/'src/games/universal/Blatant/Fly.lua').read_text()
script=PRELUDE+r'''
Enum.KeyCode={Space='Space',LeftControl='Control'}
Enum.RaycastFilterType={Exclude='Exclude'}
Enum.ActuatorRelativeTo={World='World'}
Enum.VelocityConstraintMode={Vector='Vector'}
Enum.OrientationAlignmentMode={OneAttachment='OneAttachment'}
mt.__index=function(a,k)
    if k=='Magnitude' then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) end
    if k=='Unit' then return a/a.Magnitude end
    if k=='Lerp' then return function(a,b,t) return a+(b-a)*t end end
end
mt.__mul=function(a,b)
    if type(a)=='number' then a,b=b,a end
    if type(b)=='table' then return Vector3.new(a.X*b.X,a.Y*b.Y,a.Z*b.Z) end
    return Vector3.new(a.X*b,a.Y*b,a.Z*b)
end
local cf={};local cfMt={__add=function(a,b) return cf.new(a.Position+b) end}
function cf.new(x,y,z)
    local p=type(x)=='table' and x or Vector3.new(x or 0,y or 0,z or 0)
    return setmetatable({Position=p,LookVector=Vector3.new(0,0,-1),RightVector=Vector3.new(1,0,0)},cfMt)
end
cf.lookAt=function(p) return cf.new(p) end
CFrame=cf
local RaycastParams={new=function() return {} end}
local allocated={}
local Instance={new=function(class)
    local o={ClassName=class}
    function o:Destroy() self.Parent=nil;self.destroyed=true end
    table.insert(allocated,o);return o
end}
local humanoid={Parent=true,WalkSpeed=16,HipHeight=2,ChangeState=function() end}
local function makeRoot()
    return {Parent=true,Position=Vector3.new(0,10,0),CFrame=cf.new(0,10,0),AssemblyLinearVelocity=Vector3.zero,
        AssemblyMass=1,FindFirstChild=function(self,name)
            for _,o in ipairs(allocated) do if o.Parent==self and o.Name==name then return o end end
        end,ApplyImpulse=function(self,v) self.AssemblyLinearVelocity+=v end}
end
local root=makeRoot()
local camera={CFrame=cf.new()}
local world={CurrentCamera=camera,Raycast=function() return nil end}
local owner,applied=nil,nil
local platform={set=function(_,v) owner=v end,apply=function() applied=owner end}
local callbacks={}
local handler,loop,feature
local framework={Categories={Exploits={CreateModule=function(_,definition)
    handler=definition.Function
    feature={Enabled=false}
    function feature:SetStatus() end
    function feature:Loop(fn) loop=fn end
    function feature:Toggle(v) self.Enabled=v;if not v then loop=nil end;handler(v) end
    function feature:CreateDropdown(d) callbacks[d.Name]=d.Function;return {} end
    feature.CreateSlider=feature.CreateDropdown
    feature.CreateToggle=feature.CreateDropdown
    function feature:CreateBind(d) return {Object={}} end
    return feature
end}}}
local userInput={KeyboardEnabled=true,IsKeyDown=function() return false end,GetFocusedTextBox=function() return nil end}
local host={workspace=world,UserInputService=userInput,getCharacterParts=function() return nil,humanoid,root end}
local flingActive=false
local context={framework=framework,host=host,services={platformStandOwnership=platform,mobileActions={},
    activity={isActive=function(name) return name=='fling' and flingActive end},
    movementInput={getVector=function() return 0,0 end,isJumpHeld=function() return false end}}}
'''+'\nlocal Module=(function()\n'+source+'\nend)()\n'+r'''
Module.init(context)
callbacks['Face camera'](false)
feature:Toggle(true);loop(1/60)
assert(owner==nil and applied==nil,'Fly must never request PlatformStand')
assert(callbacks.PlatformStand==nil,'no PlatformStand option')
callbacks.Method('WalkSpeed');loop(1/60)
assert(humanoid.WalkSpeed==70 and owner==nil)
callbacks.Method('Velocity');loop(1/60)
assert(humanoid.WalkSpeed==16,'switching out of WalkSpeed restores it immediately')
callbacks.Method('WalkSpeed');loop(1/60)
local previous=humanoid
humanoid={Parent=true,WalkSpeed=22,HipHeight=2,ChangeState=function() end};root=makeRoot();loop(1/60)
assert(previous.WalkSpeed==16 and humanoid.WalkSpeed==70)
feature:Toggle(false);assert(humanoid.WalkSpeed==22 and owner==nil)
callbacks.Method('Velocity');callbacks.Float('Floor');feature:Toggle(true);loop(1/60)
local floor=allocated[#allocated];assert(floor.Name=='Wurst_FlyPlatform' and floor.Parent==camera)
callbacks.Method('Constraint');loop(1/60)
assert(floor.destroyed,'switching to Constraint must release Floor')
local alive=0;for _,o in ipairs(allocated) do if o.Parent then alive+=1 end end
assert(alive==3,'Constraint owns attachment, velocity and orientation')
flingActive=true;loop(1/60)
alive=0;for _,o in ipairs(allocated) do if o.Parent then alive+=1 end end
assert(alive==0,'Fly releases constraints while Fling owns physics')
flingActive=false;loop(1/60)
alive=0;for _,o in ipairs(allocated) do if o.Parent then alive+=1 end end
assert(alive==3,'Fly constraints resume after Fling releases ownership')
callbacks.Method('Velocity');callbacks.Float('Bypass');now=0;loop(1/60)
root.Position=Vector3.new(0,8,0);root.CFrame=cf.new(root.Position);now=0.01;loop(1/60)
assert(root.CFrame.Position.Y==10,'Bypass must retain its altitude across frames')
callbacks.Float('Floor');loop(1/60);floor=allocated[#allocated]
Module.destroy()
assert(not feature.Enabled and loop==nil and owner==nil and floor.destroyed)
for _,o in ipairs(allocated) do assert(not o.Parent,'no leaked flight objects') end
print('PASS Fly: no PlatformStand ownership or option, WalkSpeed transitions/respawn, Floor to Constraint, Bypass altitude, destroy')
'''
with tempfile.TemporaryDirectory(prefix='flight-') as tmp:
    p=Path(tmp)/'flight.luau';p.write_text(script)
    subprocess.run([os.environ.get('LUAU','luau'),str(p)],check=True)
