#!/usr/bin/env python3
"""Actual final-send guard, WallCheck filter and shot dispatch. Not server validation."""
import os, subprocess, tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
B = (ROOT / 'src/games/MM2/base.lua').read_text()
S = (ROOT / 'src/games/MM2/Blatant/Shoot.lua').read_text()

code = PRELUDE + r'''
local predictionMath={finite=function(n) return type(n)=='number' and n==n and math.abs(n)<math.huge end}
local LocalPlayer={Character=nil}
local function model(pos)
 local m={parts={},humanoid={Health=100}}
 function m:FindFirstChildOfClass(k) return k=="Humanoid" and self.humanoid or nil end
 local part={Position=pos,Size=Vector3.new(2,2,2),CanQuery=true,Transparency=0}
 function part:IsA(k) return k=='BasePart' end
 function part:IsDescendantOf(o) return o==m end
 table.insert(m.parts,part)
 function m:FindFirstChild(k) return k=='HumanoidRootPart' and part or nil end
 return m,part
end
local own,ownPart=model(Vector3.new(-3,0,0));LocalPlayer.Character=own
local victim,body=model(Vector3.new(20,0,0))
local friendly,friend=model(Vector3.new(10,10,0))
local target={Character=victim,role='Murderer',alive=true,knife={}}
local innocent={Character=friendly,role='Innocent',alive=true}
local roster={LocalPlayer,target,innocent}
local Players={GetPlayers=function() return roster end}
local function isPlayerAlive(p) return p.alive end
local function isProtectedTarget(p) return p.protected end
local function getPlayerRole(p) return p.role end
local function getRoundRole(p) return p.roundRole end
local function getPlayerWeapon(p) return p.knife end
local function hasMurdererCollisionGroup(m) return m.murdererGroup end
local roundLifecycleActive=true
local tagged={}
local CollectionService={GetTagged=function() return tagged end}
local RaycastParams={new=function() return {} end}
local scene={body,friend}
-- Independent axis-aligned engine ray mock. The filter is the game's own:
-- Exclude own character + WeaponPassthrough tags, then skip invisible parts.
local rays=0
local function entry(p,o,delta)
 local lo,hi=0,1
 for _,a in ipairs({'X','Y','Z'}) do
  local low,high=p.Position[a]-p.Size[a]/2,p.Position[a]+p.Size[a]/2
  if math.abs(delta[a])<1e-8 then if o[a]<low or o[a]>high then return end
  else local x,y=(low-o[a])/delta[a],(high-o[a])/delta[a];lo=math.max(lo,math.min(x,y));hi=math.min(hi,math.max(x,y));if lo>hi then return end end
 end
 return lo
end
local function listed(part,params)
 for _,m in ipairs(params.FilterDescendantsInstances) do
  if part==m or part:IsDescendantOf(m) then return true end
 end
 return false
end
local workspace={Raycast=function(_,origin,delta,params)
 rays+=1
 local nearest,hit=math.huge,nil
 for _,part in ipairs(scene) do
  local excluded=listed(part,params)
  local include=params.FilterType=='Include'
  if part.CanQuery and ((include and excluded) or (not include and not excluded)) then
   local t=entry(part,origin,delta)
   if t and t<nearest then nearest,hit=t,part end
  end
 end
 return hit and {Instance=hit,Position=origin+delta*(nearest or 0)} or nil
end}
''' + section(B, 'local function isWeaponPathClear(', 'local function getWeaponFromContainer(') + section(B, 'local function validateGunShot(', 'local function disconnectGunFiredObserver') + r'''
local mm2SettingsWallsDefault=true
local muzzle=Vector3.zero
local function check(walls,origin,finish)
 if walls==nil then walls=mm2SettingsWallsDefault end
 return validateGunShot(target,own,victim,muzzle,origin or muzzle,finish or body.Position,walls)
end
assert(check())
local wall,wallPart=model(Vector3.new(10,0,0));table.insert(scene,wallPart)
assert(not check())
wallPart.Transparency=1
-- v62: the game's own filter skips every transparent part; the strict pass
-- treats a transparent *solid* as the invisible wall the server collided
-- with (five of nine confirmed shots in the 2026-10-18 session stopped
-- 24-56 studs short of the aim).
local invisibleAllowed,invisibleWhy,invisibleBlocker=check()
assert(not invisibleAllowed,'an invisible solid is not a clear path')
assert(type(invisibleWhy)=='string' and invisibleWhy:find('invisible'),
    'the refusal must name the invisible wall')
assert(type(invisibleBlocker)=='table' and invisibleBlocker.transparency==1
    and invisibleBlocker.canCollide~=false and invisibleBlocker.skipped==false,
    'the blocker must be recorded for the calibration')
assert(isWeaponPathClear(muzzle,body.Position,victim,nil,nil),
    'the game filter skips every transparent part')
wallPart.CanCollide=false
assert(check(),'invisible decoration that cannot collide stays skippable')
wallPart.CanCollide=true
wallPart.CanQuery=false
-- Friendly players block a normal shot until the segment is clear.
friend.CanQuery=true
friend.Position=Vector3.new(10,0,0)
assert(not check(),'an innocent in front of the murderer blocks the shot')
friend.Transparency=1
friend.CanCollide=false
assert(check(),'the game filter also skips invisible player parts')
friend.CanCollide=true
friend.Transparency=0
assert(not check())
friend.Position=Vector3.new(30,0,0);assert(check())
friend.Position=Vector3.new(10,10,0);assert(check())
-- Target and round evidence.
target.roundRole='Innocent';assert(not check());target.roundRole=nil
target.role='Innocent';assert(not check());target.role='Murderer'
assert(check())
target.knife=nil
assert(not check(),'cached murderer without current evidence is rejected')
target.knife={};assert(check());target.role='Murderer'
target.protected=true;assert(not check());target.protected=nil
target.alive=false;assert(not check());target.alive=true
target.Character=model(Vector3.new(20,0,0));assert(not check());target.Character=victim
roundLifecycleActive=false;assert(not check());roundLifecycleActive=true
LocalPlayer.Character={};assert(not check());LocalPlayer.Character=own
own.humanoid.Health=0;assert(not check());own.humanoid.Health=100
assert(not check(true,muzzle,Vector3.new(0/0,0,0)))
assert(not check(true,muzzle,Vector3.zero),'zero-length shot is rejected')
assert(check(true),'WallCheck OFF only relaxes map geometry')
local before=rays;assert(check())
assert(rays-before==3,'a clear WallCheck costs the game-rule ray, the strict ray and the occluder probe')
local ghost,ghostPart=model(Vector3.new(10,0,0))
ghostPart.Transparency=1;ghostPart.CanCollide=false
table.insert(scene,ghostPart)
assert(isWeaponPathClear(muzzle,body.Position,victim,true,nil),
    'strict: an invisible non-collidable decoration is ignored')
ghostPart.CanCollide=true
assert(not isWeaponPathClear(muzzle,body.Position,victim,true,nil),
    'strict: an invisible solid wall still stops the knife')
assert(isWeaponPathClear(muzzle,body.Position,victim,nil,nil),
    'the gun keeps the game rule: any invisible part is skipped')
table.remove(scene)
pass('strict WallCheck: invisible decorations pass, invisible solids block')
pass('actual validateGunShot: game filter, transparent skip, walls, innocents, roles, geometry, WallCheck OFF')
'''

# Actual dispatch path, with the real validateGunShot above replaced by a switch.
code += r'''
do
local character,humanoid=own,{}
local endpoint=Vector3.new(20,0,0)
local mm2Settings={silentAim=false,shootWallCheck=true,silentSpawn='Through',silentSweep=0}
local remote={IsA=function() return true end}
local sends,queues,notes=0,0,0
remote.FireServer=function() sends+=1 end
local gun={Parent=character,Enabled=true,GetAttribute=function() return nil end}
function gun:FindFirstChild(name) return name=='Shoot' and remote or nil end
local function getCharacterParts() return character,humanoid end
local function getPlayerWeapon(_,name,equipped) assert(name=='Gun' and equipped);return gun end
local function getGunOriginCFrame() return CFrame.new(Vector3.new(0,0,-10)) end
local function getPlayerRole(p) return p.role end
local function isPlayerAlive() return true end
local function isProtectedTarget() return false end
local function macroUnequip() end
local safe=true
local function validateGunShot() if safe then return true end;return false,'blocked' end
local aimEndpoint=endpoint
local aimInfo={endpoint=endpoint,targetPosition=endpoint,capturedPosition=endpoint,velocity=Vector3.zero,
 leadSeconds=.1,model='kinematic-v51',sampleAge=0,samples=4,rtt=.1,motionSource='fit'}
local function gunAim() return aimEndpoint,aimInfo,nil end
local prediction={gunAim=gunAim}
local function buildSilentShot() return CFrame.new(Vector3.zero),CFrame.new(endpoint),2.5 end
local function bystanderOnSegment() return false end
local function isWeaponPathClear() return true end
local state={mm2ShotFeedback={queue=function() queues+=1 end,shootActive=true}}
local trajectoryCalibration={noteAuthoredShot=function() notes+=1 end}
''' + section(S, '    type FireOptions', '    local shootFeatureActive:') + r'''
assert(fireGunAtTarget(target,{whenReady=true,quiet=true}))
assert(sends==1 and queues==1 and notes==1,'normal shot sends one packet and queues feedback')
safe=false
assert(not fireGunAtTarget(target,{whenReady=true,quiet=true}))
assert(sends==1 and queues==1,'final revalidation blocks the packet')
safe=true
aimEndpoint=nil
assert(not fireGunAtTarget(target,{whenReady=true,quiet=true}))
assert(sends==1 and queues==1,'missing prediction cannot send')
aimEndpoint=endpoint
local stale={gunAim=function() return nil,nil,'stale sample' end}
local original=prediction.gunAim;prediction.gunAim=stale.gunAim
assert(not fireGunAtTarget(target,{whenReady=true,quiet=true}))
assert(sends==1,'stale sample cannot send')
prediction.gunAim=original
mm2Settings.silentAim=true
assert(fireGunAtTarget(target,{whenReady=true,quiet=true}))
assert(sends==2 and queues==2 and notes==2,'silent shot dispatches through the same guard')
buildSilentShot=function() return nil,nil,0 end
assert(not fireGunAtTarget(target,{whenReady=true,quiet=true}))
assert(sends==2,'blocked silent geometry cannot send')
gun.Enabled=false
assert(not fireGunAtTarget(target,{whenReady=true,quiet=true}))
gun.Enabled=true
pass('actual fireGunAtTarget: normal/silent packets pass the final guard; no send on stale, unsafe or blocked geometry')
end
'''
with tempfile.TemporaryDirectory() as d:
    p = Path(d) / 'safety.luau'
    p.write_text(code)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(p)], check=True)
