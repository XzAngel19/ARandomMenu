local events={}
for _,name in ipairs({'PlayerDataChanged','RoundStart','RoundEndFade','RoleSelect'})do
 local e={OnClientEvent=event()};function e:IsA(c)return c=='RemoteEvent'end;events[name]=e
end
local data={Alice={Name='Alice',Role='Murderer'},Me={Name='Me',Role='Innocent'}}
local fetch={};function fetch:IsA(c)return c=='RemoteFunction'end
function fetch:InvokeServer()return data end
events.GetCurrentPlayerData=fetch
local gameplay={};function gameplay:FindFirstChild(n)return events[n]end
local remotes={};function remotes:FindFirstChild(n)if n=='Gameplay'then return gameplay end end
local rs={};function rs:FindFirstChild(n)if n=='Remotes'then return remotes end end
services.ReplicatedStorage=rs
enemy.knife=nil;tools.equipped=gunTool;gunTool.Parent=character
installGunFeatures(screenGui)
AngelHub.setters['Gun Aimbot'](true);drain();heartbeat:Fire(.1)
userInputService.InputBegan:Fire(key,false);drain();assert(#remote.shots==1)
events.RoundEndFade.OnClientEvent:Fire();fakeNow+=1;heartbeat:Fire(.2)
userInputService.InputBegan:Fire(key,false);drain();assert(#remote.shots==1)
events.PlayerDataChanged.OnClientEvent:Fire(data);fakeNow+=1;userInputService.InputBegan:Fire(key,false);drain();assert(#remote.shots==1)
events.RoundStart.OnClientEvent:Fire(120,data);fakeNow+=1;heartbeat:Fire(.2);drain()
userInputService.InputBegan:Fire(key,false);drain();assert(#remote.shots==2)
AngelHub.setters['Gun Aimbot'](false)
fakeNow+=2;AngelHub.setters['Auto Shoot'](true);drain();heartbeat:Fire(.2);drain();assert(#remote.shots==3)
events.RoundEndFade.OnClientEvent:Fire();fakeNow+=2;heartbeat:Fire(.2);drain();assert(#remote.shots==3)
AngelHub.setters['Auto Shoot'](false);tools.equipped=nil;gunTool.Parent=backpack
AngelHub.setters['Gun Aura'](true);drain();events.RoleSelect.OnClientEvent:Fire('Murderer')
local before=#touches;fakeNow+=.1;heartbeat:Fire(.2);assert(#touches==before)
AngelHub.setters['Gun Aura'](false);screenGui.Destroying:Fire()
for _,e in pairs(events)do if e.OnClientEvent then for _,c in ipairs(e.OnClientEvent.callbacks)do assert(not c.alive)end end end
