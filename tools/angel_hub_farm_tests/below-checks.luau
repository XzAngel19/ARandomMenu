run.PreSimulation=event()
local pending={};task.delay=function(_,fn)table.insert(pending,fn)end
local function drain()local now=pending;pending={};for _,fn in ipairs(now)do fn()end end
local function setting(name, value)
 V[name]=value;AngelHub.setters[name]=function(newValue)V[name]=newValue end
end
AngelHub.moduleNames['Knife Aura']=true;setting('Knife Aura',false)
AngelHub.moduleNames['Coins Aura']=true;setting('Coins Aura',false)
setting('Knife Aura Range',15);setting('Knife Hold Mouse',false)
V['Farm Mode']='Walk';setting('Farm Speed',22);setting('Farm Safe Zone',false)
setting('Coins Collected',0);setting('Farm Time',0);setting('Stay Under When Round Starts',false)
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
services.ReplicatedStorage=storage
installGameplay(screenGui)
local originalRootSize=root.Size
humanoid.PlatformStand=false;humanoid.AutoRotate=true;humanoid.FloorMaterial=Enum.Material.Ground
root.Position=Vector3.new(0,0,0);root.CFrame={Position=root.Position};local homeFrame=root.CFrame
-- Optional round-start hold is only on the map and only until coins appear.
map.descendants={};AngelHub.setters['Stay Under When Round Starts'](true)
AngelHub.setters['Auto Farm'](true);heartbeat:Fire(.6);run.PreSimulation:Fire()
assert(V['Auto Farm'] and humanoid.PlatformStand and root.AssemblyLinearVelocity.Y<0)
character.lastPivot=nil;AngelHub.setters['Stay Under When Round Starts'](false)
assert(character.lastPivot==homeFrame and root.CanCollide and not humanoid.PlatformStand)
AngelHub.setters['Stay Under When Round Starts'](true);heartbeat:Fire(.6)
map.descendants={coin};heartbeat:Fire(.6);run.PreSimulation:Fire()
assert(V['Auto Farm'] and root.AssemblyLinearVelocity.X>0)
AngelHub.setters['Auto Farm'](false);AngelHub.setters['Stay Under When Round Starts'](false)
root.Position=Vector3.zero;root.CFrame=homeFrame
-- Aura may be active before Farm; restore its moved coin before Farm scans.
AngelHub.setters['Coins Aura'](true);heartbeat:Fire(.6)
assert(coin.CFrame==root.CFrame and not coin.CanCollide and visual.Anchored and not weld.Enabled)
AngelHub.setters['Auto Farm'](true);assert(V['Auto Farm'])
assert(coin.CFrame==originalCoinFrame and coin.CanCollide and not visual.Anchored and weld.Enabled)
local before=#touches
heartbeat:Fire(0.11)
assert(#touches>before and coin.CFrame==originalCoinFrame and coin.CanCollide and not visual.Anchored and weld.Enabled)
AngelHub.setters['Coins Aura'](false);AngelHub.setters['Coins Aura'](true)
heartbeat:Fire(.11);assert(V['Auto Farm'] and coin.CFrame==originalCoinFrame and coin.CanCollide)
AngelHub.setters['Coins Aura'](false)
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
assert(V['Auto Farm']);AngelHub.setters['Noclip'](false);AngelHub.setters['Auto Farm'](false);assert(root.CanCollide)
-- Full bag returns to the original interior when Below is active.
root.Position=Vector3.zero;root.CFrame=homeFrame
AngelHub.setters['Auto Farm'](true);heartbeat:Fire(.11)
collected.OnClientEvent:Fire('Coins',50,50);character.lastPivot=nil;heartbeat:Fire(.11)
assert(character.lastPivot==homeFrame and root.CanCollide)
AngelHub.setters['Auto Farm'](false)
-- Safe Zone restores the saved interior location when disabled.
root.Position=Vector3.zero;root.CFrame=homeFrame
AngelHub.setters['Farm Safe Zone'](true);AngelHub.setters['Auto Farm'](true);heartbeat:Fire(.11)
collected.OnClientEvent:Fire('Coins',50,50);heartbeat:Fire(.11)
local platform=created[#created];assert(platform.class=='Part' and not platform.destroyed)
root.Position=character.lastPivot.Position;character.lastPivot=nil
AngelHub.setters['Farm Safe Zone'](false)
assert(platform.destroyed and character.lastPivot==homeFrame)
AngelHub.setters['Auto Farm'](false)
screenGui.Destroying:Fire()
