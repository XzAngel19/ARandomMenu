#!/usr/bin/env python3
"""Exercise the real local Collision Shield in mocked Roblox physics.

This proves lifecycle and pair filtering, not Roblox replication or server physics.
"""
import os
import subprocess
import tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'src/games/universal/Movement/AntiFling.lua').read_text()
script = PRELUDE + r'''
local function model(name, parent, class)
 local m={Name=name,Parent=parent,ClassName=class or 'Model',children={}}
 function m:IsA(kind) return kind==self.ClassName end
 function m:GetDescendants()
  local out={}
  local function visit(n) for _,c in ipairs(n.children or {}) do table.insert(out,c);visit(c) end end
  visit(self);return out
 end
 function m:FindFirstChild(name)
  for _,c in ipairs(self.children) do if c.Name==name then return c end end
 end
 return m
end
local function part(name, parent, collidable, anchored, pos)
 local p={Name=name,Parent=parent,CanCollide=collidable,Anchored=anchored,
  Position=pos or Vector3.zero,Size=Vector3.new(2,2,2),
  AssemblyLinearVelocity=Vector3.zero,AssemblyAngularVelocity=Vector3.zero}
 function p:IsA(kind) return kind=='BasePart' end
 function p:IsDescendantOf(ancestor)
  local n=self.Parent;while n do if n==ancestor then return true end;n=n.Parent end;return false
 end
 function p:FindFirstAncestorOfClass(kind)
  local n=self.Parent;while n do if n.ClassName==kind then return n end;n=n.Parent end
 end
 if parent and parent.children then table.insert(parent.children,p) end
 return p
end
local world={ClassName='Workspace',Parent=nil,children={}}
local myChar=model('Me',world);local otherChar=model('Them',world)
local root=part('HumanoidRootPart',myChar,true,false)
local arm=part('Torso',myChar,true,false)
local otherRoot=part('HumanoidRootPart',otherChar,true,false,Vector3.new(5,0,0))
local otherLimb=part('Arm',otherChar,false,false,Vector3.new(5,0,0))
local me={Name='Me',Character=myChar}
local enemy={Name='Them',Character=otherChar}
local roster={me,enemy};local rosterCalls=0
local players={GetPlayers=function() rosterCalls+=1;return roster end}
local platform=part('Moving floor',world,true,false,Vector3.new(0,-4,0))
platform.AssemblyLinearVelocity=Vector3.new(300,0,0)
local anchored=part('Map wall',world,true,true,Vector3.new(3,0,0))
anchored.AssemblyLinearVelocity=Vector3.new(300,0,0)
local slow=part('Crate',world,true,false,Vector3.new(3,0,0))
local hazard=part('Thrown object',world,true,false,Vector3.new(4,0,0))
hazard.AssemblyLinearVelocity=Vector3.new(100,0,0)
local tool=model('Weapon',otherChar,'Tool');table.insert(otherChar.children,tool)
local handle=part('Handle',tool,true,false,Vector3.new(4,0,0));handle.AssemblyLinearVelocity=Vector3.new(20,0,0)
local nearby={root,otherRoot,otherLimb,platform,anchored,slow,hazard,handle}
local scans=0;local scanThrows=false
function world:GetPartBoundsInRadius(_,_,params)
 scans+=1;assert(params.MaxParts==200)
 if scanThrows then error('unsupported') end
 return nearby
end
function world:Raycast() return {Instance=platform} end
local RaycastParams={new=function() return {} end}
local OverlapParams={new=function() return {} end}
local links={}
local Instance={new=function(class)
 assert(class=='NoCollisionConstraint')
 local link={ClassName=class,destroyed=false}
 function link:Destroy() self.destroyed=true;self.Parent=nil end
 table.insert(links,link);return link
end}
local function activeBetween(a,b)
 local n=0
 for _,l in ipairs(links) do if not l.destroyed and l.Part0==a and l.Part1==b then n+=1 end end
 return n
end
local function activeCount()
 local n=0;for _,l in ipairs(links) do if not l.destroyed then n+=1 end end;return n
end
local hum={Health=100,WalkSpeed=16,JumpPower=50,MoveDirection=Vector3.zero,HipHeight=2,Sit=false}
local currentChar,currentRoot=myChar,root
local tick,feature,options=nil,nil,{}
local activity={}
local notices={}
local host={Players=players,LocalPlayer=me,workspace=world,featureConnections={},
 getCharacterParts=function() return currentChar,hum,currentRoot end,
 notify=function(message) table.insert(notices,message) end}
host.TaskManager={Connect=function(_,fn) tick=fn;return {Disconnect=function() tick=nil end} end}
function host.disconnectFeatureConnection(key)
 local c=host.featureConnections[key];if c then c:Disconnect();host.featureConnections[key]=nil end
end
function host.createUniversalFeature(name,description,_,toggle,settings)
 feature={name=name,description=description,toggle=toggle,settings=settings};return feature
end
function host.addToggleOption(_,name,default,callback)
 assert(default==true);options[name]=callback
end
function host.addFeatureTooltip() end
local framework={GetModule=function() return nil end}
local context={host=host,framework=framework,services={activity={isActive=function(name) return activity[name]==true end}}}
local function update(dt) now+=dt;assert(tick);tick(dt) end
''' + '\nlocal Module=(function()\n' + SOURCE + '\nend)()\n' + r'''
Module.init(context)
assert(feature.name=='Anti Fling' and options['Player Shield'] and options['Impact Shield'])
assert(not tick and activeCount()==0,'OFF boot must be inert')
feature.toggle(true);update(.2)
assert(activeBetween(root,otherRoot)==1 and activeBetween(arm,otherRoot)==1
 and activeBetween(root,otherLimb)==1 and activeBetween(arm,otherLimb)==1,
 'all local colliding parts are paired with the other character, including noncolliding limbs')
assert(activeBetween(root,hazard)==1 and activeBetween(arm,hazard)==1,
 'a nearby high-speed loose part is shielded')
for _,p in ipairs({platform,anchored,slow,handle}) do
 assert(activeBetween(root,p)==0,'floor, anchored wall, slow prop and tools must remain usable: '..p.Name)
end
assert(root.CanCollide and arm.CanCollide and otherRoot.CanCollide and not otherLimb.CanCollide
 and platform.CanCollide and hazard.CanCollide,'shield never mutates CanCollide')
local oldScans,oldRoster=scans,rosterCalls
for _=1,5 do update(.01) end
assert(scans==oldScans and rosterCalls==oldRoster,'spatial and player scans are throttled')
pass('local collision pairs, floor/tool/anchored exclusions, unchanged world and bounded scans')
handle.AssemblyLinearVelocity=Vector3.new(500,0,0);update(.2)
assert(activeBetween(root,handle)==1,'an extreme-speed tool handle is a temporary hazard')
handle.AssemblyLinearVelocity=Vector3.zero;update(.8)
assert(activeBetween(root,handle)==0,'ordinary tool interaction is restored after the hazard')
pass('extreme tool fling is guarded without suppressing ordinary tools')

-- Risk must persist briefly after deceleration, then release without changing
-- normal high-speed movement once no dangerous source is nearby.
hazard.AssemblyLinearVelocity=Vector3.zero
update(.2);assert(activeBetween(root,hazard)==1,'hazard hysteresis')
update(.8);assert(activeBetween(root,hazard)==0,'expired hazard is released')
root.AssemblyLinearVelocity=Vector3.new(300,0,0);root.AssemblyAngularVelocity=Vector3.new(0,50,0)
update(.2)
assert(root.AssemblyLinearVelocity.X==300 and root.AssemblyAngularVelocity.Y==50,
 'normal speed or spin alone does not trigger protection')
-- Other-body motion, not our own speed relative to an idle opponent, arms it.
hazard.AssemblyAngularVelocity=Vector3.new(0,80,0);update(.2)
assert(activeBetween(root,hazard)==1 and root.AssemblyLinearVelocity.X==0
 and root.AssemblyAngularVelocity.Magnitude==0,'extreme nearby spin arms emergency damping')
assert(slow.AssemblyLinearVelocity.Magnitude==0 and slow.CanCollide,'other objects are never rewritten')
pass('temporary velocity/spin hazard detection and evidence-gated emergency damping')

activity.walkfling=true;root.AssemblyLinearVelocity=Vector3.new(500,0,0);update(.2)
assert(activeCount()==0 and root.AssemblyLinearVelocity.X==500,
 'intentional Walk Fling suspends both links and damping')
activity.walkfling=nil;update(.2)
assert(activeBetween(root,otherRoot)==1,'links return after deliberate fling ends')
activity.fling=true;update(.2);assert(activeCount()==0)
activity.fling=nil;update(.2);assert(activeCount()>0)
pass('own Fling and Walk Fling suspend protection and restore it afterwards')

hum.Sit=true;update(.2)
assert(activeBetween(root,hazard)==0 and activeBetween(root,otherRoot)==1,
 'seat/vehicle stays usable while player pairs remain active')
hum.Sit=false;update(.2)
options['Impact Shield'](false);update(.2)
assert(activeBetween(root,hazard)==0 and activeBetween(root,otherRoot)==1)
options['Player Shield'](false);update(.2)
assert(activeCount()==0,'individual shields can be disabled independently')
options['Player Shield'](true);options['Impact Shield'](true);update(.2)
scanThrows=true;update(.2);update(.2)
assert(#notices==1 and activeBetween(root,otherRoot)==1,
 'unavailable spatial API warns once but does not remove player protection')
scanThrows=false
pass('seat safety, independent shields and missing spatial API')

-- A crowded rig can exhaust the cap. A newly fast object must still get
-- priority instead of being starved indefinitely by older player pairs.
local ownCount=#myChar.children;local otherCount=#otherChar.children
for i=1,50 do
 part('Own'..i,myChar,true,false)
 part('Other'..i,otherChar,true,false,Vector3.new(5,0,0))
end
update(.2);assert(activeCount()<=2048 and activeCount()>=2000,'pair cap is enforced')
slow.AssemblyLinearVelocity=Vector3.new(200,0,0);update(.2)
assert(activeCount()<=2048 and activeBetween(root,slow)==1,
 'new extreme hazards take priority over old player links at the cap')
for i=#myChar.children,ownCount+1,-1 do local p=table.remove(myChar.children);p.Parent=nil end
for i=#otherChar.children,otherCount+1,-1 do local p=table.remove(otherChar.children);p.Parent=nil end
slow.AssemblyLinearVelocity=Vector3.zero;update(1)
assert(activeCount()<20,'departing crowds release their temporary links')
pass('bounded pair budget prioritizes incoming hazards and releases old crowds')

local replacement=model('Me2',world)
local newRoot=part('HumanoidRootPart',replacement,true,false)
currentChar=replacement;currentRoot=newRoot;me.Character=replacement
update(.2)
assert(activeBetween(root,otherRoot)==0 and activeBetween(newRoot,otherRoot)==1,
 'respawn retires old constraints and protects the new body')
local otherReplacement=model('Them2',world)
local otherNew=part('HumanoidRootPart',otherReplacement,true,false,Vector3.new(3,0,0))
enemy.Character=otherReplacement;update(.2)
assert(activeBetween(newRoot,otherRoot)==0 and activeBetween(newRoot,otherNew)==1,
 'remote respawn removes obsolete target constraints')
feature.toggle(false)
assert(tick==nil and activeCount()==0 and newRoot.CanCollide and otherNew.CanCollide,
 'OFF destroys every local constraint without modifying body collisions')
Module.destroy()
assert(activeCount()==0)
pass('local/remote respawn, OFF and destruction cleanup')
print('PASS '..passed..' Anti Fling collision shield suites')
'''
with tempfile.TemporaryDirectory(prefix='anti-fling-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
