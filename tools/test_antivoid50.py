#!/usr/bin/env python3
"""Exercise real Anti Void / Anti fling: false positives, contact impulses and rescue ownership."""
import os, subprocess, tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE
ROOT=Path(__file__).resolve().parents[1]
script=PRELUDE+r'''
local RaycastParams={new=function() return {} end}
local timers={};local task={delay=function(_,fn) table.insert(timers,fn) end}
local created={}
local Instance={new=function()
 local p={Destroy=function(self) self.destroyed=true end};table.insert(created,p);return p
end}
local tick,feature
local h={Health=100,WalkSpeed=16,MoveDirection=Vector3.new(1,0,0),FloorMaterial='Ground',JumpPower=50}
local props={Position=Vector3.new(0,250,0),CFrame='never roll back',AssemblyLinearVelocity=Vector3.zero,AssemblyAngularVelocity=Vector3.zero}
local root=setmetatable({}, {__index=props,__newindex=function(_,k,v) assert(k~='CFrame','anti modules must not teleport');props[k]=v end})
local character={}
local near=true;local floor;local casts=0
local world={FallenPartsDestroyHeight=-500,Raycast=function(_,origin,direction,params)
 casts+=1;assert(params.RespectCanCollide and params.FilterDescendantsInstances[1]==character)
 return floor and {Position=Vector3.new(0,floor,0)} or nil
end}
local flags={}
local speed={Enabled=false,Options={Speed={Value=5000}}}
local fly={Enabled=false}
local host={workspace=world,featureConnections={},getCharacterParts=function() return character,h,root end,
 Players={GetPlayers=function() return near and {{Character={FindFirstChild=function() return {Position=root.Position+Vector3.new(1,0,0)} end}}} or {} end}}
function host.disconnectFeatureConnection(key) local c=host.featureConnections[key];if c then c:Disconnect();host.featureConnections[key]=nil end end
host.TaskManager={Connect=function(_,fn) tick=fn;return {Disconnect=function() tick=nil end} end}
host.createUniversalFeature=function(_,_,_,fn) feature={toggle=fn,options={}};return feature end
host.addToggleOption=function(_,n,_,fn) feature.options[n]=fn end
host.addNumberOption=function(_,n,_,_,_,fn) feature.options[n]=fn;return {} end
host.addFeatureTooltip=function() end
local context={host=host,services={activity={isActive=function(n) return flags[n] end}},framework={GetModule=function(_,n) return n=='Speed' and speed or n=='Fly' and fly or nil end}}
'''+ '\nlocal Module=(function()\n'+(ROOT/'src/games/universal/Movement/AntiVoid.lua').read_text()+'\nend)()\n'+r'''
Module.init(context);feature.toggle(true);feature.options['Anti fling'](true);tick(.02)
assert(feature.options['Velocity limit']==nil,'no user-tuned velocity limit to get wrong')
-- A strong bounce under the character's own limits and a very long fall are never flings.
h.FloorMaterial='Air';root.AssemblyLinearVelocity=Vector3.new(10,110,0);tick(.02);near(root.AssemblyLinearVelocity.Y,110)
root.AssemblyLinearVelocity=Vector3.new(10,-1000,0);tick(.02);near(root.AssemblyLinearVelocity.Y,-1000);assert(#created==0 and casts==0)
-- Even near the void, a lower collidable floor makes this a legitimate drop.
root.Position=Vector3.new(0,-450,0);floor=-480;tick(.02);assert(#created==0);near(root.AssemblyLinearVelocity.Y,-1000)
-- Contact fling: remove the side/spin impulse, preserve falling and player input.
root.AssemblyLinearVelocity=Vector3.new(999,-200,0);root.AssemblyAngularVelocity=Vector3.new(0,999,0);tick(.02)
near(root.AssemblyLinearVelocity.X,16);near(root.AssemblyLinearVelocity.Y,-200);near(root.AssemblyAngularVelocity.Magnitude,0)
-- A vertical launch no jump can produce is damped to a jump, not left flying.
root.AssemblyLinearVelocity=Vector3.new(0,400,0);root.AssemblyAngularVelocity=Vector3.zero;tick(.02)
near(root.AssemblyLinearVelocity.X,16);near(root.AssemblyLinearVelocity.Y,50)
-- A single-frame planar shove is caught on the first tick, no tuning needed.
root.AssemblyLinearVelocity=Vector3.new(200,0,0);tick(.02);near(root.AssemblyLinearVelocity.X,16)
-- A distant sender is not excused: the old 10-stud proximity gate is gone.
near=false;root.AssemblyLinearVelocity=Vector3.new(900,-200,0);root.AssemblyAngularVelocity=Vector3.new(0,900,0);tick(.02)
near(root.AssemblyLinearVelocity.X,16);near(root.AssemblyAngularVelocity.Magnitude,0)
-- Intentional large Speed stays, because the threshold follows the character.
near=true;speed.Enabled=true;root.AssemblyLinearVelocity=Vector3.new(5000,-200,0);root.AssemblyAngularVelocity=Vector3.zero;tick(.02)
near(root.AssemblyLinearVelocity.X,5000);speed.Enabled=false
-- Explicit actions and vehicles/anchored roots are not fought.
for _,name in ipairs({'ghost','teleport','fling'}) do flags[name]=true;root.AssemblyLinearVelocity=Vector3.new(10000,0,0);tick(.02);near(root.AssemblyLinearVelocity.X,10000);flags[name]=nil end
h.Sit=true;tick(.02);near(root.AssemblyLinearVelocity.X,10000);h.Sit=false
root.Anchored=true;tick(.02);near(root.AssemblyLinearVelocity.X,10000);root.Anchored=false
fly.Enabled=true;tick(.02);near(root.AssemblyLinearVelocity.X,10000);fly.Enabled=false
-- Only an imminent unsupported descent gets a platform, once.
feature.options['Anti fling'](false);floor=nil;root.AssemblyLinearVelocity=Vector3.new(3,-200,4);root.AssemblyAngularVelocity=Vector3.zero
root.Position=Vector3.new(0,-470,0);tick(.02);assert(#created==1 and created[1].CanCollide and created[1].Anchored)
near(root.AssemblyLinearVelocity.Y,0);near(root.AssemblyLinearVelocity.X,3)
root.AssemblyLinearVelocity=Vector3.new(3,-50,4);tick(.02);assert(#created==1,'no platform per-frame churn')
character={};root.Position=Vector3.new(0,250,0);tick(.02);assert(created[1].destroyed,'respawn removes owned rescue')
root.Position=Vector3.new(0,-470,0);root.AssemblyLinearVelocity=Vector3.new(0,-200,0);tick(.02);assert(#created==2)
timers[1]();assert(not created[2].destroyed,'an old timer cannot destroy the new rescue')
-- Anti fling stands on its own: Anti Void off still damps, and builds nothing.
feature.options['Anti fling'](true);feature.toggle(false);assert(tick,'anti fling keeps its own connection with Anti Void off')
root.AssemblyLinearVelocity=Vector3.new(900,-200,0);tick(.02);near(root.AssemblyLinearVelocity.X,16)
assert(#created==2,'Anti Void off must not build a platform')
feature.options['Anti fling'](false);assert(not tick and created[2].destroyed)
Module.destroy()
pass('actual Anti Void/Anti fling: strong bounce, long fall and lower floor untouched, contact/vertical/spike/distant damping on the first tick, no slider, intended Speed, action/seat/anchor exclusions, imminent void, batching, respawn/timer ownership, independence from Anti Void and cleanup')
'''
# Rename the fixture proximity flag so the numeric assertion helper remains callable.
script=script.replace('local near=true','local nearby=true').replace('return near and','return nearby and').replace('near=false','nearby=false').replace('near=true','nearby=true')
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp)/'anti.luau';p.write_text(script);subprocess.run([os.environ.get('LUAU','luau'),str(p)],check=True)
