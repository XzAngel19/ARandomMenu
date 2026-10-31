#!/usr/bin/env python3
"""Exercise the real Jesus water modes with a reusable raycast-parameter mock."""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/games/universal/Blatant/Jesus.lua").read_text()

script = r'''
local vmt={}
local Vector3={}
function Vector3.new(x,y,z) return setmetatable({X=x,Y=y,Z=z},vmt) end
vmt.__mul=function(a,b) return Vector3.new(a.X*b,a.Y*b,a.Z*b) end
local CFrame={new=function(x,y,z) return {Position=Vector3.new(x,y,z)} end}
local Enum={RaycastFilterType={Exclude="Exclude"},Material={Water="Water",Grass="Grass"}}
local allocations=0
local RaycastParams={new=function() allocations+=1;return {} end}
local results
local casts=0
local player
local workspace={Raycast=function(_,_,_,params)
    casts+=1
    assert(params.FilterType=="Exclude" and params.RespectCanCollide==false and params.IgnoreWater==false)
    assert(params.FilterDescendantsInstances[1]==player.Character, "exclude the current character")
    return results
end}
local callbacks={}
local sim={Connect=function(_,fn)
    local connection={};callbacks[connection]=fn
    function connection:Disconnect() callbacks[self]=nil end
    return connection
end}
local function frame() for _,fn in pairs(callbacks) do fn(1/60) end end
local h={Health=100}
local root={Position=Vector3.new(10,9,20),AssemblyLinearVelocity=Vector3.new(3,-5,4),AssemblyMass=2}
function root:ApplyImpulse(v) self.impulse=v end
local char={FindFirstChild=function(_,name)
    if name=="HumanoidRootPart" then return root end
    if name=="Humanoid" then return h end
end}
player={Character=char}
local host={LocalPlayer=player,RunService={PreSimulation=sim},workspace=workspace}
local card
local framework={Categories={Exploits={CreateModule=function(_,def)
    card={Enabled=false,cleaners={},definitions={}}
    function card:Clean(item) table.insert(self.cleaners,item) end
    function card:SetStatus(s) self.status=s end
    function card:CreateDropdown(d) self.definitions[d.Name]=d end
    function card:CreateSlider(d) self.definitions[d.Name]=d end
    function card:Toggle(on)
        if self.Enabled==on then return end
        self.Enabled=on
        if not on then
            for i=#self.cleaners,1,-1 do
                local item=self.cleaners[i]
                if type(item)=="function" then item() else item:Disconnect() end
            end
            table.clear(self.cleaners)
        end
        def.Function(on)
    end
    return card
end}}}
'''+"\nlocal Module=(function()\n"+SOURCE+"\nend)()\n"+r'''
Module.init({host=host,framework=framework})
assert(not card.Enabled and not next(callbacks) and allocations==0, "injection is inert")
card:Toggle(true)
results={Material="Water",Position=Vector3.new(10,10,20)}
frame()
assert(root.AssemblyLinearVelocity.Y==0 and root.CFrame.Position.Y==10.5 and card.status=="Velocity")
root.AssemblyLinearVelocity=Vector3.new(3,-5,4)
card.definitions.Mode.Function("Impulse");frame()
assert(root.impulse and root.impulse.Y==150, "Impulse uses depth and assembly mass")
card.definitions.Bounce.Function(1)
card.definitions.Mode.Function("CFrame");frame()
assert(root.CFrame.Position.Y==11, "CFrame uses selected bounce")
results={Material="Grass",Position=Vector3.new(10,10,20)}
local prior=root.CFrame;frame();assert(root.CFrame==prior, "non-water surfaces are ignored")
local before=casts;h.Health=0;frame();assert(casts==before, "dead character is ignored")
h.Health=100
player.Character={FindFirstChild=char.FindFirstChild}
results={Material="Water",Position=Vector3.new(10,10,20)}
frame();assert(casts==before+1, "respawn continues using the new character")
for _=1,60 do frame() end
assert(allocations==1, "raycast parameters are reused during the same session")
card:Toggle(false);assert(not next(callbacks) and card.status==nil)
card:Toggle(true);frame();assert(allocations==2)
Module.destroy();assert(not card.Enabled and not next(callbacks), "unload disconnects")
print("PASS Jesus: three water modes, filtering, respawn, reused params and cleanup")
'''

with tempfile.TemporaryDirectory(prefix="jesus-") as tmp:
    path = Path(tmp) / "test.luau"
    path.write_text(script)
    subprocess.run([os.environ.get("LUAU", "luau"), str(path)], check=True)
