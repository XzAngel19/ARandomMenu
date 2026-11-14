local function setting(n,v)V[n]=v;AngelHub.setters[n]=function(x)V[n]=x end end
AngelHub.moduleNames['Auto Shoot']=true
for n,v in pairs({['Auto Shoot']=false,['Shoot Mode']='Bullet',['Shoot WallCheck']=false,
 ['Shoot Proximity']=false,['Shoot Proximity Aura']=30})do setting(n,v)end
localPlayer.Name='Me';localPlayer.UserId=1;localPlayer.ChildAdded=event();localPlayer.CharacterAdded=event();character.ChildAdded=event()
local enemyRoot={Position=Vector3.new(20,0,0),AssemblyLinearVelocity=Vector3.new(0,0,0)}
function enemyRoot:IsA(c)return c=='BasePart'end
local enemyHumanoid={Health=100};local enemy={}
function enemy:FindFirstChildOfClass(n)if n=='Humanoid'then return enemyHumanoid end end
function enemy:FindFirstChild(n)if n=='HumanoidRootPart'then return enemyRoot end end
function enemy:GetAttribute(n)if n=='Dead'then return self.dead end end
other.Character=enemy;other.UserId=2
function other:FindFirstChildOfClass()return nil end
function localPlayer:FindFirstChildOfClass()return nil end
local remote={shots=0};function remote:IsA(c)return c=='RemoteEvent'end
function remote:FireServer()self.shots+=1 end
local tool={Name='Gun',Enabled=true,Parent=character}
function tool:IsA(c)return c=='Tool'end
function tool:GetAttribute()return nil end
function tool:FindFirstChild(n)if n=='Shoot'then return remote end end
local charFind=character.FindFirstChild
function character:FindFirstChild(n)if n=='Gun'then return tool end;return charFind(self,n)end
function root:FindFirstChild()return nil end
root.CFrame={Position=Vector3.new(0,0,0)}
CFrame.lookAt=function(a,b)return {Position=a,Target=b}end
local data={Alice={Role='Murderer',Name='Alice',UserId=2}}
local fetch={count=0};function fetch:IsA(c)return c=='RemoteFunction'end
function fetch:InvokeServer()self.count+=1;return data end
local changed={OnClientEvent=event()};function changed:IsA(c)return c=='RemoteEvent'end
local ended={OnClientEvent=event()};function ended:IsA(c)return c=='RemoteEvent'end
local started={OnClientEvent=event()};function started:IsA(c)return c=='RemoteEvent'end
local gameplay={};function gameplay:FindFirstChild(n)return ({GetCurrentPlayerData=fetch,PlayerDataChanged=changed,RoundEndFade=ended,RoundStart=started})[n]end
local remotes={};function remotes:FindFirstChild(n)if n=='Gameplay'then return gameplay end end
local storage={};function storage:FindFirstChild(n)if n=='Remotes'then return remotes end end
services.ReplicatedStorage=storage
task.defer=function(fn)fn()end
installGameplay(screenGui)
AngelHub.setters['Auto Shoot'](true);assert(fetch.count==1 and remote.shots==1)
-- A role update marking the target dead wins over stale role data.
changed.OnClientEvent:Fire({Alice={Name='Alice',Role='Murderer',Dead=true}})
fakeNow+=.25;heartbeat:Fire(.1);assert(remote.shots==1)
changed.OnClientEvent:Fire({Alice={Name='Alice',Role='Sheriff'}})
fakeNow+=.25;heartbeat:Fire(.1);assert(remote.shots==1)
changed.OnClientEvent:Fire({Alice={Name='Alice',Role='Murderer'}})
fakeNow+=.25;enemy.dead=true;heartbeat:Fire(.1);assert(remote.shots==1)
enemy.dead=false;fakeNow+=.25;heartbeat:Fire(.1);assert(remote.shots==2)
ended.OnClientEvent:Fire();fakeNow+=3;heartbeat:Fire(.1);assert(remote.shots==2 and fetch.count==1)
started.OnClientEvent:Fire(10,data);fakeNow+=.25;heartbeat:Fire(.1);assert(remote.shots==3 and fetch.count==2)
-- Cached role data never targets from the lobby.
root.Position=Vector3.new(1000,0,0);fakeNow+=.25;heartbeat:Fire(.1);assert(remote.shots==3)
screenGui.Destroying:Fire()
for _,c in ipairs(changed.OnClientEvent.callbacks)do assert(not c.alive)end
