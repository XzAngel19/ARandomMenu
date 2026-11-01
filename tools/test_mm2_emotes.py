#!/usr/bin/env python3
"""Actual emote module: client inventory, playback requests, respawn and cleanup.

This mock does not prove server ownership, animation permission or replication.
"""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'src/games/MM2/Other/GetAllEmotes.lua').read_text()
script = r'''
local function signal()
 local listeners={};local s={}
 function s:Connect(fn) local c={};listeners[c]=fn;function c:Disconnect() listeners[self]=nil end;return c end
 function s:Fire(...) for _,fn in pairs(table.clone(listeners)) do fn(...) end end
 function s:Count() local n=0;for _ in pairs(listeners) do n+=1 end;return n end
 return s
end
local delayed={};local task={delay=function(_,fn) table.insert(delayed,fn) end}
local function flush() while #delayed>0 do table.remove(delayed,1)() end end
local function container(children) return {FindFirstChild=function(_,name) return children[name] end} end
local profile={Emotes={Owned={'sit'}}}
local profileMod={data=profile}
local catalog={bonus={Name='Bonus',AnimationID=5},
 floss={Name='Live Floss',Command='livefloss',AnimationID=998877}}
local emotesMod={data=catalog}
local notices,inventoryEvents={},{}
local changed={Fire=function(_,kind,id,count) table.insert(inventoryEvents,{kind,id,count}) end}
local playEvent
local modules=container({ProfileData=profileMod})
local inventory=container({InventoryDataChanged=changed})
local remotes={FindFirstChild=function(_,name)
 if name=='Inventory' then return inventory elseif name=='Misc' and playEvent then return container({PlayEmote=playEvent}) end
end}
local db=container({Sync=container({Emotes=emotesMod})})
local rs={FindFirstChild=function(_,name)
 if name=='Modules' then return modules elseif name=='Remotes' then return remotes elseif name=='Database' then return db end
end}
local game={GetService=function(_,name) assert(name=='ReplicatedStorage');return rs end}
local require=function(mod) return mod.data end
local animations={}
local Instance={new=function(class)
 assert(class=='Animation');local a={destroyed=false}
 function a:Destroy() self.destroyed=true end
 table.insert(animations,a);return a
end}
local tracks={}
local animator={LoadAnimation=function(_,anim)
 local t={animation=anim,stops=0,plays=0};function t:Stop() self.stops+=1 end;function t:Play() self.plays+=1 end
 table.insert(tracks,t);return t
end}
local humanoid={Health=100,FindFirstChildOfClass=function(_,name) return name=='Animator' and animator end}
local character={FindFirstChildOfClass=function(_,name) return name=='Humanoid' and humanoid end}
local LocalPlayer={Character=character,CharacterAdded=signal()}
local featureConnections={};local state={mm2Core={}}
local function disconnectFeatureConnection(name)
 local c=featureConnections[name];if c then c:Disconnect();featureConnections[name]=nil end
end
local feature
local function createUniversalFeature(_,_,_,callback)
 feature={enabled=false,actions={},cycles={}}
 function feature:Toggle(v) callback(v);self.enabled=v end
 function feature:SetStatus(s) self.status=s end
 return feature
end
local function addActionOption(f,name,callback) f.actions[name]=callback end
local function addCycleOption(f,name,_,_,callback) f.cycles[name]=callback end
local function notify(s) table.insert(notices,s) end
local MM2Scroll,mm2Features={},{}
''' + '\nlocal Module=(function()\n' + SOURCE + '\nend)()\n' + r'''
Module.init({})
assert(not feature.enabled and LocalPlayer.CharacterAdded:Count()==0 and #profile.Emotes.Owned==1)
feature:Toggle(true)
assert(#profile.Emotes.Owned==15 and #inventoryEvents==15,'built-ins and catalog update the client inventory once')
assert(feature.status and string.find(string.lower(feature.status),'local'), 'initial status must describe local entries')
assert(string.find(string.lower(notices[#notices]),'local'), 'do not claim server ownership')
feature.actions['Get All Emotes']();assert(#profile.Emotes.Owned==15,'client owned IDs must not duplicate')
local before=#inventoryEvents
LocalPlayer.CharacterAdded:Fire();assert(#delayed==1)
feature:Toggle(false);feature:Toggle(true);local after=#inventoryEvents
flush();assert(#inventoryEvents==after and after==before+15,'a previous activation may not run its respawn callback later')
-- No native event: a selected animation is loaded via the existing animator.
feature.actions['Play Emote']();assert(#tracks==1 and tracks[1].plays==1 and animations[1].destroyed)
assert(animations[1].AnimationId=='rbxassetid://998877' and animations[1].Name=='livefloss' and tracks[1].Looped==false,
 'live numeric IDs, commands and non-looping metadata must override stale builtins')
feature.actions['Play Emote']();assert(tracks[1].stops==1 and #tracks==2 and animations[2].destroyed)
local played={}
playEvent={Fire=function(_,id) table.insert(played,id) end}
feature.actions['Play Emote']();assert(tracks[2].stops==1 and played[1]=='floss', 'switching path stops our prior fallback track')
playEvent=nil;feature.actions['Play Emote']();assert(#tracks==3)
feature:Toggle(false);assert(tracks[3].stops==1 and LocalPlayer.CharacterAdded:Count()==0, 'OFF stops owned track and respawn listener')
-- A successful BindableEvent fire alone does not prove local inventory changed.
modules=container({});inventory=container({InventoryDataChanged=changed});feature.actions['Get All Emotes']()
assert(string.find(notices[#notices],'0'), 'an event without ProfileData must not be counted as a local entry')
-- If neither a local profile nor an inventory event exists, the count cannot
-- be reported as fourteen successful unlocks.
inventory=container({});feature.actions['Get All Emotes']()
assert(string.find(notices[#notices],'0'), 'no local inventory must report zero, not a fabricated catalog count')
db=container({}) -- fall back to the known client snapshot if Sync is unavailable
feature.actions['Play Emote']();assert(#tracks==4 and animations[4].AnimationId=='rbxassetid://2452938820' and tracks[4].Looped==true,
 'fallback Floss must use the MM2 snapshot animation and looping behavior')
Module.destroy();assert(tracks[4].stops==1 and state.mm2GetAllEmotesFeature==nil)
print('PASS MM2 emotes: local catalog, honest counts, native/fallback playback, delayed cancellation and cleanup')
'''
with tempfile.TemporaryDirectory(prefix='mm2-emotes-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
