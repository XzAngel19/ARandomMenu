#!/usr/bin/env python3
"""Live Gun rollback vs unmodified 66d / v41 equations on equal inputs. No live hit-rate claim."""
import hashlib,json,os,subprocess,tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE,section
ROOT=Path(__file__).resolve().parents[1]
S=(ROOT/'src/games/MM2/Blatant/Shoot.lua').read_text();B=(ROOT/'src/games/MM2/base.lua').read_text()
archive=ROOT/'docs/prediction-baselines/66d'
old=(archive/'computeGunAim.lua.txt').read_text();assert hashlib.sha256(old.encode()).hexdigest()==json.loads((archive/'metadata.json').read_text())['sectionSHA256']
script=PRELUDE+r'''
local mm2Settings={predictionModel='66d',shootWallCheck=false,gunLeadBias=0}
local velocity=Vector3.zero
local workspace={Gravity=196.2}
local root={Position=Vector3.zero,Size=Vector3.new(2,2,1)}
local part={Position=Vector3.new(0,.8,0),IsA=function() return true end}
local humanoid={Health=100,FloorMaterial='Ground',MoveDirection=Vector3.zero,WalkSpeed=16,GetState=function() return 'Running' end}
local character={FindFirstChild=function(_,n) return n=='HumanoidRootPart' and root or part end,FindFirstChildOfClass=function() return humanoid end}
local target={Character=character};local LocalPlayer={Character={}}
local sample={character=character,grounded=true,sampledAt=0,acceleration=Vector3.zero,stability=1,turnRate=0}
local motionSamples={[target]=sample}
local function getFilteredVelocity() return velocity end
local GUN_LEAD={defaultTurnRate=math.pi*.5,maxTurnRate=math.pi*1.5}
local function isMotionGrounded(h,v) return h.FloorMaterial~='Air' and math.abs(v.Y)<=6 end
local horizon=.1
local function getGunHorizonSeconds() return horizon end
'''+section(B,'local function getGunTurnRate','local function getGunLeadStatus')+'\n'+section(S,'    local BODY_HALF_WIDTH:','    local function getSelectedShootTarget')+'\nlocal old=(function()\n'+r'''
local function getGunTurnRate(stability)
 return type(stability)=='number' and math.clamp((1-math.clamp(stability,0,1))*6,0,math.pi*1.5) or math.pi*.5
end
'''+old+'\nreturn computeGunAim end)()\n'+r'''
local count=0
for _,h in ipairs({.025,.1,.25,.45}) do
 horizon=h
 for _,v in ipairs({Vector3.zero,Vector3.new(16,0,0),Vector3.new(12,25,-4),Vector3.new(2,-20,10)}) do
  velocity=v
  for _,a in ipairs({Vector3.zero,Vector3.new(-160,0,20),Vector3.new(250,0,-80)}) do
   sample.acceleration=a
   for _,stability in ipairs({0,.5,1}) do
    sample.stability=stability
    for _,ground in ipairs({true,false}) do
     sample.grounded=ground;humanoid.FloorMaterial=ground and 'Ground' or 'Air'
     for _,intent in ipairs({Vector3.zero,Vector3.new(1,0,0)}) do
      humanoid.MoveDirection=intent
      local _,actual=computeGunAim(target,CFrame.new(Vector3.new(0,0,-50)),{ignoreVisibility=true,allowUncertain=true})
      local _,expected=old(target,CFrame.new(Vector3.new(0,0,-50)),{ignoreVisibility=true,bodyHalfWidth=1000})
      assert(actual and expected);near((actual.endpoint-expected.endpoint).Magnitude,0,1e-7)
      near(actual.leadSeconds,expected.leadSeconds,1e-7);assert(actual.model=='classic-66d');count+=1
     end
    end
   end
  end
 end
end
print('PASS current Gun equals archived 66d equation on',count,'motion/ground/intent/horizon cases; safety is separate')
'''+ '\nlocal reference=(function()\n'+section((ROOT/'docs/prediction-baselines/v41/Shoot.lua.txt').read_text(),'    local BODY_HALF_WIDTH:','    local function getSelectedShootTarget')+'\nreturn computeGunAim end)()\n'+r'''
mm2Settings.predictionModel='Reference v41';count=0
for _,h in ipairs({.025,.1,.25}) do
 horizon=h
 for _,v in ipairs({Vector3.zero,Vector3.new(16,0,0),Vector3.new(12,25,-4),Vector3.new(2,-20,10)}) do
  velocity=v
  for _,a in ipairs({Vector3.zero,Vector3.new(-160,0,20),Vector3.new(250,0,-80)}) do
   sample.acceleration=a
   local _,actual=computeGunAim(target,CFrame.new(Vector3.new(0,0,-50)),{ignoreVisibility=true,allowUncertain=true})
   local _,expected=reference(target,CFrame.new(Vector3.new(0,0,-50)),{ignoreVisibility=true,allowUncertain=true})
   near((actual.endpoint-expected.endpoint).Magnitude,0);count+=1
  end
 end
end
print('PASS live Reference v41 remains unchanged on',count,'equal-input cases')
local rtt=.08
local function getEstimatedLatency() return rtt end
local correction=0
local function getActiveAutoLeadCorrection() return correction end
local trajectoryCalibration
local predictionMath={finite=function(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end}
local GUN_LEAD={maximumManualBias=.15,maximumAutoCorrection=.1,minimumHorizon=0,maximumHorizon=.25}
'''+section(B,'local function getGunHorizonSeconds():','local function getGunTurnRate')+r'''
mm2Settings.predictionModel='66d';near(getGunHorizonSeconds(),.2+1/30)
trajectoryCalibration={getEstimates=function() return {confirmedShots=2,gunAcceptanceMs=120} end}
near(getGunHorizonSeconds(),.12+1/30)
trajectoryCalibration=nil;rtt=1;near(getGunHorizonSeconds(),.45)
mm2Settings.predictionModel='Reference v41';rtt=.08;near(getGunHorizonSeconds(),.08)
print('PASS legacy timing fallback/calibration/caps, without changing Reference v41 timing')
'''
# Current UI has no Adaptive selection; old files are archived, not live evidence.
assert '"66d", "Reference v41"' in (ROOT/'src/games/MM2/Other/TrajectoryCalibration.lua').read_text()
assert 'local adaptive =' not in S
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'classic.luau';p.write_text(script);subprocess.run([os.environ.get('LUAU','luau'),str(p)],check=True)
