#!/usr/bin/env python3
"""Real Fullbright and Zoom owners: skip unchanged property writes and restore baselines.

Mocks validate property-level behavior; they don't measure Roblox frame time.
"""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
def module(path):
    return '(function()\n' + (ROOT / path).read_text() + '\nend)()'

script = r'''
local colorMt={__eq=function(a,b) return a.R==b.R and a.G==b.G and a.B==b.B end}
local Color3={fromRGB=function(r,g,b) return setmetatable({R=r,G=g,B=b},colorMt) end}
local function proxy(initial)
    local values=initial;local writes=0
    local object=setmetatable({}, {
        __index=function(_,key) return values[key] end,
        __newindex=function(_,key,value) values[key]=value;writes+=1 end,
    })
    return object,function() return writes end
end
local card
local function makeCard(definition)
    card={Options={},Enabled=false,cleaners={}}
    local function option(self,d)
        local value={Value=d.Default,definition=d}
        function value:Set(v) self.Value=v;if d.Function then d.Function(v) end end
        self.Options[d.Name]=value
        return value
    end
    card.CreateSlider=option;card.CreateToggle=option
    function card:Clean(callback) table.insert(self.cleaners,callback) end
    function card:Loop(callback) self.loop=callback end
    function card:Toggle(on)
        if self.Enabled==on then return end
        self.Enabled=on
        if not on then
            for i=#self.cleaners,1,-1 do self.cleaners[i]() end
            table.clear(self.cleaners);self.loop=nil
        end
        definition.Function(on)
    end
    return card
end
local framework={Categories={Render={CreateModule=function(_,definition) return makeCard(definition) end}}}
local lighting,lightingWrites=proxy({Brightness=2,GlobalShadows=true,FogEnd=900,
    Ambient="original",OutdoorAmbient="outside",ClockTime=7})
local context={host={Lighting=lighting},framework=framework}
'''+ '\nlocal Fullbright='+module('src/games/universal/Render/Fullbright.lua')+r'''
local bright=Fullbright.init(context);bright:Toggle(true)
assert(lighting.Brightness==3 and not lighting.GlobalShadows and lighting.ClockTime==7)
local writesAfterEnable=lightingWrites()
for _=1,60 do bright.loop(1/60) end
assert(lightingWrites()==writesAfterEnable, "Fullbright must not rewrite unchanged lighting 60 times")
lighting.Brightness=4;bright.loop(1/60);assert(lighting.Brightness==3, "external changes are still reasserted")
bright.Options['Time Changer']:Set(true);bright.loop(0)
assert(lighting.ClockTime==14)
local writesAfterTime=lightingWrites()
for _=1,20 do bright.loop(1/60) end
assert(lightingWrites()==writesAfterTime, "static time must not be rewritten")
lighting.ClockTime=18;bright.loop(0);assert(lighting.ClockTime==14)
bright:Toggle(false)
assert(lighting.Brightness==4 and lighting.ClockTime==18 and lighting.GlobalShadows==true
    and lighting.Ambient=="original" and lighting.OutdoorAmbient=="outside" and lighting.FogEnd==900,
    "OFF restores the latest observed external baseline")
Fullbright.destroy()

local player,playerWrites=proxy({CameraMinZoomDistance=60,CameraMaxZoomDistance=128,CameraMode='LockFirstPerson'})
local Enum={CameraMode={Classic='Classic'}}
local host={LocalPlayer=player,featureConnections={}}
function host.disconnectFeatureConnection(key)
    local conn=host.featureConnections[key]
    if conn then conn:Disconnect();host.featureConnections[key]=nil end
end
host.TaskManager={Connect=function(_,fn)
    return {tick=fn,Disconnect=function(self) self.disconnected=true end}
end}
local zoom,controls
function host.createUniversalFeature(_,_,_,callback)
    controls={};zoom={enabled=false}
    function zoom:SetStatus(value) self.status=value end
    function zoom:Toggle(value) self.enabled=value;callback(value) end
    return zoom
end
function host.addNumberOption(_,name,_,_,_,callback) controls[name]=callback end
function host.addToggleOption(_,name,_,callback) controls[name]=callback end
local access={enabled=false}
function access:ThroughWalls(value) self.enabled=value;return value end
'''+ '\nlocal Zoom='+module('src/games/universal/Render/ZoomUnlocker.lua')+r'''
Zoom.init({host=host,services={cameraAccess=access}})
assert(playerWrites()==0 and not host.featureConnections.ZoomUnlocker, "zoom OFF is inert")
zoom:Toggle(true)
assert(player.CameraMinZoomDistance==.5 and player.CameraMaxZoomDistance==400 and player.CameraMode=='Classic')
local zoomWrites=playerWrites()
for _=1,60 do host.featureConnections.ZoomUnlocker.tick() end
assert(playerWrites()==zoomWrites, "Zoom must not rewrite unchanged camera properties every frame")
player.CameraMaxZoomDistance=100;host.featureConnections.ZoomUnlocker.tick()
assert(player.CameraMaxZoomDistance==400, "Zoom still enforces its bounds after external changes")
controls['Maximum distance'](25);controls['Minimum distance'](50);controls['Through walls'](true)
assert(player.CameraMinZoomDistance==25 and player.CameraMaxZoomDistance==50 and access.enabled)
local connection=host.featureConnections.ZoomUnlocker
zoom:Toggle(false)
assert(connection.disconnected and not access.enabled and player.CameraMinZoomDistance==60
    and player.CameraMaxZoomDistance==128 and player.CameraMode=='LockFirstPerson', "Zoom OFF restores")
local afterOff=playerWrites();Zoom.destroy();assert(playerWrites()==afterOff)
print('PASS Fullbright/Zoom: no unchanged frame writes, external reassertion, options and ownership cleanup')
'''

with tempfile.TemporaryDirectory(prefix='render-updates-') as tmp:
    path=Path(tmp)/'test.luau';path.write_text(script)
    subprocess.run([os.environ.get('LUAU','luau'),str(path)],check=True)
