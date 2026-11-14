local function setting(n,v)V[n]=v;AngelHub.setters[n]=function(x)V[n]=x end end
for _,name in ipairs({'Auto Win','Insta Kill As Murder'})do AngelHub.moduleNames[name]=true;setting(name,false)end
for _,name in ipairs({'Sheriff Wins','Murder Wins','Innocent Wins'})do setting(name,0)end
localPlayer.Neutral=true;other.Neutral=true
function other:FindFirstChildOfClass()return nil end
local targetFrame={Position=Vector3.new(20,0,0)}
local targetRoot={Position=targetFrame.Position,CFrame=targetFrame,Anchored=false,CanCollide=true}
function targetRoot:IsA(c)return c=='BasePart'end
local targetHuman={Health=100};local target={Parent=workspace}
function target:FindFirstChildOfClass(n)if n=='Humanoid'then return targetHuman end end
function target:FindFirstChild(n)if n=='HumanoidRootPart'then return targetRoot end end
other.Character=target
local handle={CFrame={Position=Vector3.new(0,125,0)}};function handle:IsA(c)return c=='BasePart'end
local remote={calls=0,shouldYield=false};function remote:IsA(c)return c=='RemoteEvent'end
function remote:FireServer(part)
 self.calls+=1;assert(part==targetRoot and part.Anchored and not part.CanCollide and part.CFrame==handle.CFrame)
 if self.shouldError then error('uncertain hit') end
 if self.shouldYield then coroutine.yield('pending-hit')end
end
local events={};function events:FindFirstChild(n)if n=='HandleTouched'then return remote end end
local knife={Parent=character,Enabled=true,activations=0};function knife:IsA(c)return c=='Tool'end
function knife:GetAttribute()return nil end
function knife:Activate()self.activations+=1 end
function knife:FindFirstChild(n)return ({Handle=handle,Events=events})[n]end
local oldFind=character.FindFirstChild
function character:FindFirstChild(n)if n=='Knife'then return self.hasKnife and knife end;return oldFind(self,n)end
character.hasKnife=true
local victory={OnClientEvent=event()};function victory:IsA(c)return c=='RemoteEvent'end
local ended={OnClientEvent=event()};function ended:IsA(c)return c=='RemoteEvent'end
local started={OnClientEvent=event()};function started:IsA(c)return c=='RemoteEvent'end
local gameplay={};function gameplay:FindFirstChild(n)return ({VictoryScreen=victory,RoundEndFade=ended,RoundStart=started})[n]end
local remotes={};function remotes:FindFirstChild(n)if n=='Gameplay'then return gameplay end end
local storage={};function storage:FindFirstChild(n)if n=='Remotes'then return remotes end end
services.ReplicatedStorage=storage
local queue={};task.spawn=function(fn)table.insert(queue,fn)end
local function runQueue()
 local pending
 for _,fn in ipairs(queue)do local co=coroutine.create(fn);local ok,result=coroutine.resume(co);assert(ok,tostring(result));if result=='pending-hit'then pending=co end end
 queue={};return pending
end
root.Position=Vector3.new(0,0,0);root.CFrame={Position=root.Position};humanoid.FloorMaterial=Enum.Material.Ground
installGameplay(screenGui)
AngelHub.setters['Insta Kill As Murder'](true);heartbeat:Fire(.2);runQueue();assert(remote.calls==0)
AngelHub.setters['Auto Win'](true);heartbeat:Fire(.11);root.Position=character.lastPivot.Position
heartbeat:Fire(.11);runQueue();assert(remote.calls==1 and knife.activations==1)
assert(targetRoot.CFrame==targetFrame and targetRoot.Anchored==false and targetRoot.CanCollide==true and V['Murder Wins']==0)
heartbeat:Fire(.11);runQueue();assert(remote.calls==1) -- per-player throttle
fakeNow+=1;remote.shouldYield=true;heartbeat:Fire(.11);local pending=runQueue()
assert(pending and targetRoot.Anchored and targetRoot.CFrame==handle.CFrame)
AngelHub.setters['Insta Kill As Murder'](false)
assert(targetRoot.CFrame==targetFrame and not targetRoot.Anchored and targetRoot.CanCollide)
assert(coroutine.resume(pending));heartbeat:Fire(.11);runQueue();assert(remote.calls==2)
-- Round end cancels an in-flight action and restores the victim too.
AngelHub.setters['Insta Kill As Murder'](true);fakeNow+=1;heartbeat:Fire(.11);pending=runQueue();assert(pending)
ended.OnClientEvent:Fire();assert(targetRoot.CFrame==targetFrame and not targetRoot.Anchored and targetRoot.CanCollide)
assert(coroutine.resume(pending));fakeNow+=1;heartbeat:Fire(.11);runQueue();assert(remote.calls==3)
started.OnClientEvent:Fire(10);remote.shouldYield=false;targetRoot.Anchored=true;heartbeat:Fire(.11);runQueue();assert(remote.calls==3)
targetRoot.Anchored=false;targetHuman.Health=0;fakeNow+=1;heartbeat:Fire(.11);runQueue();assert(remote.calls==3)
targetHuman.Health=100;remote.shouldError=true;fakeNow+=1;heartbeat:Fire(.11);runQueue()
assert(remote.calls==4 and not V['Insta Kill As Murder'] and targetRoot.CFrame==targetFrame and not targetRoot.Anchored and targetRoot.CanCollide)
AngelHub.setters['Auto Win'](false);screenGui.Destroying:Fire()
