#!/usr/bin/env python3
"""Exercise the Vape-derived Swim region lifecycle with grid-aware terrain mocks.

This does not emulate Roblox water physics. The algorithm replaces terrain
materials and, like upstream, may clear pre-existing local water in its region.
"""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/games/universal/Blatant/Swim.lua").read_text()

script = r'''
local vmt = {}
local Vector3={}
function Vector3.new(x,y,z) return setmetatable({X=x,Y=y,Z=z},vmt) end
Vector3.zero=Vector3.new(0,0,0)
vmt.__add=function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vmt.__sub=function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vmt.__eq=function(a,b) return a.X==b.X and a.Y==b.Y and a.Z==b.Z end
local Region3={}
function Region3.new(a,b)
    local region={minimum=a,maximum=b,aligned=false}
    function region:ExpandToGrid(grid)
        local mn,mx=self.minimum,self.maximum
        local a=Vector3.new(math.floor(mn.X/grid)*grid,math.floor(mn.Y/grid)*grid,math.floor(mn.Z/grid)*grid)
        local b=Vector3.new(math.ceil(mx.X/grid)*grid,math.ceil(mx.Y/grid)*grid,math.ceil(mx.Z/grid)*grid)
        local result={aligned=true,minimum=a,maximum=b}
        result.CFrame={Position=Vector3.new((a.X+b.X)/2,(a.Y+b.Y)/2,(a.Z+b.Z)/2)}
        result.Size=b-a
        return result
    end
    return region
end
local Enum={Material={Water="Water",Air="Air"},KeyCode={Space="Space"}}
local operations={}
local invalid=0
local terrain={}
function terrain:ReplaceMaterial(region,resolution,from,to)
    if not region.aligned or resolution~=4 then invalid+=1;error("region must be grid-aligned") end
    table.insert(operations,{region=region,from=from,to=to})
end
local workspace={FindFirstChildWhichIsA=function(_,name) if name=="Terrain" then return terrain end end}
local listeners={}
local simulation={Connect=function(_,fn)
    local c={};listeners[c]=fn
    function c:Disconnect() listeners[self]=nil end
    return c
end}
local function frame()
    local list={};for _,fn in pairs(listeners) do table.insert(list,fn) end
    for _,fn in ipairs(list) do fn(1/60) end
end
local root={Position=Vector3.new(1.3,100.2,2.1)}
local humanoid={Health=100,MoveDirection=Vector3.zero}
local character={FindFirstChild=function(_,name)
    if name=="HumanoidRootPart" then return root end
    if name=="Humanoid" then return humanoid end
end}
local host={LocalPlayer={Character=character},RunService={PreSimulation=simulation},workspace=workspace,
    UserInputService={IsKeyDown=function() return false end}}
local card
local framework={Categories={Exploits={CreateModule=function(_,definition)
    card={Enabled=false,cleaners={}}
    function card:Clean(item) table.insert(self.cleaners,item) end
    function card:SetStatus(status) self.status=status end
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
        definition.Function(on)
    end
    return card
end}}}
'''+"\nlocal Module=(function()\n"+SOURCE+"\nend)()\n"+r'''
Module.init({host=host,framework=framework})
assert(not card.Enabled and not next(listeners) and #operations==0, "injection stays inert")
card:Toggle(true);frame()
assert(invalid==0 and #operations==1 and operations[1].from=="Air" and operations[1].to=="Water",
    "the first region is aligned and creates water")
for _=1,60 do frame() end
assert(#operations==1, "the same grid region is not rewritten every frame")
root.Position=Vector3.new(20.3,100.2,2.1);frame()
assert(#operations==3 and operations[2].from=="Water" and operations[2].to=="Air"
    and operations[3].from=="Air" and operations[3].to=="Water", "movement restores old region and fills the new one")
card:Toggle(false)
assert(#operations==4 and operations[4].from=="Water" and operations[4].to=="Air" and not next(listeners),
    "OFF restores the last region and disconnects")
card:Toggle(true);frame();Module.destroy()
assert(not card.Enabled and not next(listeners) and operations[#operations].to=="Air", "unload cleans up")
print("PASS Swim: aligned Vape regions, no unchanged voxel rewrites, movement and cleanup")
'''

with tempfile.TemporaryDirectory(prefix="swim-") as tmp:
    path = Path(tmp) / "test.luau"
    path.write_text(script)
    subprocess.run([os.environ.get("LUAU", "luau"), str(path)], check=True)
