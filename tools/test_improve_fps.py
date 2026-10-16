#!/usr/bin/env python3
"""Execute real reversible FPS lifecycle, including paused/stale worker races."""
import os
import subprocess
import tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'src/games/universal/Other/ImproveFps.lua').read_text()
PRELUDE=r'''
local Enum={Material={SmoothPlastic='SmoothPlastic'}}
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
    function o:IsA(c) return c==class or (c=='BasePart' and (class=='Part' or class=='MeshPart')) end
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
print('PASS Improve FPS: every touched property restored, false/zero values, detached objects, new descendants, option refresh, stale workers, destroy')
'''
with tempfile.TemporaryDirectory(prefix='improve-fps-') as tmp:
    path=Path(tmp)/'test.luau';path.write_text(PRELUDE+'\nlocal Module=(function()\n'+SOURCE+'\nend)()\n'+TEST)
    subprocess.run([os.environ.get('LUAU','luau'),str(path)],check=True)
