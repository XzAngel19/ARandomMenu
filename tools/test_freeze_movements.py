#!/usr/bin/env python3
"""Run the real FreezeMovements module with strict, deterministic Luau mocks."""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'src/games/universal/Movement/FreezeMovements.lua').read_text()
PRELUDE = r'''
local now = 0
local os = {clock=function() return now end}
local Vector3 = {zero={Magnitude=0}}
local Enum = {AnimationPriority={Core='Core',Movement='Movement',Action='Action',Idle='Idle'}}
local function typeof(v) return type(v)=='table' and v.instance and 'Instance' or type(v) end
local function signal()
    local s={listeners={}}
    function s:Connect(fn)
        local c={Connected=true,fn=fn}
        function c:Disconnect() self.Connected=false end
        table.insert(self.listeners,c)
        return c
    end
    function s:Fire(v)
        for _,c in ipairs(self.listeners) do if c.Connected then c.fn(v) end end
    end
    return s
end
local tracks={}
local animator={AnimationPlayed=signal(),GetPlayingAnimationTracks=function() return tracks end}
local root={Parent=true,Anchored=false,AssemblyLinearVelocity={Magnitude=0}}
local humanoid={Parent=true,WalkSpeed=16,JumpPower=50,JumpHeight=7.2,AutoRotate=true,
    FindFirstChildOfClass=function() return animator end,
    GetAppliedDescription=function() return {GetEmotes=function() return {Salute={12345}} end,Destroy=function() end} end}
local tick,mode,toggle,feature
local connections={}
local host={
    TaskManager={Connect=function(_,fn) tick=fn; return {Disconnect=function() tick=nil end} end},
    featureConnections=connections,
    disconnectFeatureConnection=function(key) if connections[key] then connections[key]:Disconnect(); connections[key]=nil end end,
    getCharacterParts=function() return nil,humanoid,root end,
    createUniversalFeature=function(_,_,_,fn)
        toggle=fn; feature={enabled=false,SetStatus=function(self,s) self.status=s end};return feature
    end,
    addCycleOption=function(_,_,_,_,fn) mode=fn;fn('Anchor') end,
    addInformationOption=function() end,
}
local function track(name,id,priority)
    local t={Name=name,Animation={instance=true,Name=name,AnimationId='rbxassetid://'..id},
        Priority=priority,IsPlaying=true,Looped=true,plays=0,stops=0,TimePosition=1}
    function t:Play() self.plays+=1;self.IsPlaying=true;animator.AnimationPlayed:Fire(self) end
    function t:Stop() self.stops+=1;self.IsPlaying=false end
    return t
end
'''
TESTS = r'''
Module.init({host=host})
feature.enabled=true;toggle(true);tick()
assert(root.Anchored and humanoid.WalkSpeed==0 and humanoid.JumpHeight==0)
mode('Freeze Emotes')
assert(not root.Anchored and humanoid.WalkSpeed==16 and humanoid.JumpHeight==7.2)
tick() -- binds AnimationPlayed and reads avatar emotes
local custom=track('Salute',999,'Idle')
local attack=track('Stab',222,'Action')
local idOnly=track('Animation',12345,'Core')
animator.AnimationPlayed:Fire(custom)
animator.AnimationPlayed:Fire(attack)
animator.AnimationPlayed:Fire(idOnly)
root.AssemblyLinearVelocity={Magnitude=16}
custom.IsPlaying=false;attack.IsPlaying=false;idOnly.IsPlaying=false
tracks={};now=0.1;tick()
assert(custom.plays==1 and idOnly.plays==1 and attack.plays==0,'named/catalog emotes only; never attacks')
tracks={custom,idOnly};tick();tick()
-- Disable must release revived tracks and the event connection.
feature.enabled=false;toggle(false)
assert(custom.stops==1 and idOnly.stops==1 and attack.stops==0)
for _,c in ipairs(animator.AnimationPlayed.listeners) do assert(not c.Connected) end
assert(not tick)
mode('Glitch Animations');feature.enabled=true;toggle(true)
local walk=track('Walk',444,'Movement')
local stab=track('Stab',222,'Action')
tracks={walk,stab};tick()
assert(walk.TimePosition==0 and stab.TimePosition==1)
walk.TimePosition=0.09;now+=0.01;tick()
assert(walk.TimePosition==0.09 and walk.plays==0,'fixed cadence, no frame-by-frame Play')
now+=0.12;tick();assert(walk.TimePosition==0)
mode('Humanoid');tick();assert(not root.Anchored and humanoid.JumpHeight==0)
Module.destroy();assert(humanoid.JumpHeight==7.2 and humanoid.WalkSpeed==16 and not tick)
print('PASS FreezeMovements: mode restoration, avatar names/IDs, immediate tracks, attack exclusion, duplicate prevention, disable cleanup, glitch cadence, JumpHeight, destroy')
'''


def main():
    with tempfile.TemporaryDirectory(prefix='freeze-regression-') as tmp:
        path = Path(tmp) / 'test.luau'
        path.write_text(PRELUDE + '\nlocal Module=(function()\n' + SOURCE + '\nend)()\n' + TESTS)
        subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)


if __name__ == '__main__':
    main()
