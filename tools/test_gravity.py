#!/usr/bin/env python3
"""Execute Gravity's real enable/disable/unload ownership path in a mock workspace."""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/games/universal/Movement/Gravity.lua").read_text()

script = r'''
local world={Gravity=196.2}
local tick,feature,setValue
local host={workspace=world,featureConnections={}}
host.TaskManager={Connect=function(_,fn) tick=fn;return {Disconnect=function() tick=nil end} end}
function host.disconnectFeatureConnection(key)
    local conn=host.featureConnections[key]
    if conn then conn:Disconnect();host.featureConnections[key]=nil end
end
function host.createUniversalFeature(name,_,_,toggle,options)
    feature={name=name,toggle=toggle,enabled=false,options=options}
    function feature:SetStatus(value) self.status=value end
    return feature
end
function host.addNumberOption(_,_,_,_,_,callback) setValue=callback end
'''+"\nlocal Module=(function()\n"+SOURCE+"\nend)()\n"+r'''
Module.init({host=host})
assert(not tick and world.Gravity==196.2, "injection with Gravity OFF changes nothing")
world.Gravity=100
Module.destroy()
assert(world.Gravity==100, "unloading an unused module must not overwrite the game's new gravity")
Module.init({host=host})
feature.enabled=true;feature.toggle(true)
assert(tick)
tick();assert(world.Gravity==196.2)
setValue(-20);tick();assert(world.Gravity==-20, "negative manual gravity remains usable")
world.Gravity=300;tick();assert(world.Gravity==-20, "ON keeps the selected value")
feature.enabled=false;feature.toggle(false)
assert(not tick and world.Gravity==100 and feature.status==nil, "OFF restores the value captured at enable")
world.Gravity=50;Module.destroy()
assert(world.Gravity==50, "unload after OFF does not write a stale snapshot")
Module.init({host=host});feature.enabled=true;feature.toggle(true);tick()
assert(world.Gravity==196.2)
Module.destroy()
assert(not tick and world.Gravity==50, "unload while ON restores the latest captured gravity")
print("PASS Gravity: inert injection, typed negatives, external writes and exact ON/OFF/unload ownership")
'''

with tempfile.TemporaryDirectory(prefix="gravity-") as tmp:
    path=Path(tmp)/"test.luau"
    path.write_text(script)
    subprocess.run([os.environ.get("LUAU", "luau"),str(path)],check=True)
