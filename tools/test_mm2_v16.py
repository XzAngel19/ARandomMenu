#!/usr/bin/env python3
"""Execute retained v16 visibility and migration code in mocked Luau.
LUAU=/path/to/luau python3 tools/test_mm2_v16.py
These are deterministic regression tests, not a Roblox runtime/physics test.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import sys
sys.dont_write_bytecode = True
from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
BASE = (ROOT / 'src/games/MM2/base.lua').read_text()


def build():
    chunks = [PRELUDE, section(BASE, 'local predictionMath = {}', 'type MotionSample')]
    chunks += [r'''
do
local localChar, target, tagged = {}, {}, {}
local LocalPlayer={Character=localChar}
local CollectionService={GetTagged=function(_,tag) assert(tag=="WeaponPassthrough"); return {tagged} end}
local RaycastParams={new=function() return {} end}
local layers,calls={},0
local workspace={Raycast=function(_,origin,direction,params)
    calls+=1
    assert(table.find(params.FilterDescendantsInstances,localChar))
    assert(table.find(params.FilterDescendantsInstances,tagged))
    for _,part in ipairs(layers) do
        local ignored=table.find(params.FilterDescendantsInstances,part)~=nil
        for _,excluded in ipairs(params.FilterDescendantsInstances) do
            if part:IsDescendantOf(excluded) then ignored=true end
        end
        if not ignored then return {Instance=part} end
    end
    return nil
end}
local function part(transparency, owner)
    return {Transparency=transparency,IsA=function(_,t) return t=="BasePart" end,
        IsDescendantOf=function(_,p) return p==owner end}
end
''', section(BASE, 'local function isWeaponPathClear(', 'local function getWeaponFromContainer('), r'''
local a,b=Vector3.zero,Vector3.new(10,0,0)
assert(isWeaponPathClear(a,b,target))
assert(not isWeaponPathClear(a,b,target,nil,{requireTarget=true}),"empty air is not a visible body")
layers={part(0,target)};assert(isWeaponPathClear(a,b,target,nil,{requireTarget=true}))
layers={part(0)};assert(not isWeaponPathClear(a,b,target,nil,{requireTarget=true}))
layers={part(1),part(0,target)}; assert(isWeaponPathClear(a,b,target))
assert(not isWeaponPathClear(a,b,target,true),"Shoot must not ignore untagged invisible blockers")
layers={part(0,target)};assert(isWeaponPathClear(a,b,target,true))
layers={part(1),part(0)}; assert(not isWeaponPathClear(a,b,target))
layers={part(0.99)}; assert(not isWeaponPathClear(a,b,target))
layers={part(0,target),part(0)}
assert(isWeaponPathClear(a,b,target),"hitscan accepts current body")
assert(not isWeaponPathClear(a,b,target,nil,{ignoreTarget=true}),"present body must not mask future projectile wall")
layers={part(0,target)}
assert(isWeaponPathClear(a,b,target,nil,{ignoreTarget=true}),"projectile ignores current target pose, not world")
layers={}; for i=1,40 do table.insert(layers,part(1)) end
calls=0; assert(not isWeaponPathClear(a,b,target) and calls==32)
pass("native LOS filters: local/tagged excluded; transparent skipped; opaque blocked; bounded fail-closed")
end

do
local runtime={sessionId="new-session",sessionGunAttempts=0,events={},motionBuckets={},
    gunAcceptance={},knifeSpeed={},knifeSpawnDelay={}}
local source={session={gunAttempts=3.139e57,events={{kind="gun"}}},aggregate={
    gunAcceptanceMs={count=51,mean=150,m2=5,minimum=80,maximum=250},
    knifeSpeedStudsPerSecond={count=192,mean=96,m2=0,minimum=96,maximum=96},
    knifeSpawnDelayMs={count=1e57,mean=200,m2=0,minimum=200,maximum=200}}}
local files={out="original bytes"}
local failBackup=false
local environment={readfile=function(path) assert(files[path],"not found"); return files[path] end,
    isfile=function(path) return files[path]~=nil end,
    writefile=function(path,text) if failBackup then error("no space") end; files[path]=text end}
local HttpService={JSONDecode=function() return source end}
local OUTPUT_PATH,trajectoryLogPrefix="out","test"
local warn=function() end
''', section(BASE, '    local function applyStatsPayload(', '    local function restoreMotionBucket('),
              section(BASE, '    local function loadSavedHistory()', '    local function vectorArray('), r'''
loadSavedHistory()
assert(files[runtime.historyBackup]=="original bytes" and files.out=="original bytes")
assert(runtime.sessionGunAttempts==0 and #runtime.events==0 and next(runtime.motionBuckets)==nil)
assert(runtime.gunAcceptance.count==51 and runtime.knifeSpeed.mean==96)
assert(runtime.knifeSpawnDelay.count==nil,"corrupt stats imported")
runtime.persistenceBlocked=false; failBackup=true; loadSavedHistory()
assert(runtime.persistenceBlocked and files.out=="original bytes")
failBackup=false; environment.readfile=function() error("permission denied") end
runtime.persistenceBlocked=false; loadSavedHistory(); assert(runtime.persistenceBlocked)
files.out=nil; runtime.persistenceBlocked=false; loadSavedHistory(); assert(not runtime.persistenceBlocked)
pass("migration: byte-exact backup; poisoned totals/events quarantined; valid stats kept; failures protected")
end

''']
    return '\n'.join(chunks)


def main():
    with tempfile.TemporaryDirectory(prefix='mm2-v16-') as directory:
        script = Path(directory) / 'regressions.luau'
        script.write_text(build())
        subprocess.run([os.environ.get('LUAU', 'luau'), str(script)], check=True)


if __name__ == '__main__':
    main()
