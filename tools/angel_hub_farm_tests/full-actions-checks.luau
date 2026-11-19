local function setting(n,v)V[n]=v;AngelHub.setters[n]=function(x)V[n]=x end end
for _,name in ipairs({'Coins Aura','Farm Safe Zone','Auto Grab Gun And Shoot','Reset When Full Coin Bag',
 'Stay Under When Round Starts','Auto Kill All When Full Bag','Fling Murder After Full Bag','Fling Sheriff After Full Bag'})do setting(name,false)end
setting('Farm Speed',22);setting('Coins Collected',0);setting('Farm Time',0)
local collected={OnClientEvent=event()};function collected:IsA(c)return c=='RemoteEvent'end
local ended={OnClientEvent=event()};function ended:IsA(c)return c=='RemoteEvent'end
local started={OnClientEvent=event()};function started:IsA(c)return c=='RemoteEvent'end
local gameplay={};function gameplay:FindFirstChild(n)return ({CoinCollected=collected,RoundEndFade=ended,RoundStart=started})[n]end
local remotes={};function remotes:FindFirstChild(n)if n=='Gameplay'then return gameplay end end
local storage={};function storage:FindFirstChild(n)if n=='Remotes'then return remotes end end;services.ReplicatedStorage=storage
local coin={Name='Coin_Server',Parent=map,Position=Vector3.new(8,0,0),CanCollide=true}
function coin:IsA(c)return c=='BasePart'end;function coin:GetAttribute()return nil end
function coin:FindFirstChild()return nil end;function coin:IsDescendantOf(p)return p==map and self.Parent==map end
map.descendants={coin};root.Position=Vector3.zero;root.CFrame={Position=root.Position};root.Parent=character;character.Parent=workspace
humanoid.FloorMaterial=Enum.Material.Ground;humanoid.PlatformStand=false;humanoid.AutoRotate=true
local home=root.CFrame
local murderer=other;murderer.Name='Murderer';local sheriff={Name='Sheriff'}
local function target(p,x)
 local r={Position=Vector3.new(x,0,0)};function r:IsA(c)return c=='BasePart'end
 local h={Health=100};local c={};function c:FindFirstChildOfClass(n)if n=='Humanoid'then return h end end
 function c:FindFirstChild(n)if n=='HumanoidRootPart'then return r end end;p.Character=c
end
target(murderer,20);target(sheriff,30)
function playersService:GetPlayers()return {localPlayer,murderer,sheriff}end
local roles={[localPlayer]='Murderer',[murderer]='Murderer',[sheriff]='Sheriff'}
AngelHub.getMM2Role=function(p)return roles[p]end;AngelHub.refreshMM2Roles=function()end
AngelHub.releaseMM2Roles=function()end
local attempts={};local activeValid
AngelHub.mm2StartFarmKills=function(valid)
 assert(not AngelHub.mm2FlingBusy and valid());activeValid=valid;table.insert(attempts,'kill')
 AngelHub.mm2KnifeKillBusy=true;AngelHub.mm2KnifeKillOwner='farm';return true
end
AngelHub.mm2CancelFarmKills=function()AngelHub.mm2KnifeKillBusy=false;AngelHub.mm2KnifeKillOwner=nil end
AngelHub.mm2StartOwnedFling=function(owner,target,valid)
 assert(owner=='farm' and valid() and not AngelHub.mm2KnifeKillBusy);activeValid=valid
 table.insert(attempts,target.Name);AngelHub.mm2FlingBusy=true;AngelHub.mm2FlingOwner=owner;return true
end
AngelHub.mm2CancelOwnedFling=function(owner)if AngelHub.mm2FlingOwner==owner then AngelHub.mm2FlingBusy=false;AngelHub.mm2FlingOwner=nil end end
installMM2Farm(screenGui)
AngelHub.setters['Auto Kill All When Full Bag'](true);AngelHub.setters['Fling Murder After Full Bag'](true)
AngelHub.setters['Fling Sheriff After Full Bag'](true);AngelHub.setters['Auto Farm'](true)
heartbeat:Fire(.2);assert(#attempts==0 and humanoid.PlatformStand)
collected.OnClientEvent:Fire('Coins',50,50);character.lastPivot=nil;heartbeat:Fire(.2)
assert(#attempts==1 and attempts[1]=='kill' and character.lastPivot==home and activeValid())
heartbeat:Fire(.2);assert(#attempts==1 and V['Auto Farm'])
AngelHub.mm2CancelFarmKills();heartbeat:Fire(.2);assert(attempts[2]=='Murderer' and activeValid())
heartbeat:Fire(.2);assert(V['Auto Farm'] and #attempts==2)
roles[murderer]='Innocent';assert(not activeValid());roles[murderer]='Murderer';assert(activeValid())
AngelHub.mm2CancelOwnedFling('farm');heartbeat:Fire(.2);assert(attempts[3]=='Sheriff' and activeValid())
AngelHub.mm2CancelOwnedFling('farm');character.lastPivot=nil;heartbeat:Fire(.2)
assert(#attempts==3 and character.lastPivot==nil and V['Auto Farm']) -- must not teleport to spawn after return
heartbeat:Fire(.2);assert(#attempts==3)
-- A new bag creates a new sequence. Disabling an active option cancels it.
collected.OnClientEvent:Fire('Coins',0,50);heartbeat:Fire(.2)
collected.OnClientEvent:Fire('Coins',50,50);heartbeat:Fire(.2)
assert(attempts[4]=='kill' and activeValid())
AngelHub.setters['Auto Kill All When Full Bag'](false);assert(not AngelHub.mm2KnifeKillBusy and not activeValid())
heartbeat:Fire(.2);assert(attempts[5]=='Murderer' and activeValid())
ended.OnClientEvent:Fire();assert(not AngelHub.mm2FlingBusy and not activeValid())
heartbeat:Fire(.2);assert(#attempts==5)
started.OnClientEvent:Fire(10);collected.OnClientEvent:Fire('Coins',0,50);heartbeat:Fire(.2)
collected.OnClientEvent:Fire('Coins',50,50);heartbeat:Fire(.2)
assert(attempts[6]=='Murderer' and activeValid())
AngelHub.setters['Auto Farm'](false);assert(not AngelHub.mm2FlingBusy and not activeValid())
screenGui.Destroying:Fire()
