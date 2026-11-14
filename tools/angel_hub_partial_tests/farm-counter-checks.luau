local function setting(n,v)V[n]=v;AngelHub.setters[n]=function(x)V[n]=x end end
setting('Farm Mode','Walk');setting('Farm Speed',16);setting('Farm Safe Zone',false)
setting('Coins Collected',0);setting('Farm Time',0)
local collected={OnClientEvent=event()};function collected:IsA(c)return c=='RemoteEvent'end
local ended={OnClientEvent=event()};function ended:IsA(c)return c=='RemoteEvent'end
local gameplay={};function gameplay:FindFirstChild(n)return ({CoinCollected=collected,RoundEndFade=ended})[n]end
local remotes={};function remotes:FindFirstChild(n)if n=='Gameplay'then return gameplay end end
local storage={};function storage:FindFirstChild(n)if n=='Remotes'then return remotes end end
services.ReplicatedStorage=storage
installGameplay(screenGui)
AngelHub.setters['Auto Farm'](true);heartbeat:Fire(1.25)
collected.OnClientEvent:Fire('Coins',4,50);collected.OnClientEvent:Fire('Coins',5,50)
assert(V['Farm Time']=='00:01' and V['Coins Collected']==2)
AngelHub.setters['Auto Farm'](true);collected.OnClientEvent:Fire('Coins',6,50)
assert(V['Farm Time']=='00:01' and V['Coins Collected']==3)
AngelHub.setters['Auto Farm'](false);heartbeat:Fire(20)
collected.OnClientEvent:Fire('Coins',8,50)
assert(V['Farm Time']=='00:01' and V['Coins Collected']==3)
AngelHub.setters['Auto Farm'](true);assert(V['Farm Time']=='00:01' and V['Coins Collected']==3)
heartbeat:Fire(.8);assert(V['Farm Time']=='00:02')
collected.OnClientEvent:Fire('Coins',9,50);assert(V['Coins Collected']==4)
collected.OnClientEvent:Fire('Coins',10,50);assert(V['Coins Collected']==5)
AngelHub.setters['Auto Farm'](false)
-- Settings load/reset use the same counter state; invalid data does not corrupt it.
AngelHub.setters['Coins Collected'](12);AngelHub.setters['Farm Time']('02:01')
AngelHub.setters['Farm Time']('invalid');AngelHub.setters['Coins Collected'](-1)
assert(V['Farm Time']=='02:01' and V['Coins Collected']==12)
AngelHub.setters['Auto Farm'](true);heartbeat:Fire(2.2)
assert(V['Farm Time']=='02:03' and V['Coins Collected']==12)
AngelHub.setters['Auto Farm'](false);heartbeat:Fire(20)
AngelHub.setters['Auto Farm'](true);assert(V['Farm Time']=='02:03' and V['Coins Collected']==12)
screenGui.Destroying:Fire()
