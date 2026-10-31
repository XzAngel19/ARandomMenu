#!/usr/bin/env python3
"""Simulate live MM2 prediction against known synthetic motion (not server hits).

Runs actual Prediction.lua with simple Luau mocks at 30/60/120 Hz, three
latencies, ranges and blade speeds. The simulated world intentionally defines
Gun resolution delay as RTT + 25 ms and straight Knife flight at constant speed,
independent of the aim output. These assumptions are NOT observations of MM2's
server. Abrupt changes after firing expose a limit of causal prediction.
"""
from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
BASE = (ROOT / 'src/games/MM2/base.lua').read_text()
PREDICTION = (ROOT / 'src/games/MM2/Prediction.lua').read_text()

code = PRELUDE + '\n' + section(BASE, 'local predictionMath = {}', 'local lastLatencyReadAt') + r'''
local workspace = {Gravity=196.2}
local LocalPlayer = {Character={}}
local currentState='Running'
local humanoid = {Health=100, GetState=function() return currentState end,
    GetAttribute=function() return nil end}
local root = {Position=Vector3.zero, AssemblyLinearVelocity=Vector3.zero}
local torso = {Position=Vector3.zero, IsA=function(_,class) return class=='BasePart' end}
local character = {FindFirstChild=function(_,name)
    if name=='HumanoidRootPart' then return root end
    if name=='UpperTorso' then return torso end
    return nil
end, FindFirstChildOfClass=function(_,name) return name=='Humanoid' and humanoid or nil end}
local target = {Character=character}
local Players = {GetPlayers=function() return {LocalPlayer,target} end}
local latency = .12
local state = {mm2Core={predictionMath=predictionMath,getEstimatedLatency=function() return latency end}}
local featureConnections = {}
local function disconnectFeatureConnection(key)
    if featureConnections[key] then featureConnections[key]:Disconnect();featureConnections[key]=nil end
end
local sampleTick
local TaskManager = {Connect=function(_,callback)
    sampleTick=callback
    return {Disconnect=function() sampleTick=nil end}
end}
local function loadPrediction()
''' + PREDICTION + r'''
end
local Module=loadPrediction()
Module.init({})
local prediction=state.mm2Prediction
local offset=Vector3.new(0,1,0)
local function trajectory(name, distance, t)
    local start=Vector3.new(distance,0,0)
    local v=Vector3.new(0,0,16)
    if name=='stationary' then v=Vector3.zero end
    if name=='approaching' then v=Vector3.new(-16,0,0) end
    if name=='jump' then
        local age=t-.8
        if age>0 and age<80/196.2 then
            return start+v*t+Vector3.new(0,40*age-98.1*age*age,0),
                v+Vector3.new(0,40-196.2*age,0)
        end
        return start+v*t,v
    end
    if t<=1 or name=='stationary' or name=='lateral' or name=='approaching' then
        return start+v*t,v
    end
    local change=t-1
    if name=='sudden-stop' then return start+v,Vector3.zero end
    if name=='sudden-turn' then
        local nextV=Vector3.new(-16,0,0)
        return start+v+nextV*change,nextV
    end
    error('unknown scenario')
end
local stats={}
local count=0
for _,fps in ipairs({30,60,120}) do
 for _,rtt in ipairs({.05,.12,.22}) do
  for _,distance in ipairs({15,50,100}) do
   for _,speed in ipairs({72,96,140}) do
    for _,name in ipairs({'stationary','lateral','approaching','jump','sudden-stop','sudden-turn'}) do
        prediction.reset()
        latency=rtt
        now=0
        for i=1,fps do
            now=i/fps
            local position,velocity=trajectory(name,distance,now)
            currentState = name=='jump' and now>.8 and now<.8+80/196.2 and 'Freefall' or 'Running'
            root.Position=position
            root.AssemblyLinearVelocity=velocity
            torso.Position=position+offset
            sampleTick(1/fps)
        end
        local gun,g=prediction.gunAim(target,Vector3.zero)
        local knife,k=prediction.knifeAim(target,Vector3.zero,speed)
        assert(gun and g and knife and k and k.flightSeconds, 'simulation must produce both aims')
        -- Simulator's world clock is independent of the predictor's chosen
        -- horizon. An aim exactly at the blade endpoint travels that distance
        -- at the simulated speed; no server or collision model is implied.
        local simulatedDelay=rtt+.025
        local simulatedFlight=knife.Magnitude/speed
        local gunTruth=trajectory(name,distance,now+simulatedDelay)+offset
        local knifeTruth=trajectory(name,distance,now+simulatedDelay+simulatedFlight)+offset
        local gunError=(gun-gunTruth).Magnitude
        local knifeError=(knife-knifeTruth).Magnitude
        assert(gunError==gunError and knifeError==knifeError, 'non-finite simulated error')
        -- For steady paths the model has enough exact input; these thresholds
        -- are numerical regression tests, not hitboxes or live accuracy.
        if name=='stationary' or name=='lateral' or name=='approaching' then
            assert(gunError < .4, string.format('%s gun %.3f',name,gunError))
            assert(knifeError < .4, string.format('%s knife %.3f',name,knifeError))
            near(knife.Magnitude, speed*k.flightSeconds, .02)
        end
        local s=stats[name] or {n=0,gun=0,knife=0,maxGun=0,maxKnife=0}
        s.n+=1; s.gun+=gunError; s.knife+=knifeError
        s.maxGun=math.max(s.maxGun,gunError); s.maxKnife=math.max(s.maxKnife,knifeError)
        stats[name]=s; count+=1
    end
   end
  end
 end
end
assert(count==486)
for _,name in ipairs({'stationary','lateral','approaching','jump','sudden-stop','sudden-turn'}) do
    local s=stats[name]
    print(string.format('SIM %-12s n=%d gunMean=%.3f gunMax=%.3f knifeMean=%.3f knifeMax=%.3f studs',
        name,s.n,s.gun/s.n,s.maxGun,s.knife/s.n,s.maxKnife))
end
Module.destroy()
assert(sampleTick==nil and state.mm2Prediction==nil)
print('PASS 486 synthetic Gun/Knife scenarios; assumed timing and straight flight, not MM2 hit-rate')
'''

with tempfile.TemporaryDirectory(prefix='mm2-trajectory-simulation-') as directory:
    script = Path(directory) / 'simulation.luau'
    script.write_text(code)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(script)], check=True)
