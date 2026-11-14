local function setting(n,v)V[n]=v;AngelHub.setters[n]=function(x)V[n]=x end end
AngelHub.moduleNames['Auto Shoot']=true;AngelHub.moduleNames['Auto Win']=true;AngelHub.moduleNames['Insta Kill As Sheriff']=true
for n,v in pairs({['Auto Shoot']=false,['Auto Win']=false,['Insta Kill As Sheriff']=false,
 ['Shoot Mode']='Normal',['Shoot WallCheck']=false,['Win Sheriff WallCheck']=true,['Shoot Proximity']=true,['Shoot Proximity Aura']=5,
 ['Sheriff Wins']=0,['Murder Wins']=0,['Innocent Wins']=0})do setting(n,v)end
localPlayer.ChildAdded=event();localPlayer.CharacterAdded=event();character.ChildAdded=event()
local enemyRoot={Position=Vector3.new(20,0,0),AssemblyLinearVelocity=Vector3.new(0,0,0)}
function enemyRoot:IsA(c)return c=='BasePart'end
local knife={};function knife:IsA(c)return c=='Tool'end
local enemyHumanoid={Health=100};local enemy={}
function enemy:FindFirstChildOfClass(n)if n=='Humanoid'then return enemyHumanoid end end
function enemy:FindFirstChild(n)if n=='HumanoidRootPart'then return enemyRoot elseif n=='Knife'then return knife end end
other.Character=enemy;function other:FindFirstChildOfClass()return nil end
function localPlayer:FindFirstChildOfClass()return nil end
local remote={shots={}};function remote:IsA(c)return c=='RemoteEvent'end
function remote:FireServer(a,b)table.insert(self.shots,{a,b})end
local gun={Name='Gun',Enabled=true,Parent=character};function gun:IsA(c)return c=='Tool'end
function gun:GetAttribute()return nil end
function gun:FindFirstChild(n)if n=='Shoot'then return remote end end
local find=character.FindFirstChild
function character:FindFirstChild(n)if n=='Gun'then return gun else return find(self,n)end end
function root:FindFirstChild()return nil end
CFrame.lookAt=function(a,b)return {Position=a,Target=b}end
Color3={fromRGB=function(...)return {...}end}
local victory={OnClientEvent=event()};function victory:IsA(c)return c=='RemoteEvent'end
local ended={OnClientEvent=event()};function ended:IsA(c)return c=='RemoteEvent'end
local started={OnClientEvent=event()};function started:IsA(c)return c=='RemoteEvent'end
local gameplay={};function gameplay:FindFirstChild(n)return ({VictoryScreen=victory,RoundEndFade=ended,RoundStart=started})[n]end
local remotes={};function remotes:FindFirstChild(n)if n=='Gameplay'then return gameplay end end
local storage={};function storage:FindFirstChild(n)if n=='Remotes'then return remotes end end
services.ReplicatedStorage=storage
task.defer=function(f)f()end
workspace.shotWall=true
function workspace:Raycast()if self.shotWall then return {Instance=wall}end end
root.Position=Vector3.new(1000,0,0);root.CFrame={Position=root.Position}
humanoid.FloorMaterial=Enum.Material.Ground
installGameplay(screenGui)
AngelHub.setters['Insta Kill As Sheriff'](true);heartbeat:Fire(.1);assert(#remote.shots==0)
AngelHub.setters['Auto Win'](true);heartbeat:Fire(.1);assert(#remote.shots==0)
root.Position=Vector3.new(0,0,0);root.CFrame={Position=root.Position}
fakeNow+=1;heartbeat:Fire(.11);assert(#remote.shots==0) -- forced WallCheck
V['Win Sheriff WallCheck']=false;fakeNow+=1;heartbeat:Fire(.11)
assert(#remote.shots==1 and math.abs(remote.shots[1][1].Position.X-19)<.0001) -- CFrame despite Bullet/proximity
-- Toggle Auto Shoot separately; Win keeps its independent shooting after it turns off.
AngelHub.setters['Auto Shoot'](true);AngelHub.setters['Auto Shoot'](false)
fakeNow+=1;heartbeat:Fire(.11);assert(#remote.shots==2)
AngelHub.setters['Auto Win'](false);fakeNow+=1;heartbeat:Fire(.11);assert(#remote.shots==2)
-- With only Auto Shoot active, its own proximity still applies.
AngelHub.setters['Auto Shoot'](true);fakeNow+=1;heartbeat:Fire(.11);assert(#remote.shots==2)
AngelHub.setters['Auto Shoot'](false);screenGui.Destroying:Fire()
