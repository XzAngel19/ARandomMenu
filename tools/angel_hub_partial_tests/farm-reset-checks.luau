local function setting(n,v)V[n]=v;AngelHub.setters[n]=function(x)V[n]=x end end
setting('Farm Mode','Walk');setting('Farm Speed',16);setting('Farm Safe Zone',false)
setting('Coins Collected',0);setting('Farm Time',0);setting('Reset When Full Coin Bag',true);setting('Auto Grab Gun And Shoot',false)
local collected={OnClientEvent=event()};function collected:IsA(c)return c=='RemoteEvent'end
local ended={OnClientEvent=event()};function ended:IsA(c)return c=='RemoteEvent'end
local gameplay={};function gameplay:FindFirstChild(n)return ({CoinCollected=collected,RoundEndFade=ended})[n]end
local remotes={};function remotes:FindFirstChild(n)if n=='Gameplay'then return gameplay end end
local storage={};function storage:FindFirstChild(n)if n=='Remotes'then return remotes end end
services.ReplicatedStorage=storage;Enum.HumanoidStateType={Dead='dead'};function humanoid:ChangeState(s)self.state=s end
installGameplay(screenGui);AngelHub.setters['Auto Farm'](true)
collected.OnClientEvent:Fire('Coins',49,50);heartbeat:Fire(.2);assert(humanoid.Health==100)
collected.OnClientEvent:Fire('Coins',50,50);heartbeat:Fire(.2);assert(humanoid.Health==0 and humanoid.state=='dead')
-- This bag triggers one reset even if the character becomes alive on the same map.
humanoid.Health=100;heartbeat:Fire(.2);assert(humanoid.Health==100)
AngelHub.setters['Auto Farm'](false);AngelHub.setters['Auto Farm'](true)
V['Auto Grab Gun And Shoot']=true;collected.OnClientEvent:Fire('Coins',50,50)
heartbeat:Fire(.2);assert(humanoid.Health==100)
fakeNow+=1;heartbeat:Fire(.2);assert(humanoid.Health==100)
AngelHub.setters['Auto Farm'](false);fakeNow+=2;heartbeat:Fire(.2);assert(humanoid.Health==100)
AngelHub.setters['Auto Farm'](true);collected.OnClientEvent:Fire('Coins',50,50);heartbeat:Fire(.2)
fakeNow+=2.3;heartbeat:Fire(.2);assert(humanoid.Health==0)
screenGui.Destroying:Fire()
