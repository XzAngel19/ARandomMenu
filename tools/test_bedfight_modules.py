#!/usr/bin/env python3
"""Execute the real BedFight Auto Swing/Round Info modules with a mock Heartbeat."""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
def module(path):
    return '(function()\n'+(ROOT/path).read_text()+'\nend)()'

script=r'''
local now=0
local os={clock=function() return now end}
local function signal()
    local connections={};local event={}
    function event:Connect(callback)
        local conn={callback=callback,Connected=true};table.insert(connections,conn)
        function conn:Disconnect() self.Connected=false end
        return conn
    end
    function event:Fire(dt) for _,conn in ipairs(connections) do if conn.Connected then conn.callback(dt) end end end
    function event:Count() local n=0;for _,c in ipairs(connections) do if c.Connected then n+=1 end end;return n end
    return event
end
local heartbeat=signal()
local function value(data)
    return {Value=data,IsA=function(_,kind) return kind=='ValueBase' end}
end
local status=value('Countdown')
local mode=value('Classic')
local beds=value(false)
local info={FindFirstChild=function(_,name)
    return ({Status=status,GameMode=mode,AllBedsBroken=beds})[name]
end}
local storage={FindFirstChild=function(_,name) if name=='GameInfo' then return info end end}
local game={GetService=function(_,name)
    if name=='RunService' then return {Heartbeat=heartbeat} end
    if name=='ReplicatedStorage' then return storage end
    error('unexpected service '..name)
end}
local Vector2={new=function(...) return {...} end}
local UDim2={new=function(...) return {...} end,fromOffset=function(...) return {...} end}
local UDim={new=function(...) return {...} end}
local Color3={fromRGB=function(...) return {...} end}
local features,options={},{}
local swings=0
local env={state={weaponLibrary={Swing=function() swings+=1 end},bedFightScroll={},bedFightFeatures={}},ScreenGui={}}
function env.createUniversalFeature(name,_,_,callback)
    local feature={enabled=false}
    function feature:Toggle(on) self.enabled=on;callback(on) end
    features[name]=feature;return feature
end
function env.addNumberOption(_,name,_,_,_,callback) options[name]=callback end
local labels={}
function env.create(class,properties)
    local obj={ClassName=class,properties=properties}
    function obj:Destroy() self.destroyed=true end
    return obj
end
local textWrites=0
function env.makeTextLabel()
    local props={Text=''}
    local label=setmetatable({}, {__index=function(_,key) return props[key] end,
        __newindex=function(_,key,value) props[key]=value;if key=='Text' then textWrites+=1 end end})
    table.insert(labels,label);return label
end
local function getfenv() return env end
'''+ '\nlocal Swing='+module('src/games/BedFight/Combat/AutoSwing.lua')+r'''
Swing.init({})
assert(heartbeat:Count()==0 and swings==0, "Auto Swing has no idle per-frame connection")
features['Auto Swing']:Toggle(true);assert(heartbeat:Count()==1)
heartbeat:Fire(0);assert(swings==1)
now=.05;heartbeat:Fire(.05);assert(swings==1, "rate limit stays in force")
options['Swings per second'](20);now=.12;heartbeat:Fire(.07);assert(swings==2)
now=.18;heartbeat:Fire(.06);assert(swings==3)
features['Auto Swing']:Toggle(false);assert(heartbeat:Count()==0)
now=5;heartbeat:Fire(1);assert(swings==3)
features['Auto Swing']:Toggle(true);heartbeat:Fire(0);assert(swings==4)
Swing.destroy();assert(heartbeat:Count()==0)
'''+ '\nlocal Info='+module('src/games/BedFight/Render/RoundInfo.lua')+r'''
Info.init({});assert(heartbeat:Count()==0, "Round Info has no idle per-frame connection")
features['Round Info']:Toggle(true)
assert(heartbeat:Count()==1 and #labels==3 and labels[1].Text=='Countdown'
    and labels[2].Text=='Mode: Classic' and labels[3].Text=='Beds: standing', "first values appear immediately")
status.Value='Live';beds.Value=true
heartbeat:Fire(.1);assert(labels[1].Text=='Countdown')
heartbeat:Fire(.1);assert(labels[1].Text=='Live' and labels[3].Text=='Beds: all broken', "values refresh after 0.2s")
local writes=textWrites
for _=1,60 do heartbeat:Fire(1/60) end
assert(textWrites==writes, "unchanged text does not relayout repeatedly")
local panel=Info.Panel
features['Round Info']:Toggle(false)
assert(heartbeat:Count()==0 and panel.destroyed and Info.Panel==nil)
features['Round Info']:Toggle(true);Info.destroy();assert(heartbeat:Count()==0 and Info.Panel==nil)
print('PASS BedFight: no idle Heartbeats, paced swings, immediate/0.2s round data, no repeated UI writes, cleanup')
'''
with tempfile.TemporaryDirectory(prefix='bedfight-modules-') as tmp:
    path=Path(tmp)/'test.luau';path.write_text(script)
    subprocess.run([os.environ.get('LUAU','luau'),str(path)],check=True)
