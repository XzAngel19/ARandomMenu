#!/usr/bin/env python3
"""Replay actual A/B Gun functions against client trajectory windows (not server hits)."""
import argparse,json,os,subprocess,tempfile,hashlib
from pathlib import Path
from test_mm2_precision import PRELUDE, section
ROOT=Path(__file__).resolve().parents[1]
BASE=(ROOT/'src/games/MM2/base.lua').read_text(); SHOOT=(ROOT/'src/games/MM2/Blatant/Shoot.lua').read_text()
def lua(v):
 if isinstance(v,dict):return '{'+','.join('['+json.dumps(str(k))+']='+lua(x) for k,x in v.items())+'}'
 if isinstance(v,list):return '{'+','.join(lua(x) for x in v)+'}'
 if isinstance(v,str):return json.dumps(v)
 if isinstance(v,bool):return 'true' if v else 'false'
 if v is None:return 'nil'
 return str(v)
def run(paths,output=None,candidate="66d"):
 if candidate=="Adaptive" and "local adaptive =" not in SHOOT:raise ValueError("Adaptive is archived, not a live model")
 windows={}
 for path in paths:
  data=json.loads(path.read_text())
  for event in data.get('session',{}).get('events',[]):
   points=event.get('targetTrajectory',[])
   if len(points)<4:continue
   key=str(data.get('sessionId',''))+str(event.get('shotId'))
   if key not in windows or len(windows[key]['points'])<len(points):windows[key]={'id':key,'points':points,'ping':event.get('pingMs',80),'kind':event.get('kind')}
 code=PRELUDE+'\n'+section(BASE,'local predictionMath = {}','local lastLatencyReadAt:')+r'''
local mm2Settings={shootWallCheck=false}
local workspace={Gravity=196.2}
local velocity=Vector3.zero
local humanoid={Health=100,FloorMaterial='Ground',HipHeight=2,MoveDirection=Vector3.zero,WalkSpeed=16}
local stateName='Running'
function humanoid:GetState() return stateName end
local root={Position=Vector3.zero,Size=Vector3.new(2,2,1)}
local part={Position=Vector3.zero,IsA=function() return true end}
local character={FindFirstChild=function(_,n) if n=='HumanoidRootPart' then return root end;return part end,FindFirstChildOfClass=function() return humanoid end}
local target={Character=character};local LocalPlayer={Character={}}
local horizon=.1
local function getGunHorizonSeconds() return horizon end
'''+section(BASE,'local function getGunTurnRate','local function getGunLeadStatus')+'\n'+section(SHOOT,'    local BODY_HALF_WIDTH:','    local function getSelectedShootTarget')+'\nlocal candidate='+lua(candidate)+'\nlocal windows='+lua(list(windows.values()))+r'''
local count=0
for wi,window in ipairs(windows) do
 motionSamples={};horizon=math.min(window.ping/1000,.15)
 for i,p in ipairs(window.points) do
  now=100+p.dt;root.Position=Vector3.new(unpack(p.position));root.AssemblyLinearVelocity=Vector3.new(unpack(p.velocity))
  part.Position=root.Position+Vector3.new(0,.8,0);stateName=p.humanoidState
  Enum.HumanoidStateType.Jumping='Jumping';Enum.HumanoidStateType.Freefall='Freefall'
  humanoid.FloorMaterial=p.grounded and 'Ground' or 'Air'
  getFilteredVelocity(target,root)
  local desired=p.dt+horizon
  local truth
  for j=i+1,#window.points do
   local b=window.points[j];local a=window.points[j-1]
   if b.dt>=desired and b.dt>a.dt then
    local x=(desired-a.dt)/(b.dt-a.dt)
    truth=Vector3.new(unpack(a.position))*(1-x)+Vector3.new(unpack(b.position))*x+Vector3.new(0,.8,0);break
   end
  end
  if truth then
   local errors={}
   for _,model in ipairs({'Reference v41',candidate}) do
    mm2Settings.predictionModel=model
    local _,pred=computeGunAim(target,CFrame.new(root.Position+Vector3.new(0,0,-50)),{ignoreVisibility=true,allowUncertain=true})
    assert(pred and pred.endpoint.X==pred.endpoint.X)
    errors[model]=(pred.endpoint-truth).Magnitude
   end
   count+=1
   print(string.format('ROW\t%d\t%d\t%.9f\t%.9f',wi,i,errors['Reference v41'],errors[candidate]))
  end
 end
end
assert(count>0,'no replayable client windows')
'''
 with tempfile.TemporaryDirectory() as t:
  p=Path(t)/'replay.luau';p.write_text(code);result=subprocess.check_output([os.environ.get('LUAU','luau'),str(p)],text=True)
 rows=[]
 for line in result.splitlines():
  if line.startswith('ROW\t'):
   _,w,i,a,b=line.split('\t');rows.append({'window':int(w),'sample':int(i),'reference':float(a),'adaptive':float(b)})
 def summary(rs):
  return {'samples':len(rs),'referenceMAE':sum(r['reference'] for r in rs)/len(rs) if rs else None,'adaptiveMAE':sum(r['adaptive'] for r in rs)/len(rs) if rs else None}
 report={'candidateModel':candidate,'sources':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},'windows':len(windows),'all':summary(rows),'oddWindows':summary([r for r in rows if r['window']%2]),'evenWindows':summary([r for r in rows if not r['window']%2]),'byRecordedKind':{str(kind):summary([r for r in rows if list(windows.values())[r['window']-1]['kind']==kind]) for kind in sorted(set(w['kind'] for w in windows.values()),key=str)},'rows':rows,'limits':'Client-observed future pose only, same RTT hypothesis for A/B, default gravity, no map floor geometry, no server hit-rate or rewind inference; fixed final model; development variants were inspected, no per-shot fitting. Legacy adaptiveMAE field denotes the selected candidate. MoveDirection unavailable in poses, assumed zero.'}
 if output:output.write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps({k:v for k,v in report.items() if k!='rows'},indent=2))
 return report
if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('files',nargs='+',type=Path);ap.add_argument('--output',type=Path);ap.add_argument('--candidate',choices=['66d','Reference v41'],default='66d');a=ap.parse_args();run(a.files,a.output,a.candidate)
