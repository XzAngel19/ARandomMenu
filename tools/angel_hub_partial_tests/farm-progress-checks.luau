local function setting(name,value)V[name]=value;AngelHub.setters[name]=function(x)V[name]=x end end
setting('Farm Mode','Walk');setting('Farm Speed',22);setting('Farm Safe Zone',false)
setting('Coins Collected',0);setting('Farm Time',0)
local collected={OnClientEvent=event()};function collected:IsA(c)return c=='RemoteEvent'end
local ended={OnClientEvent=event()};function ended:IsA(c)return c=='RemoteEvent'end
local gameplay={};function gameplay:FindFirstChild(n)return ({CoinCollected=collected,RoundEndFade=ended})[n]end
local remotes={};function remotes:FindFirstChild(n)if n=='Gameplay'then return gameplay end end
local storage={};function storage:FindFirstChild(n)if n=='Remotes'then return remotes end end
services.ReplicatedStorage=storage
local coin={Name='Coin_Server',Position=Vector3.new(300,0,0),Parent=map}
function coin:IsA(c)return c=='BasePart'end
function coin:GetAttribute()return nil end
function coin:FindFirstChild()return nil end
function coin:IsDescendantOf(o)return o==map and self.Parent==map end
map.descendants={coin}
installGameplay(screenGui)
AngelHub.setters['Auto Farm'](true)
heartbeat:Fire(.11);assert(humanoid.lastMove.X==1)
-- Advancing toward a far coin for longer than six seconds must not blacklist it.
for i=1,8 do
 fakeNow+=1;root.Position=Vector3.new(i*10,0,0);heartbeat:Fire(.11)
 assert(humanoid.lastMove.X==1 and humanoid.WalkSpeed==22)
end
-- If progress stops, Walk tries a jump, then drops an unreachable target.
fakeNow+=2;humanoid.Jump=false;heartbeat:Fire(.11);assert(humanoid.Jump==true and root.AssemblyLinearVelocity.X==22)
fakeNow+=5;heartbeat:Fire(.11);heartbeat:Fire(.11)
assert(humanoid.lastMove.Magnitude==0 and humanoid.WalkSpeed==16 and root.AssemblyLinearVelocity.X==0)
fakeNow+=7;heartbeat:Fire(.11);assert(humanoid.lastMove.X==1)
-- An emptied bag after a full bag should allow farming again.
collected.OnClientEvent:Fire('Coins',50,50);heartbeat:Fire(.11)
assert(humanoid.WalkSpeed==16)
root.Position=Vector3.new(0,0,0);collected.OnClientEvent:Fire('Coins',0,50);heartbeat:Fire(.11)
assert(humanoid.WalkSpeed==22)
AngelHub.setters['Auto Farm'](false)
-- Actual coin-container maps outrank other non-lobby models with Spawns.
local fakeModel={Name='Decoy',Parent=workspace};function fakeModel:IsA(c)return c=='Model'end
function fakeModel:FindFirstChild(n)if n=='Spawns'then return spawns end end
local container={};function container:GetDescendants()return {coin}end
function container:IsA()return false end
local oldFind=map.FindFirstChild
function map:FindFirstChild(n)if n=='CoinContainer'then return container end;return oldFind(self,n)end
table.insert(workspace.objects,1,fakeModel)
AngelHub.setters['Auto Farm'](true);heartbeat:Fire(.11);assert(humanoid.WalkSpeed==22)
-- In lobby no movement, even with a map and coins available.
root.Position=Vector3.new(1000,0,0);heartbeat:Fire(.11);assert(humanoid.lastMove.Magnitude==0)
AngelHub.setters['Auto Farm'](false)
-- A real map may lack a Spawns folder: use a coin-container reference.
root.Position=Vector3.new(0,0,0)
function container:FindFirstChildWhichIsA(c)if c=='BasePart'then return coin end end
function map:FindFirstChild(n)if n=='CoinContainer'then return container end end
function map:FindFirstChildWhichIsA()return nil end
AngelHub.setters['Auto Farm'](true);heartbeat:Fire(.11);assert(humanoid.WalkSpeed==22)
screenGui.Destroying:Fire()
