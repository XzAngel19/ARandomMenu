#!/usr/bin/env python3
"""Execute real reversible FPS lifecycle, including paused/stale worker races."""
import os
import subprocess
import tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'src/games/universal/Other/ImproveFps.lua').read_text()
PRELUDE=r'''
local Enum={Material={SmoothPlastic='SmoothPlastic'},RenderFidelity={Performance='Performance'},QualityLevel={Level01='Level01'},CoreGuiType={PlayerList='PlayerList',Backpack='Backpack',Chat='Chat',EmotesMenu='EmotesMenu'}}
local rendering={QualityLevel='Automatic'}
local function settings() return {Rendering=rendering} end
local handlers={}
local signal={Connect=function(_,fn)
    local h={Connected=true,fn=fn};function h:Disconnect() self.Connected=false end
    table.insert(handlers,h);return h
end}
local jobs={}
local task={spawn=function(fn)
    local thread=coroutine.create(fn);table.insert(jobs,thread)
    local ok,err=coroutine.resume(thread);assert(ok,err)
end,wait=function() coroutine.yield() end}
local function drain()
    for _,thread in ipairs(jobs) do
        while coroutine.status(thread)~='dead' do local ok,err=coroutine.resume(thread);assert(ok,err) end
    end
    jobs={}
end
local function object(class,props)
    local o=props or {};o.Parent=true;o.class=class
    function o:IsA(c) return c==class or (c=='BasePart' and (class=='Part' or class=='MeshPart')) or (c=='PostEffect' and class=='BloomEffect') or (c=='Light' and class=='PointLight') end
    function o:FindFirstChildOfClass(c) return self.humanoid and c=='Humanoid' and self.humanoid or nil end
    return o
end
local decal=object('Decal',{Transparency=.35})
local texture=object('Texture',{Transparency=0})
local mesh=object('MeshPart',{TextureID='texture-123',CastShadow=true,Material='Wood',Reflectance=.7})
local part=object('Part',{CastShadow=false,Material='Glass',Reflectance=0})
local off=object('ParticleEmitter',{Enabled=false})
local on=object('ParticleEmitter',{Enabled=true})
local beam=object('Beam',{Enabled=true})
local trail=object('Trail',{Enabled=false})
local smoke=object('Smoke',{Enabled=true})
local fire=object('Fire',{Enabled=true})
local sparkles=object('Sparkles',{Enabled=true})
local all={decal,texture,mesh,part,off,on,beam,trail,smoke,fire,sparkles}
for i=#all+1,270 do table.insert(all,object('Part',{CastShadow=true,Material='Marble',Reflectance=.2})) end
local baseline={}
for _,o in ipairs(all) do
    local snapshot={};for key,v in pairs(o) do if type(v)~='function' and key~='Parent' then snapshot[key]=v end end
    baseline[o]=snapshot
end
local visible=all
local workspace={DescendantAdded=signal,GetDescendants=function() return visible end}
local connections={}
local toggle,feature
local options={}
local host={
    featureConnections=connections,
    disconnectFeatureConnection=function(k) if connections[k] then connections[k]:Disconnect();connections[k]=nil end end,
    createUniversalFeature=function(name,_,_,fn,config)
        assert(name=='Improve FPS' and config.categoryName=='World')
        toggle=fn;feature={SetStatus=function(self,v) self.status=v end};return feature
    end,
    addToggleOption=function(_,name,default,fn) options[name]=fn;fn(default) end,
}
local function checkRestored()
    for o,properties in pairs(baseline) do
        for key,value in pairs(properties) do assert(o[key]==value,`not restored: {o.class}.{key}`) end
    end
end
'''
TEST=r'''
Module.init({host=host})
options['Simple materials'](true)
toggle(true)
assert(mesh.TextureID=='' and mesh.Material=='SmoothPlastic' and mesh.Reflectance==0)
assert(decal.Transparency==1 and texture.Transparency==1)
assert(not on.Enabled and not off.Enabled and not beam.Enabled)
assert(all[270].CastShadow==true,'worker should be paused after 250 objects')
local added=object('ParticleEmitter',{Enabled=true})
for _,h in ipairs(handlers) do if h.Connected then h.fn(added) end end
assert(not added.Enabled,'new descendants must be covered during initial scan')
-- Detached instances must be restored, not skipped because Parent is nil.
mesh.Parent=nil;on.Parent=nil
-- OFF then ON before the first worker wakes: old scans must be invalidated.
toggle(false);checkRestored();assert(added.Enabled)
visible={};toggle(true);drain()
assert(all[270].CastShadow==true,'old generation must not mutate the previous scene')
toggle(false);checkRestored()
-- Fully drained cycle, then change individual options while active.
mesh.Parent=true;on.Parent=true
visible=all;toggle(true);drain()
assert(all[270].Material=='SmoothPlastic')
options['Remove textures'](false);drain()
assert(mesh.TextureID=='texture-123' and decal.Transparency==.35 and texture.Transparency==0)
assert(mesh.Material=='SmoothPlastic' and not on.Enabled)
options['Simple materials'](false);drain()
assert(mesh.Material=='Wood' and mesh.Reflectance==.7 and part.Material=='Glass')
options['Disable particles'](false);drain()
assert(on.Enabled and not off.Enabled and beam.Enabled and not trail.Enabled)
Module.destroy();drain();checkRestored()
assert(feature.status==nil)
for _,h in ipairs(handlers) do assert(not h.Connected,'no descendant listeners after OFF') end

-- Exercise every new optimization against the actual module, not copies of
-- its setters. Protect own UI/touch, restore false values, cover late objects.
local function container(class,props,children)
    local o=object(class,props);o.Parent=nil
    o.DescendantAdded=signal;o.GetDescendants=function() return children or {} end
    return o
end
local bloom=object('BloomEffect',{Enabled=true})
local blur=object('BloomEffect',{Enabled=true})
local lighting=container('Lighting',{GlobalShadows=true,EnvironmentDiffuseScale=.6,EnvironmentSpecularScale=.7},{bloom,blur})
bloom.Parent=lighting;blur.Parent=lighting
local menu=object('ScreenGui',{Name='Wurst',Enabled=true})
local menuStroke=object('UIStroke',{Enabled=true});menuStroke.Parent=menu
local touch=object('ScreenGui',{Name='TouchGui',Enabled=true})
local stroke=object('UIStroke',{Enabled=true})
local gradient=object('UIGradient',{Enabled=false})
local viewport=object('ViewportFrame',{Visible=true})
local hud=object('ScreenGui',{Name='HUD',Enabled=true})
local disabledHud=object('ScreenGui',{Name='Inventory',Enabled=false})
local pg=container('PlayerGui',{}, {menu,menuStroke,touch,stroke,gradient,viewport,hud,disabledHud})
menu.Parent=pg;touch.Parent=pg;stroke.Parent=hud;gradient.Parent=hud;viewport.Parent=hud;hud.Parent=pg;disabledHud.Parent=pg
local panel=object('SurfaceGui',{Enabled=true})
local light=object('PointLight',{Enabled=true})
local terrain=object('Terrain',{Decoration=true,WaterWaveSize=.5,WaterWaveSpeed=10,WaterReflectance=.8})
local lod=object('MeshPart',{RenderFidelity='Automatic',TextureID='mesh',CastShadow=true,Material='Wood',Reflectance=.2})
local function pos(x) return setmetatable({x=x},{__sub=function(a,b) return {Magnitude=math.abs(a.x-b.x)} end}) end
local root={Position=pos(0)}
local character=object('Model',{humanoid={}});character.Parent=workspace
local distant=object('Part',{Anchored=true,CanCollide=true,Position=pos(500),LocalTransparencyModifier=.2})
local avatarPart=object('Part',{Anchored=true,CanCollide=true,Position=pos(500),LocalTransparencyModifier=0});avatarPart.Parent=character
local physics=object('Part',{Anchored=false,CanCollide=true,Position=pos(500),LocalTransparencyModifier=0})
visible={panel,light,terrain,lod,distant,avatarPart,physics}
for _,o in ipairs(visible) do if o~=avatarPart then o.Parent=workspace end end
local panels={PlayerList=true,Backpack=false,Chat=true,EmotesMenu=true}
local distanceTick
host.Lighting=lighting;host.MenuBlur=blur;host.PlayerGui=pg;host.ScreenGui=menu
host.LocalPlayer={Character={FindFirstChild=function() return root end}}
host.StarterGui={GetCoreGuiEnabled=function(_,k) return panels[k] end,SetCoreGuiEnabled=function(_,k,v) panels[k]=v end}
host.TaskManager={Connect=function(_,fn) distanceTick=fn;return {Disconnect=function() distanceTick=nil end} end}
Module.init({host=host})
for _,name in ipairs({'Lowest render quality','Simple lighting','Disable local lights','Simplify terrain','Disable post effects',
    'Simplify game UI','Hide world UI','Hide game UI','Hide Roblox panels','Low detail meshes','Hide distant scenery'}) do options[name](true) end
toggle(true);drain()
assert(rendering.QualityLevel=='Level01' and not lighting.GlobalShadows and lighting.EnvironmentDiffuseScale==0)
assert(not bloom.Enabled and not blur.Enabled and not light.Enabled)
assert(not terrain.Decoration and terrain.WaterWaveSize==0 and terrain.WaterReflectance==0)
assert(not stroke.Enabled and not gradient.Enabled and not viewport.Visible and not hud.Enabled and not disabledHud.Enabled)
assert(menu.Enabled and menuStroke.Enabled and touch.Enabled,'menu and native touch controls protected')
assert(not panel.Enabled and lod.RenderFidelity=='Performance')
assert(not panels.PlayerList and not panels.Chat and not panels.Backpack)
assert(distant.LocalTransparencyModifier==1 and avatarPart.LocalTransparencyModifier==0 and physics.LocalTransparencyModifier==0)
root.Position=pos(490);distanceTick(1);assert(distant.LocalTransparencyModifier==.2,'near scenery restored')
root.Position=pos(0);distanceTick(1);assert(distant.LocalTransparencyModifier==1)
distant.Anchored=false;distanceTick(1);assert(distant.LocalTransparencyModifier==.2,'new physics objects no longer culled')
local dyingCallback
local dying=object('Decal',{Transparency=.4,Destroying={Connect=function(_,fn) dyingCallback=fn;return {Disconnect=function() dyingCallback=nil end} end}});dying.Parent=workspace
for _,h in ipairs(handlers) do if h.Connected then h.fn(dying) end end
assert(dying.Transparency==1 and dyingCallback);dyingCallback();assert(not dyingCallback)
local removed=object('Decal',{Transparency=.6});removed.Parent=nil
for _,h in ipairs(handlers) do if h.Connected then h.fn(removed) end end
assert(removed.Transparency==.6,'deferred callbacks must not acquire already removed objects')
local late=object('UIStroke',{Enabled=true});late.Parent=hud
for _,h in ipairs(handlers) do if h.Connected then h.fn(late) end end
assert(not late.Enabled)
options['Hide game UI'](false);drain();assert(hud.Enabled and not disabledHud.Enabled)
Module.destroy();drain()
assert(rendering.QualityLevel=='Automatic' and lighting.GlobalShadows and lighting.EnvironmentDiffuseScale==.6 and lighting.EnvironmentSpecularScale==.7)
assert(bloom.Enabled and blur.Enabled and light.Enabled and terrain.Decoration and terrain.WaterWaveSize==.5 and terrain.WaterWaveSpeed==10 and terrain.WaterReflectance==.8)
assert(stroke.Enabled and not gradient.Enabled and viewport.Visible and hud.Enabled and not disabledHud.Enabled and late.Enabled)
assert(panel.Enabled and lod.RenderFidelity=='Automatic' and distant.LocalTransparencyModifier==.2)
assert(panels.PlayerList and panels.Chat and not panels.Backpack and distanceTick==nil)
assert(dying.Transparency==1,'destroyed instances are evicted; detached instances above still restore')
for _,h in ipairs(handlers) do assert(not h.Connected) end
print('PASS Improve FPS: every touched property restored, false/zero values, detached objects, new descendants, option refresh, stale workers, destroy')
'''
with tempfile.TemporaryDirectory(prefix='improve-fps-') as tmp:
    path=Path(tmp)/'test.luau';path.write_text(PRELUDE+'\nlocal Module=(function()\n'+SOURCE+'\nend)()\n'+TEST)
    subprocess.run([os.environ.get('LUAU','luau'),str(path)],check=True)
