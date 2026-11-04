#!/usr/bin/env python3
"""Exercise fog movement and cleanup against the real Shaders source.

This models Roblox properties and signals. It does not render particles or
measure actual CPU, GPU, latency, or compatibility with any executor.
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
card.Options["Surface textures"].Metadata.callback(false)
card.Options["Glass reflections"].Metadata.callback(false)
features.Shaders.toggle(true)
local localRoot=part("HumanoidRootPart",Enum.Material.Plastic,Vector3.new(2,2,1),localCharacter)
localRoot.Position=Vector3.new(0,10,0);localRoot.Anchored=false
localRoot.AssemblyLinearVelocity=Vector3.new(9,0,0)
local remoteChar=Instance.new("Model");remoteChar.Name="RemoteCharacter";remoteChar.Parent=world
local remoteHum=Instance.new("Humanoid");remoteHum.Parent=remoteChar
local remoteRoot=part("HumanoidRootPart",Enum.Material.Plastic,Vector3.new(2,2,1),remoteChar)
remoteRoot.Position=Vector3.new(36,10,0);remoteRoot.Anchored=false
remoteRoot.AssemblyLinearVelocity=Vector3.new(0,0,0)
local remote={Character=remoteChar}
local playerList={host.LocalPlayer,remote}
local playerReads=0
host.Players={GetPlayers=function() playerReads+=1;return playerList end}
card.Options.Fog.Metadata.callback(true)
local fogFolder=assert(byName(world,"ARMShaderWeather"))
local function cells()
    local list={}
    for _,p in ipairs(children(fogFolder,"Part")) do if p.Name=="FogCell" then table.insert(list,p) end end
    return list
end
local function at(x,z)
    for _,p in ipairs(cells()) do
        if p.Position and p.Position.X==x and p.Position.Z==z then return p end
    end
end
local function waitSample()
    local before=playerReads
    for i=1,10 do
        frames(1,0.05)
        if playerReads>before then return end
    end
    error("fog actor sampling did not run")
end
frames(1,0.05)
assert(#cells()==17 and activeHandles("Shaders weather")==1 and activeHandles("Shaders surfaces")==0)
local center=assert(byName(at(0,0),"Fog mist"))
assert(center.Acceleration.X>2 and center.Acceleration.Z==0.04,
    "moving local root must apply an outward acceleration to its live mist patch")
assert(center.Transparency.Keypoints[1].Value==1 and center.Transparency.Keypoints[4].Value==1,
    "mist fades in and out instead of popping")
local countBefore=playerReads
frames(120,1/60)
assert(playerReads-countBefore<=9,"the player list is sampled at most about four times per second")

-- A remote player moves near another patch while the local avatar is still.
localRoot.AssemblyLinearVelocity=Vector3.new(0,0,0)
remoteRoot.Position=Vector3.new(36.2,10,0)
remoteRoot.AssemblyLinearVelocity=Vector3.new(-8,0,0)
waitSample()
local remoteMist=assert(byName(at(36,0),"Fog mist"))
assert(remoteMist.Acceleration.X < -1,
    "a remote moving body affects the nearby patch, not only the local avatar")
local printed={}
local savedPrint=print
print=function(s) table.insert(printed,tostring(s)) end
card.Options.Diagnose.Metadata.callback()
print=savedPrint
assert(table.concat(printed,"\n"):find("fogCells=17 moving=1",1,true),
    "diagnostics report actual mist patches and sampled moving actors")

-- Position differences cover movement not reflected in AssemblyLinearVelocity.
remoteRoot.AssemblyLinearVelocity=Vector3.new(0,0,0)
waitSample()
assert(math.abs(remoteMist.Acceleration.X-0.12)<0.01,"stopping restores the gentle wind")
remoteRoot.Position=Vector3.new(40,10,0)
waitSample()
assert(remoteMist.Acceleration.X < -1,"CFrame-style root movement also displaces mist")
waitSample()
assert(math.abs(remoteMist.Acceleration.X-0.12)<0.01,"a stopped root does not push forever")
remote.Character=nil
waitSample()
assert(math.abs(remoteMist.Acceleration.X-0.12)<0.01,"a removed or streamed-out character is ignored")

-- A replacement character must not inherit the previous character's motion.
local replacement=Instance.new("Model");replacement.Parent=world
local newRoot=part("HumanoidRootPart",Enum.Material.Plastic,Vector3.new(2,2,1),replacement)
newRoot.Position=Vector3.new(36,10,0);newRoot.AssemblyLinearVelocity=Vector3.new(0,0,0)
remote.Character=replacement;waitSample()
assert(math.abs(remoteMist.Acceleration.X-0.12)<0.01,"respawn does not compare unrelated roots")
newRoot.AssemblyLinearVelocity=Vector3.new(5,0,0);waitSample()
assert(remoteMist.Acceleration.X>1,"replacement roots are detected")
newRoot.Position=Vector3.new(112.2,10,0);newRoot.AssemblyLinearVelocity=Vector3.new(-5,0,0)
waitSample()
local outerMist=assert(byName(at(112,0),"Fog mist"))
assert(outerMist.Rate==1 and outerMist.Acceleration.X < -1,
    "the sparse outer fog can respond to another player far from the local body")

-- More players do not multiply emitters or create an unbounded per-frame loop.
local reads={}
playerList={host.LocalPlayer}
for i=1,50 do
    local character=Instance.new("Model");character.Parent=world
    local root=part("HumanoidRootPart",Enum.Material.Plastic,Vector3.new(2,2,1),character)
    root.Position=Vector3.new(4,10,0);root.AssemblyLinearVelocity=Vector3.new(3,0,0)
    local player=setmetatable({}, {__index=function(_,key)
        if key=="Character" then reads[i]=(reads[i] or 0)+1;return character end
    end})
    table.insert(playerList,player)
end
reads={};waitSample()
local firstTotal=0
for _,n in pairs(reads) do firstTotal+=n end
assert(firstTotal<=16,"at most 16 non-local player slots are sampled in one pass")
for _=1,4 do waitSample() end
local visited=0
for _,n in pairs(reads) do if n>0 then visited+=1 end end
assert(visited==50,"round-robin eventually samples every remote player")
assert(#cells()==17,"player count must not create per-character emitters")

world.CurrentCamera=nil;frames(2)
for _,p in ipairs(cells()) do assert(not byName(p,"Fog mist").Enabled) end
world.CurrentCamera=camera;frames(2)
for _,p in ipairs(cells()) do assert(byName(p,"Fog mist").Enabled) end
card.Options.Fog.Metadata.callback(false);flushDeferred();runAllSpawned()
assert(fogFolder.destroyed and activeHandles("Shaders weather")==0 and lighting.FogEnd==1000,
    "OFF destroys all mist, disconnects its loop and restores game fog")

-- Touch/keyboard hybrids and mobile receive the reduced mist budget.
host.state.isMobile=false;host.UserInputService={TouchEnabled=true}
card.Options.Fog.Metadata.callback(true)
fogFolder=byName(world,"ARMShaderWeather");frames(2)
for _,p in ipairs(cells()) do assert(byName(p,"Fog mist").Rate==1) end
local mobileRate=0
for _,p in ipairs(cells()) do mobileRate+=byName(p,"Fog mist").Rate end
assert(mobileRate==17)
card.Options.Fog.Metadata.callback(false);runAllSpawned()
host.UserInputService=nil

-- An older client without sequence keypoints retains a constant fallback.
local sequenceKeys=NumberSequenceKeypoint
NumberSequenceKeypoint=nil
card.Options.Fog.Metadata.callback(true)
card.Options.Snow.Metadata.callback(true)
fogFolder=byName(world,"ARMShaderWeather");frames(65)
assert(byName(byName(fogFolder,"FogCell"),"Fog mist").Transparency.Value==0.78,
    "mist survives unavailable optional fade keypoints")
local snowFallback
for _,p in ipairs(children(fogFolder,"Part")) do
    if p.Name=="WeatherCell" then snowFallback=byName(p,"Snow");break end
end
assert(snowFallback and snowFallback.Enabled and snowFallback.Transparency.Value==0.12)
card.Options.Snow.Metadata.callback(false)
card.Options.Fog.Metadata.callback(false);runAllSpawned()
NumberSequenceKeypoint=sequenceKeys

-- Acceleration is optional on a restricted client: weather must stay alive.
Instance.failProperty.ParticleEmitter={Acceleration=true,name="Fog mist"}
card.Options.Rain.Metadata.callback(true)
card.Options.Fog.Metadata.callback(true)
fogFolder=byName(world,"ARMShaderWeather");frames(65)
local precipitation
for _,p in ipairs(children(fogFolder,"Part")) do
    if p.Name=="WeatherCell" then precipitation=byName(p,"Rain");break end
end
assert(precipitation and precipitation.Enabled and activeHandles("Shaders weather")==1,
    "an unavailable mist acceleration does not stop rain or global haze")
Instance.failProperty.ParticleEmitter=nil
features.Shaders.toggle(false);runAllSpawned();flushDeferred()
assert(activeHandles()==0 and not byName(world,"ARMShaderWeather"))
print("PASS shader fog: local/remote movement, bounded sampling, respawn, compact mode and cleanup")
'''


def main() -> None:
    source = (PRELUDE + "\nlocal FRAMEWORK_SOURCE = " + lua_quote(FRAMEWORK)
              + "\nlocal SHADERS_SOURCE = " + lua_quote(SHADERS) + "\n" + BODY)
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "fog_movement.luau"
        path.write_text(source, encoding="utf-8")
        subprocess.run([os.environ.get("LUAU", "luau"), str(path)], check=True)


if __name__ == "__main__":
    main()
