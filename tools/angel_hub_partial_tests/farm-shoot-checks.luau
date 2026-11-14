setting('Farm Mode','Walk');setting('Farm Speed',22);setting('Farm Safe Zone',false)
setting('Coins Collected',0);setting('Farm Time',0);setting('Auto Grab Gun And Shoot',true)
localPlayer.Name='Me';localPlayer.UserId=1
local collected={OnClientEvent=event()};function collected:IsA(c)return c=='RemoteEvent'end
local ended={OnClientEvent=event()};function ended:IsA(c)return c=='RemoteEvent'end
local role={};function role:IsA(c)return c=='RemoteFunction'end
role.me='Innocent';function role:InvokeServer()return {Me={Name='Me',Role=self.me},Alice={Name='Alice',Role='Murderer'}}end
local gameplay={};function gameplay:FindFirstChild(n)return ({CoinCollected=collected,RoundEndFade=ended,GetCurrentPlayerData=role})[n]end
local remotes={};function remotes:FindFirstChild(n)if n=='Gameplay'then return gameplay end end
local storage={};function storage:FindFirstChild(n)if n=='Remotes'then return remotes end end
services.ReplicatedStorage=storage
tools.equipped=gunTool;gunTool.Parent=character
workspace.rayMode='wall';V['Shoot Mode']='Normal';V['Shoot WallCheck']=true;V['Shoot Proximity']=true;V['Shoot Proximity Aura']=5
installGameplay(screenGui)
AngelHub.setters['Auto Farm'](true);assert(V['Auto Farm'] and not V['Auto Shoot'] and #remote.shots==0)
heartbeat:Fire(.1);assert(#remote.shots==0) -- Never during ordinary farming.
collected.OnClientEvent:Fire('Coins',50,50);fakeNow+=.25;heartbeat:Fire(.11)
assert(#remote.shots==1 and math.abs(remote.shots[1][1].Position.X-19)<.0001) -- Instakill, no wallcheck
-- A dropped gun is touched only after full bag as Innocent; no teleport is performed.
tools.equipped=nil;gunTool.Parent=backpack;gun.Parent=map
function gun:IsDescendantOf(parent)return parent==map or parent==workspace end
function map:FindFirstChildOfClass()return nil end
local oldPivot=character.lastPivot
local touchCount=#touches;role.me='Murderer';fakeNow+=2.1;heartbeat:Fire(.11);assert(#touches==touchCount)
role.me='Innocent';fakeNow+=2.1;heartbeat:Fire(.11);assert(#touches==touchCount+2 and character.lastPivot==oldPivot)
fakeNow+=.11;heartbeat:Fire(.11);assert(#touches==touchCount+2)
AngelHub.setters['Auto Farm'](false);fakeNow+=1;heartbeat:Fire(.2);assert(#remote.shots==1)
root.Position=Vector3.new(1000,0,0);AngelHub.setters['Auto Farm'](true);collected.OnClientEvent:Fire('Coins',50,50)
fakeNow+=1;heartbeat:Fire(.2);assert(#remote.shots==1) -- never from lobby
AngelHub.setters['Auto Farm'](false);screenGui.Destroying:Fire()
