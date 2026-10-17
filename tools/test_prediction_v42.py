#!/usr/bin/env python3
"""Real-source Adaptive solver, rollback/shadow, respawn-safe history and echo guards."""
import os,subprocess,tempfile,json,hashlib
from pathlib import Path
from test_mm2_precision import PRELUDE,section
ROOT=Path(__file__).resolve().parents[1]
BASE=(ROOT/'src/games/MM2/base.lua').read_text();GUN=(ROOT/'src/games/MM2/Blatant/Shoot.lua').read_text();KNIFE=(ROOT/'src/games/MM2/Blatant/KnifeThrow.lua').read_text()
for name,sha in json.loads((ROOT/'docs/prediction-baselines/v41/metadata.json').read_text())['files'].items():
 assert hashlib.sha256((ROOT/'docs/prediction-baselines/v41'/name).read_bytes()).hexdigest()==sha
assert KNIFE.count('remote:FireServer(')==1 and GUN.count(':FireServer(')==2
script=PRELUDE+'\n'+section(BASE,'local predictionMath = {}','local lastLatencyReadAt:')+r'''
local d,e,s=predictionMath.gunAdaptive(Vector3.new(16,0,0),Vector3.new(-160,0,0),.2,196.2,true,false)
near(d.X,.8);near(s,0)
near(predictionMath.gunAdaptive(Vector3.zero,Vector3.new(250,0,0),.2,196.2,true,false).Magnitude,0)
near(predictionMath.gunAdaptive(Vector3.new(0,0,0),Vector3.zero,.1,196.2,false,true).Y,-.981)
near(predictionMath.gunAdaptive(Vector3.new(0,0,0),Vector3.zero,.1,196.2,true,true).Y,0)
near(predictionMath.gunAdaptive(Vector3.new(0/0,0,0),Vector3.zero,.1,196.2,true,false).Magnitude,0)
local left=predictionMath.gunAdaptive(Vector3.new(16,0,0),Vector3.zero,.2,196.2,true,false,2)
local right=predictionMath.gunAdaptive(Vector3.new(16,0,0),Vector3.zero,.2,196.2,true,false,-2)
near(left.X,right.X);near(left.Z,-right.Z);assert(left.Z>0)
local offset=Vector3.new(24,10,0)
for _,floor in ipairs({-10,-3,0}) do
 local p,t=predictionMath.knifeBallisticIntercept(offset,Vector3.new(0,12,16),96,.08,196.2,floor)
 assert(p and t);near(p.Magnitude,96*t,1e-4)
 local h=t+.08;near(p.Y,offset.Y+math.max(12*h-98.1*h*h,floor),1e-4)
end
assert(predictionMath.knifeBallisticIntercept(offset,Vector3.zero,0/0,.1,196.2)==nil)
pass('bounded stop integration, no rest acceleration, apex/ground distinction, signed turns, target-ballistic intercept with landing')
local mm2Settings={predictionModel='Adaptive',shootWallCheck=false}
local velocity=Vector3.new(16,0,0)
local stateName='Running'
local humanoid={Health=100,FloorMaterial='Ground',HipHeight=2,GetState=function() return stateName end}
local root={Position=Vector3.zero,AssemblyLinearVelocity=velocity,Size=Vector3.new(2,2,1)}
local part={Position=Vector3.new(0,.8,0),IsA=function() return true end}
local character={FindFirstChild=function(_,name) return name=='HumanoidRootPart' and root or part end,FindFirstChildOfClass=function() return humanoid end}
local target={Character=character};local LocalPlayer={Character={}}
-- Replication history is bounded and excludes render-only repeats.
for _,fps in ipairs({30,60,120,240}) do
 motionSamples={};now=0
 for i=1,fps do now=i/fps;getFilteredVelocity(target,root) end
 assert(#motionSamples[target].history==1)
 for i=1,fps do now=1+i/fps;root.Position=Vector3.new(math.floor(i/fps*20),0,0);getFilteredVelocity(target,root) end
 assert(#motionSamples[target].history<=12)
 target.Character={FindFirstChildOfClass=function() return humanoid end};now+=.01;getFilteredVelocity(target,root)
 assert(#motionSamples[target].history==1,'new character resets velocity history');target.Character=character
end
local horizon=.2
local function getGunHorizonSeconds() return horizon end
local function getGunTurnRate() return 0 end
local function getGunTurnDiscount() return 1 end
local function getGunLeadSensitivity() return 1 end
local workspace={Gravity=196.2}
'''+section(GUN,'    local BODY_HALF_WIDTH:','    local function getSelectedShootTarget')+r'''
now=20;root.Position=Vector3.zero
local sample={character=character,sampledAt=now,velocity=velocity,acceleration=Vector3.new(-160,0,0),stability=1,grounded=true,
 history={{at=19.9,velocity=Vector3.new(32,0,0)},{at=19.95,velocity=Vector3.new(24,0,0)},{at=20,velocity=Vector3.new(16,0,0)}}}
motionSamples[target]=sample
local function aim(model)
 mm2Settings.predictionModel=model
 return computeGunAim(target,CFrame.new(Vector3.new(0,0,-10)),{ignoreVisibility=true,allowUncertain=true})
end
local _,b=aim('Adaptive');local _,a=aim('Reference v41')
near(b.endpoint.X,.8);near(a.endpoint.X,1.2)
near((b.referenceEndpoint-a.endpoint).Magnitude,0);near(b.leadSensitivity,0)
assert(b.model=='adaptive-v42' and a.model=='reference-v41')
velocity=Vector3.zero;root.AssemblyLinearVelocity=velocity
sample.velocity=velocity;sample.history={};sample.sampledAt=now
local _,rest=aim('Adaptive');near(rest.endpoint.X,0)
velocity=Vector3.new(16,0,0);root.AssemblyLinearVelocity=velocity;sample.velocity=velocity
sample.acceleration=Vector3.zero;horizon=.12
sample.history={}
for i=1,3 do local angle=(i-3)*.12;table.insert(sample.history,{at=now+(i-3)*.02,velocity=Vector3.new(16*math.cos(angle),0,16*math.sin(angle))}) end
local _,turn=aim('Adaptive');assert(turn.endpoint.Z>.35 and turn.referenceEndpoint.Z==0 and turn.leadSensitivity==0)
-- Adaptive uncertainty is telemetry, never a distance/motion fire gate.
horizon=.2;velocity=Vector3.new(100,0,0);root.AssemblyLinearVelocity=velocity;sample.velocity=velocity;sample.acceleration=Vector3.new(250,0,0);sample.stability=0;sample.history={}
mm2Settings.predictionModel='Adaptive'
assert(computeGunAim(target,CFrame.new(Vector3.new(0,0,-1000)),{ignoreVisibility=true})~=nil)
pass('actual Gun: supported braking/turns, archived A shadow endpoint, rest guard, reversible model, no uncertainty distance gate')
'''+ '\nlocal archivedReference=(function()\n'+section((ROOT/'docs/prediction-baselines/v41/Shoot.lua.txt').read_text(),'    local BODY_HALF_WIDTH:','    local function getSelectedShootTarget')+'\nreturn computeGunAim end)()\n'+r'''

for _,h in ipairs({.025,.1,.25}) do
 horizon=h
 for _,v in ipairs({Vector3.zero,Vector3.new(16,0,0),Vector3.new(12,25,-4),Vector3.new(2,-20,10)}) do
  for _,acc in ipairs({Vector3.zero,Vector3.new(-160,0,20),Vector3.new(250,0,-80)}) do
   velocity=v;root.AssemblyLinearVelocity=v;sample.velocity=v;sample.acceleration=acc;sample.sampledAt=now
   for _,st in ipairs({'Running','Jumping','Freefall'}) do
    stateName=st;sample.grounded=st=='Running';mm2Settings.predictionModel='Reference v41'
    local _,current=computeGunAim(target,CFrame.new(Vector3.new(0,0,-50)),{ignoreVisibility=true,allowUncertain=true})
    local _,archived=archivedReference(target,CFrame.new(Vector3.new(0,0,-50)),{ignoreVisibility=true,allowUncertain=true})
    near((current.endpoint-archived.endpoint).Magnitude,0)
   end
  end
 end
end
pass('Reference v41 matches immutable archived Gun math over 108 motion/state/horizon cases')
-- Real Knife predictAim, not just a copied equation.
local lastKnifePrediction=nil
local function getReadyKnife() return nil end
local function getEstimatedLatency() return .08 end
velocity=Vector3.new(16,10,0);root.AssemblyLinearVelocity=velocity;root.Position=Vector3.new(20,10,0)
stateName='Freefall';humanoid.FloorMaterial='Air'
workspace.Raycast=function() return {Position=Vector3.zero} end
local RaycastParams={new=function() return {} end}
'''+section(KNIFE,'    local function predictAim','    local KNIFE_VISIBILITY_PARTS:')+r'''
mm2Settings.predictionModel='Reference v41';local ka=predictAim(target,Vector3.zero)
mm2Settings.predictionModel='Adaptive';local kb=predictAim(target,Vector3.zero)
assert(ka and kb and kb.Y<ka.Y and kb.Y>=3)
local t=kb.Magnitude/96;local total=t+.08
near(kb.X,20+16*total,1e-4);near(kb.Y,10+math.max(10*total-98.1*total*total,-7),1e-4)
near((lastKnifePrediction.referenceEndpoint-ka).Magnitude,0)
pass('actual Knife: linear blade intercepts ballistic target/landing; A shadow and rollback; same release-time path for PC/mobile')
local function typeof(v) if getmetatable(v)==mt then return 'Vector3' end;return type(v)=='table' and v.instance and 'Instance' or type(v) end
local gun={instance=true,IsA=function(_,c) return c=='Tool' end,IsDescendantOf=function(self,g) return self==g end}
local state={mm2ShotFeedback={shootActive=true,toPosition=function(v) return v end}}
local resolved=0;state.mm2ShotFeedback.resolve=function() resolved+=1 end
'''+section(BASE,'state.mm2ShotFeedback.handleGunFired = function(', 'type KnifeSettings = {')+r'''
local candidate={gun=gun,queuedAt=now,origin=Vector3.zero,aimPosition=Vector3.new(10,0,0)}
state.mm2ShotFeedback.pending=candidate
state.mm2ShotFeedback.handleGunFired(gun,Vector3.zero,Vector3.new(0,0,10),nil)
assert(resolved==0 and state.mm2ShotFeedback.pending==candidate,'matching Tool never bypasses direction check')
state.mm2ShotFeedback.handleGunFired(gun,Vector3.new(20,0,0),Vector3.new(30,0,0),nil)
assert(resolved==0 and state.mm2ShotFeedback.pending==candidate,'matching Tool never bypasses origin check')
candidate.ambiguous=true
state.mm2ShotFeedback.handleGunFired(gun,Vector3.zero,Vector3.new(10,0,0),nil)
assert(resolved==0 and not state.mm2ShotFeedback.pending,'ambiguous rapid attempts cannot train or count as hits')
candidate.ambiguous=false;state.mm2ShotFeedback.pending=candidate
state.mm2ShotFeedback.handleGunFired(gun,Vector3.zero,Vector3.new(10,0,0),nil);assert(resolved==1)
pass('server echo geometry guards and explicit exclusion of ambiguous rapid attempts')
'''
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp)/'test.luau';p.write_text(script);subprocess.run([os.environ.get('LUAU','luau'),str(p)],check=True)
