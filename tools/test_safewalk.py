#!/usr/bin/env python3
"""Run the real Safe Walk module against a deterministic 1-D world.

Ground is a set of X intervals; the character walks along +X. Checks: a real
drop gets one persistent barrier that never sits on the body; jumping releases
it; narrow lips and stair-sized gaps are not guarded; no per-frame part churn.
"""
import os, subprocess, tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'src/games/universal/Movement/SafeWalk.lua').read_text()

script = PRELUDE + r'''
local RaycastParams={new=function() return {} end}
local created={}
local Instance={new=function(kind)
  local p={kind=kind,CanCollide=true,Parent=nil,SetAttribute=function() end,Destroy=function(self) self.destroyed=true;self.Parent=nil end}
  table.insert(created,p);return p
end}
local groundIntervals={}
local rayCount=0
local world={}
function world:Raycast(origin,direction,params)
  rayCount+=1
  for _,iv in ipairs(groundIntervals) do
    if origin.X>=iv[1] and origin.X<=iv[2] then return {Position=Vector3.new(origin.X,0,origin.Z)} end
  end
  return nil
end
local state='Running'
local humanoid={Health=100,HipHeight=2,FloorMaterial='Ground',MoveDirection=Vector3.new(1,0,0)}
function humanoid:GetState() return state end
local root={Position=Vector3.new(0,3,0),Size=Vector3.new(2,2,1)}
local character={}
local tick
local host={workspace=world,featureConnections={},getCharacterParts=function() return character,humanoid,root end}
function host.disconnectFeatureConnection(key) local c=host.featureConnections[key];if c then c:Disconnect();host.featureConnections[key]=nil end end
host.TaskManager={Connect=function(_,fn) tick=fn;return {Disconnect=function() tick=nil end} end}
local feature
host.createUniversalFeature=function(_,_,_,fn) feature={toggle=fn,SetStatus=function(self,s) self.status=s end};return feature end
host.addNumberOption=function() end
host.workspace=world
local Module=(function()
''' + SOURCE + r'''
end)()
Module.init({host=host})
feature.toggle(true)
assert(tick,'tick connected')

local function frame() tick() end
local function barriers()
  local n=0
  for _,p in ipairs(created) do if p.kind=='Part' and p.CanCollide then n+=1 end end
  return n
end
local function activeBarrier()
  for i=#created,1,-1 do local p=created[i]; if p.kind=='Part' and not p.destroyed then return p end end
end
local function barrierFrontX(p)
  -- barrier plane sits on the walk axis at its CFrame position
  return p.CFrame.Position.X
end

-- 1) Flat ground that ends 3 studs ahead: one barrier, placed beyond the body.
groundIntervals={{-100,3}}
root.Position=Vector3.new(0,3,0);frame()
local b=activeBarrier()
assert(b and b.CanCollide,'drop 3 studs ahead must raise a barrier')
local planeX=barrierFrontX(b)
assert(planeX>=1.25,'barrier must sit beyond the body half depth, got '..planeX)
assert(planeX<=3.0,'barrier must stay on the ground side of the drop, got '..planeX)
local partsAfterFirst=#created

-- 2) Many frames: no new parts are created (no per-frame churn).
for i=1,30 do frame() end
assert(#created==partsAfterFirst,'barrier must be reused, not recreated each frame')

-- 3) Jumping releases the barrier at once; it stays released while airborne.
state='Jumping';frame()
assert(b.CanCollide==false,'jump must release the barrier')
frame();assert(b.CanCollide==false)
state='Running'

-- 4) Narrow lip: ground ends 1 stud ahead. No barrier may be created (it would
--    sit inside the body and be pushed back every frame).
local before=#created
groundIntervals={{-100,1}}
root.Position=Vector3.new(0,3,0);frame()
assert(#created==before,'a lip closer than MIN_EDGE must not create a barrier')

-- 5) Stair-sized seam: a 1-stud gap between treads is not a drop.
groundIntervals={{-100,2},{3,100}}
root.Position=Vector3.new(0,3,0);frame()
assert(b.CanCollide==false,'a 1-stud seam must not raise the barrier')

-- 6) Death tears nothing apart: release only, no new part.
local count=#created
humanoid.Health=0;frame();assert(#created==count and b.CanCollide==false)
humanoid.Health=100

-- 7) Feature off: barrier destroyed, connection gone.
feature.toggle(false)
local folders=0
for _,p in ipairs(created) do if p.kind=='Folder' and p.destroyed then folders+=1 end end
assert(folders>=1,'disable must destroy the barrier folder')
assert(tick==nil,'disable must disconnect the tick')
print('PASS\tSafe Walk: one persistent barrier beyond the body, released on jump, lips and seams not guarded, no per-frame churn')
'''

with tempfile.TemporaryDirectory(prefix='safewalk-') as tmp:
    path = Path(tmp) / 'safewalk.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
