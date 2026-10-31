#!/usr/bin/env python3
"""Run Interact Extender lifecycle, settings and interrupted scans in mocked Roblox."""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/games/universal/Other/InteractExtender.lua").read_text()

script = r'''
local function signal()
    local listeners={};local event={}
    function event:Connect(fn)
        local connection={};listeners[connection]=fn
        function connection:Disconnect() listeners[self]=nil end
        return connection
    end
    function event:Fire(value) for _,fn in pairs(listeners) do fn(value) end end
    function event:Count() local n=0;for _ in pairs(listeners) do n+=1 end;return n end
    return event
end
local function prompt(distance,hold)
    return {Parent=true,MaxActivationDistance=distance,HoldDuration=hold,
        IsA=function(_,class) return class=="ProximityPrompt" end}
end
local function detector(distance)
    return {Parent=true,MaxActivationDistance=distance,
        IsA=function(_,class) return class=="ClickDetector" end}
end
local first=prompt(10,1.5)
local click=detector(12)
local workspace={objects={first,click},DescendantAdded=signal()}
function workspace:GetDescendants() return self.objects end
local jobs={}
local task={}
function task.spawn(fn)
    local co=coroutine.create(fn);table.insert(jobs,co)
    local ok,err=coroutine.resume(co);assert(ok,err)
end
function task.wait() coroutine.yield() end
local function resume(co)
    local ok,err=coroutine.resume(co);assert(ok,err)
end
local tick,feature,settings
local host={featureConnections={}}
host.TaskManager={Connect=function(_,fn) tick=fn;return {Disconnect=function() tick=nil end} end}
function host.disconnectFeatureConnection(key)
    local connection=host.featureConnections[key]
    if connection then connection:Disconnect();host.featureConnections[key]=nil end
end
function host.createUniversalFeature(name,_,_,toggle,options)
    feature={name=name,toggle=toggle,enabled=false,options=options}
    function feature:SetStatus(s) self.status=s end
    return feature
end
function host.addToggleOption(_,name,_,callback) settings[name]=callback end
function host.addNumberOption(_,name,_,_,_,callback) settings[name]=callback end
'''+"\nlocal Module=(function()\n"+SOURCE+"\nend)()\n"+r'''
settings={};Module.init({host=host})
assert(not tick and workspace.DescendantAdded:Count()==0 and first.MaxActivationDistance==10,
    "injection is inert")
feature.enabled=true;feature.toggle(true)
assert(first.MaxActivationDistance==32 and first.HoldDuration==1.5 and click.MaxActivationDistance==32)
settings["Interaction distance"](80);settings["Instant prompts"](true)
assert(first.MaxActivationDistance==80 and first.HoldDuration==0 and click.MaxActivationDistance==80)
settings["Proximity prompts"](false);settings["Click detectors"](false)
assert(first.MaxActivationDistance==10 and first.HoldDuration==1.5 and click.MaxActivationDistance==12,
    "individual toggles restore their original properties")
settings["Proximity prompts"](true);settings["Click detectors"](true)
local added=prompt(5,2);workspace.DescendantAdded:Fire(added)
assert(added.MaxActivationDistance==80 and added.HoldDuration==0, "new prompts are applied")
added.MaxActivationDistance=3;tick(.49);assert(added.MaxActivationDistance==3)
tick(.01);assert(added.MaxActivationDistance==80, "periodic refresh remains throttled")
feature.enabled=false;feature.toggle(false)
assert(first.MaxActivationDistance==10 and first.HoldDuration==1.5 and click.MaxActivationDistance==12
    and added.MaxActivationDistance==5 and added.HoldDuration==2 and not tick
    and workspace.DescendantAdded:Count()==0, "OFF restores and disconnects")

-- Each scan yields at 240 entries. OFF/ON must not let the previous
-- generation resume and mutate entry 241 of the next session.
workspace.objects={}
for i=1,241 do table.insert(workspace.objects,prompt(8,1)) end
feature.enabled=true;feature.toggle(true)
local old=jobs[#jobs]
assert(coroutine.status(old)=="suspended" and workspace.objects[241].MaxActivationDistance==8)
feature.enabled=false;feature.toggle(false)
feature.enabled=true;feature.toggle(true)
local current=jobs[#jobs]
assert(coroutine.status(current)=="suspended")
resume(old)
assert(workspace.objects[241].MaxActivationDistance==8, "stale scan must stop after OFF/ON")
resume(current)
assert(workspace.objects[241].MaxActivationDistance==80, "current scan reaches the final prompt")
Module.destroy()
assert(not tick and workspace.DescendantAdded:Count()==0 and workspace.objects[241].MaxActivationDistance==8,
    "unload restores the latest scan")
print("PASS Interact Extender: per-type settings, dynamic objects, refresh, scan cancellation and cleanup")
'''

with tempfile.TemporaryDirectory(prefix="interact-") as tmp:
    path=Path(tmp)/"test.luau"
    path.write_text(script)
    subprocess.run([os.environ.get("LUAU","luau"),str(path)],check=True)
