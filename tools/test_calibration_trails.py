#!/usr/bin/env python3
"""Actual TrailESP module: lifecycle, packet validation, bounded visuals, no recorder."""
import os
import subprocess
import tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE
ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'src/games/MM2/Other/CalibrationTrails.lua').read_text()
assert 'FireServer' not in SOURCE and 'noteTracerData' not in SOURCE and 'PreSimulation' not in SOURCE
script=PRELUDE+r'''
local function signal()
 local s={list={}};function s:Connect(fn) local c={fn=fn,Connected=true};function c:Disconnect() self.Connected=false end;table.insert(self.list,c);return c end
 function s:Fire(...) for _,c in ipairs(self.list) do if c.Connected then c.fn(...) end end end;return s
end
local methods={}
local objectMt={__index=function(o,k) return methods[k] or o.props[k] end,__newindex=function(o,k,v)
 if k=='Parent' then
  local previous=o.props.Parent
  if previous then local i=table.find(previous.children,o);if i then table.remove(previous.children,i) end end
  if v then table.insert(v.children,o) end
 end
 o.props[k]=v
end}
local Instance={new=function(class) return setmetatable({props={ClassName=class,Name=class},children={}},objectMt) end}
function methods:GetChildren() return table.clone(self.children) end
function methods:Destroy() for _,c in ipairs(self:GetChildren()) do c:Destroy() end;self.Parent=nil end
local workspace=Instance.new('Folder')
local function typeof(value)
 if getmetatable(value)==mt then return 'Vector3' end
 if type(value)=='table' and value.Position and getmetatable(value)~=objectMt then return 'CFrame' end
 return type(value)
end
local Color3={fromRGB=function(...) return {...} end}
Enum.Material.Neon='Neon'
local UDim2={fromOffset=function(...) return {...} end,fromScale=function(...) return {...} end}
local UDim={new=function(...) return {...} end}
local timers={}
local task={delay=function(_,fn) table.insert(timers,fn) end}
local gun=signal()
local state={mm2CalibrationFeature={},mm2Core={getWeaponServiceModule=function() return {GunFired={OnClientEvent=gun}} end}}
local configData={states={['MM2.WeaponVisuals.TrailESP']=true},values={}}
local controls={}
local function addToggleOption(feature,name,default,fn)
 assert(feature==state.mm2CalibrationFeature and name=='TrailESP');controls[name]=fn
 fn(configData.states['MM2.Calibration.TrailESP']==true)
end
local function addColorOption(_,name,_,fn) controls[name]=fn end
'''+ '\nlocal Module=(function()\n'+SOURCE+'\nend)()\n'+r'''
Module.init({});assert(configData.states['MM2.Calibration.TrailESP'])
gun:Fire(nil,Vector3.zero,Vector3.new(100,0,0),nil)
assert(#workspace.children==1 and #workspace.children[1].children==2)
local folder=workspace.children[1]
gun:Fire(nil,Vector3.new(0/0,0,0),Vector3.new(100,0,0),nil)
assert(#folder.children==2,'reject malformed positions')
for i=1,100 do gun:Fire(nil,Vector3.zero,Vector3.new(i+1,0,0),nil) end
assert(#folder.children<=65,'bound rendering resources during bursts')
controls.TrailESP(false);assert(#workspace.children==0)
for _,c in ipairs(gun.list) do assert(not c.Connected) end
controls.TrailESP(true);gun:Fire(nil,CFrame.new(Vector3.zero),CFrame.new(Vector3.new(5,0,0)),nil)
assert(#workspace.children==1)
Module.destroy();assert(#workspace.children==0)
for _,c in ipairs(gun.list) do assert(not c.Connected) end
for _,fn in ipairs(timers) do fn() end
assert(#workspace.children==0,'delayed cleanup cannot recreate visuals after unload')
print('PASS Calibration TrailESP: migrated state, valid vectors/CFrames, bad packets ignored, bounded instances, OFF/unload, no duplicate recorder or animation loop')
'''
with tempfile.TemporaryDirectory(prefix='trails-') as tmp:
    path=Path(tmp)/'test.luau';path.write_text(script)
    subprocess.run([os.environ.get('LUAU','luau'),str(path)],check=True)
