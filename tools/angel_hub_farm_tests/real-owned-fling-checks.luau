local function setting(n,v)V[n]=v;AngelHub.setters[n]=function(x)V[n]=x end end
for _,n in ipairs({'Auto Farm','Coins Aura','Farm Safe Zone','Auto Grab Gun And Shoot','Reset When Full Coin Bag',
 'Stay Under When Round Starts','Auto Kill All When Full Bag','Fling Murder After Full Bag','Fling Sheriff After Full Bag',
 'Auto Fling Selected Target','Enable Speed','Enable Fly','Noclip','Auto Vote'})do setting(n,false)end
setting('Farm Speed',22);setting('Coins Collected',0);setting('Farm Time',0)
V['Fling Retries']=0;V['Fling Target']='Alice'
local fmt={};fmt.__index=fmt
fmt.__mul=function(a,b)return setmetatable({Position=a.Position+b.Position},fmt)end
function fmt:ToObjectSpace(b)return CFrame.new(b.Position-self.Position)end
function CFrame.new(x,y,z)local p=type(x)=='table' and x or Vector3.new(x or 0,y or 0,z or 0);return setmetatable({Position=p},fmt)end
function CFrame.Angles()return CFrame.new(0,0,0)end
Enum.HumanoidStateType={Seated='seated'};humanoid.FloorMaterial=Enum.Material.Ground;humanoid.seated=true
function humanoid:GetStateEnabled()return self.seated end;function humanoid:SetStateEnabled(_,v)self.seated=v end
character.Parent=workspace;root.Parent=character;root.Position=Vector3.zero;root.CFrame=CFrame.new(root.Position)
root.AssemblyAngularVelocity=Vector3.zero;root.Velocity=Vector3.zero;root.RotVelocity=Vector3.zero
function character:GetPivot()return root.CFrame end
function character:PivotTo(cf)self.lastPivot=cf;root.CFrame=cf;root.Position=cf.Position end
local human={Health=100,Sit=false,MoveDirection=Vector3.zero}
local targetRoot={Position=Vector3.new(20,0,0),AssemblyLinearVelocity=Vector3.zero}
function targetRoot:IsA(c)return c=='BasePart'end
local target={Parent=workspace};targetRoot.Parent=target
function target:FindFirstChildOfClass(n)if n=='Humanoid'then return human end end
function target:FindFirstChild(n)if n=='HumanoidRootPart'then return targetRoot end end
other.Character=target;workspace.FallenPartsDestroyHeight=-500
local collected={OnClientEvent=event()};function collected:IsA(c)return c=='RemoteEvent'end
local ended={OnClientEvent=event()};function ended:IsA(c)return c=='RemoteEvent'end
local started={OnClientEvent=event()};function started:IsA(c)return c=='RemoteEvent'end
local gameplay={};function gameplay:FindFirstChild(n)return ({CoinCollected=collected,RoundEndFade=ended,RoundStart=started})[n]end
local remotes={};function remotes:FindFirstChild(n)if n=='Gameplay'then return gameplay end end
local storage={};function storage:FindFirstChild(n)if n=='Remotes'then return remotes end end;services.ReplicatedStorage=storage
AngelHub.actions={};local role='Murderer'
AngelHub.getMM2Role=function(p)if p==other then return role end end
AngelHub.refreshMM2Roles=function()end;AngelHub.releaseMM2Roles=function()end
local coin={Name='Coin_Server',Parent=map,Position=Vector3.new(8,0,0)}
function coin:IsA(c)return c=='BasePart'end;function coin:GetAttribute()return nil end
function coin:FindFirstChild()return nil end;function coin:IsDescendantOf(p)return p==map and self.Parent==map end
map.descendants={coin};installMM2Fling(screenGui);installMM2Farm(screenGui)
AngelHub.setters['Fling Murder After Full Bag'](true);AngelHub.setters['Auto Farm'](true)
heartbeat:Fire(.2);collected.OnClientEvent:Fire('Coins',50,50);heartbeat:Fire(.2)
assert(not AngelHub.mm2FlingBusy) -- rests on map 1.5s before flinging
fakeNow+=1.6;heartbeat:Fire(.2)
local pin=created[#created];assert(pin.class=='BodyVelocity' and AngelHub.mm2FlingOwner=='farm' and V['Auto Farm'])
fakeNow+=.1;heartbeat:Fire(.2);assert(not pin.destroyed and V['Auto Farm'])
AngelHub.setters['Fling Murder After Full Bag'](false)
assert(pin.destroyed and not AngelHub.mm2FlingBusy and root.Position.X==0 and humanoid.seated)
-- Re-enabling while Murderer is still alive resumes flinging until Murderer dies!
AngelHub.setters['Fling Murder After Full Bag'](true);heartbeat:Fire(.2)
local pin2=created[#created];assert(pin2~=pin and pin2.class=='BodyVelocity' and AngelHub.mm2FlingOwner=='farm')
human.Health=0;fakeNow+=0.2;heartbeat:Fire(.2)
assert(pin2.destroyed and not AngelHub.mm2FlingBusy)
heartbeat:Fire(.2);assert(created[#created]==pin2) -- stops once target died
human.Health=100
collected.OnClientEvent:Fire('Coins',0,50);heartbeat:Fire(.2)
collected.OnClientEvent:Fire('Coins',50,50);heartbeat:Fire(.2);fakeNow+=1.6;heartbeat:Fire(.2);pin=created[#created]
assert(not pin.destroyed and AngelHub.mm2FlingOwner=='farm')
started.OnClientEvent:Fire(0);assert(pin.destroyed and not AngelHub.mm2FlingBusy and root.Position.X==0)
started.OnClientEvent:Fire(10);collected.OnClientEvent:Fire('Coins',0,50);heartbeat:Fire(.2)
collected.OnClientEvent:Fire('Coins',50,50);heartbeat:Fire(.2);fakeNow+=1.6;heartbeat:Fire(.2);pin=created[#created]
assert(not pin.destroyed and AngelHub.mm2FlingOwner=='farm')
humanoid.Health=0;heartbeat:Fire(.2);assert(pin.destroyed and not AngelHub.mm2FlingBusy)
humanoid.Health=100;fakeNow+=2;heartbeat:Fire(.2);assert(created[#created]==pin and not AngelHub.mm2FlingBusy)
screenGui.Destroying:Fire()
