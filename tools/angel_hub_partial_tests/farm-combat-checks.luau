run.PreSimulation=event()
local pending={};task.delay=function(_,fn)table.insert(pending,fn)end
local function drain()local now=pending;pending={};for _,fn in ipairs(now)do fn()end end
local function setting(name, value)
 V[name]=value;AngelHub.setters[name]=function(newValue)V[name]=newValue end
end
AngelHub.moduleNames['Knife Aura']=true;setting('Knife Aura',false)
AngelHub.moduleNames['Coins Aura']=true;setting('Coins Aura',false)
setting('Knife Aura Range',15);setting('Knife Hold Mouse',false)
setting('Farm Mode','Below');setting('Farm Speed',22);setting('Farm Safe Zone',false)
setting('Coins Collected',0);setting('Farm Time',0)
local collected={OnClientEvent=event()};function collected:IsA(c)return c=='RemoteEvent'end
local ended={OnClientEvent=event()};function ended:IsA(c)return c=='RemoteEvent'end
local started={OnClientEvent=event()};function started:IsA(c)return c=='RemoteEvent'end
local gameplay={};function gameplay:FindFirstChild(name)
 return ({CoinCollected=collected,RoundEndFade=ended,RoundStart=started})[name]
end
local remotes={};function remotes:FindFirstChild(name)if name=='Gameplay'then return gameplay end end
local storage={};function storage:FindFirstChild(name)if name=='Remotes'then return remotes end end
local coin={Name='Coin_Server',Parent=map,Position=Vector3.new(8,0,0),attrs={}}
function coin:IsA(c)return c=='BasePart'end
function coin:IsDescendantOf(object)return object==map and self.Parent==map end
function coin:GetAttribute(name)return self.attrs[name]end
local originalCoinFrame={Position=coin.Position};coin.CFrame=originalCoinFrame;coin.CanCollide=true
local weld={Enabled=true};local visual={Anchored=false}
function visual:IsA(c)return c=='BasePart'end
function visual:GetAttribute()return nil end
function visual:FindFirstChildOfClass(c)if c=='WeldConstraint'then return weld end end
function coin:FindFirstChild(n)if n=='CoinVisual'then return visual end end
map.descendants={coin}
installGameplay(screenGui)
assert(AngelHub.setters['Auto Farm'](true)==false and not V['Auto Farm'])
AngelHub.setters['Farm Mode']('Walk')
assert(AngelHub.setters['Auto Farm'](true)==false and not V['Auto Farm'])
services.ReplicatedStorage=storage
AngelHub.setters['Auto Farm'](true);assert(V['Auto Farm'])
heartbeat:Fire(0.11);assert(humanoid.lastMove.X==1 and humanoid.WalkSpeed==22)
collected.OnClientEvent:Fire('Coins',3,50);assert(V['Coins Collected']==1)
local beforeTouches=#touches;root.Position=Vector3.new(7,0,0);heartbeat:Fire(0.11)
assert(#touches==beforeTouches+2 and touches[#touches][2]==coin)
root.Position=Vector3.new(0,0,0);heartbeat:Fire(0.11)
root.Position=Vector3.new(1000,0,0);heartbeat:Fire(0.11)
assert(humanoid.lastMove.Magnitude==0 and humanoid.WalkSpeed==16)
root.Position=Vector3.new(0,0,0);heartbeat:Fire(0.11)
assert(humanoid.lastMove.X==1 and humanoid.WalkSpeed==22)
map.descendants={};heartbeat:Fire(0.6)
assert(humanoid.lastMove.Magnitude==0 and humanoid.WalkSpeed==16 and V['Auto Farm'])
map.descendants={coin};heartbeat:Fire(0.6);assert(humanoid.lastMove.X==1)
collected.OnClientEvent:Fire('Coins',50,50);assert(V['Coins Collected']==48);character.lastPivot=nil;heartbeat:Fire(0.11)
assert(humanoid.lastMove.Magnitude==0 and humanoid.WalkSpeed==16 and character.lastPivot.Y==3)
character.lastPivot=nil;heartbeat:Fire(0.2);assert(character.lastPivot==nil)
ended.OnClientEvent:Fire();heartbeat:Fire(0.2);assert(humanoid.lastMove.Magnitude==0)
started.OnClientEvent:Fire(10);heartbeat:Fire(0.2);assert(humanoid.lastMove.X==1)
AngelHub.setters['Farm Mode']('Below');assert(not V['Auto Farm'] and humanoid.lastMove.Magnitude==0 and humanoid.WalkSpeed==16)
AngelHub.setters['Farm Mode']('Walk');AngelHub.setters['Auto Farm'](true)
heartbeat:Fire(0.11);AngelHub.setters['Enable Speed'](true);assert(not V['Auto Farm'])
AngelHub.setters['Enable Speed'](false)
local originalRootSize=root.Size
humanoid.PlatformStand=false;humanoid.AutoRotate=true;humanoid.FloorMaterial=Enum.Material.Ground
root.Position=Vector3.new(0,0,0);root.CFrame={Position=root.Position};local homeFrame=root.CFrame
AngelHub.setters['Farm Mode']('Below');AngelHub.setters['Auto Farm'](true);assert(V['Auto Farm'])
heartbeat:Fire(0.11)
assert(not root.CanCollide and not head.CanCollide and root.Size.Y==8 and humanoid.PlatformStand and not humanoid.AutoRotate)
run.PreSimulation:Fire();assert(root.AssemblyLinearVelocity.X==22 and root.AssemblyLinearVelocity.Y<0)
root.Position=Vector3.new(3,-2,0);map.descendants={};heartbeat:Fire(0.6);run.PreSimulation:Fire()
assert(root.AssemblyLinearVelocity.Y<0)
map.descendants={coin};root.Position=Vector3.new(3,-3,0);character.lastPivot=nil;AngelHub.setters['Auto Farm'](false)
assert(root.CanCollide and head.CanCollide and root.Size==originalRootSize and not humanoid.PlatformStand and humanoid.AutoRotate and character.lastPivot==homeFrame)
root.Position=Vector3.new(0,0,0);root.CFrame=homeFrame
AngelHub.setters['Auto Farm'](true);heartbeat:Fire(0.11);assert(not root.CanCollide)
character.lastPivot=nil;root.Position=Vector3.new(1000,0,0);AngelHub.setters['Auto Farm'](false)
assert(character.lastPivot==nil and root.CanCollide and root.Size==originalRootSize)
root.Position=Vector3.new(0,0,0);root.CFrame=homeFrame
AngelHub.setters['Auto Farm'](true);heartbeat:Fire(0.11)
root.Position=Vector3.new(0,-500,0);character.lastPivot=nil;run.PreSimulation:Fire()
assert(not V['Auto Farm'] and root.CanCollide and character.lastPivot==homeFrame)
root.Position=Vector3.new(0,0,0);root.CFrame=homeFrame
AngelHub.setters['Auto Farm'](true);heartbeat:Fire(0.11);AngelHub.setters['Noclip'](true)
assert(not V['Auto Farm']);AngelHub.setters['Noclip'](false);assert(root.CanCollide)
AngelHub.setters['Farm Mode']('Under');assert(AngelHub.setters['Auto Farm'](true)==false)
AngelHub.setters['Farm Mode']('Walk')
root.Position=Vector3.new(0,0,0);root.CFrame=homeFrame
AngelHub.setters['Farm Safe Zone'](true);AngelHub.setters['Auto Farm'](true);heartbeat:Fire(0.11)
collected.OnClientEvent:Fire('Coins',50,50);character.lastPivot=nil;heartbeat:Fire(0.11)
local platform=created[#created]
assert(platform.class=='Part' and not platform.destroyed and character.lastPivot.Position.Y==385)
root.Position=character.lastPivot.Position;character.lastPivot=nil
AngelHub.setters['Farm Safe Zone'](false)
assert(platform.destroyed and character.lastPivot.Y==3)
character.lastPivot=nil;AngelHub.setters['Farm Safe Zone'](false);assert(character.lastPivot==nil)
AngelHub.setters['Auto Farm'](false);root.Position=Vector3.new(0,0,0);root.CFrame=homeFrame
AngelHub.setters['Farm Safe Zone'](true);AngelHub.setters['Auto Farm'](true);heartbeat:Fire(0.11)
collected.OnClientEvent:Fire('Coins',50,50);heartbeat:Fire(0.11)
local platform2=created[#created];root.Position=character.lastPivot.Position;character.lastPivot=nil
AngelHub.setters['Auto Farm'](false);assert(platform2.destroyed and character.lastPivot.Y==3)
AngelHub.setters['Farm Safe Zone'](false);root.Position=Vector3.new(0,0,0)
AngelHub.setters['Farm Mode']('Below');root.CFrame=homeFrame
AngelHub.setters['Farm Safe Zone'](true);AngelHub.setters['Auto Farm'](true);heartbeat:Fire(0.11)
collected.OnClientEvent:Fire('Coins',50,50);heartbeat:Fire(0.11)
local platform3=created[#created];root.Position=character.lastPivot.Position;character.lastPivot=nil
AngelHub.setters['Farm Safe Zone'](false);assert(platform3.destroyed and character.lastPivot==homeFrame)
AngelHub.setters['Auto Farm'](false);root.Position=Vector3.new(0,0,0);root.CFrame=homeFrame
AngelHub.setters['Farm Mode']('Walk');AngelHub.setters['Farm Safe Zone'](true);AngelHub.setters['Auto Farm'](true)
heartbeat:Fire(0.11);collected.OnClientEvent:Fire('Coins',50,50);heartbeat:Fire(0.11)
local platform4=created[#created];root.Position=character.lastPivot.Position;character.lastPivot=nil;map.Parent=nil
AngelHub.setters['Auto Farm'](false);assert(not platform4.destroyed and character.lastPivot==nil)
map.Parent=workspace;AngelHub.setters['Farm Safe Zone'](false);assert(platform4.destroyed and character.lastPivot.Y==3)
root.Position=Vector3.new(0,0,0)
local previous=#touches;AngelHub.setters['Coins Aura'](true);heartbeat:Fire(0.1)
assert(coin.CFrame==root.CFrame and not coin.CanCollide and visual.Anchored and not weld.Enabled)
assert(#touches==previous+2 and touches[#touches][2]==coin)
AngelHub.setters['Coins Aura'](false)
assert(coin.CFrame==originalCoinFrame and coin.CanCollide and not visual.Anchored and weld.Enabled)
local originalTouch=firetouchinterest;firetouchinterest=nil
assert(AngelHub.setters['Coins Aura'](true)==false and not V['Coins Aura']);firetouchinterest=originalTouch
AngelHub.setters['Coins Aura'](true);heartbeat:Fire(0.1)
local externalFrame={Position=coin.Position};coin.CFrame=externalFrame;coin.CanCollide=true
AngelHub.setters['Coins Aura'](false);assert(coin.CFrame==externalFrame and coin.CanCollide and not visual.Anchored and weld.Enabled)
coin.CFrame=originalCoinFrame
root.Position=Vector3.new(1000,0,0);previous=#touches;AngelHub.setters['Coins Aura'](true);heartbeat:Fire(0.1)
assert(#touches==previous and coin.CFrame==originalCoinFrame);AngelHub.setters['Coins Aura'](false)
root.Position=Vector3.new(0,0,0)

local enemyRoot={Position=Vector3.new(5,0,0)};function enemyRoot:IsA(c)return c=='BasePart'end
local enemyHumanoid={Health=100}
local enemyCharacter={};function enemyCharacter:FindFirstChild(name)if name=='HumanoidRootPart'then return enemyRoot end end
function enemyCharacter:FindFirstChildOfClass(name)if name=='Humanoid'then return enemyHumanoid end end
local enemy={Name='Victim',DisplayName='Victim',Character=enemyCharacter,Team='B'}
function enemy:FindFirstChildOfClass()return nil end
local localTeam='A';localPlayer.Team=localTeam;localPlayer.Neutral=false
function playersService:GetPlayers()return {localPlayer,enemy}end
local remote={hits=0};function remote:IsA(c)return c=='RemoteEvent'end
function remote:FireServer(target)assert(target==enemyRoot);self.hits+=1 end
local knifeEvents={};function knifeEvents:FindFirstChild(n)if n=='HandleTouched'then return remote end end
local handle={};function handle:IsA(c)return c=='BasePart'end
local knife={Enabled=true,swings=0}
function knife:IsA(c)return c=='Tool'end
function knife:GetAttribute()return nil end
function knife:Activate()self.swings+=1 end
function knife:FindFirstChild(n)if n=='Handle'then return handle elseif n=='Events'then return knifeEvents end end
local originalFind=character.FindFirstChild
function character:FindFirstChild(n)if n=='Knife'then return knife else return originalFind(self,n)end end
root.Position=Vector3.new(0,0,0)
AngelHub.setters['Knife Aura'](true);heartbeat:Fire(0.1)
assert(knife.swings==1 and #pending==1 and remote.hits==0)
drain();assert(remote.hits==1)
AngelHub.setters['Knife Aura'](false);AngelHub.setters['Knife Aura'](true);heartbeat:Fire(0.1)
assert(#pending==1);AngelHub.setters['Knife Aura'](false);drain();assert(remote.hits==1)
enemy.Team='A';AngelHub.setters['Knife Aura'](true);heartbeat:Fire(0.1);assert(#pending==0 and remote.hits==1)
AngelHub.setters['Knife Aura'](false);enemy.Team='B';V['Knife Hold Mouse']=true;AngelHub.setters['Knife Aura'](true)
heartbeat:Fire(0.2);assert(#pending==0)
userInputService.InputBegan:Fire({UserInputType=Enum.UserInputType.MouseButton1},true);assert(#pending==0)
AngelHub.mainWindow={Visible=true,AbsolutePosition={X=10,Y=10},AbsoluteSize={X=100,Y=100}}
function playerGui:GetGuiObjectsAtPosition()return {} end
userInputService.InputBegan:Fire({UserInputType=Enum.UserInputType.MouseButton1,Position={X=50,Y=50}},false);assert(#pending==0)
userInputService.InputBegan:Fire({UserInputType=Enum.UserInputType.MouseButton1,Position={X=200,Y=200}},false);assert(#pending==1)
drain();assert(remote.hits==2)
AngelHub.setters['Knife Aura'](false);V['Knife Hold Mouse']=false
AngelHub.setters['Knife Aura'](true);heartbeat:Fire(0.1);enemyRoot.Position=Vector3.new(100,0,0)
drain();assert(remote.hits==2)
AngelHub.setters['Knife Aura'](false);enemyRoot.Position=Vector3.new(5,0,0)
function remote:FireServer()error('mock remote denied')end
local touchCount=#touches;AngelHub.setters['Knife Aura'](true);heartbeat:Fire(0.1);drain()
assert(#touches==touchCount+2 and touches[#touches][1]==handle and touches[#touches][2]==enemyRoot)
AngelHub.setters['Knife Aura'](false);screenGui.Destroying:Fire()
print('farm/combat mock PASS')
