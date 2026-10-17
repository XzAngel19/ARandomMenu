#!/usr/bin/env python3
"""Execute actual MM2 item-provider registration, marking and cleanup."""
import os
import subprocess
import tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'src/games/MM2/Render/RoundEsp.lua').read_text()
script=r'''
local gunMarks,trapMarks={},{}
local gun={Parent=true}
local trap={Name='TrapVisual',IsA=function(_,c) return c=='Model' end}
local added
local workspace={DescendantAdded={Connect=function(_,fn) added=fn;return {Disconnect=function() added=nil end} end}}
local loops={}
local featureConnections={}
local function disconnectFeatureConnection(key)
 if featureConnections[key] then featureConnections[key]:Disconnect();featureConnections[key]=nil end
end
local TaskManager={Connect=function(_,fn) loops.gun=fn;return {Disconnect=function() loops.gun=nil end} end}
local providers={}
local services={itemEsp={register=function(p)
 assert(not providers[p.name]);providers[p.name]=p
 return function() providers[p.name]=nil end
end}}
local state={mm2Core={GunEffects=gunMarks,TrapEffects=trapMarks,
 clearEffects=function(folder) table.clear(folder) end,
 createMM2Marker=function(folder,object) table.insert(folder,object) end,
 createMM2Cham=function(folder,object) table.insert(folder,object) end,
 findDroppedGun=function() return gun end,
 findMM2Map=function() return {GetDescendants=function() return {trap} end} end,
 mm2Settings={gunColor='gold',gunTransparency=.5,trapColor='red',trapTransparency=.5}}}
'''+ '\nlocal Module=(function()\n'+SOURCE+'\nend)()\n'+r'''
Module.init({});assert(providers['Gun ESP'] and providers['Trap ESP'])
assert(not loops.gun and not added,'providers start OFF; ItemESP owns activation')
providers['Gun ESP'].setEnabled(true);loops.gun(.4);assert(#gunMarks==1 and gunMarks[1]==gun)
loops.gun(.4);assert(#gunMarks==1,'same gun is not rebuilt every scan')
gun=nil;loops.gun(.4);assert(#gunMarks==0,'pickup removes dropped-gun marker')
providers['Trap ESP'].setEnabled(true);assert(#trapMarks==1 and added)
added(trap);assert(#trapMarks==1,'existing traps deduplicated')
local nextTrap={Name='Trap',IsA=function(_,c) return c=='BasePart' end}
added(nextTrap);assert(#trapMarks==2)
providers['Gun ESP'].setEnabled(false);assert(not loops.gun and #gunMarks==0)
Module.destroy();assert(not added and not next(providers) and #trapMarks==0)
print('PASS MM2 ItemESP: provider registration, dropped gun/pickup, existing/new traps, dedup, independent OFF, unregister/unload')
'''
with tempfile.TemporaryDirectory(prefix='item-providers-') as tmp:
    path=Path(tmp)/'test.luau';path.write_text(script)
    subprocess.run([os.environ.get('LUAU','luau'),str(path)],check=True)
