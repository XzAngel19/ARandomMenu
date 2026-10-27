#!/usr/bin/env python3
"""Boot-time restore transaction and lazy scheduler regression test.

Runs the real Wurst entry point and real bundle with hostile saved states. The
probe wraps section initialization so a persisted physics callback cannot slip
through before the runtime-ready gate without failing the test.
"""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build" / "startup_restore.luau"
LOG = ROOT / "build" / "startup_restore.log"

spec = importlib.util.spec_from_file_location(
    "gen_full_boot_harness", ROOT / "tools" / "gen_full_boot_harness.py"
)
assert spec and spec.loader
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)
generator.main()
source = (ROOT / "build" / "full_boot.luau").read_text(encoding="utf-8")

old_states = 'states = { ["ClickGUI.Showdock"] = false },'
new_states = '''states = {
        ["ClickGUI.Showdock"] = false,
        ["Universal.Noclip"] = true,
        ["Universal.AntiVoid.Antifling"] = true,
        ["MM2.AutoFarm"] = true,
        ["Universal.TouchFling"] = true,
        ["MM2.Fling.TouchFling"] = true,
        ["MM2.Fling.AutoFlingSelectedTarget"] = true,
    },'''
assert source.count(old_states) == 1
source = source.replace(old_states, new_states, 1)

old_expose = "allFeatures = allFeatures} end end"
new_expose = (
    "allFeatures = allFeatures, TaskManager = TaskManager, "
    "RunService = RunService, featureConnections = featureConnections} end end"
)
assert source.count(old_expose) == 1
source = source.replace(old_expose, new_expose, 1)

section_anchor = "\nSectionManager.initializeAllAsync()\n"
assert source.count(section_anchor) == 1
section_probe = r'''
do
    local originalInitialize = SectionManager.initialize
    SectionManager.initialize = function(sectionName)
        local ok, failure = originalInitialize(sectionName)
        if not state.featureRestoresReady then
            assert(featureConnections.Noclip == nil,
                "Noclip restored during section " .. tostring(sectionName))
            assert(featureConnections.MM2AutoFarmTick == nil,
                "Auto Farm started during section " .. tostring(sectionName))
            assert(featureConnections.AntiVoidStepped == nil,
                "toggle option restored during section " .. tostring(sectionName))
            assert(featureConnections.MM2AutoFlingTarget == nil,
                "session-only Auto Fling started during boot")
            local physics = state.flingPhysics
            assert(not physics or not physics.isRunning(),
                "directed Fling started during section registration")
            assert(not physics or not physics.isTouchEnabled(),
                "Touch Fling started during section registration")
        end
        return ok, failure
    end
end
'''
source = source.replace(
    section_anchor, "\n" + section_probe + section_anchor, 1
)

source += r'''
-- startup restore + lazy scheduler acceptance probe
do
    local ex = GENV.__expose
    assert(ex and ex.state and ex.TaskManager and ex.featureConnections)
    assert(ex.state.featureRestoresReady == true,
        "the initial section batch must open the restore gate")

    local function findFeature(name)
        for _, feature in ipairs(ex.allFeatures) do
            if feature.name == name then return feature end
        end
        return nil
    end

    local noclip = findFeature("Noclip")
    assert(noclip and noclip.enabled == true,
        "an ordinary saved card must restore after the boot gate")
    assert(ex.featureConnections.Noclip ~= nil,
        "restored Noclip must own its task after boot")
    assert(ex.featureConnections.AntiVoidStepped ~= nil,
        "a saved toggle option must restore after the boot gate")
    assert(ex.configData.states["Universal.AntiVoid.Antifling"] == true)

    local autoFarm = findFeature("Auto Farm")
    assert(autoFarm and autoFarm.enabled ~= true,
        "Auto Farm must be an explicit per-session action")
    assert(ex.featureConnections.MM2AutoFarmTick == nil,
        "stale Auto Farm config must not create a physics writer")
    assert(ex.configData.states["MM2.AutoFarm"] == false)

    local touch = findFeature("Touch Fling")
    assert(touch and touch.enabled ~= true,
        "Touch Fling must not restore from a stale config")
    assert(ex.configData.states["Universal.TouchFling"] == false)
    -- v148 retired the duplicate MM2 toggle: a stale `true` is erased, not
    -- restored, and the key does not even survive the config load.
    assert(ex.configData.states["MM2.Fling.TouchFling"] == nil,
        "the retired MM2 Touch Fling key must be erased from an old config")
    assert(ex.configData.states["MM2.Fling.AutoFlingSelectedTarget"] == false)
    assert(ex.featureConnections.MM2AutoFlingTarget == nil)
    assert(not ex.state.flingPhysics.isRunning())
    assert(not ex.state.flingPhysics.isTouchEnabled())

    -- Session-only must not mean read-only: explicit controls still work, but
    -- they never write a true value that a later boot/profile can resurrect.
    autoFarm.activate()
    assert(autoFarm.enabled == true and ex.featureConnections.MM2AutoFarmTick ~= nil,
        "the user must still be able to enable Auto Farm explicitly")
    assert(ex.configData.states["MM2.AutoFarm"] == false)
    autoFarm.activate()
    assert(autoFarm.enabled ~= true and ex.featureConnections.MM2AutoFarmTick == nil)

    touch.activate()
    assert(touch.enabled == true and ex.state.flingPhysics.isTouchEnabled(),
        "the user must still be able to enable Touch explicitly")
    assert(ex.configData.states["Universal.TouchFling"] == false)
    assert(ex.configData.states["MM2.Fling.TouchFling"] == nil)
    touch.activate()
    assert(not ex.state.flingPhysics.isTouchEnabled())

    local autoFling = ex.state.toggleControls["MM2.Fling.AutoFlingSelectedTarget"]
    assert(autoFling and autoFling.restore == false)
    autoFling.setChecked(true)
    assert(ex.featureConnections.MM2AutoFlingTarget ~= nil,
        "the user must still be able to enable Auto Fling explicitly")
    assert(ex.configData.states["MM2.Fling.AutoFlingSelectedTarget"] == false)
    autoFling.setChecked(false)
    assert(ex.featureConnections.MM2AutoFlingTarget == nil)

    local tasks = ex.TaskManager
    tasks:Destroy()
    tasks:Destroy()
    assert(tasks.connection == nil and tasks.renderConnection == nil,
        "empty scheduler buckets must not own RunService signals")

    local elapsed = 0
    local heartbeat = tasks:Connect(function(deltaTime)
        elapsed += deltaTime
    end)
    assert(tasks.connection ~= nil,
        "first Heartbeat task must open its signal lazily")
    ex.RunService.Heartbeat:Fire(0.25)
    assert(math.abs(elapsed - 0.25) < 1e-6,
        "lazy Heartbeat connection must still execute its callback")
    heartbeat:Disconnect()
    assert(tasks.connection == nil,
        "last Heartbeat task must close its signal")

    local render = tasks:Connect(function() end, "render")
    assert(tasks.renderConnection ~= nil,
        "first render task must open its own signal")
    render:Disconnect()
    assert(tasks.renderConnection == nil,
        "last render task must close its own signal")
    tasks:Destroy()
    print("[STARTUP RESTORE] transactional boot, session-only physics and lazy schedulers verified")
end
'''

BUILD.parent.mkdir(parents=True, exist_ok=True)
BUILD.write_text(source, encoding="utf-8")
luau = os.environ.get("LUAU") or str(ROOT / "tools" / "luau" / "bin" / "luau")
result = subprocess.run(
    [luau, str(BUILD)],
    cwd=ROOT,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
)
LOG.write_text(result.stdout, encoding="utf-8")
if result.returncode != 0:
    print(result.stdout, end="")
    raise SystemExit(result.returncode)
assert "Load complete · failures=0" in result.stdout, result.stdout
assert "[HARNESS] done" in result.stdout, result.stdout
assert "[STARTUP RESTORE] transactional boot" in result.stdout, result.stdout
print("PASS startup restore gate, session-only physics and lazy TaskManager")
