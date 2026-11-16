local function setting(n,v)V[n]=v;AngelHub.setters[n]=function(x)V[n]=x end end
for _,n in ipairs({'Auto Farm','Auto Win','Enable Speed','Noclip','Enable Fly','Auto Vote','Auto Fling Selected Target','Auto Knife Throw','Insta Kill As Murder','Insta Kill As Sheriff','Farm Safe Zone'})do setting(n,false)end
for _,n in ipairs({'Coins Collected','Farm Time','Sheriff Wins','Murder Wins','Innocent Wins'})do setting(n,0)end
setting('Farm Mode','Walk');setting('Farm Speed',16)
local collected={OnClientEvent=event()};function collected:IsA(c)return c=='RemoteEvent'end
local ended={OnClientEvent=event()};function ended:IsA(c)return c=='RemoteEvent'end
local started={OnClientEvent=event()};function started:IsA(c)return c=='RemoteEvent'end
local victory={OnClientEvent=event()};function victory:IsA(c)return c=='RemoteEvent'end
local gameplay={};function gameplay:FindFirstChild(n)return ({CoinCollected=collected,RoundEndFade=ended,RoundStart=started,VictoryScreen=victory})[n]end
local remotes={};function remotes:FindFirstChild(n)if n=='Gameplay'then return gameplay end end
local storage={};function storage:FindFirstChild(n)if n=='Remotes'then return remotes end end
services.ReplicatedStorage=storage
humanoid.FloorMaterial=Enum.Material.Ground;root.CFrame={Position=root.Position}
installMM2Farm(screenGui);installMM2Win(screenGui)
-- Auto Farm and Auto Win are independent and never block Speed, Fly, Noclip, or each other.
AngelHub.setters['Auto Farm'](true);assert(V['Auto Farm'])
AngelHub.setters['Auto Win'](true);assert(V['Auto Farm'] and V['Auto Win'])
AngelHub.setters['Enable Speed'](true);assert(V['Enable Speed'] and V['Auto Win'] and V['Auto Farm'])
AngelHub.setters['Enable Fly'](true);assert(V['Enable Fly'] and V['Auto Win'] and V['Auto Farm'])
AngelHub.setters['Auto Farm'](false);AngelHub.setters['Enable Speed'](false);AngelHub.setters['Enable Fly'](false)
heartbeat:Fire(.11);local platform=created[#created];root.Position=character.lastPivot.Position;map.Parent=nil
AngelHub.setters['Auto Win'](false);assert(not platform.destroyed)
AngelHub.setters['Enable Fly'](true);assert(V['Enable Fly'])
map.Parent=workspace;AngelHub.setters['Enable Fly'](true);assert(V['Enable Fly'])
AngelHub.setters['Enable Fly'](false);root.Position=Vector3.new(0,0,0)
AngelHub.setters['Farm Safe Zone'](true);AngelHub.setters['Auto Farm'](true);collected.OnClientEvent:Fire('Coins',50,50);heartbeat:Fire(.11)
local farmPlatform=created[#created];root.Position=character.lastPivot.Position;map.Parent=nil
AngelHub.setters['Auto Farm'](false);assert(not farmPlatform.destroyed)
AngelHub.setters['Auto Win'](true);assert(V['Auto Win'])
map.Parent=workspace;AngelHub.setters['Auto Win'](true);assert(V['Auto Win'])
AngelHub.setters['Auto Win'](false);screenGui.Destroying:Fire()
