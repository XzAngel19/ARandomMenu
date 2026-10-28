#!/usr/bin/env python3
"""Execute the X2 live evidence collector against a faithful small mock.

This checks the collector's own file, hook and cleanup behavior. It does not
claim to validate executor-specific decompilation or a live X2 remote schema.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

import gen_full_boot_harness as harness

ROOT = harness.ROOT
LUAU = os.environ.get("LUAU", str(ROOT / "tools" / "luau" / "bin" / "luau"))
OUT = ROOT / "build" / "x2duels_decompiler_test.luau"

SETUP = r'''
XDG = {
    files = {}, folders = {}, forwarded = {}, nativeIncoming = {},
    currentMethod = "", activeNamecall = nil, caller = nil,
}
function writefile(path, contents)
    if string.find(path, "XDWriteFailScript", 1, true)
        and string.sub(path, -5) == ".luau" then
        error("synthetic source write failure")
    end
    XDG.files[path] = contents
end
function makefolder(path) XDG.folders[path] = true end
appendfile = nil
readfile = nil -- Exercise the in-memory append fallback.

function XDFullName(instance, path)
    instance.GetFullName = function() return path end
end
local xdReplicated = game:GetService("ReplicatedStorage")
XDFullName(xdReplicated, "ReplicatedStorage")
local xdLocal = game:GetService("Players").LocalPlayer
if xdLocal.PlayerGui then xdLocal.PlayerGui.Parent = xdLocal end

local function xdScript(className, name)
    local script = Instance.new(className)
    script.Name = name
    script.Parent = xdReplicated
    XDFullName(script, "ReplicatedStorage." .. name)
    return script
end
XDGoodScript = xdScript("ModuleScript", "XDGoodScript")
xdScript("LocalScript", "XDPanicScript")
xdScript("ModuleScript", "XDEmptyScript")
xdScript("ModuleScript", "XDWriteFailScript")

local function xdRemote(className, name)
    local remote = Instance.new(className)
    remote.Name = name
    remote.Parent = xdReplicated
    XDFullName(remote, "ReplicatedStorage." .. name)
    return remote
end
XDCaptureRemote = xdRemote("RemoteEvent", "XDCaptureRemote")
XDCaptureFunction = xdRemote("RemoteFunction", "XDCaptureFunction")
XDCaptureRemote.OnClientEvent:Connect(function(...)
    XDG.nativeIncoming = {...}
end)

local xdTool = Instance.new("Tool")
xdTool.Name = "DefaultGun"
local xdBackpack = xdLocal:FindFirstChildOfClass("Backpack")
assert(xdBackpack, "fixture Backpack missing")
xdTool.Parent = xdBackpack
local xdToolRemote = Instance.new("RemoteEvent")
xdToolRemote.Name = "Shoot"
xdToolRemote.Parent = xdTool
local xdPumpkinModel = Instance.new("Model")
xdPumpkinModel.Name = "PumpkinCurrency_77"
xdPumpkinModel.Parent = workspace
local xdPumpkin = Instance.new("Part")
xdPumpkin.Name = "Pumpkin"
xdPumpkin.Position = Vector3.new(4, 5, 6)
xdPumpkin.CanTouch = false
xdPumpkin.Parent = xdPumpkinModel
local xdButton = Instance.new("TextButton")
xdButton.Name = "PlayAgainButton"
xdButton.Text = "Play Again"
xdButton.Parent = xdLocal.PlayerGui

function decompile(script)
    if script.Name == "XDPanicScript" then
        return "-- decompilation panicked: synthetic placeholder"
    end
    if script.Name == "XDEmptyScript" then return "" end
    return "-- recovered " .. script.Name
end
function getscriptbytecode(script) return "BC-" .. script.Name end

XDG.originalNamecall = function(self, ...)
    table.insert(XDG.forwarded, {self = self, arguments = {...}})
    return "forwarded", ...
end
XDG.activeNamecall = XDG.originalNamecall
function hookmetamethod(target, method, replacement)
    assert(target == game and method == "__namecall")
    local previous = XDG.activeNamecall
    XDG.activeNamecall = replacement
    return previous
end
function getnamecallmethod() return XDG.currentMethod end
function getcallingscript() return XDG.caller end
function checkcaller() return false end
function getrawmetatable() return {} end
function setreadonly() end
function isreadonly() return true end
XDG.caller = XDGoodScript

local xdHttp = game:GetService("HttpService")
function xdHttp:JSONEncode(value)
    if value.direction then
        local entries = value.arguments.entries
        local first = entries[1] and entries[1].value or "<none>"
        if type(first) == "table" and first.type == "buffer" then
            first = "buffer:" .. tostring(first.length) .. ":" .. tostring(first.hex)
        else
            first = tostring(first)
        end
        local secondType = entries[2] and type(entries[2].value) == "table"
            and entries[2].value.type or "none"
        local thirdType = entries[3] and type(entries[3].value) == "table"
            and entries[3].value.type or "none"
        return table.concat({
            value.direction, value.method, value.path, value.parent,
            value.caller, first, secondType, thirdType, tostring(value.executor),
        }, "|")
    end
    if value.weaponScripts then
        XDG.weaponSnapshots = XDG.weaponSnapshots or {}
        XDG.weaponSnapshots[value.snapshot] = value
    elseif value.remotes then XDG.inventory = value
    elseif value.stopped ~= nil then XDG.status = value
    elseif value.decompile ~= nil then XDG.capabilities = value
    elseif value[1] and value[1].decompiled ~= nil then XDG.manifest = value
    end
    return "{}"
end
'''

PROBE = r'''
local controller = getgenv().X2DuelsDecompiler
assert(type(controller) == "table", "collector controller missing")
assert(controller.isSourceDumpDone(), "source dump did not finish")
assert(type(XDG.manifest) == "table", "source manifest missing")
local byName = {}
for _, entry in ipairs(XDG.manifest) do byName[entry.name] = entry end
local good = byName.XDGoodScript
assert(good and good.decompiled and good.usableSource and good.sourceFile,
    "usable source was not recorded")
assert(XDG.files[good.sourceFile] == "-- recovered XDGoodScript",
    "source contents differ")
local panic = byName.XDPanicScript
assert(panic and panic.decompiled and not panic.usableSource,
    "panicked decompilation was marked as usable source")
local empty = byName.XDEmptyScript
assert(empty and not empty.decompiled and empty.error and empty.bytecodeFile,
    "empty source did not retain its bytecode fallback")
local failedWrite = byName.XDWriteFailScript
assert(failedWrite and failedWrite.sourceWriteError and not failedWrite.sourceFile
    and failedWrite.bytecodeFile, "failed source write was reported as saved")
assert(XDG.capabilities and XDG.capabilities.getcallingscript and XDG.capabilities.debugInfo,
    "executor attribution capabilities were not recorded")
assert(XDG.capabilities.checkcaller and XDG.capabilities.getrawmetatable
    and XDG.capabilities.setreadonly and XDG.capabilities.isreadonly,
    "anonymous Mouse/raw metatable capability presence was not recorded")

-- The initial capture was made before this respawn and tool existed. A fresh
-- snapshot must use the CURRENT character and explicitly decompile the tool.
local replacementCharacter = Instance.new("Model")
replacementCharacter.Name = "ReplacementCharacter"
replacementCharacter.Parent = workspace
xdLocal.Character = replacementCharacter
local lateGun = Instance.new("Tool")
lateGun.Name = "LateDefaultGun"
lateGun.Parent = replacementCharacter
local lateScript = Instance.new("LocalScript")
lateScript.Name = "LateGunLocalScript"
lateScript.Parent = lateGun
controller.snapshot()
local foundLateInventory = false
for _, entry in ipairs(XDG.inventory.scripts) do
    if entry.name == "LateGunLocalScript" then foundLateInventory = true end
end
assert(foundLateInventory, "snapshot used a stale character after respawn")
controller.snapshotWeapons()
assert(controller.areWeaponSnapshotsDone(), "weapon snapshot never completed")
local weaponSnapshot = XDG.weaponSnapshots and XDG.weaponSnapshots[1]
assert(weaponSnapshot and weaponSnapshot.complete and #weaponSnapshot.tools >= 1,
    "late equipped tool was not captured")
local lateEntry = nil
for _, entry in ipairs(weaponSnapshot.weaponScripts) do
    if entry.name == "LateGunLocalScript" then lateEntry = entry end
end
assert(lateEntry and lateEntry.usableSource and lateEntry.sourceFile and lateEntry.bytecodeFile
    and XDG.files[lateEntry.sourceFile] == "-- recovered LateGunLocalScript"
    and XDG.files[lateEntry.bytecodeFile] == "BC-LateGunLocalScript",
    "dynamic gun source or bytecode was missed")

XDG.currentMethod = "FireServer"
local returned, firstArg = XDG.activeNamecall(XDCaptureRemote, "Alpha", 7, {Nested = true})
assert(returned == "forwarded" and firstArg == "Alpha", "outgoing result changed")
XDG.currentMethod = "InvokeServer"
local invoked = XDG.activeNamecall(XDCaptureFunction, "Request")
assert(invoked == "forwarded", "RemoteFunction result changed")
XDG.currentMethod = "FireServer"
XDG.activeNamecall(XDCaptureRemote, buffer.fromstring("ABC"))
XDG.activeNamecall({}, "not a remote")
XDCaptureRemote.OnClientEvent:Fire("IncomingArg", Vector3.new(1, 2, 3))
assert(XDG.nativeIncoming[1] == "IncomingArg", "native incoming handler was displaced")
assert(#XDG.forwarded == 4, "not every outgoing call reached its predecessor")

local log = XDG.files[controller.folder .. "/remote-calls.jsonl"]
assert(type(log) == "string", "remote JSONL log missing")
assert(string.find(log, "outgoing|FireServer|ReplicatedStorage.XDCaptureRemote|ReplicatedStorage|ReplicatedStorage.XDGoodScript|Alpha", 1, true),
    "outgoing parent/caller/arguments missing\n" .. tostring(log))
assert(string.find(log, "outgoing|InvokeServer|ReplicatedStorage.XDCaptureFunction", 1, true),
    "RemoteFunction call missing")
assert(string.find(log, "buffer:3:414243", 1, true), "buffer bytes missing")
assert(string.find(log, "incoming|OnClientEvent|ReplicatedStorage.XDCaptureRemote", 1, true),
    "incoming call missing")
assert(string.find(log, "IncomingArg|Vector3", 1, true), "incoming arguments missing")
assert(not string.find(log, "not a remote", 1, true), "non-remote namecall was recorded")

assert(type(XDG.inventory) == "table" and #XDG.inventory.remotes >= 2
    and #XDG.inventory.spawnables == 1 and #XDG.inventory.tools >= 1
    and #XDG.inventory.buttons >= 1, "hierarchy inventory incomplete")
local remoteInfo = nil
for _, info in ipairs(XDG.inventory.remotes) do
    if info.name == "XDCaptureRemote" then remoteInfo = info end
end
assert(remoteInfo and remoteInfo.parent == "ReplicatedStorage",
    "fully parented remote inventory missing")

local collectorHook = XDG.activeNamecall
local foreignHook = function(...) return collectorHook(...) end
XDG.activeNamecall = foreignHook
controller.stop()
assert(XDG.activeNamecall == foreignHook, "stop displaced a hook installed later")
assert(XDG.status and XDG.status.stopped and XDG.status.sourcesDone
    and XDG.status.weaponSnapshotsIssued == 1 and XDG.status.weaponSnapshotsCompleted == 1,
    "stop status incomplete")
local logAtStop = XDG.files[controller.folder .. "/remote-calls.jsonl"]
XDG.currentMethod = "FireServer"
XDG.activeNamecall(XDCaptureRemote, "AfterStop")
XDCaptureRemote.OnClientEvent:Fire("AfterStop")
assert(XDG.files[controller.folder .. "/remote-calls.jsonl"] == logAtStop,
    "capture continued after stop")
controller.stop()
print("[X2DECOMPILER] sources, dynamic weapons, parents, remote capture and cleanup: PASS")
'''


def main() -> None:
    source = (ROOT / "tools" / "X2DuelsDecompiler.luau").read_text(encoding="utf-8")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(harness.PRELUDE + SETUP + source + PROBE, encoding="utf-8")
    result = subprocess.run(
        [LUAU, str(OUT)], cwd=ROOT, capture_output=True, text=True, check=False,
    )
    if result.returncode:
        raise SystemExit(result.stdout + result.stderr)
    marker = "[X2DECOMPILER] sources, dynamic weapons, parents, remote capture and cleanup: PASS"
    if marker not in result.stdout:
        raise AssertionError("decompiler harness marker missing\n" + result.stdout)
    print(marker)

    # A missing mobile API must be reported as false, not inferred from another
    # executor API. This is a fresh mock, not a live compatibility probe.
    unavailable = SETUP.replace("function checkcaller() return false end", "checkcaller = nil")
    unavailable = unavailable.replace("function getrawmetatable() return {} end", "getrawmetatable = nil")
    unavailable = unavailable.replace("function setreadonly() end", "setreadonly = nil")
    unavailable = unavailable.replace("function isreadonly() return true end", "isreadonly = nil")
    negative_probe = r'''
assert(XDG.capabilities and XDG.capabilities.checkcaller == false
    and XDG.capabilities.getrawmetatable == false
    and XDG.capabilities.setreadonly == false
    and XDG.capabilities.isreadonly == false,
    "missing executor capabilities were not reported as false")
getgenv().X2DuelsDecompiler.stop()
print("[X2DECOMPILER] absent mobile APIs reported: PASS")
'''
    OUT.write_text(harness.PRELUDE + unavailable + source + negative_probe, encoding="utf-8")
    result = subprocess.run(
        [LUAU, str(OUT)], cwd=ROOT, capture_output=True, text=True, check=False,
    )
    negative_marker = "[X2DECOMPILER] absent mobile APIs reported: PASS"
    if result.returncode or negative_marker not in result.stdout:
        raise SystemExit(result.stdout + result.stderr)
    print(negative_marker)


if __name__ == "__main__":
    main()
