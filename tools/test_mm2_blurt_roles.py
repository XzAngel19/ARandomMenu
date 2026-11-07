#!/usr/bin/env python3
"""Execute real MM2 Blurt Roles scheduling against delayed OFF/ON and round changes."""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'src/games/MM2/Fun/BlurtRoles.lua').read_text()

script=r'''
local now=0
local os={clock=function() return now end}
local jobs={}
local task={spawn=function(fn) fn() end,delay=function(delay,fn) table.insert(jobs,{due=now+delay,fn=fn}) end}
local function advance(time)
    now=time
    while true do
        local chosen
        for i,job in ipairs(jobs) do if job.due<=now and (not chosen or job.due<jobs[chosen].due) then chosen=i end end
        if not chosen then break end
        local job=table.remove(jobs,chosen);job.fn()
    end
end
local sent={}
local failText=false
local channel={IsA=function(_,kind) return kind=='TextChannel' end,SendAsync=function(_,message)
    if failText then error('text chat unavailable') end
    table.insert(sent,{kind='text',message=message,time=now})
end}
local channels={FindFirstChild=function(_,name) if name=='RBXGeneral' then return channel end end,
    FindFirstChildWhichIsA=function() return channel end}
local textChat={ChatVersion='TextChatService',FindFirstChild=function(_,name) if name=='TextChannels' then return channels end end}
local legacy={IsA=function(_,kind) return kind=='RemoteEvent' end,FireServer=function(_,message,target)
    assert(target=='All');table.insert(sent,{kind='legacy',message=message,time=now})
end}
local events={FindFirstChild=function(_,name) if name=='SayMessageRequest' then return legacy end end}
local storage={FindFirstChild=function(_,name) if name=='DefaultChatSystemChatEvents' then return events end end}
local game={GetService=function(_,name)
    if name=='TextChatService' then return textChat end
    if name=='ReplicatedStorage' then return storage end
    error('unexpected service '..name)
end}
local Enum={ChatVersion={TextChatService='TextChatService'}}
local active=true
local callback,unsubscribed
local settings={blurtDelay=10,blurtRepeat=false,blurtFake=false,instantRoleNotify=false}
local core={mm2Settings=settings,hasActiveRoundRoles=function() return active end,
    findMurderer=function() return {Name='Murderer'} end,findSheriff=function() return {Name='Sheriff'} end,
    onRoundRoles=function(fn) callback=fn;return function() unsubscribed=true;callback=nil end end}
local state={mm2Core=core}
local featureConnections={}
local function disconnectFeatureConnection(key)
    local conn=featureConnections[key];if conn then conn:Disconnect();featureConnections[key]=nil end
end
local TaskManager={Connect=function(_,fn) return {fn=fn,Disconnect=function(self) self.disconnected=true end} end}
local feature,actions,options=nil,{},{}
local MM2Scroll,mm2Features={},{}
-- v191: the card is an ACTION (click = blurt instantly), and the automatic
-- path lives in the "Auto blurt" option.
local function createUniversalFeature(_,_,_,toggle)
    feature={enabled=false}
    function feature:Toggle(value) self.enabled=value;toggle(value) end
    function feature:Run() toggle() end
    return feature
end
local function autoBlurt(value)
    assert(options['Auto blurt'], 'the automatic path is an option, not the card')
    options['Auto blurt'](value)
end
local function addToggleOption(_,name,_,fn) options[name]=fn end
local function addNumberOption(_,name,_,_,_,fn) options[name]=fn end
local function addActionOption(_,name,fn) actions[name]=fn end
local function addInformationOption() end
local notices={}
local function notify(text) table.insert(notices,text) end
'''+ '\nlocal Module=(function()\n'+SOURCE+'\nend)()\n'+r'''
Module.init({});assert(callback and not next(jobs))
callback(true);assert(#jobs==0, 'public blurt is off at injection')
autoBlurt(true);callback(true);assert(#jobs==1)
advance(1);autoBlurt(false)
advance(2);autoBlurt(true);callback(true)
advance(10.1);assert(#sent==0, 'an OFF/ON must cancel the previous pending public message')
advance(12);assert(#sent==1 and sent[1].time==12 and sent[1].message:find('Murderer',1,true), 'new session keeps full delay')
active=false;callback(false);active=true;advance(13);callback(true)
active=false;advance(14);callback(false);active=true;callback(true)
advance(23.1);assert(#sent==1, 'a previous round must not blurt the next round early')
advance(24);assert(#sent==2 and sent[2].time==24, 'new round receives its own delay')
active=false;feature:Run();assert(#sent==2, 'manual action requires known live roles')
active=true;advance(25);feature:Run();assert(#sent==3 and sent[3].kind=='text')
failText=true;feature:Run();assert(#sent==4 and sent[4].kind=='legacy', 'legacy chat fallback remains')
Module.destroy();assert(unsubscribed and not featureConnections.MM2BlurtRoles)
advance(100);assert(#sent==4, 'no delayed messages after unload')
print('PASS MM2 Blurt Roles: instant card click, auto-blurt option, OFF/ON and round cancellation, full delay, chat fallback, cleanup')
'''
with tempfile.TemporaryDirectory(prefix='mm2-blurt-') as tmp:
    path=Path(tmp)/'test.luau';path.write_text(script)
    subprocess.run([os.environ.get('LUAU','luau'),str(path)],check=True)
