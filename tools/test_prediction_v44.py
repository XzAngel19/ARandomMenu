#!/usr/bin/env python3
"""Historical v43/v44 replay (archived, not the live v45 solver or hit-rate)."""
import contextlib, hashlib, io, json, os, subprocess, tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE, section
import replay_gun_prediction as replay
ROOT=Path(__file__).resolve().parents[1]
print("Historical archived prediction test; live v45 is covered by test_prediction_66d and test_gun_safety",flush=True)
archive=ROOT/'docs/prediction-baselines/v43'
for saved in (archive,ROOT/'docs/prediction-baselines/v44'):
 for name,sha in json.loads((saved/'metadata.json').read_text())['files'].items():
  assert hashlib.sha256((saved/name).read_bytes()).hexdigest()==sha
BASE=(ROOT/'docs/prediction-baselines/v44/base.lua.txt').read_text();GUN=(ROOT/'docs/prediction-baselines/v44/Shoot.lua.txt').read_text();KNIFE=(ROOT/'docs/prediction-baselines/v44/KnifeThrow.lua.txt').read_text()
script=PRELUDE+'\n'+section(BASE,'local predictionMath = {}','local lastLatencyReadAt:')+r'''
local function points(speed)
 local result={}
 for i=0,6 do table.insert(result,{at=i*.025,position=Vector3.new(speed*i*.025,0,0)}) end
 return result
end
local p=points(16);near(predictionMath.observedHorizontalVelocity(p).X,16)
assert(predictionMath.observedHorizontalVelocity(points(0))==nil)
assert(predictionMath.observedHorizontalVelocity(points(120))==nil)
assert(predictionMath.observedHorizontalVelocity({p[1],p[2],p[3]})==nil)
p[7].position=Vector3.new(40,0,0);assert(predictionMath.observedHorizontalVelocity(p)==nil)
p[7].position=Vector3.new(0/0,0,0);assert(predictionMath.observedHorizontalVelocity(p)==nil)
p=points(16);for i=4,7 do p[i].position=Vector3.new(1.2,0,0) end
assert(predictionMath.observedHorizontalVelocity(p)==nil)
local mm2Settings={predictionModel='Adaptive',shootWallCheck=false}
local workspace={Gravity=196.2}
local humanoid={Health=100,FloorMaterial='Ground',HipHeight=2,GetState=function() return 'Running' end}
local root={Position=Vector3.zero,AssemblyLinearVelocity=Vector3.zero,Size=Vector3.new(2,2,1)}
local part={Position=Vector3.zero,IsA=function() return true end}
local character={FindFirstChild=function(_,n) return n=='HumanoidRootPart' and root or part end,FindFirstChildOfClass=function() return humanoid end}
local target={Character=character};local LocalPlayer={Character={}}
local horizon=.1
local function getGunHorizonSeconds() return horizon end
'''+section(BASE,'local function getGunTurnRate','local function getGunLeadStatus')+'\n'+section(GUN,'    local BODY_HALF_WIDTH:','    local function getSelectedShootTarget')+r'''
for i=0,6 do now=i*.025;root.Position=Vector3.new(16*now,0,0);getFilteredVelocity(target,root) end
part.Position=root.Position+Vector3.new(0,.8,0)
local _,b=computeGunAim(target,CFrame.new(Vector3.new(0,0,-50)),{ignoreVisibility=true})
near(b.endpoint.X-root.Position.X,1.6);assert(b.motionSource=='position');near(b.leadSeconds,.1)
mm2Settings.predictionModel='Reference v41'
local _,a=computeGunAim(target,CFrame.new(Vector3.new(0,0,-50)),{ignoreVisibility=true})
near(a.endpoint.X,root.Position.X);near((a.endpoint-b.referenceEndpoint).Magnitude,0)
local lastKnifePrediction
local function getReadyKnife() return nil end
local function getEstimatedLatency() return .08 end
'''+section(KNIFE,'    local function predictAim','    local KNIFE_VISIBILITY_PARTS:')+r'''
local origin=Vector3.new(0,0,-48)
local reference=predictAim(target,origin)
mm2Settings.predictionModel='Adaptive';local predicted=predictAim(target,origin)
assert(lastKnifePrediction.motionSource=='position');near((lastKnifePrediction.referenceEndpoint-reference).Magnitude,0)
local flight=(predicted-origin).Magnitude/96
near(predicted.X,root.Position.X+16*(flight+.08),1e-4)
for i=7,26 do now=i*.025;getFilteredVelocity(target,root) end
assert(predictionMath.observedHorizontalVelocity(motionSamples[target].positionHistory)==nil,'stopped pose must not invent movement')
now+=.3;getFilteredVelocity(target,root);assert(#motionSamples[target].positionHistory==1)
now+=.02;root.Position=Vector3.new(100,0,0);getFilteredVelocity(target,root);assert(#motionSamples[target].positionHistory==1,'teleport resets pose history')
for _,fps in ipairs({30,60,120,240}) do
 motionSamples={};now=0;root.Position=Vector3.zero
 for i=0,fps do now=i/fps;root.Position=Vector3.new(now*16,0,0);getFilteredVelocity(target,root) end
 assert(#motionSamples[target].positionHistory<=24)
 near(predictionMath.observedHorizontalVelocity(motionSamples[target].positionHistory).X,16,1e-4)
end
pass('position-verified motion with near-zero replicated velocity: causal windows, stops/jitter/teleports, bounded history across FPS; real Gun and Knife, preserved reference and 96-stud/s intercept')
'''
with tempfile.TemporaryDirectory() as t:
 p=Path(t)/'prediction.luau';p.write_text(script);subprocess.run([os.environ.get('LUAU','luau'),str(p)],check=True)
sets={n:[ROOT/'tools/fixtures/prediction-v42'/(n+'.json')] for n in ['development','holdout','small-v34','small-v31']}
sets['v33']=[ROOT/'tools/fixtures/prediction-v44/v33.json']
report={}
for name,paths in sets.items():
 with contextlib.redirect_stdout(io.StringIO()):
  replay.BASE=(archive/'base.lua.txt').read_text();replay.SHOOT=(archive/'Shoot.lua.txt').read_text();a=replay.run(paths,candidate="Adaptive")
  replay.BASE=BASE;replay.SHOOT=GUN;b=replay.run(paths,candidate="Adaptive")
 assert a['all']['samples']==b['all']['samples']
 assert b['all']['adaptiveMAE']<=a['all']['adaptiveMAE']+1e-9,(name,a['all'],b['all'])
 assert abs(a['all']['referenceMAE']-b['all']['referenceMAE'])<1e-9
 report[name]={'samples':b['all']['samples'],'v43MAE':a['all']['adaptiveMAE'],'v44MAE':b['all']['adaptiveMAE'],'changedSamples':sum(abs(x['adaptive']-y['adaptive'])>1e-8 for x,y in zip(a['rows'],b['rows']))}
assert report['v33']['v44MAE']<report['v33']['v43MAE']
print('PASS identical-sample replay v43/v44:',json.dumps(report,sort_keys=True))
