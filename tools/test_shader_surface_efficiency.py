#!/usr/bin/env python3
"""Check bounded surface work, event-driven changes and overflow recovery.

The simulated scheduler only verifies code paths and operation counts, not FPS.
"""
import os
import subprocess
import tempfile
from pathlib import Path

from test_shaders import FRAMEWORK, PRELUDE, SHADERS, lua_quote

BODY = r'''
local Framework=assert(loadstring(FRAMEWORK_SOURCE))()
local framework=Framework.init(host)
local Shaders=assert(loadstring(SHADERS_SOURCE))()
local card=Shaders.init({framework=framework,host=host,libraries={}})
card.Options["Glass reflections"].Metadata.callback(false)
local originals={}
for i=1,350 do
    table.insert(originals,part("Coverage"..i,Enum.Material.Concrete,Vector3.new(20,1,20)))
end

-- The first second must do the same amount of bounded work at 60 and 120 Hz.
features.Shaders.toggle(true)
local start=created.Texture or 0
frames(60,1/60)
local at60=(created.Texture or 0)-start
features.Shaders.toggle(false);runAllSpawned()
features.Shaders.toggle(true)
start=created.Texture or 0
frames(120,1/120)
local at120=(created.Texture or 0)-start
assert(at60>70 and at60<=120 and math.abs(at60-at120)<=4,
    "surface jobs should be cadence-bound, not double at higher FPS: "..at60.."/"..at120)

-- After a complete pass, game decals and streamed objects are prioritized;
-- the root hierarchy is not needlessly rescanned every two seconds.
frames(200,0.05)
for _,p in ipairs(originals) do assert(textureOf(p),"initial full-map pass eventually reaches all eligible parts") end
local beforeRootReads=rootReads
frames(200,0.05)
assert(rootReads==beforeRootReads,"idle surface handling must not restart the world pass during the first 10 seconds")
local wall=originals[1]
local decal=Instance.new("Decal");decal.Face=Enum.NormalId.Top;decal.Parent=wall
world.DescendantAdded:Fire(decal);frames(1,0.05)
assert(not textureOf(wall),"a newly added game decal must win without waiting 30 seconds")
-- Deferred Roblox signals can arrive after Parent has already become nil.
decal.Parent=nil;world.DescendantRemoving:Fire(decal);decal:Destroy();frames(1,0.05)
assert(textureOf(wall),"a deferred removal still releases its previously blocked face")
local preblocked=part("PreBlocked",Enum.Material.Concrete,Vector3.new(20,1,20))
local existing=Instance.new("Decal");existing.Face=Enum.NormalId.Top;existing.Parent=preblocked
world.DescendantAdded:Fire(preblocked);frames(1,0.05)
assert(not textureOf(preblocked),"an already-present decal reserves its face")
existing.Parent=nil;world.DescendantRemoving:Fire(existing);existing:Destroy();frames(1,0.05)
assert(textureOf(preblocked),"scanned game decals retain a bounded owner for deferred removal")
local streamed=part("FarStreamed",Enum.Material.Concrete,Vector3.new(20,1,20))
streamed.Position=Vector3.new(10000,0,0)
world.DescendantAdded:Fire(streamed);frames(1,0.05)
assert(textureOf(streamed),"distant streamed-in parts are not limited to the camera radius")
world.DescendantRemoving:Fire(streamed);streamed.Parent=nil
assert(not textureOf(streamed),"streaming removal releases a record immediately")
frames(650,0.05)
assert(rootReads>beforeRootReads,"the slower fallback pass eventually reconciles silent changes")

-- A single giant streamed model can overflow the bounded priority queue.
-- Its dropped tail is recovered by the normal hierarchy walk rather than lost.
local tail={}
for i=1,2100 do
    local eligible=i>2080
    local p=part("Burst"..i,if eligible then Enum.Material.Concrete else Enum.Material.Metal,Vector3.new(20,1,20))
    if eligible then table.insert(tail,p) end
    world.DescendantAdded:Fire(p)
end
local captured={};local realPrint=print
print=function(s) table.insert(captured,tostring(s)) end
card.Options.Diagnose.Metadata.callback()
print=realPrint
local joined=table.concat(captured,"\n")
local dropped=tonumber(joined:match("queueDrops=(%d+)"))
assert(dropped and dropped>0,"queue overflow should be explicit in diagnostics")
frames(2200,0.05)
for _,p in ipairs(tail) do assert(textureOf(p),"dropped streamed entries must be reached by a recovery pass") end
features.Shaders.toggle(false);runAllSpawned()
assert(activeHandles()==0 and not textureOf(originals[1]),"surface cleanup disconnects and restores")
print("PASS shader surfaces: FPS-independent batches, quiet idle, events, distant coverage and overflow recovery")
'''


def main() -> None:
    source = (PRELUDE + "\nlocal FRAMEWORK_SOURCE = " + lua_quote(FRAMEWORK)
              + "\nlocal SHADERS_SOURCE = " + lua_quote(SHADERS) + "\n" + BODY)
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "surface_efficiency.luau"
        path.write_text(source, encoding="utf-8")
        subprocess.run([os.environ.get("LUAU", "luau"), str(path)], check=True)


if __name__ == "__main__":
    main()
