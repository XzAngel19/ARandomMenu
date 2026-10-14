#!/usr/bin/env python3
"""Read-only characterization of remaining MM2 v16 defects, not a game test.

Requires fetched Git object 2c7ab1a and Luau 0.732. No checkout or network calls.
Run: python3 tools/audit_mm2_remaining.py --luau /path/to/luau
Assertions deliberately reproduce current defects; passing does NOT mean fixed.
The runtime source is extracted unchanged from the pinned revision. GUI/Roblox
services are mocked. Generated harnesses live only in a temporary directory.
"""
from __future__ import annotations

import argparse
import ast
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
REV = "2c7ab1a36164bd17fd0d0643cb8395c2e4a4da77"


def source(path: str) -> str:
    return subprocess.check_output(
        ["git", "show", f"{REV}:{path}"], cwd=ROOT, text=True
    )


def section(text: str, start: str, end: str) -> str:
    assert text.count(start) == 1, start
    tail = text.split(start, 1)[1]
    assert end in tail, end
    return start + tail.split(end, 1)[0]


def harness() -> str:
    base = source("src/games/MM2/base.lua")
    shoot = source("src/games/MM2/Blatant/Shoot.lua")
    aura = source("src/games/MM2/Blatant/KnifeAura.lua")
    throw = source("src/games/MM2/Blatant/KnifeThrow.lua")
    widgets = source("src/guis/Wurst/Code/Widgets.lua")
    # Reuse only the literal vector/clock mock; do not import/execute that script.
    tree = ast.parse(source("tools/test_mm2_precision.py"))
    prelude = next(ast.literal_eval(n.value) for n in tree.body
                   if isinstance(n, ast.Assign)
                   and any(isinstance(t, ast.Name) and t.id == "PRELUDE" for t in n.targets))
    chunks = [prelude, section(base, "local predictionMath = {}", "type MotionSample")]
    chunks += [r'''
do
local state={mm2Core={predictionMath=predictionMath, trajectoryCalibration={}}}
local featureConnections={}
local mm2Features={}
local MM2Scroll={}
local LocalPlayer={CharacterAdded={Connect=function() return {Disconnect=function() end} end}}
local TaskManager={Connect=function(_,fn) return {Disconnect=function() end, fn=fn} end}
local function disconnectFeatureConnection(key) featureConnections[key]=nil end
local toggles, numbers = {}, {}
local function createUniversalFeature(name,description,order,onToggle,config)
    return {configKey="MM2."..name,onToggle=onToggle}
end
local function addToggleOption(feature,label,default,callback)
    -- Same initial invocation and private UI boolean as Widgets.addToggleOption.
    local control={value=default}
    function control:click() self.value=not self.value; callback(self.value) end
    toggles[label]=control
    callback(default)
end
local function addNumberOption(feature,label,default,minimum,maximum,callback)
    table.insert(numbers,{label=label,key=feature.configKey.."."..label:gsub("%W",""),
        default=default,apply=callback})
    callback(default)
end
local function addCycleOption(feature,label,values,index,callback) callback(values[index]) end
local Aura=(function()
''', aura, r'''
end)()
local Throw=(function()
''', throw, r'''
end)()
Aura.init({}); Throw.init({})
local card=state.mm2KnifeFeature
card.onToggle(true)
assert(featureConnections.MM2KnifeThrow==nil)
assert(featureConnections.MM2KnifeController==nil)
toggles["Knife Throw"]:click()
assert(featureConnections.MM2KnifeThrow~=nil)
card.onToggle(false)
assert(featureConnections.MM2KnifeThrow==nil and toggles["Knife Throw"].value)
card.onToggle(true)
assert(featureConnections.MM2KnifeThrow==nil and toggles["Knife Throw"].value)
print("REPRO Knife master OFF->ON: checked Throw has no running callback")
-- Sub-option does not consult the master either.
card.onToggle(false)
toggles["Knife Throw"]:click(); toggles["Knife Throw"]:click()
assert(featureConnections.MM2KnifeThrow~=nil)
print("REPRO Knife sub-toggle starts Throw even while master is OFF")
local ranges={}
for _,row in ipairs(numbers) do if row.label=="Range" then table.insert(ranges,row) end end
assert(#ranges==2 and ranges[1].key==ranges[2].key)
assert(ranges[1].default==14 and ranges[2].default==120)
print("REPRO independent ranges share persisted key",ranges[1].key)
Aura.destroy(); Throw.destroy()
pass("full Knife modules with mocked widgets: master/sub-options and Range collision")
end

do
local minimum,maximum,step,precisionFactor=0.2,3,0.1,10
local value,editing=1,false
local fill,knob,valueInput={},{},{}
local UDim2={fromScale=function(x,y) return {x,y} end}
local formatCompactNumber=tostring
local configData={values={}}
local optionKey="MM2.Knife.Firedelay"
local function queueConfigSave() end
local function isFiniteNumber(v) return predictionMath.finite(v) end
local applied=nil
local function callback(v) applied=v end
''', section(widgets, "        local function quantize(raw:", "        local function updateFromScreenX("), r'''
setValue(-1,true,false)
assert(applied==-1 and configData.values[optionKey]==-1)
setValue(999,false,false)
assert(applied==999)
setValue(-1,true,true)
assert(applied==minimum)
pass("actual numeric widget: text/config bypass min/max; slider clamps")
end

do
local mm2Settings={}
''', section(base, "local GUN_LEAD = {", "local autoLeadCorrection:"),
        section(base, "local function getGunTurnRate(", "local function getGunLeadStatus()"),
        section(base, "local function isMotionGrounded(", "local lastLatencyReadAt:"), r'''
local hum={FloorMaterial="Ground",GetState=function() return "Running" end}
local char={FindFirstChildOfClass=function() return hum end}
local player={Character=char}
local rates={}
for _,hz in ipairs({20,60,120}) do
    motionSamples[player]=nil
    now=0
    local root={Position=Vector3.zero,AssemblyLinearVelocity=Vector3.new(16,0,0)}
    getFilteredVelocity(player,root)
    now=1/hz
    local theta=math.pi/hz -- same physical turn: 180 degrees/second
    root.AssemblyLinearVelocity=Vector3.new(16*math.cos(theta),0,16*math.sin(theta))
    getFilteredVelocity(player,root)
    rates[hz]=getGunTurnRate(motionSamples[player].stability)
    print("REPRO same physical turn, Hz",hz,"computed rate",rates[hz])
end
assert(rates[20]>rates[120]*30)
pass("motion instability is not time-normalized; rate changes with sample interval")
end

do
local autoSettings={mode="Normal",fireDelay=0.5,maxError=0.6}
local mm2Settings={silentAim=true}
local lastAutoShot,lastGunCheck=-math.huge,0
local lastAutoReject=nil
local lastRejectReason=""
local sent=nil
local function equipSheriffGun() end
local function getSelectedShootTarget() return {} end
local function fireGunAtTarget(target,options) sent=options; return true end
local function notify() end
''', section(shoot, "    local function autoShootTick():", "    local function toggleAutoShoot("), r'''
now=1; autoShootTick()
assert(sent.silent==false and mm2Settings.silentAim==true)
pass("Auto Shoot Normal explicitly overrides Shoot.SilentAIM=true")
end

do
local runtime={active=true,pendingGuns={},freshGunLatency={},gunAcceptance={},sessionGunConfirmed=0}
local tool={}
local first={shotId="first",tool=tool,activatedAt=0,origin=Vector3.zero}
local second={shotId="second",tool=tool,activatedAt=0.2,origin=Vector3.new(100,0,0)}
runtime.pendingGuns={first,second}
local estimatesAt=0
local function compactPending() end
local function normalizeGun(x) return x end
local function worldPosition(x) return x end
local function addSample() end
local function ensureTrajectorySampler() end
local emitted=nil
local function emitShot(kind,payload) emitted=payload end
''', section(base, "    local function handleGunFired(", "    local finishKnifeTrack:"), r'''
now=0.3
-- Delayed signal originating at first shot, same tool, completely different origin.
handleGunFired(tool,Vector3.zero,Vector3.new(1,0,0),nil)
assert(first.confirmedAt==nil and second.confirmedAt==0.3)
assert(emitted.shotId=="second")
near(runtime.freshGunLatency[1].ms,100)
print("REPRO first shot response attributed to second; 300ms becomes",emitted.latencyMs,"ms")
pass("actual GunFired matcher favors most recent same-tool pending, feeds live lead")
end

do
local state={mm2ShotFeedback={hide=function() end,spawnStats={}}}
local mm2Settings={predictionRtt=0.2,showMissCooldown=false}
local task={delay=function(_,fn) fn() end}
local function getPlayerRole() return "Murderer" end
local function tuneFromConfirmedShot() error("must not train from inferred hit") end
local character={Parent={},FindFirstChildOfClass=function() return {Health=100} end}
local candidate={target={Parent=nil},targetCharacter=character,healthBefore=100,
    targetedMurderer=true,silentSpawn="Through"}
''', section(base, "state.mm2ShotFeedback.resolve = function(", "state.mm2ShotFeedback.handleGunFired = function("), r'''
state.mm2ShotFeedback.resolve(candidate,false)
assert(state.mm2ShotFeedback.spawnStats.Through.hits==1)
pass("Spawn A/B reports a hit after target disconnect without direct hit evidence")
end
print("Remaining-defect characterization groups:",passed)
''']
    # This is a direct contradiction of the public numeric interval, even with
    # perfectly stable motion: every solver result has an error floor of 0.35.
    assert "local MINIMUM_ERROR_RADIUS: number = 0.35" in shoot
    assert '"Max error",\n        autoSettings.maxError,\n        0.1,' in shoot
    assert "resolved.errorRadius > opts.maxError" in shoot
    return "\n".join(chunks)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luau", required=True, type=Path)
    args = parser.parse_args()
    print(f"Auditing pinned source {REV}; no runtime changes", flush=True)
    with tempfile.TemporaryDirectory(prefix="mm2-remaining-") as directory:
        file = Path(directory) / "characterize.luau"
        file.write_text(harness())
        subprocess.run([str(args.luau.resolve()), str(file)], check=True)
    print("STATIC: Auto Max error in [0.1, 0.35) cannot pass the 0.35 solver floor")
    print("DONE. These are reproduced defects/behaviors, not a Roblox hit-rate or FPS measurement.")


if __name__ == "__main__":
    main()
