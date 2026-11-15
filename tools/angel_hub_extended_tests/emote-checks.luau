V['Select Emote']='Sit';AngelHub.setters['Select Emote']=function(v)V['Select Emote']=v end
local profile={Emotes={Owned={'sit','other'}}}
local module={data=profile};function module:IsA(c)return c=='ModuleScript'end
local modules={};function modules:FindFirstChild(n)if n=='ProfileData'then return module end end
local inventoryEvent={fired={}};function inventoryEvent:IsA(c)return c=='BindableEvent'end
function inventoryEvent:Fire(a,b,c)table.insert(self.fired,{a,b,c})end
local inventory={};function inventory:FindFirstChild(n)if n=='InventoryDataChanged'then return inventoryEvent end end
local playEvent={fired={}};function playEvent:IsA(c)return c=='BindableEvent'end
function playEvent:Fire(id)table.insert(self.fired,id);if self.fail then error('uncertain')end end
local misc={};function misc:FindFirstChild(n)if n=='PlayEmote'then return self.play end end
misc.play=playEvent
local remotes={};function remotes:FindFirstChild(n)return ({Misc=misc,Inventory=inventory})[n]end
local catalog={data={special={Name='Special',Command='special',AnimationID=12345,Loop=true},wave={Command='wave',AnimationID=1},otherdefault={Command='dance',AnimationID=2},bad={Command='bad'}}}
function catalog:IsA(c)return c=='ModuleScript'end
local sync={};function sync:FindFirstChild(n)if n=='Emotes'then return catalog end end
local database={};function database:FindFirstChild(n)if n=='Sync'then return sync end end
local selectedOptions;AngelHub.cycleOptions={['Select Emote']=function(items)selectedOptions=items end}
local storage={};function storage:FindFirstChild(n)return ({Modules=modules,Remotes=remotes,Database=database})[n]end
services.ReplicatedStorage=storage
local queue={};task.spawn=function(f)table.insert(queue,f)end
local function drain()local q=queue;queue={};for _,f in ipairs(q)do f()end end
local tracks={}
function humanoid:FindFirstChildOfClass()return nil end
function humanoid:LoadAnimation(animation)
 local track={asset=animation.AnimationId,name=animation.Name}
 function track:Play()self.played=true end
 function track:Stop()self.stopped=true end
 function track:Destroy()self.destroyed=true end
 table.insert(tracks,track);return track
end
installEmotes(screenGui)
AngelHub.actions['Play Emote']();assert(#playEvent.fired==1 and playEvent.fired[1]=='sit' and #tracks==0)
playEvent.fail=true;AngelHub.actions['Play Emote']();assert(#playEvent.fired==2 and #tracks==0)
playEvent.fail=false;misc.play=nil;V['Select Emote']='Ninja Rest';AngelHub.actions['Play Emote']()
assert(#tracks==1 and tracks[1].asset=='rbxassetid://2431864798' and tracks[1].Looped and tracks[1].played)
V['Select Emote']='Dab';AngelHub.actions['Play Emote']()
assert(tracks[1].stopped and tracks[1].destroyed and tracks[2].asset=='rbxassetid://2445521505' and not tracks[2].Looped)
screenGui.Destroying:Fire();assert(tracks[2].stopped and tracks[2].destroyed)
