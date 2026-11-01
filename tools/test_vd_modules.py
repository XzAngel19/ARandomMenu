#!/usr/bin/env python3
"""Run the real VD module's animation and movement ownership lifecycles."""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'src/games/VD/base.lua').read_text()
script=r'''
local function signal()
    local listeners={};local event={}
    function event:Connect(fn)
        local c={};listeners[c]=fn
        function c:Disconnect() listeners[self]=nil end
        return c
    end
    function event:Fire(...) for _,fn in pairs(listeners) do fn(...) end end
    function event:Count() local n=0;for _ in pairs(listeners) do n+=1 end;return n end
    return event
end
local now=0
local os={clock=function() return now end}
local delayed={}
local task={delay=function(_,fn) table.insert(delayed,fn) end}
local function flush() while #delayed>0 do table.remove(delayed,1)() end end
local Enum={AnimationPriority={Action='Action',Action2='Action2',Action3='Action3',Action4='Action4'}}
local Color3={fromRGB=function(...) return {...} end}
local function track(name,speed)
    return {Name=name,Animation={AnimationId='rbxassetid://1'},Priority='Action',Speed=speed,writes=0,
        AdjustSpeed=function(self,v) self.writes+=1;self.Speed=v end}
end
local function character(speed,tracks)
    local animator={AnimationPlayed=signal(),tracks=tracks or {}}
    function animator:GetPlayingAnimationTracks() return self.tracks end
    local hum={Parent=true,WalkSpeed=speed,Health=100,HealthChanged=signal()}
    function hum:FindFirstChildOfClass(class) if class=='Animator' then return animator end end
    local body={humanoid=hum,root={Parent=true}}
    function body:FindFirstChildOfClass(class) if class=='Humanoid' then return self.humanoid end end
    function body:FindFirstChild(name) if name=='HumanoidRootPart' then return self.root end end
    return body,hum,animator
end
local body,hum,animator=character(16)
local teamSignal=signal()
local LocalPlayer={Character=body,Team={Name='Survivors'}}
function LocalPlayer:GetPropertyChangedSignal() return teamSignal end
local workspace={FindFirstChild=function(_,name) if name=='Map' then return {} end end}
local attack={IsA=function(_,kind) return kind=='RemoteEvent' end,FireServer=function() end}
local remotes={FindFirstChild=function(_,name)
    if name=='Attacks' then return {FindFirstChild=function(_,event) if event=='BasicAttack' then return attack end end} end
end}
local game={GetService=function() return {FindFirstChild=function(_,name) if name=='Remotes' then return remotes end end} end}
local Players={GetPlayers=function() return {LocalPlayer} end}
local state={vdScroll={},vdFeatures={}}
local featureConnections={}
local function disconnectFeatureConnection(name)
    local c=featureConnections[name];if c then c:Disconnect();featureConnections[name]=nil end
end
local TaskManager={Connect=function(_,fn)
    return {callback=fn,active=true,Disconnect=function(self) self.active=false end}
end}
local features={}
local function createUniversalFeature(name,_,_,fn)
    local f={name=name,row={},enabled=false,options={}}
    function f:Toggle(v) self.enabled=v;fn(v) end
    features[name]=f;return f
end
local function addNumberOption(f,name,_,_,_,fn) f.options[name]=fn;return {Parent={}} end
local function addToggleOption(f,name,_,fn) f.options[name]=fn;return {Parent={}} end
local function addCycleOption(f,name,_,_,fn) f.options[name]=fn;return {Parent={}} end
local roleProvider
local function registerRoleProvider(provider) roleProvider=provider end
state.unregisterRoleProvider=function(provider) if roleProvider==provider then roleProvider=nil end end
local function registerEspExtra() end
'''+ '\nlocal Module=(function()\n'+SOURCE+'\nend)()\n'+r'''
local function init() Module.init({Menu={},TaskManager=TaskManager}) end
local function tick(name)
    local c=featureConnections[name];assert(c and c.active,'missing '..name);c.callback(1/60)
end
-- Unloading a never-enabled card must not alter the game's existing tracks.
local first=track('vault',1.75);body,hum,animator=character(16,{first});LocalPlayer.Character=body
init();assert(roleProvider and roleProvider.Name=='VD');Module.destroy()
assert(first.Speed==1.75 and first.writes==0, 'unload while OFF must not reset foreign animations')
assert(teamSignal:Count()==0 and roleProvider==nil, 'module visibility and owned role provider removed')
init();local foreign={Name='Other game'};roleProvider=foreign;Module.destroy()
assert(roleProvider==foreign, 'unload must not remove a newer game role provider')
roleProvider=nil
-- Only accelerated tracks are restored, at their previous speeds, including after respawn.
first=track('vault',1.75);body,hum,animator=character(16,{first});LocalPlayer.Character=body
init();features['Cooldown Modifier']:Toggle(true);tick('VDCooldownModifier')
assert(first.Speed==4)
local second=track('pallet',0.6);animator.AnimationPlayed:Fire(second);assert(second.Speed==4)
local nextTrack=track('repair',1.3)
local nextBody,nextHum,nextAnimator=character(13,{nextTrack});LocalPlayer.Character=nextBody
tick('VDCooldownModifier')
assert(first.Speed==1.75 and second.Speed==0.6 and nextTrack.Speed==4,
    'respawn restores old animator tracks and accelerates the new one')
features['Cooldown Modifier']:Toggle(false);assert(nextTrack.Speed==1.3 and nextAnimator.AnimationPlayed:Count()==0)
Module.destroy()
-- Multiple damage hits refresh, but must not stack the burst or leave the speed boosted.
body,hum,animator=character(16);LocalPlayer.Character=body;now=0
init();features['Damage Boost']:Toggle(true);tick('VDDamageBoost')
hum.HealthChanged:Fire(90);assert(hum.WalkSpeed==21)
now=0.2;hum.HealthChanged:Fire(80);assert(hum.WalkSpeed==21, 'overlapping hits do not compound the burst')
now=2;flush();assert(hum.WalkSpeed==16, 'latest burst restores the pre-burst speed')
hum.HealthChanged:Fire(70);assert(hum.WalkSpeed==21)
local oldHum=hum;body,hum,animator=character(12);LocalPlayer.Character=body;tick('VDDamageBoost')
assert(oldHum.WalkSpeed==16 and hum.WalkSpeed==12, 'damage respawn restores only the old owner')
features['Damage Boost']:Toggle(false);flush();assert(hum.WalkSpeed==12)
Module.destroy()
-- WalkSpeed owns its snapshot per humanoid and does not overwrite changes while inactive.
body,hum,animator=character(16);LocalPlayer.Character=body
init();features['WalkSpeed Hack'].options.WalkSpeed(25);features['WalkSpeed Hack']:Toggle(true)
tick('VDWalkSpeed');assert(hum.WalkSpeed==25)
oldHum=hum;body,hum,animator=character(12);LocalPlayer.Character=body;tick('VDWalkSpeed')
assert(oldHum.WalkSpeed==16 and hum.WalkSpeed==25, 'WalkSpeed respawn restores the prior character')
features['WalkSpeed Hack']:Toggle(false);assert(hum.WalkSpeed==12, 'new character gets its own speed back')
-- External game writes are not replaced by a stale snapshot on OFF.
features['WalkSpeed Hack']:Toggle(true);tick('VDWalkSpeed');hum.WalkSpeed=9
features['WalkSpeed Hack']:Toggle(false);assert(hum.WalkSpeed==9)
Module.destroy()
-- The two speed features can overlap and be disabled in either order.
body,hum,animator=character(16);LocalPlayer.Character=body;now=0
init();features['WalkSpeed Hack'].options.WalkSpeed(25)
features['WalkSpeed Hack']:Toggle(true);tick('VDWalkSpeed')
features['Damage Boost']:Toggle(true);tick('VDDamageBoost');hum.HealthChanged:Fire(90)
assert(hum.WalkSpeed==30);tick('VDWalkSpeed')
features['WalkSpeed Hack']:Toggle(false);assert(hum.WalkSpeed==21, 'live burst continues on the native base')
now=2;flush();assert(hum.WalkSpeed==16)
features['WalkSpeed Hack']:Toggle(true);tick('VDWalkSpeed')
hum.HealthChanged:Fire(80);tick('VDWalkSpeed');features['Damage Boost']:Toggle(false)
now=4;flush();tick('VDWalkSpeed');assert(hum.WalkSpeed==25)
features['WalkSpeed Hack']:Toggle(false);assert(hum.WalkSpeed==16)
Module.destroy()
-- Respawn in both callback orders must restore the old owner and capture the new one.
for _,damageFirst in ipairs({true,false}) do
    body,hum,animator=character(16);LocalPlayer.Character=body;now=0
    init();features['WalkSpeed Hack'].options.WalkSpeed(25)
    features['WalkSpeed Hack']:Toggle(true);tick('VDWalkSpeed')
    features['Damage Boost']:Toggle(true);tick('VDDamageBoost');hum.HealthChanged:Fire(90)
    oldHum=hum;body,hum,animator=character(12);LocalPlayer.Character=body
    if damageFirst then tick('VDDamageBoost');tick('VDWalkSpeed') else tick('VDWalkSpeed');tick('VDDamageBoost') end
    assert(oldHum.WalkSpeed==16 and hum.WalkSpeed==25,
        'overlapping respawn: damageFirst='..tostring(damageFirst)..' old='..oldHum.WalkSpeed..' new='..hum.WalkSpeed)
    Module.destroy();flush();assert(hum.WalkSpeed==12)
end
-- Hit Aura must not write a stale speed when slowdown prevention never ran.
body,hum,animator=character(16);LocalPlayer.Character=body;LocalPlayer.Team={Name='Killer'}
init();features['Killer Hit Aura']:Toggle(true);tick('VDKillerHitAura')
hum.WalkSpeed=9;features['Killer Hit Aura']:Toggle(false)
assert(hum.WalkSpeed==9, 'Hit Aura without Run never owned WalkSpeed')
features['Killer Hit Aura'].options.Run(true);features['Killer Hit Aura']:Toggle(true);tick('VDKillerHitAura')
hum.WalkSpeed=5;tick('VDKillerHitAura');assert(hum.WalkSpeed==9)
features['Killer Hit Aura']:Toggle(false);assert(hum.WalkSpeed==5, 'Run restores only the slowdown it replaced')
now=0;features['Damage Boost']:Toggle(true);tick('VDDamageBoost');hum.HealthChanged:Fire(90)
assert(hum.WalkSpeed==10);features['Killer Hit Aura']:Toggle(true);tick('VDKillerHitAura')
now=2;flush();tick('VDKillerHitAura');assert(hum.WalkSpeed==5, 'Run must not retain an expired damage burst')
features['WalkSpeed Hack'].options.WalkSpeed(25);features['WalkSpeed Hack']:Toggle(true)
tick('VDWalkSpeed');tick('VDKillerHitAura');features['WalkSpeed Hack']:Toggle(false);tick('VDKillerHitAura')
assert(hum.WalkSpeed==5, 'Run must not retain a disabled WalkSpeed setting')
Module.destroy()
print('PASS VD: inert unload, animation and speed ownership, overlapping boosts, external changes, respawn/unload')
'''
with tempfile.TemporaryDirectory(prefix='vd-modules-') as tmp:
    path=Path(tmp)/'vd.luau';path.write_text(script)
    subprocess.run([os.environ.get('LUAU','luau'),str(path)],check=True)
