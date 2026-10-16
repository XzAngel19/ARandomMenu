#!/usr/bin/env python3
"""Exercise ItemESP's real bounded geometry fingerprint without Roblox."""
import os
import subprocess
import tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'src/games/universal/Render/ItemRender.lua').read_text().split('function Module.init(', 1)[0]
script = r'''
local V={};local mt={}
function V.new(x,y,z) return setmetatable({X=x,Y=y,Z=z},mt) end
V.zero=V.new(0,0,0)
mt.__add=function(a,b) return V.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
mt.__sub=function(a,b) return V.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
mt.__div=function(a,b) return V.new(a.X/b,a.Y/b,a.Z/b) end
mt.__index=function(a,k) if k=='Magnitude' then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) end end
local Vector3=V
local function node(class,name,children)
    local n={ClassName=class,Name=name,children=children or {},Position=V.zero,Size=V.new(1,2,1),Shape='Block',MeshId='rbxassetid://12'}
    function n:IsA(c) return c==class or c=='BasePart' and (class=='Part' or class=='MeshPart') end
    function n:GetChildren() return self.children end
    function n:FindFirstChildOfClass(c) for _,n in ipairs(self.children) do if n.ClassName==c then return n end end end
    return n
end
''' + source + r'''
local signature=Module.appearanceSignature
local key=node('Model','Model',{node('MeshPart','Handle')})
local duplicate=node('Model','Something else',{node('MeshPart','Part')})
duplicate.children[1].Position=V.new(100,30,-50)
assert(signature(key)==signature(duplicate),'translation/name must not matter')
local unrelated=node('Model','Model',{node('MeshPart','Handle')})
unrelated.children[1].MeshId='rbxassetid://99'
assert(signature(key)~=signature(unrelated),'same Model name cannot match different meshes')
unrelated.children[1].MeshId=key.children[1].MeshId
unrelated.children[1].Size=V.new(2,2,1)
assert(signature(key)~=signature(unrelated),'different size must not match')
local pair=node('Model','Model',{node('Part','A'),node('Part','B')})
pair.children[2].Position=V.new(3,0,0)
local rotated=node('Model','Model',{node('Part','B'),node('Part','A')})
rotated.children[1].Position=V.new(0,0,3)
assert(signature(pair)==signature(rotated),'rotation/order invariance')
rotated.children[1].Position=V.new(0,0,8)
assert(signature(pair)~=signature(rotated),'composition distances matter')
local many={};for i=1,33 do many[i]=node('Part','Part') end
assert(signature(node('Model','Model',many))==nil,'large geometry rejected')
assert(signature(node('Model','Empty'))==nil)
assert(signature(node('Tool','Key',key.children))==signature(key))
local large={};for i=1,100 do large[i]=node('Folder','Folder') end
assert(signature(node('Model','Map',large))==nil,'bounded traversal')
print('PASS Item appearance: names ignored; mesh/size/composition checked; rotation/translation/order invariance; Tool; bounded traversal')
'''
with tempfile.TemporaryDirectory(prefix='item-appearance-') as tmp:
    p=Path(tmp)/'test.luau';p.write_text(script)
    subprocess.run([os.environ.get('LUAU','luau'),str(p)],check=True)
