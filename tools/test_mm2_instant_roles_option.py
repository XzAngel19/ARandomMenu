#!/usr/bin/env python3
"""Execute Notifications migration, private role/gun/danger alerts and lifecycle."""
import os
import subprocess
import tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'src/games/MM2/Other/Notifications.lua').read_text()
BLURT=(ROOT/'src/games/MM2/Fun/BlurtRoles.lua').read_text()
assert 'Instant Roles' not in BLURT and 'sendPublicChat' in BLURT
assert 'SendAsync' not in SOURCE and 'FireServer' not in SOURCE
script=r'''
local now=0
local os={clock=function() return now end}
local mt
mt={__sub=function(a,b) return setmetatable({x=a.x-b.x,y=a.y-b.y,z=a.z-b.z},mt) end,
    __index=function(v,k) if k=='Magnitude' then return math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z) end end}
local function pos(x,y,z) return setmetatable({x=x,y=y,z=z},mt) end
local function makePlayer(name,x)
    local root={Position=pos(x,0,0)}
    local humanoid={Health=100}
    local character={FindFirstChild=function(_,key) if key=='HumanoidRootPart' then return root end end,
        FindFirstChildOfClass=function(_,key) if key=='Humanoid' then return humanoid end end}
    return {Name=name,Character=character},root,humanoid
end
local LocalPlayer,localRoot=makePlayer('Local',0)
local murderer,murderRoot,murderHumanoid=makePlayer('Murderer',60)
local sheriff=makePlayer('Sheriff',50)
local hero=makePlayer('Hero',20)
local selectedMurderer,selectedSheriff=nil,nil
local phaseValue='lobby'
local active=false
local roleCallback,phaseCallback
local rolesUnsubscribed,phaseUnsubscribed=false,false
local roles={[LocalPlayer]='Innocent',[murderer]='Murderer',[sheriff]='Sheriff',[hero]='Hero'}
local armed={}
local drop=nil
local mm2Settings={instantRoleNotify=false}
local core={mm2Settings=mm2Settings,findMurderer=function() return selectedMurderer end,
    findSheriff=function() return selectedSheriff end,getRoundPhase=function() return phaseValue end,
    isRoundLifecycleActive=function() return active end,hasActiveRoundRoles=function() return active end,
    getPlayerRole=function(p) return roles[p] end,
    isPlayerAlive=function(p) local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid');return h~=nil and h.Health>0 end,
    getPlayerWeapon=function(p,name) return name=='Gun' and armed[p] and {} or nil end,
    findDroppedGun=function() return drop end,
    onRoundRoles=function(fn) roleCallback=fn;return function() rolesUnsubscribed=true;roleCallback=nil end end,
    onRoundPhase=function(fn) phaseCallback=fn;return function() phaseUnsubscribed=true;phaseCallback=nil end end}
local state={mm2Core=core}
local configData={states={['MM2.BlurtRoles.InstantRoles']=true},values={}}
local saves=0
local function queueConfigSave() saves+=1 end
local MM2Scroll,mm2Features={},{}
local messages={}
local function notify(message) table.insert(messages,message) end
local warnings={}
local function warn(message) table.insert(warnings,message) end
local function count(text)
    local n=0;for _,m in ipairs(messages) do if m:find(text,1,true) then n+=1 end end;return n
end
local featureConnections={}
local function disconnectFeatureConnection(key)
    local c=featureConnections[key];if c then c:Disconnect();featureConnections[key]=nil end
end
local tick
local TaskManager={Connect=function(_,fn)
    tick=fn;return {Disconnect=function() tick=nil end}
end}
local feature,options
local function createUniversalFeature(name,_,_,toggle,config)
    assert(name=='Notifications' and config.categoryName=='Utilities')
    feature={onToggle=toggle};options={};return feature
end
local function addToggleOption(_,name,default,callback)
    local key='MM2.Notifications.'..name:gsub('%W','')
    local value=configData.states[key]
    if value==nil then value=default end
    options[name]=callback;callback(value)
end
local function addInformationOption() end
local function advance(seconds)
    now+=seconds
    if tick then tick(seconds) end
end
local function phase(value,reason)
    phaseValue=value;phaseCallback(value,reason)
end
'''+'\nlocal Module=(function()\n'+SOURCE+'\nend)()\n'+r'''
Module.init({})
assert(configData.states['MM2.BlurtRoles.InstantRoles']==nil
    and configData.states['MM2.Notifications.InstantRoles']==true
    and configData.states['MM2.Notifications']==true and saves==1,
    'legacy independent Instant Roles is migrated and its master enabled')
for _,name in ipairs({'Instant Roles','Gun Notification','Murder Close','Your Role','Round Events','Murderer Defeated'}) do
    assert(options[name], 'missing Notifications option '..name)
end
feature.onToggle(true);assert(tick and #messages==0, 'lobby stays quiet')
active=true;phase('map','teleport')
assert(count('round starting')==1 and count('Your role: Innocent')==1)
selectedMurderer=murderer
-- A core role-index rebuild can emit onRoundRoles synchronously inside a
-- lookup. It must not recurse through the Notifications sampler.
local originalFind=core.findMurderer
local depth=0;local reenter=true
core.findMurderer=function()
    depth+=1;assert(depth==1, 'synchronous role update must be coalesced')
    if reenter then reenter=false;roleCallback(true) end
    local result=originalFind();depth-=1;return result
end
roleCallback(true);core.findMurderer=originalFind
assert(count('Murderer: Murderer')==1, 'partial role is announced without waiting for Sheriff')
selectedSheriff=sheriff;armed[sheriff]=true;roleCallback(true)
assert(count('Sheriff/Hero: Sheriff')==1, 'other role arrives later once')
roleCallback(true);advance(1)
assert(count('Murderer: Murderer')==1 and count('Sheriff/Hero: Sheriff')==1, 'role refresh is deduplicated')

-- Dropped and picked-up gun: one alert each, never a guess from disappearance.
-- The original holder can still appear armed during delayed replication.
local dropped={Position=pos(40,0,0),IsA=function(_,kind) return kind=='BasePart' end}
drop=dropped;advance(.3);advance(.3)
assert(count('Gun dropped')==1 and count('40 studs away')==1)
drop=nil;advance(.3)
assert(count('Gun picked up')==0, 'stale previous holder is not a confirmed pickup')
armed[sheriff]=false;selectedSheriff=nil;advance(.3)
assert(count('Gun picked up')==0, 'missing drop alone is not a confirmed pickup')
selectedSheriff=hero;armed[hero]=true;advance(.3);advance(.3)
assert(count('Gun picked up by Hero')==1)

-- Hysteresis and cooldown: one warning near 30, then a new warning only
-- after a genuine exit/re-entry and the cooldown.
murderRoot.Position=pos(29,0,0);advance(.3);advance(.3)
assert(count('Murderer close')==1 and count('29 studs')==1)
murderRoot.Position=pos(35,0,0);advance(.3)
murderRoot.Position=pos(29,0,0);advance(.3)
assert(count('Murderer close')==1, '35 studs is within exit hysteresis')
murderRoot.Position=pos(45,0,0);advance(.3)
murderRoot.Position=pos(20,0,0);advance(.3)
assert(count('Murderer close')==1, 'rapid re-entry is cooled down')
advance(8);assert(count('Murderer close')==2, 'still nearby after cooldown is warned')

roles[LocalPlayer]='Hero';roleCallback(true)
assert(count('Your role: Hero')==1)
-- getPlayerRole can say Dead merely because the character streamed away.
-- That is not the explicit round data or a visible zero-health humanoid.
local savedCharacter=murderer.Character
roles[murderer]='Dead';selectedMurderer=nil;murderer.Character=nil;advance(.3)
assert(count('Murderer defeated')==0, 'streaming absence is not confirmed death')
murderer.Character=savedCharacter;murderHumanoid.Health=0;advance(.3);advance(.3)
assert(count('Murderer defeated')==1, 'only confirmed death produces the extra alert')
active=false;phase('lobby','RoundEndFade');assert(count('Round ended')==1)
feature.onToggle(false);assert(tick==nil)
local before=#messages
active=true;phase('map','teleport');roleCallback(true)
assert(#messages==before, 'master OFF suppresses all private alerts')
Module.destroy();assert(rolesUnsubscribed and phaseUnsubscribed and not mm2Settings.instantRoleNotify)

-- Explicit new settings win over old data and an explicit master OFF.
configData.states={['MM2.BlurtRoles.InstantRoles']=true,
    ['MM2.Notifications.InstantRoles']=false,['MM2.Notifications']=false}
rolesUnsubscribed,phaseUnsubscribed=false,false
Module.init({})
assert(configData.states['MM2.Notifications.InstantRoles']==false
    and configData.states['MM2.Notifications']==false and configData.states['MM2.BlurtRoles.InstantRoles']==nil)
Module.destroy()
print('PASS Notifications: migration, private partial roles, gun drop/pickup, 30-stud cooldown, round/role/death alerts, OFF and cleanup')
'''
with tempfile.TemporaryDirectory(prefix='mm2-notifications-') as tmp:
    p=Path(tmp)/'test.luau';p.write_text(script)
    subprocess.run([os.environ.get('LUAU','luau'),str(p)],check=True)
