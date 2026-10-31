#!/usr/bin/env python3
"""Execute Anti AFK's actual fallback and cleanup paths with mocked services.

A successful mock call does not demonstrate that Roblox resets an idle timer.
"""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/games/universal/Other/AntiAfk.lua").read_text()

script = r'''
local vectorMeta = {}
vectorMeta.__div=function(v,n) return setmetatable({X=v.X/n,Y=v.Y/n}, vectorMeta) end
local Vector2={new=function(x,y) return setmetatable({X=x,Y=y}, vectorMeta) end}
local function signal()
    local listeners={}
    local event={}
    function event:Connect(fn)
        local connection={}
        listeners[connection]=fn
        function connection:Disconnect() listeners[self]=nil end
        return connection
    end
    function event:Fire() for _,fn in pairs(listeners) do fn() end end
    function event:Count() local n=0;for _ in pairs(listeners) do n+=1 end;return n end
    return event
end
local idle=signal()
local mode="full"
local calls={}
local mousePositions={}
local virtual={}
function virtual:CaptureController() table.insert(calls,"capture") end
function virtual:Button2Down(pos)
    table.insert(calls,"down");table.insert(mousePositions,pos)
    if mode~="full" then error("denied") end
end
function virtual:Button2Up() table.insert(calls,"up") end
function virtual:ClickButton2(pos)
    table.insert(calls,"legacy");table.insert(mousePositions,pos)
    if mode~="legacy" then error("denied") end
end
local vim={}
function vim:SendMouseButtonEvent(x,y,_,down)
    table.insert(calls,down and "inputDown" or "inputUp")
    table.insert(mousePositions,{X=x,Y=y})
    if mode~="input" then error("denied") end
end
local game={}
function game:GetService(name)
    if mode=="unsupported" then error("not available") end
    if name=="VirtualUser" then return virtual end
    if name=="VirtualInputManager" then return vim end
    error("unexpected service")
end
local tick,feature
local host={LocalPlayer={Idled=idle},featureConnections={},
    workspace={CurrentCamera={ViewportSize=Vector2.new(1200,800),CFrame={}}}}
host.TaskManager={Connect=function(_,fn)
    tick=fn;return {Disconnect=function() tick=nil end}
end}
function host.disconnectFeatureConnection(key)
    local conn=host.featureConnections[key]
    if conn then conn:Disconnect();host.featureConnections[key]=nil end
end
function host.createUniversalFeature(name,_,_,toggle,options)
    feature={name=name,toggle=toggle,options=options};return feature
end
function host.addFeatureTooltip() end
'''+"\nlocal Module=(function()\n"+SOURCE+"\nend)()\n"+r'''
Module.init({host=host})
assert(feature.name=="Anti AFK" and not tick and idle:Count()==0 and #calls==0,
    "injection with Anti AFK OFF is inert")
feature.toggle(true)
assert(tick and idle:Count()==1)
tick(149);assert(#calls==0)
tick(1);assert(table.concat(calls,",")=="capture,down,up", "timer tries VirtualUser")
assert(mousePositions[1].X==600 and mousePositions[1].Y==400, "uses the viewport centre")
table.clear(calls);mode="legacy";idle:Fire()
assert(table.concat(calls,",")=="capture,down,legacy", "legacy click follows denied down")
table.clear(calls);mode="input";idle:Fire()
assert(table.concat(calls,",")=="capture,down,legacy,inputDown,inputUp",
    "VirtualInputManager follows denied VirtualUser calls")
table.clear(calls);table.clear(mousePositions);host.workspace.CurrentCamera=nil;idle:Fire()
assert(mousePositions[#mousePositions].X==400 and mousePositions[#mousePositions].Y==300,
    "missing camera uses the centre fallback")
table.clear(calls);mode="unsupported";idle:Fire();assert(#calls==0, "unsupported services do not throw")
feature.toggle(false);assert(not tick and idle:Count()==0)
feature.toggle(true);assert(tick and idle:Count()==1)
Module.destroy();assert(not tick and idle:Count()==0, "unload disconnects both paths")
print("PASS Anti AFK runtime: timer, Idled, native/legacy/input fallbacks, missing camera and cleanup")
'''

with tempfile.TemporaryDirectory(prefix="anti-afk-") as tmp:
    path = Path(tmp) / "test.luau"
    path.write_text(script)
    subprocess.run([os.environ.get("LUAU", "luau"), str(path)], check=True)
