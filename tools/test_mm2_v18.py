#!/usr/bin/env python3
"""Actual-source v18 regressions; no claim of in-game hit rate."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
sys.dont_write_bytecode = True
from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
BASE = (ROOT / 'src/games/MM2/base.lua').read_text()
SHOOT = (ROOT / 'src/games/MM2/Blatant/Shoot.lua').read_text()

def build():
    return '\n'.join([PRELUDE, section(BASE, 'local predictionMath = {}', 'type MotionSample'), r'''
do
local workspace={Gravity=196.2}
local mm2Settings={shootWallCheck=false,gunLeadBias=0,gunMotionModel="Classic 66d",manualErrorGate=false}
local function getEstimatedLatency() return .18 end
''', section(BASE, 'local GUN_LEAD =', 'local function getGunOriginCFrame'), r'''
local velocity=Vector3.new(16,0,0)
local humanoid={Health=100,FloorMaterial="Ground",MoveDirection=Vector3.new(0,0,1),WalkSpeed=16,GetState=function() return "Running" end}
local root={Position=Vector3.zero}
local part={Position=Vector3.new(0,.8,0),IsA=function() return true end}
local character={FindFirstChild=function(_,name) return name=="HumanoidRootPart" and root or part end,FindFirstChildOfClass=function() return humanoid end}
local target={Name="target",Character=character}
local sample={character=character,sampledAt=now,sampleInterval=1/120,acceleration=Vector3.zero,stability=1,classicStability=1}
local motionSamples={[target]=sample}
local function getFilteredVelocity() return velocity end
local function isWeaponPathClear() return true end
local floorY=nil
local function getLandingRootY() return floorY end
''', section(SHOOT, '    local BODY_HALF_WIDTH:', '    local function getSelectedShootTarget'), r'''
local origin=CFrame.new(Vector3.new(0,0,-20))
for _,similarity in ipairs({1,.999,.95,.8,0,-.5}) do
    sample.stability=similarity; sample.classicStability=math.clamp(similarity,0,1)
    local _,p=computeGunAim(target,origin)
    near(p.snapshot.turnRate,math.clamp((1-math.clamp(similarity,0,1))*6,0,math.pi*1.5))
    near(p.snapshot.horizon,7/30)
end
mm2Settings.gunTimingModel="RTT"
near(getGunHorizonSeconds(),.18+1/30)
mm2Settings.gunTimingModel="V17 floor"
near(getGunHorizonSeconds(),.2+1/30)
pass("Classic 66d motion formula, safe RTT and selectable legacy floor")
sample.stability=.8;sample.classicStability=.8
mm2Settings.gunMotionModel="V17"
local _,v17=computeGunAim(target,origin)
assert(v17.errorRadius>1)
mm2Settings.manualErrorGate=true
local held,_,reason=computeGunAim(target,origin)
assert(held==nil and reason=="turning too hard")
mm2Settings.manualErrorGate=false
assert(computeGunAim(target,origin)~=nil)
pass("manual uncertainty hold is optional; best-effort does not change the error estimate")
mm2Settings.gunMotionModel="Intent blend"
local _,blend=computeGunAim(target,origin)
near(blend.endpoint.X,8*7/30);near(blend.endpoint.Z,8*7/30)
near(blend.leadSeconds,7/30);near(blend.leadSensitivity,1)
assert(blend.snapshot.measuredVelocity[1]==16 and blend.snapshot.usedVelocity[1]==8)
velocity=Vector3.zero
local _,still=computeGunAim(target,origin)
near(still.endpoint.X,0);near(still.endpoint.Z,0) -- stale intent cannot start a stopped target
velocity=Vector3.new(16,10,0)
local _,jump=computeGunAim(target,origin)
near(jump.endpoint.Y,.8+10*7/30-.5*196.2*(7/30)^2)
pass("experimental blend uses measured speed, preserves vertical physics, records exact inputs")
velocity=Vector3.new(16,-15,0)
mm2Settings.gunLandingGuard=true;floorY=-2
local _,land=computeGunAim(target,origin)
near(land.endpoint.Y,-1.2)
assert(land.snapshot.landingRootY==-2)
floorY=nil
local _,fall=computeGunAim(target,origin)
assert(fall.endpoint.Y < land.endpoint.Y)
mm2Settings.gunLandingGuard=false
pass("actual solver clamps descending aim to observed floor; no floor keeps ballistic fall")

-- Run the actual send path, not a mock of its gate/counters.
local diagnostics={checks=0,sentNormal=0,sentSilent=0,rejected={}}
local state={mm2ShotFeedback={queue=function() end}}
local notify=function() end
local function setWeaponStatus() end
local LocalPlayer={FindFirstChildOfClass=function() return nil end}
local sends,notes=0,{}
local remote={IsA=function() return true end,FireServer=function() sends+=1 end}
local gun={Name="Gun",Parent=character,Enabled=true,GetAttribute=function() return nil end,FindFirstChild=function() return remote end}
local function getCharacterParts() return character,humanoid end
local function getPlayerWeapon() return gun end
local function getGunOriginCFrame() return origin end
local function buildSilentShot() return origin,CFrame.new(Vector3.new(20,0,20)),0 end
local trajectoryCalibration={noteAuthoredShot=function(_,info) table.insert(notes,info) end}
local function macroUnequip() end
''', section(SHOOT, '    local lastRejectReason:', '    local shootFeatureActive:'), r'''
velocity=Vector3.new(16,0,0)
mm2Settings.gunMotionModel="V17"
assert(not fireGunAtTarget(target,{maxError=.6,quiet=true}))
assert(sends==0 and diagnostics.checks==1)
assert(fireGunAtTarget(target,{quiet=true}))
assert(sends==1 and diagnostics.sentNormal==1 and #notes==1)
assert(notes[1].settings.prediction.model=="V17")
assert(fireGunAtTarget(target,{silent=true,quiet=true}))
assert(diagnostics.sentSilent==1 and #notes==2)
gun.Enabled=false
assert(not fireGunAtTarget(target,{quiet=true}))
assert(sends==2 and #notes==2)
gun.Enabled=true;remote.FireServer=function() error("transport") end
assert(not fireGunAtTarget(target,{quiet=true}))
assert(diagnostics.sentNormal==1 and diagnostics.sentSilent==1)
assert(diagnostics.rejected["Shot accuracy is too low to fire."]==1)
pass("actual Auto max-error remains enforced; manual/Normal/Silent counters and send failure semantics")
end

do
local runtime={timedOutAttempts=0}
local MAX_PENDING_AGE=2.5
local records={}
local function appendEvent(e) table.insert(records,e) end
local function finalizeGunCapture() error("unconfirmed cannot finalize a signal") end
local function vectorArray(v) return {v.X,v.Y,v.Z} end
local workspace={GetServerTimeNow=function() return now end}
local compactPending
''', section(BASE, '    compactPending = function(', '    local function vectorFromArray('), r'''
now=3
local trajectory={{dt=.1,position={1,2,3}}}
local queue={{kind="gun",activatedAt=0,attemptCounted=true,shotId="test",pingMs=180,
    origin=Vector3.zero,requestedAim=Vector3.new(1,2,3),targetTrajectory=trajectory}}
compactPending(queue,now)
assert(#queue==0 and records[1].phase=="unconfirmed")
assert(records[1].targetTrajectory==trajectory and records[1].aim[2]==2)
assert(records[1].hitTarget==nil and runtime.timedOutAttempts==1)
pass("expired attempts retain trajectory and geometry without invented hit/miss labels")
end
do
Enum.HumanoidRigType={R6="R6",R15="R15"}
local RaycastParams={new=function() return {} end}
local character,tag={},{}
local Players={GetPlayers=function() return {{Character=character}} end}
local CollectionService={GetTagged=function() return {tag} end}
local solid={CanCollide=true,IsA=function() return true end}
local hit={Position=Vector3.new(0,-4,0),Normal=Vector3.new(0,1,0),Instance=solid}
local lastDirection
local workspace={Raycast=function(_,origin,direction,params)
    assert(params.RespectCanCollide and params.FilterDescendantsInstances[1]==character)
    assert(params.FilterDescendantsInstances[2]==tag)
    near(origin.X,6);lastDirection=direction
    return hit
end}
''', section(BASE, 'local function getLandingRootY(', 'local function getWeaponFromContainer('), r'''
local root={Position=Vector3.zero,Size=Vector3.new(2,2,1),Parent={FindFirstChild=function() return {Size=Vector3.new(1,1,1),IsA=function() return true end} end}}
local humanoid={HipHeight=2,RigType="R15"}
near(getLandingRootY(root,humanoid,Vector3.new(6,-500,0)),-1)
near(lastDirection.Y,-64)
humanoid.HipHeight=0;humanoid.RigType="R6"
near(getLandingRootY(root,humanoid,Vector3.new(6,-5,0)),-2)
hit.Normal=Vector3.new(1,.1,0);assert(getLandingRootY(root,humanoid,Vector3.new(6,-5,0))==nil)
hit.Normal=Vector3.new(0,1,0);hit.Position=Vector3.new(0,2,0)
assert(getLandingRootY(root,humanoid,Vector3.new(6,-5,0))==nil)
hit.Position=Vector3.new(0,-4,0);solid.CanCollide=false
assert(getLandingRootY(root,humanoid,Vector3.new(6,-5,0))==nil)
hit=nil;assert(getLandingRootY(root,humanoid,Vector3.new(6,-5,0))==nil)
pass("actual bounded landing ray: character exclusions, R6/R15 clearance, slope/ledge/visual rejection")
end
print("v18 regression groups passed:",passed)
'''])

def main():
    knife = (ROOT / 'src/games/MM2/Blatant/KnifeThrow.lua').read_text()
    assert 'latencyModel = "Replica RTT"' in knife
    assert '{"Packet RTT/2", "Replica RTT"}, 2,' in knife
    with tempfile.TemporaryDirectory(prefix='mm2-v18-') as folder:
        path = Path(folder) / 'test.luau'
        path.write_text(build())
        subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)

if __name__ == '__main__': main()
