#!/usr/bin/env python3
"""Exercise MM2's real BindableEvent contract and both emote UI paths.

The mock models the newer CrossPlatform controller: InventoryDataChanged.Event
is a read-only RBXScriptSignal, while Fire belongs to the BindableEvent itself.
This cannot prove game permissions, server ownership or animation replication.
"""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'src/games/MM2/Other/GetAllEmotes.lua').read_text()
SCRIPT = r'''
local _G={}
local function signal()
 local listeners={}
 local api={}
 function api:Connect(fn)
  local c={};listeners[c]=fn
  function c:Disconnect() listeners[self]=nil end
  return c
 end
 function api:Count() local n=0;for _ in pairs(listeners) do n+=1 end;return n end
 local function emit(...) for _,fn in pairs(table.clone(listeners)) do fn(...) end end
 -- RBXScriptSignal has Connect/Wait, not :Fire. Roblox raises on invalid members.
 return setmetatable(api,{__index=function(_,k) error(k..' is not a valid member of RBXScriptSignal') end}),emit
end
local respawn,emitRespawn=signal()
local invSignal,emitInventory=signal()
local delayed={}
local task={spawn=function(fn,...) fn(...) end,delay=function(_,fn) table.insert(delayed,fn) end}
local function flush() while #delayed>0 do table.remove(delayed,1)() end end
local function container(children) return {FindFirstChild=function(_,name) return children[name] end} end
local profile={Emotes={Owned={'legitimate-toy'}}}
local profileMod={data=profile}
local sync={
 sit={Name='Sit',Command='sit2',AnimationID=2431845940,Loop=true},
 ninja={Name='Ninja Rest',Command='ninja',AnimationID=2431864798,Loop=true},
 zen={Name='Zen',Command='zen',AnimationID=2431812646,Loop=true},
 dab={Name='Dab',Command='dab',AnimationID=2445521505},
 floss={Name='Live Floss',Command='livefloss',AnimationID=998877,Loop=true},
 zombie={Name='Zombie',Command='zombie',AnimationID=2513692312,Loop=true},
 headless={Name='Headless',Command='headless',AnimationID=2513664073},
 wave={Name='Wave'},laugh={Name='Laugh'},dance1={Name='Dance 1'},bonus={Name='Bonus',AnimationID=99},
}
local syncMod={data=sync}
local events,notices,played,tracks,animations={},{},{},{},{}
local changed={Event=invSignal}
function changed:Fire(kind,id,count)
 table.insert(events,{kind,id,count})
 emitInventory(kind,id,count)
end
local modernVisible={}
invSignal:Connect(function(kind)
 if kind=='Emotes' then
  for _,id in ipairs(profile.Emotes.Owned) do modernVisible[id]=true end
 end
end)
local playEvent={Fire=function(_,id) table.insert(played,id) end}
local inventory=container({InventoryDataChanged=changed})
local emoteReqs=0
local emoteMod={data={GenerateEmotes=function() error('legacy module should not run without legacy UI') end}}
local modules=container({ProfileData=profileMod,EmoteModule=emoteMod})
local remotes={FindFirstChild=function(_,name)
 if name=='Inventory' then return inventory elseif name=='Misc' and playEvent then return container({PlayEmote=playEvent}) end
end}
local database=container({Sync=container({Emotes=syncMod})})
local rs={FindFirstChild=function(_,name)
 if name=='Modules' then return modules elseif name=='Remotes' then return remotes elseif name=='Database' then return database end
end}
local game={GetService=function(_,name) assert(name=='ReplicatedStorage');return rs end}
local require=function(mod)
 if mod==emoteMod then emoteReqs+=1 end
 return mod.data
end
local Instance={new=function(class)
 assert(class=='Animation');local a={destroyed=false}
 function a:Destroy() self.destroyed=true end
 table.insert(animations,a);return a
end}
local animator={LoadAnimation=function(_,anim)
 local t={animation=anim,stops=0,plays=0};function t:Stop() self.stops+=1 end;function t:Play() self.plays+=1 end
 table.insert(tracks,t);return t
end}
local humanoid={Health=100,FindFirstChildOfClass=function(_,name) return name=='Animator' and animator end}
local character={FindFirstChildOfClass=function(_,name) return name=='Humanoid' and humanoid end}
local LocalPlayer={Character=character,CharacterAdded=respawn}
local featureConnections={};local state={mm2Core={},valueControls={}}
local configData={values={}}
local function disconnectFeatureConnection(name)
 local c=featureConnections[name];if c then c:Disconnect();featureConnections[name]=nil end
end
local feature,featureOptions
local function createUniversalFeature(_,_,_,callback,options)
 featureOptions=options;feature={enabled=false,actions={},cycles={}}
 function feature:Toggle(v) callback(v);self.enabled=false end
 function feature:SetStatus(s) self.status=s end
 return feature
end
local function addActionOption(f,name,callback) f.actions[name]=callback end
local function addCycleOption(f,name,labels,index,callback)
 f.cycles[name]={labels=labels,callback=callback,displayed=labels[index]}
 state.valueControls['MM2.GetAllEmotes.SelectEmote']={
  setIndex=function(i) f.cycles[name].displayed=labels[i] end,
 }
 callback(labels[index])
end
local function addInformationOption() end
local function notify(s) table.insert(notices,s) end
local MM2Scroll,mm2Features={},{}
''' + '\nlocal Module=(function()\n' + SOURCE + '\nend)()\n' + r'''
local function has(list,id) for _,v in ipairs(list) do if v==id then return true end end return false end
local wanted={'sit','ninja','zen','dab','floss','zombie','headless'}
local excluded={'wave','cheer','laugh','point','dance1','dance2','dance3','bonus'}
Module.init({})
assert(featureOptions.action==true and featureOptions.configKey=='MM2.GetAllEmotes')
assert(#profile.Emotes.Owned==1 and #played==0,'boot must not grant or play anything')
emitRespawn();flush()
assert(#profile.Emotes.Owned==1,'a respawn before the first press must not grant emotes')
feature:Toggle(true)
assert(#profile.Emotes.Owned==8,'add exactly the seven requested IDs, preserving existing ownership')
for _,id in ipairs(wanted) do
 assert(has(profile.Emotes.Owned,id),'missing '..id)
 assert(modernVisible[id],'the modern UI did not receive InventoryDataChanged for '..id)
end
for _,id in ipairs(excluded) do assert(not has(profile.Emotes.Owned,id),'unexpected default or non-requested id '..id) end
assert(#events>=1 and events[1][1]=='Emotes','Fire must be invoked on the BindableEvent, not its Event signal')
assert(emoteReqs==0,'do not require legacy EmoteModule when the legacy GUI is absent')
assert(string.find(string.lower(notices[#notices]),'local'),'do not claim server ownership')
local count=#profile.Emotes.Owned
feature:Toggle(true);assert(#profile.Emotes.Owned==count,'presses must be idempotent')
local cycle=assert(feature.cycles['Select Emote'])
assert(#cycle.labels==7 and table.find(cycle.labels,'Sit') and table.find(cycle.labels,'Zombie') and table.find(cycle.labels,'Headless'))
cycle.callback('Sit');assert(played[#played]=='sit','selecting Sit must request the game event')
feature.actions['Play Emote']();assert(played[#played]=='sit')
playEvent=nil
feature.actions['Play Emote']();assert(#tracks==1 and tracks[1].plays==1 and animations[1].destroyed)
assert(animations[1].AnimationId=='rbxassetid://2431845940' and animations[1].Name=='sit2' and tracks[1].Looped==true)
cycle.callback('Floss');assert(tracks[1].stops==1 and #tracks==2 and tracks[2].Looped==true)
assert(animations[2].AnimationId=='rbxassetid://998877' and animations[2].Name=='livefloss')
profile.Emotes.Owned={'legitimate-toy'};modernVisible={};emitRespawn();flush()
for _,id in ipairs(wanted) do assert(has(profile.Emotes.Owned,id) and modernVisible[id],'respawn must refresh '..id) end
-- User-owned defaults are preserved, but the feature never adds new ones.
profile.Emotes.Owned={'wave'};feature:Toggle(true)
assert(has(profile.Emotes.Owned,'wave') and #profile.Emotes.Owned==8)
for _,id in ipairs(excluded) do if id~='wave' then assert(not has(profile.Emotes.Owned,id)) end end
-- A legacy UI can be rebuilt when the native BindableEvent is missing, but
-- only when the legacy controller exists (its require otherwise can hang).
local legacyGui=container({EmotePages={}});local rebuilt={}
_G.EmoteFrame=legacyGui;_G.EmoteController={}
emoteMod.data={GenerateEmotes=function(owned,gui) table.insert(rebuilt,{owned,gui}) end}
inventory=container({});profile.Emotes.Owned={};feature:Toggle(true)
assert(emoteReqs==1 and #rebuilt==1 and rebuilt[1][1]==profile.Emotes.Owned and rebuilt[1][2]==legacyGui)
_G.EmoteFrame=nil;_G.EmoteController=nil;inventory=container({InventoryDataChanged=changed})
-- Missing live profile must report failure, not "already granted" or a made-up count.
modules=container({});local before=#events;feature:Toggle(true)
assert(#events==before,'no inventory signals without the live profile')
assert(notices[#notices] and (string.find(string.lower(notices[#notices]),'unavailable') or string.find(string.lower(notices[#notices]),'not ready')),
 'missing profile must be reported honestly: '..tostring(notices[#notices]))
-- The user asked to exclude only defaults. A future playable MM2 catalog
-- entry must join the list; aliases of Roblox defaults and Back must not.
modules=container({ProfileData=profileMod,EmoteModule=emoteMod})
profile.Emotes.Owned={'wave'};modernVisible={}
sync.bonus.Command='bonus'
sync.defaultAlias={Name='Default alias',Command='wave',AnimationID=42}
sync.Back={Name='Back',Command='return',AnimationID=43}
feature:Toggle(true)
assert(#profile.Emotes.Owned==9 and has(profile.Emotes.Owned,'bonus') and modernVisible.bonus,
 'additional playable non-default MM2 emotes must be included')
assert(not has(profile.Emotes.Owned,'defaultAlias') and not has(profile.Emotes.Owned,'Back'))
assert(#cycle.labels==8 and table.find(cycle.labels,'Bonus'),'live catalog updates the selector')
assert(string.find(feature.status,'8'),'status follows the actual live catalog count')
playEvent={Fire=function(_,id) table.insert(played,id) end}
cycle.callback('Bonus');assert(played[#played]=='bonus','new live emote can be selected')
feature:Toggle(true);assert(#profile.Emotes.Owned==9,'discovered emotes remain idempotent')
-- Catalog discovery must not hold up the known entries, and only one slow
-- require may be pending even when the user presses the action again.
local originalSpawn=task.spawn;local queued={}
task.spawn=function(fn) table.insert(queued,fn) end
profile.Emotes.Owned={};feature:Toggle(true)
assert(#queued==1);table.remove(queued,1)()
assert(#profile.Emotes.Owned==8 and #queued==1,'known entries arrive before catalog discovery')
feature:Toggle(true);assert(#queued==2);table.remove(queued,2)()
assert(#queued==1,'a waiting catalog scan must not be duplicated')
table.remove(queued,1)();task.spawn=originalSpawn
-- Queued work must not mutate a profile after destruction.
profile.Emotes.Owned={};emitRespawn()
local spawned={};task.spawn=function(fn) table.insert(spawned,fn) end
feature:Toggle(true);assert(#spawned==1 and #profile.Emotes.Owned==0)
Module.destroy();flush();spawned[1]()
assert(#profile.Emotes.Owned==0 and respawn:Count()==0 and tracks[#tracks].stops==1 and state.mm2GetAllEmotesFeature==nil)
-- Restoring a saved future catalog entry is silent: discovering the label
-- updates the selector, but it must not play an animation at startup.
task.spawn=originalSpawn;configData.values['MM2.GetAllEmotes.SelectEmote']='Bonus'
local playedBefore=#played
Module.init({});assert(#profile.Emotes.Owned==0 and #played==playedBefore)
feature:Toggle(true)
assert(feature.cycles['Select Emote'].displayed=='Bonus','a saved future emote is restored after discovery')
assert(#played==playedBefore,'restoring the selection must not play it')
feature.actions['Play Emote']();assert(played[#played]=='bonus','the restored selection is used')
Module.destroy()
print('PASS MM2 emotes: catalog/defaults, modern/legacy UI, playback, concurrency and cleanup')
'''
with tempfile.TemporaryDirectory(prefix='mm2-emotes-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(SCRIPT)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
