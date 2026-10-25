#!/usr/bin/env python3
"""Read-only characterization of the reported MM2 v10-v14 snapshots.

This is an audit, not a claim that Roblox's server accepts these shots.
Requires the historical Git objects (git fetch origin arena/2daf1a78-arandommenu).
Optional --luau /path/to/luau executes extracted, unmodified function bodies
with small deterministic mocks. --compiler checks the audited source files.
No checkout, source modification, executor, game connection, or network calls.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REVS = {
    "v10": "66d7152796ecb4562a8e4aa50f983fee7d6d7c60",
    "v11": "7385fcdae7457056ac22b8ae4cf8f5fb0fcaafbb",
    "v12": "076e166f976450378dc129964be4daf99e7e7e08",
    "v13": "bfba7cca3c40980f8e29b36a7e1fd9cbbe4bff1a",
    "v14": "17c15f3ff802d0d2e036dbd18a6204d09169517f",
}
BASE = "src/games/MM2/base.lua"
SHOOT = "src/games/MM2/Blatant/Shoot.lua"
THROW = "src/games/MM2/Combat/KnifeThrow.lua"
AURA = "src/games/MM2/Blatant/KnifeAura.lua"
LEARNING = "src/games/universal/Other/GameLearning.lua"


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True)


def source(rev: str, path: str) -> str:
    return git("show", f"{REVS.get(rev, rev)}:{path}")


def section(text: str, start: str, end: str) -> str:
    return start + text.split(start, 1)[1].split(end, 1)[0]


def tokens(text: str) -> tuple[str, ...]:
    """Ignore comments/whitespace, preserving quoted and long-string contents."""
    pattern = re.compile(r'''--\[(=*)\[.*?\]\1\]|--[^\n]*|'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"|\[(=*)\[.*?\]\2\]|\s+|[A-Za-z_][A-Za-z_0-9]*|[0-9]+(?:\.[0-9]+)?|.''', re.S)
    return tuple(m.group() for m in pattern.finditer(text)
                 if not m.group().isspace() and not m.group().startswith("--"))


def check_bundle(rev: str) -> int:
    bundle = source(rev, "src/libraries/bundle.lua")
    stamp = re.search(r'stamp\s*=\s*"([^"]+)"', bundle).group(1)
    loader = source(rev, "src/Wurst.lua")
    assert re.search(r'SOURCE_STAMP: string = "([^"]+)"', loader).group(1) == stamp
    embedded = {m[0]: m[2] for m in re.findall(
        r'\["([^"]+)"\]\s*=\s*\[(=*)\[\n(.*?)\n\]\2\],', bundle, re.S)}
    paths = {p for p in git("ls-tree", "-r", "--name-only", REVS[rev], "src").splitlines()
             if p.endswith(".lua") and p not in {"src/Wurst.lua", "src/libraries/bundle.lua"}}
    assert set(embedded) == paths, f"{rev}: bundle file list differs"
    for path in sorted(paths):
        assert embedded[path] == source(rev, path), f"{rev}: stale bundle entry {path}"
    print(f"PASS {rev} {git('rev-parse', REVS[rev]).strip()} {stamp}: {len(paths)} bundle entries match")
    return len(paths)


VECTOR_MOCK = r'''
local Vector3 = {}
local mt = {}
function Vector3.new(x, y, z) return setmetatable({X=x, Y=y, Z=z}, mt) end
Vector3.zero = Vector3.new(0, 0, 0)
mt.__add = function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
mt.__sub = function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
mt.__unm = function(a) return Vector3.new(-a.X,-a.Y,-a.Z) end
mt.__mul = function(a,b)
    if type(a) == "number" then a,b=b,a end
    return Vector3.new(a.X*b,a.Y*b,a.Z*b)
end
mt.__div = function(a,b) return a*(1/b) end
mt.__index = function(a,k)
    if k == "Magnitude" then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) end
    if k == "Unit" then return a/a.Magnitude end
    if k == "Dot" then return function(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end end
end
local CFrame = {
    new = function(p) return {Position=p} end,
    lookAt = function(p,q) return {Position=p, Endpoint=q} end,
}
'''


def harness(rev: str) -> str:
    base, shoot, throw = (source(rev, p) for p in (BASE, SHOOT, THROW))
    lead = section(base, "local GUN_LEAD =", "local function getGunOriginCFrame")
    knife = section(throw, "    local function predictAim", "    local throwTrack:") if rev != "v10" else section(throw, "    local function predictAim", "    local function throwKnife")
    scheduler = section(throw, "    local function toggleKnifeThrow", "    local KnifeThrowFeature:")
    geometry = section(shoot, "    local SILENT_ORIGIN_STUDS:", "    type FireOptions")
    solver = section(shoot, "    local BODY_HALF_WIDTH:", "    local function getSelectedShootTarget")
    aura = source(rev, AURA)
    effective_range = section(aura, "    local function getEffectiveRange", "    local function getEquippedWeapon")
    aura_process = section(aura, "    local function processKnifeAura", "    local function refreshKnifeController")
    estimates = section(base, "    local function estimates():", "    saveSnapshot = function")
    knife_expected = 5 + 16 * (5 / 96 + (0.1 if rev in ("v10", "v11") else 0))
    return VECTOR_MOCK + f'''
-- Scope reproducer: keep the original order (function first, local controller later).
do
local mm2Settings = {{autoTuneLead=false, gunLeadBias=0}}
local function getEstimatedLatency() return 0.08 end
{lead}
local calls = 0
local trajectoryCalibration = {{getEstimates=function() calls+=1; return {{gunAcceptanceMs=60,confirmedShots=10}} end}}
local horizon = getGunHorizonSeconds()
assert(calls == 0, "unexpected capture of a later local")
assert(math.abs(horizon - (0.2 + 1/40 + 1/120)) < 1e-9)
print("CONFIRMED {rev}: calibration controller not read; fallback horizon", horizon)
end

do
local root = {{Position=Vector3.new(5,0,0)}}
local target = {{Character={{FindFirstChild=function() return root end}}}}
local trajectoryCalibration = {{getEstimates=function() return {{knifeSpeed=96}} end}}
local function getFilteredVelocity() return Vector3.new(16,0,0) end
local function getEstimatedLatency() return 0.2 end
{knife}
local aim = predictAim(target, Vector3.zero)
assert(math.abs(aim.X - {knife_expected!r}) < 1e-8)
print("CONFIRMED {rev}: knife endpoint X at 200 ms modeled RTT", aim.X)
end

do
local callbacks = {{}}
local TaskManager = {{Connect=function(self, f) table.insert(callbacks,f); return {{}} end}}
local featureConnections = {{}}
local function disconnectFeatureConnection() table.clear(callbacks) end
local knifeThrowSettings = {{}}
local lastThrow = 0
local checks = 0
local function throwKnife() checks+=1 end
{scheduler}
local counts = {{}}
for _, hz in ipairs({{20,60,120}}) do
    knifeThrowSettings.throwHz = hz
    checks = 0
    toggleKnifeThrow(true)
    for i=1,1200 do callbacks[1](1/120) end
    table.insert(counts, checks)
end
if "{rev}" == "v11" then
    assert(counts[1] < counts[2] and counts[2] < counts[3])
else
    assert(counts[1] == counts[2] and counts[2] == counts[3])
end
print("CONFIRMED {rev}: scheduler checks in 10s for 20/60/120 Hz", unpack(counts))
end

do
local mm2Settings = {{silentSweep=0.5}}
local bystanderChecks = 0
local function bystanderOnSegment() bystanderChecks+=1; return false end
{geometry}
local p = {{targetPosition=Vector3.new(3.7333333333,0,0),capturedPosition=Vector3.zero,velocity=Vector3.new(16,0,0)}}
local muzzle = CFrame.new(Vector3.new(0,0,-20))
local function distanceToSegment(point,a,b)
    local d=b-a
    local t=math.clamp((point-a):Dot(d)/d:Dot(d),0,1)
    return (point-(a+d*t)).Magnitude
end
local f1,f2 = buildSilentShot({{}},p,muzzle,"Front")
local t1,t2 = buildSilentShot({{}},p,muzzle,"Through")
local front = distanceToSegment(Vector3.zero,f1.Position,f2.Position)
local through = distanceToSegment(Vector3.zero,t1.Position,t2.Position)
assert(front > 3 and through < 1)
print("CONFIRMED {rev}: illustrative distance from captured point to Front/Through",front,through)
mm2Settings.silentSweep=0
bystanderChecks=0
buildSilentShot({{}},p,muzzle,"Through")
assert(bystanderChecks==0)
print("CONFIRMED {rev}: Through does not test bystanders when extra sweep=0")
end

-- Same solver inputs: default hitbox-off behavior vs the removed relaxed gate.
do
local Enum={{Material={{Air="Air"}}}}
local mm2Settings={{shootWallCheck=false}}
local humanoid={{Health=100,FloorMaterial="Ground",MoveDirection=Vector3.zero,WalkSpeed=16}}
local part={{Position=Vector3.zero,IsA=function() return true end}}
local character={{FindFirstChild=function() return part end,FindFirstChildOfClass=function() return humanoid end}}
local target={{Character=character}}
local sample={{character=character,acceleration=Vector3.zero,grounded=true,stability=1}}
local motionSamples={{[target]=sample}}
local function getFilteredVelocity() return Vector3.new(16,0,0) end
local function getGunHorizonSeconds() return 0.2+1/40+1/120 end
local function getGunTurnRate(s) return math.clamp((1-s)*6,0,math.pi*1.5) end
local function getGunTurnDiscount(h,r) return math.clamp(math.cos(h*r*0.5),0.25,1) end
{solver}
local origin=CFrame.new(Vector3.new(0,0,-20))
local aim,prediction=computeGunAim(target,origin)
assert(aim and math.abs(prediction.endpoint.X-3.7333333333333334)<1e-8)
assert(prediction.errorRadius==0.35)
sample.stability=0.5
sample.acceleration=Vector3.new(120,0,0)
local rejected,_,reason=computeGunAim(target,origin)
assert(not rejected and reason=="turning too hard")
local widened=computeGunAim(target,origin,{{bodyHalfWidth=4}})
assert((widened~=nil)==("{rev}"~="v14"))
print("CONFIRMED {rev}: default linear/turning gun cases identical; relaxed hitbox gate exists", widened~=nil)
end

-- Actual Aura selection + delayed guard with an auto-range of 20 and manual range 14.
do
local knifeSettings={{aura=true,autoRange=true,auraRange=14}}
local trajectoryCalibration={{getEstimates=function() return {{maxStabDistance=20}} end,noteAuthoredShot=function() end}}
{effective_range}
local activated, sent=0,0
local handle={{IsA=function() return true end}}
local remote={{IsA=function() return true end,FireServer=function() sent+=1 end}}
local events={{FindFirstChild=function() return remote end}}
local knife={{Activate=function() activated+=1 end,FindFirstChild=function(self,name) if name=="Events" then return events else return handle end end}}
local localRoot={{Position=Vector3.zero}}
local targetRoot={{Position=Vector3.new(18,0,0)}}
local target={{Character={{FindFirstChild=function() return targetRoot end}}}}
local function canUseEquippedKnife() return knife,localRoot end
local function findKnifeAuraTarget(root,range) assert(range==20); return target end
local state={{mm2KnifeRuntime={{lastAuraSwing=-math.huge}}}}
local task={{delay=function(_,fn) fn() end}}
{aura_process}
processKnifeAura()
assert(activated==1 and sent==0)
print("CONFIRMED {rev}: Auto Range 20 selects target at 18 but manual 14 blocks delayed contact")
end

do
local runtime={{gunAcceptance={{count=0}},knifeSpeed={{count=0}},events={{{{kind="stab",distance=28,hitTarget=false}}}}}}
{estimates}
assert(estimates().maxStabDistance==28)
print("CONFIRMED {rev}: maxStabDistance accepts unconfirmed stab attempt")
end
'''


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luau", type=Path)
    parser.add_argument("--compiler", type=Path)
    args = parser.parse_args()
    for rev in REVS:
        check_bundle(rev)
    for path in (BASE, SHOOT, AURA, LEARNING):
        assert source("v10", path) == source("v11", path)
    print("PASS v10 -> v11: base, Shoot, KnifeAura, GameLearning byte-identical")
    for rev in REVS:
        base, throw = source(rev, BASE), source(rev, THROW)
        spawn = re.search(r'silentSpawn = "([^"]+)"', base).group(1)
        assert spawn == ("Through" if rev in ("v10", "v11") else "Front")
        lead = "getEstimatedLatency() * 0.5" in throw
        assert lead == (rev in ("v10", "v11"))
        dynamic_hz = "math.clamp(knifeThrowSettings.throwHz, 20, 120)" in throw
        assert dynamic_hz == (rev == "v11")
        print(f"FACT {rev}: spawn={spawn}, knife RTT/2={lead}, wired Throw Hz={dynamic_hz}")
    for path, start, end in (
        (BASE, "local function getFilteredVelocity", "local function getGunOriginCFrame"),
        (SHOOT, "    local function buildSilentShot", "    type FireOptions"),
        (AURA, "function Module.init", "function Module.destroy"),
    ):
        assert tokens(section(source("v10", path), start, end)) == tokens(section(source("v14", path), start, end)), path
    print("PASS v10 -> v14: motion/horizon, silent geometry and Aura logic unchanged ignoring comments/whitespace")
    for rev in ("v10", "v11", "v14"):
        base = source(rev, BASE)
        assert base.index("local function getGunHorizonSeconds") < base.index("local trajectoryCalibration: any")
        assert "runtime.sessionGunAttempts = payload.session.gunAttempts" in base
        assert "+ runtime.sessionGunAttempts" in base
        assert "runtime.motionBuckets = mergedBuckets" in base
        assert "target[field] = target[field] + value" in base
    print("FACT v10/v11/v14: persistence feeds cumulative counters/buckets back into next merge")
    print("MODEL no new attempts between forced saves: persisted/runtime 1 -> 2 -> 4 (not a game measurement)")
    print("MODEL removed knife term: 16 studs/s * RTT/2 = 0.64/1.60/2.40 studs at 80/200/300 ms")
    with tempfile.TemporaryDirectory(prefix="mm2-audit-") as temp:
        temp = Path(temp)
        if args.compiler:
            compiled = 0
            for rev in REVS:
                for path in ("src/Wurst.lua", BASE, SHOOT, THROW, AURA, LEARNING, "src/libraries/bundle.lua"):
                    file = temp / f"{rev}-{Path(path).name}"
                    file.write_text(source(rev, path))
                    result = subprocess.run([str(args.compiler.resolve()), "--null", str(file)], text=True, capture_output=True)
                    assert result.returncode == 0, result.stderr + result.stdout
                    compiled += 1
            print(f"PASS Luau compilation: {compiled} historical files (not Roblox type/runtime validation)", flush=True)
        else:
            print("SKIP compilation: supply --compiler")
        if args.luau:
            for rev in ("v10", "v11", "v14"):
                file = temp / f"{rev}-characterization.luau"
                file.write_text(harness(rev))
                subprocess.run([str(args.luau.resolve()), str(file)], check=True)
        else:
            print("SKIP source-function execution: supply --luau")
    print("DONE: audit assertions describe historical defects; they do not certify hit rate or FPS.")


if __name__ == "__main__":
    main()
