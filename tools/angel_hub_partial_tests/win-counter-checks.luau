local function setting(n,v)V[n]=v;AngelHub.setters[n]=function(x)V[n]=x end end
AngelHub.moduleNames['Auto Win']=true;setting('Auto Win',false)
for _,n in ipairs({'Sheriff Wins','Murder Wins','Innocent Wins'})do setting(n,0)end
setting('Farm Mode','Walk');setting('Farm Speed',16);setting('Farm Safe Zone',false)
local victory={OnClientEvent=event()};function victory:IsA(c)return c=='RemoteEvent'end
local ended={OnClientEvent=event()};function ended:IsA(c)return c=='RemoteEvent'end
local started={OnClientEvent=event()};function started:IsA(c)return c=='RemoteEvent'end
local gameplay={};function gameplay:FindFirstChild(n)return ({VictoryScreen=victory,RoundEndFade=ended,RoundStart=started})[n]end
local remotes={};function remotes:FindFirstChild(n)if n=='Gameplay'then return gameplay end end
local storage={};function storage:FindFirstChild(n)if n=='Remotes'then return remotes end end
services.ReplicatedStorage=storage
root.Position=Vector3.new(1000,0,0);root.CFrame={Position=root.Position}
humanoid.FloorMaterial=Enum.Material.Ground
installGameplay(screenGui)
AngelHub.setters['Auto Win'](true);assert(V['Auto Win'])
character.lastPivot=nil;heartbeat:Fire(.11);assert(character.lastPivot==nil) -- lobby
root.Position=Vector3.new(0,0,0);root.CFrame={Position=root.Position};local home=root.CFrame
heartbeat:Fire(.11);local platform=created[#created]
assert(platform.Name=='AngelHub_AutoWinSafe' and character.lastPivot.Position.Y==125)
root.Position=character.lastPivot.Position
character.lastPivot=nil;AngelHub.setters['Auto Win'](true)
assert(not platform.destroyed and character.lastPivot==nil)
victory.OnClientEvent:Fire(true,'Sheriff','SheriffWin');assert(V['Sheriff Wins']==1)
victory.OnClientEvent:Fire(true,'Sheriff','SheriffWin');assert(V['Sheriff Wins']==1)
AngelHub.setters['Auto Win'](false)
assert(platform.destroyed and character.lastPivot==home and V['Sheriff Wins']==1)
root.Position=Vector3.new(0,0,0);heartbeat:Fire(10)
started.OnClientEvent:Fire(10);victory.OnClientEvent:Fire(true,'Murderer','MurdererWin')
assert(V['Murder Wins']==0 and V['Sheriff Wins']==1)
AngelHub.setters['Auto Win'](true);assert(V['Sheriff Wins']==1)
victory.OnClientEvent:Fire(true,'Murderer','MurdererWin');assert(V['Murder Wins']==0)
started.OnClientEvent:Fire(10);victory.OnClientEvent:Fire(true,'Murderer','MurdererWin')
assert(V['Murder Wins']==1 and V['Sheriff Wins']==1)
started.OnClientEvent:Fire(10);victory.OnClientEvent:Fire(false,'Innocent','MurdererDied')
assert(V['Innocent Wins']==0)
started.OnClientEvent:Fire(10);victory.OnClientEvent:Fire(true,'Innocent','MurdererWin')
assert(V['Innocent Wins']==0)
started.OnClientEvent:Fire(10);victory.OnClientEvent:Fire(true,'Innocent','Time')
assert(V['Innocent Wins']==1)
started.OnClientEvent:Fire(10);victory.OnClientEvent:Fire(true,'Hero','MurdererLeft')
assert(V['Sheriff Wins']==2)
assert(AngelHub.setters['Noclip'](true)~=false and V['Noclip'])
assert(AngelHub.setters['Enable Speed'](true)~=false and V['Enable Speed'])
AngelHub.setters['Noclip'](false);AngelHub.setters['Enable Speed'](false)
AngelHub.setters['Auto Win'](false)
assert(V['Sheriff Wins']==2 and V['Murder Wins']==1 and V['Innocent Wins']==1)
started.OnClientEvent:Fire(10);AngelHub.setters['Auto Win'](true)
assert(V['Sheriff Wins']==2 and V['Murder Wins']==1 and V['Innocent Wins']==1)
-- Keep the platform if the map is gone and return would be unsafe.
root.Position=Vector3.new(0,0,0);root.CFrame=home;heartbeat:Fire(.11)
local last=created[#created];root.Position=character.lastPivot.Position;map.Parent=nil
AngelHub.setters['Auto Win'](false);assert(not last.destroyed)
map.Parent=workspace;AngelHub.setters['Auto Win'](true);assert(last.destroyed)
AngelHub.setters['Auto Win'](false)
-- While airborne use a map spawn for safe return, not a midair frame.
root.Position=Vector3.new(0,10,0);root.CFrame={Position=root.Position};humanoid.FloorMaterial=Enum.Material.Air
AngelHub.setters['Auto Win'](true);heartbeat:Fire(.11)
local airPlatform=created[#created];assert(airPlatform.Name=='AngelHub_AutoWinSafe')
root.Position=character.lastPivot.Position;AngelHub.setters['Auto Win'](false)
assert(airPlatform.destroyed and character.lastPivot.Y==3)
-- A character near the destroy plane is not moved further into danger.
root.Position=Vector3.new(0,-450,0);root.CFrame={Position=root.Position};local objectsBefore=#created
AngelHub.setters['Auto Win'](true);heartbeat:Fire(.11);assert(#created==objectsBefore)
AngelHub.setters['Auto Win'](false);screenGui.Destroying:Fire()
for _,c in ipairs(victory.OnClientEvent.callbacks)do assert(not c.alive)end
