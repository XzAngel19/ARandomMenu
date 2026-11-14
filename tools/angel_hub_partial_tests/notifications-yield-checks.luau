V['Instant Roles']=true;localPlayer.Name='Me';localPlayer.UserId=1;other.UserId=2
localPlayer.Character=character
local enemyHuman={Health=100};local enemy={Parent=workspace};function enemy:FindFirstChildOfClass(n)if n=='Humanoid'then return enemyHuman end end
function enemy:FindFirstChild()return nil end;other.Character=enemy
local remote={};function remote:IsA(c)return c=='RemoteFunction'end
function remote:InvokeServer()coroutine.yield('pending-roles');return {Alice={Name='Alice',Role='Murderer'}} end
local ended={OnClientEvent=event()};function ended:IsA(c)return c=='RemoteEvent'end
local started={OnClientEvent=event()};function started:IsA(c)return c=='RemoteEvent'end
local gameplay={};function gameplay:FindFirstChild(n)return ({GetCurrentPlayerData=remote,RoundEndFade=ended,RoundStart=started})[n]end
local remotes={};function remotes:FindFirstChild(n)if n=='Gameplay'then return gameplay end end
local storage={};function storage:FindFirstChild(n)if n=='Remotes'then return remotes end end
services.ReplicatedStorage=storage
local queue={};task.spawn=function(f)table.insert(queue,f)end
local function pending()
 local found
 for _,fn in ipairs(queue)do local co=coroutine.create(fn);local ok,result=coroutine.resume(co);assert(ok)
  if result=='pending-roles'then found=co end
 end
 queue={};assert(found);return found
end
local function announced()for _,x in ipairs(AngelHub.reports)do if string.find(x,'Murderer: Alice',1,true)then return true end end;return false end
installGameplay(screenGui);heartbeat:Fire(.21);local thread=pending()
ended.OnClientEvent:Fire();assert(coroutine.resume(thread));heartbeat:Fire(.21);assert(not announced())
started.OnClientEvent:Fire(10);heartbeat:Fire(.21);thread=pending()
screenGui.Destroying:Fire();assert(coroutine.resume(thread));assert(not announced())
