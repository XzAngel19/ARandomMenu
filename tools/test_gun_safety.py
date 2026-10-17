#!/usr/bin/env python3
"""Actual final-send guard and gun ray against dynamic deterministic geometry. Not Roblox server validation."""
import os,subprocess,tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE,section
ROOT=Path(__file__).resolve().parents[1]
B=(ROOT/'src/games/MM2/base.lua').read_text();S=(ROOT/'src/games/MM2/Blatant/Shoot.lua').read_text()
code=PRELUDE+r'''
local predictionMath={finite=function(n) return type(n)=='number' and n==n and math.abs(n)<math.huge end}
local function cf(p,angle)
 local c,s=math.cos(angle or 0),math.sin(angle or 0)
 return {Position=p,RightVector=Vector3.new(c,0,s),UpVector=Vector3.new(0,1,0),PointToObjectSpace=function(_,v) v=v-p;return Vector3.new(c*v.X+s*v.Z,v.Y,-s*v.X+c*v.Z) end,
 VectorToObjectSpace=function(_,v) return Vector3.new(c*v.X+s*v.Z,v.Y,-s*v.X+c*v.Z) end}
end
local function model(pos)
 local m={parts={},humanoid={Health=100}}
 function m:FindFirstChildOfClass(k) return k=="Humanoid" and self.humanoid or nil end
 local part={Position=pos,Size=Vector3.new(2,2,2),CFrame=cf(pos),AssemblyLinearVelocity=Vector3.zero,CanQuery=true,Transparency=0}
 function part:IsA(k) return k=='BasePart' end
 function part:IsDescendantOf(o) return o==m end
 table.insert(m.parts,part)
 function m:GetBoundingBox() return part.CFrame,part.Size end
 function m:GetDescendants() return self.parts end
 function m:FindFirstChild(k) return k=='HumanoidRootPart' and part or nil end
 return m,part
end
local own=model(Vector3.new(-3,0,0));local victim,body=model(Vector3.new(20,0,0));local friendly,friend=model(Vector3.new(10,10,0))
local CollectionService={GetTagged=function() return {} end}
local LocalPlayer={Character=own};local target={Character=victim,role='Murderer',alive=true};local innocent={Character=friendly,role='Innocent',alive=true}
local roster={LocalPlayer,target,innocent};local Players={GetPlayers=function() return roster end}
local function isPlayerAlive(p) return p.alive end
local function isProtectedTarget(p) return p.protected end
local function getPlayerRole(p) return p.role end
local roundLifecycleActive=true
local function getRoundRole(p) if p.unknownRound then return nil end;return p.roundRole or p.role end
local function getPlayerWeapon(p) return p.knife end
local function hasMurdererCollisionGroup(m) return m.murdererGroup end
local function getEstimatedLatency() return .08 end
local RaycastParams={new=function() return {} end}
local scene={body,friend};local rays=0
-- Independent axis-aligned engine-ray mock. Query-disabled parts are ignored;
-- starting inside a part does not count as a hit (important for Silent origins).
local function entry(p,o,delta)
 local lo,hi=0,1;local inside=true
 for _,a in ipairs({'X','Y','Z'}) do
  local low,high=p.Position[a]-p.Size[a]/2,p.Position[a]+p.Size[a]/2
  inside=inside and o[a]>low and o[a]<high
  if math.abs(delta[a])<1e-8 then if o[a]<low or o[a]>high then return end
  else local x,y=(low-o[a])/delta[a],(high-o[a])/delta[a];lo=math.max(lo,math.min(x,y));hi=math.min(hi,math.max(x,y));if lo>hi then return end end
 end
 if not inside then return lo end
end
local workspace={Raycast=function(_,origin,delta,params)
 rays+=1;local nearest,hit=math.huge,nil
 for _,part in ipairs(scene) do
  local listed=false;for _,m in ipairs(params.FilterDescendantsInstances) do if part:IsDescendantOf(m) then listed=true end end
  if part.CanQuery and (params.FilterType=='Include' and listed or params.FilterType=='Exclude' and not listed) then
   local t=entry(part,origin,delta);if t and t<nearest then nearest,hit=t,part end
  end
 end
 return hit and {Instance=hit} or nil
end}
'''+section(B,'-- Gun rays deliberately','local function disconnectGunFiredObserver')+r'''
local muzzle=Vector3.zero;local endpoint=Vector3.new(20,0,0)
local function check(walls,origin,finish)
 return validateGunShot(target,own,victim,muzzle,origin or muzzle,finish or endpoint,walls~=false,.1)
end
local function move(part,pos) part.Position=pos;part.CFrame=cf(pos) end
assert(check());assert(rays==1)
local wall,wallPart=model(Vector3.new(10,0,0));table.insert(scene,wallPart)
assert(not check());wallPart.Transparency=1;assert(check(),'game WeaponService filter skips Transparency==1 geometry')
assert(check(false),'WallCheck OFF only relaxes map geometry')
wallPart.CanQuery=false
move(friend,Vector3.new(10,0,0));assert(not check(),'normal path must reject an innocent before the murderer')
friend.CanQuery=false;assert(not check(),'CanQuery=false must not bypass friendly safety')
move(friend,Vector3.new(30,0,0));assert(not check(),'an innocent behind the target/endpoint still blocks a possible miss')
friend.Transparency=1;assert(not check())
move(friend,Vector3.new(10,2.6,0));friend.AssemblyLinearVelocity=Vector3.new(0,-16,0)
assert(not check(),'buffer a moving bystander entering the line during latency')
move(friend,Vector3.new(10,8,0));friend.AssemblyLinearVelocity=Vector3.new(0,-100,0);assert(not check(),'fast bystander reach must not be capped at three studs')
friend.AssemblyLinearVelocity=Vector3.zero;move(friend,Vector3.new(10,10,0));assert(check(),'next fresh check immediately sees clear geometry')
assert(not check(true,nil,Vector3.new(20,0,10)),'empty-air lead is not a target hit')
assert(check(true,Vector3.new(18,0,0)))
wallPart.Transparency=0;wallPart.CanQuery=true;assert(not check(true,Vector3.new(18,0,0)),'Silent cannot bypass WallCheck at the muzzle')
wallPart.CanQuery=false
assert(not check(true,Vector3.new(20,0,0),Vector3.new(20.2,0,0)),'inside-body silent origins are not proof of intersection')
roundLifecycleActive=false;assert(not check());roundLifecycleActive=true
target.roundRole='Innocent';assert(not check(),'fresh round role overrides a stale murderer cache');target.roundRole=nil
target.unknownRound=true;assert(not check(),'cached murderer without current evidence is rejected');target.knife={};assert(check());target.knife=nil;target.unknownRound=nil
target.role='Innocent';assert(not check());target.role=nil;assert(not check());target.role='Murderer'
target.protected=true;assert(not check());target.protected=nil
target.alive=false;assert(not check());target.alive=true
target.Character=model(Vector3.new(20,0,0));assert(not check());target.Character=victim
LocalPlayer.Character={};assert(not check());LocalPlayer.Character=own
assert(not check(true,nil,Vector3.new(0/0,0,0)))
near(gunBoxEntry(Vector3.zero,Vector3.new(1,0,0),cf(Vector3.new(10,0,0),math.pi/4),Vector3.new(2,2,2),0),10-math.sqrt(2))
assert(gunBoxEntry(Vector3.zero,Vector3.new(1,0,0),cf(Vector3.new(10,5,0)),Vector3.new(2,2,2),0)==nil)
pass('actual core guard: dynamic walls, transparent/query-disabled players, beyond-endpoint innocents, latency buffer, both origins, roles/protection/death/respawn, empty air and rotated OBB')
-- Actual solver plus actual final guard: an open primary shot uses two rays,
-- and closing/reopening cover is seen by the very next attempt, without a cache.
do
 local mm2Settings={predictionModel='66d',shootWallCheck=true}
 local humanoid=victim.humanoid
 humanoid.MoveDirection=Vector3.zero;humanoid.WalkSpeed=16;humanoid.FloorMaterial='Ground';humanoid.GetState=function() return 'Running' end
 local sample={character=victim,sampledAt=now,grounded=true,stability=1,acceleration=Vector3.zero}
 local motionSamples={[target]=sample}
 local function getFilteredVelocity() return Vector3.zero end
 local function isMotionGrounded() return true end
 local function getGunHorizonSeconds() return .1 end
 local function getGunTurnRate() return 0 end
 local function getGunTurnDiscount() return 1 end
 local function getGunLeadSensitivity() return 1 end
 local function isWeaponPathClear(a,b,c,required) return isGunPathClear(a,b,c,required) end
''' + section(S,'    local BODY_HALF_WIDTH:','    local function getSelectedShootTarget') + r'''

 local before=rays
 local _,prediction=computeGunAim(target,CFrame.new(muzzle),{allowUncertain=true})
 assert(prediction and check());assert(rays-before==2,'common clear normal path: 1 solve ray + 1 final ray')
 wallPart.CanQuery=true;before=rays
 assert(computeGunAim(target,CFrame.new(muzzle),{allowUncertain=true})==nil)
 assert(rays-before<=64,'blocked probe work must remain bounded')
 wallPart.CanQuery=false
 assert(computeGunAim(target,CFrame.new(muzzle),{allowUncertain=true}))
 print('PASS live solver/guard: two-ray open normal path, bounded blocked search, no remembered peek')
end
-- Execute the real send function as well: no safety rejection can enqueue or send.
local character,humanoid=own,{}
local mm2Settings={silentAim=false,shootWallCheck=true,motionSampleHz=60,gunLeadBias=0,silentSpawn='Through'}
local remote={IsA=function() return true end}
local sends,notes,queues=0,0,0
remote.FireServer=function() sends+=1 end
local gun={Parent=own,Enabled=true,GetAttribute=function() return nil end,FindFirstChild=function() return remote end}
local function getCharacterParts() return character,humanoid end
local function getPlayerWeapon() return gun end
local function getGunOriginCFrame() return CFrame.new(muzzle) end
local duringCompute
local function computeGunAim()
 if duringCompute then duringCompute() end
 return CFrame.new(endpoint),{endpoint=endpoint,targetPosition=endpoint,velocity=Vector3.zero,errorRadius=0,leadSeconds=.1}
end
local function buildSilentShot() return CFrame.new(Vector3.new(18,0,0)),CFrame.new(endpoint),0 end
local function notify() end
local function macroUnequip() end
local state={mm2ShotFeedback={queue=function() queues+=1 end}}
local trajectoryCalibration={noteAuthoredShot=function() notes+=1 end}
local core={validateGunShot=validateGunShot,isGunPathClear=isGunPathClear}
'''+section(S,'    type FireOptions','    local shootFeatureActive:')+r'''
assert(fireGunAtTarget(target,{whenReady=true,quiet=true}));assert(sends==1 and notes==1 and queues==1)
move(friend,Vector3.new(30,0,0));assert(not fireGunAtTarget(target,{whenReady=true,quiet=true}));assert(sends==1 and queues==1)
mm2Settings.silentAim=true;assert(not fireGunAtTarget(target,{whenReady=true,quiet=true}));assert(sends==1)
move(friend,Vector3.new(30,10,0));wallPart.CanQuery=true
assert(not fireGunAtTarget(target,{whenReady=true,quiet=true}));assert(sends==1)
wallPart.CanQuery=false;assert(fireGunAtTarget(target,{whenReady=true,quiet=true}));assert(sends==2)
target.role='Innocent';assert(not fireGunAtTarget(target,{whenReady=true,quiet=true}));assert(sends==2);target.role='Murderer'
duringCompute=function() target.role='Innocent' end
assert(not fireGunAtTarget(target,{whenReady=true,quiet=true}));assert(sends==2);target.role='Murderer'
duringCompute=function() wallPart.CanQuery=true end
assert(not fireGunAtTarget(target,{whenReady=true,quiet=true}));assert(sends==2);wallPart.CanQuery=false
duringCompute=function() own.humanoid.Health=0 end
assert(not fireGunAtTarget(target,{whenReady=true,quiet=true}));assert(sends==2);own.humanoid.Health=100
duringCompute=function() error('geometry unavailable') end
assert(not fireGunAtTarget(target,{whenReady=true,quiet=true}));assert(sends==2)
duringCompute=nil
core.validateGunShot=function() error('raycast failed') end
assert(not fireGunAtTarget(target,{whenReady=true,quiet=true}));assert(sends==2)
pass('actual normal/Silent FireServer paths: final revalidation, no packet/feedback on unsafe geometry or exceptions; no arbitrary range/time gate')
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'safety.luau';p.write_text(code);subprocess.run([os.environ.get('LUAU','luau'),str(p)],check=True)
