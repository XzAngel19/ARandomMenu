for _,name in ipairs({'Instant Roles','Gun Notification','Murder Close','Sheriff Down','Your Role','Round Events','Murderer Defeated'})do V[name]=true end
V['Close Radius']=40;V['Close Cooldown']=10
localPlayer.Name='Me';localPlayer.UserId=1;other.UserId=2
local enemyRoot={Position=Vector3.new(20,0,0)};local enemyHumanoid={Health=100}
local enemy={};function enemy:FindFirstChildOfClass(n)if n=='Humanoid'then return enemyHumanoid end end
function enemy:FindFirstChild(n)if n=='HumanoidRootPart'then return enemyRoot end end
other.Character=enemy
localPlayer.Character=character
local data={Me={Name='Me',Role='Sheriff'},Alice={Name='Alice',Role='Murderer'}}
local fetch={count=0};function fetch:IsA(c)return c=='RemoteFunction'end
function fetch:InvokeServer()self.count+=1;return data end
local changed={OnClientEvent=event()};function changed:IsA(c)return c=='RemoteEvent'end
local ended={OnClientEvent=event()};function ended:IsA(c)return c=='RemoteEvent'end
local started={OnClientEvent=event()};function started:IsA(c)return c=='RemoteEvent'end
local roleSelect={OnClientEvent=event()};function roleSelect:IsA(c)return c=='RemoteEvent'end
local gameplay={};function gameplay:FindFirstChild(n)return ({GetCurrentPlayerData=fetch,PlayerDataChanged=changed,RoundEndFade=ended,RoundStart=started,RoleSelect=roleSelect})[n]end
local remotes={};function remotes:FindFirstChild(n)if n=='Gameplay'then return gameplay end end
local storage={};function storage:FindFirstChild(n)if n=='Remotes'then return remotes end end
services.ReplicatedStorage=storage
local currentGun=gun;local oldFind=workspace.FindFirstChild
function workspace:FindFirstChild(n,...)if n=='GunDrop'then return currentGun end;return oldFind(self,n,...)end
local function count(text)local n=0;for _,msg in ipairs(AngelHub.reports)do if string.find(msg,text,1,true)then n+=1 end end;return n end
installGameplay(screenGui)
heartbeat:Fire(.21)
assert(fetch.count==1 and count('Murderer: Alice')==1 and count('Sheriff/Hero: Me')==1 and count('Your role: Sheriff')==1)
assert(count('Murderer nearby')==1 and count('Gun dropped')==1)
roleSelect.OnClientEvent:Fire(0,data);heartbeat:Fire(.21)
assert(count('Murderer: Alice')==1 and count('Your role: Sheriff')==1)
fakeNow+=5;heartbeat:Fire(.21);assert(count('Murderer nearby')==1)
fakeNow+=6;heartbeat:Fire(.21);assert(count('Murderer nearby')==2)
-- Disappearance is not evidence of a death.
other.Character=nil;changed.OnClientEvent:Fire({Alice={Name='Alice',Role='Murderer'}});heartbeat:Fire(.21)
assert(count('Murderer defeated')==0)
other.Character=enemy;enemyHumanoid.Health=0;changed.OnClientEvent:Fire({Alice={Name='Alice',Role='Murderer',Dead=true}});heartbeat:Fire(.21)
assert(count('Murderer defeated')==1);heartbeat:Fire(.21);assert(count('Murderer defeated')==1)
ended.OnClientEvent:Fire();assert(count('Round ended')==1)
fakeNow+=3;heartbeat:Fire(.21);local before=fetch.count;heartbeat:Fire(.21);assert(fetch.count==before)
root.Position=Vector3.new(1000,0,0);started.OnClientEvent:Fire(10,data);heartbeat:Fire(.21);assert(count('Round started')==1 and count('Murderer: Alice')==1)
root.Position=Vector3.new(0,0,0);enemyHumanoid.Health=100;heartbeat:Fire(.21);assert(count('Murderer: Alice')==2)
screenGui.Destroying:Fire();for _,c in ipairs(changed.OnClientEvent.callbacks)do assert(not c.alive)end
