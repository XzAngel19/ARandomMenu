local function setting(n,v)V[n]=v;AngelHub.setters[n]=function(x)V[n]=x end end
setting('Farm Mode','Walk');setting('Farm Speed',16);setting('Farm Safe Zone',false)
setting('Coins Collected',0);setting('Farm Time',0);setting('Auto Grab Gun And Shoot',true)
setting('Reset When Full Coin Bag',false)
local collected={OnClientEvent=event()};function collected:IsA(c)return c=='RemoteEvent'end
local ended={OnClientEvent=event()};function ended:IsA(c)return c=='RemoteEvent'end
local gameplay={};function gameplay:FindFirstChild(n)return ({CoinCollected=collected,RoundEndFade=ended})[n]end
local remotes={};function remotes:FindFirstChild(n)if n=='Gameplay'then return gameplay end end
local storage={};function storage:FindFirstChild(n)if n=='Remotes'then return remotes end end
services.ReplicatedStorage=storage
local role='Innocent';AngelHub.getMM2Role=function()return role end
local touches,shots=0,0;AngelHub.actions={['Get Gun']=function()touches+=1 end}
AngelHub.farmGrabShoot=function()shots+=1 end
local gun={};local equipped=false;local oldFind=character.FindFirstChild
function character:FindFirstChild(n)if n=='Gun' and equipped then return gun end;return oldFind(self,n)end
installMM2Farm(screenGui);AngelHub.setters['Auto Farm'](true)
-- Grab gun & shoot works immediately even while coin bag is not full (0/50 or 49/50)
heartbeat:Fire(.2);assert(touches==1 and shots==0)
fakeNow+=.3;collected.OnClientEvent:Fire('Coins',49,50);heartbeat:Fire(.2);assert(touches==2)
fakeNow+=.3;collected.OnClientEvent:Fire('Coins',50,50);heartbeat:Fire(.2);assert(touches==3 and shots==0)
fakeNow+=.3;role='Murderer';heartbeat:Fire(.2);assert(touches==3)
fakeNow+=.3;role='Innocent';equipped=true;heartbeat:Fire(.2);assert(shots==1)
fakeNow+=.3;root.Position=Vector3.new(1000,0,0);heartbeat:Fire(.2);assert(shots==1)
root.Position=Vector3.zero;fakeNow+=.3;heartbeat:Fire(.2);assert(shots==2)
local ticket=AngelHub.farmFullTicket();AngelHub.setters['Auto Grab Gun And Shoot'](false);AngelHub.setters['Auto Grab Gun And Shoot'](true)
assert(AngelHub.farmFullTicket()~=ticket);ticket=AngelHub.farmFullTicket()
collected.OnClientEvent:Fire('Coins',0,50);assert(AngelHub.farmFullTicket()~=ticket)
collected.OnClientEvent:Fire('Coins',50,50);ticket=AngelHub.farmFullTicket();ended.OnClientEvent:Fire();assert(AngelHub.farmFullTicket()~=ticket)
fakeNow+=.3;heartbeat:Fire(.2);assert(shots==2)
AngelHub.setters['Auto Farm'](false);screenGui.Destroying:Fire()
