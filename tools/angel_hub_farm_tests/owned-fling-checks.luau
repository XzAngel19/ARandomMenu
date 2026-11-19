local function setting(n,v)V[n]=v;AngelHub.setters[n]=function(x)V[n]=x end end
for _,n in ipairs({'Auto Farm','Auto Win','Enable Speed','Noclip','Enable Fly','Auto Vote','Auto Fling Selected Target','Auto Knife Throw','Insta Kill As Murder','Insta Kill As Sheriff','Fling Sheriff And Get Gun','Fling Murder If Dead'})do setting(n,false)end
for _,n in ipairs({'Sheriff Wins','Murder Wins','Innocent Wins'})do setting(n,0)end
setting('Fling Retries',1);setting('Fling Target','Alice')
local fmt={};fmt.__index=fmt
fmt.__mul=function(a,b)return setmetatable({Position=a.Position+b.Position},fmt)end
fmt.__add=function(a,v)return CFrame.new(a.Position+v)end
function fmt:ToObjectSpace(b)return CFrame.new(b.Position-self.Position)end
function CFrame.new(x,y,z)local p=type(x)=='table' and x or Vector3.new(x or 0,y or 0,z or 0);return setmetatable({Position=p},fmt)end
function CFrame.Angles()return CFrame.new(0,0,0)end
Enum.HumanoidStateType={Seated='seated'}
local function prepare(c,h,r)
 c.Parent=workspace;r.Parent=c;r.CFrame=CFrame.new(r.Position);r.AssemblyAngularVelocity=Vector3.zero
 h.seated=true;function h:GetStateEnabled()return self.seated end;function h:SetStateEnabled(_,v)self.seated=v end
 function c:GetPivot()return r.CFrame end
 function c:PivotTo(frame)self.lastPivot=frame;r.CFrame=frame;r.Position=frame.Position end
end
prepare(character,humanoid,root);humanoid.FloorMaterial=Enum.Material.Ground
local victimHuman={Health=100,Sit=false};local victimRoot={Position=Vector3.new(20,0,0),AssemblyLinearVelocity=Vector3.zero}
function victimRoot:IsA(c)return c=='BasePart'end
local target={Parent=workspace};victimRoot.Parent=target
function target:FindFirstChildOfClass(n)if n=='Humanoid'then return victimHuman end end
function target:FindFirstChild(n)if n=='HumanoidRootPart'then return victimRoot end end
other.Character=target;function other:FindFirstChildOfClass()return nil end
local role='Sheriff';local localRole='Innocent'
AngelHub.getMM2Role=function(p)if p==localPlayer then return localRole elseif p==other then return role end end
local drop,touches=nil,0;AngelHub.findMM2DroppedGun=function()return drop end
AngelHub.actions={['Get Gun']=function()touches+=1 end}
local ended={OnClientEvent=event()};function ended:IsA(c)return c=='RemoteEvent'end
local started={OnClientEvent=event()};function started:IsA(c)return c=='RemoteEvent'end
local victory={OnClientEvent=event()};function victory:IsA(c)return c=='RemoteEvent'end
local gameplay={};function gameplay:FindFirstChild(n)return ({RoundEndFade=ended,RoundStart=started,VictoryScreen=victory})[n]end
local remotes={};function remotes:FindFirstChild(n)if n=='Gameplay'then return gameplay end end
local storage={};function storage:FindFirstChild(n)if n=='Remotes'then return remotes end end
services.ReplicatedStorage=storage;workspace.FallenPartsDestroyHeight=-500
installMM2Fling(screenGui);installMM2Win(screenGui)
AngelHub.setters['Auto Win'](true);heartbeat:Fire(.2)
local platform=created[#created];assert(platform.Name=='AngelHub_AutoWinSafe')
fakeNow+=3;heartbeat:Fire(.2);assert(not AngelHub.mm2FlingBusy and not platform.destroyed)
AngelHub.setters['Fling Sheriff And Get Gun'](true);heartbeat:Fire(.2)
local pin=created[#created];assert(pin.class=='BodyVelocity' and AngelHub.mm2FlingOwner=='win' and V['Auto Win'])
heartbeat:Fire(.2);assert(not platform.destroyed and V['Auto Win'] and pin.Parent==root)
drop={};heartbeat:Fire(.2);assert(pin.destroyed and not AngelHub.mm2FlingBusy and not platform.destroyed and touches>0 and V['Auto Win'])
drop=nil;fakeNow+=7;heartbeat:Fire(.2);pin=created[#created];assert(pin.class=='BodyVelocity' and not pin.destroyed)
AngelHub.setters['Auto Fling Selected Target'](false);assert(not pin.destroyed)
ended.OnClientEvent:Fire();assert(pin.destroyed and platform.destroyed and not AngelHub.mm2FlingBusy)
AngelHub.setters['Auto Win'](false);started.OnClientEvent:Fire(10)
-- If the map unloads mid-fling, return to the still-existing safe platform,
-- and retain it on disable until the map return is available again.
root.Position=Vector3.zero;root.CFrame=CFrame.new(root.Position);AngelHub.setters['Auto Win'](true);heartbeat:Fire(.2)
local safePlatform=created[#created];fakeNow+=3;heartbeat:Fire(.2);local mapPin=created[#created]
assert(mapPin.class=='BodyVelocity' and AngelHub.mm2FlingOwner=='win')
heartbeat:Fire(.2);map.Parent=nil;heartbeat:Fire(.2)
assert(mapPin.destroyed and not safePlatform.destroyed and root.Position.Y==125 and V['Auto Win'])
AngelHub.setters['Auto Win'](false);assert(not safePlatform.destroyed)
map.Parent=workspace;AngelHub.setters['Auto Win'](true);assert(safePlatform.destroyed);AngelHub.setters['Auto Win'](false)
-- Death retaliation is opt-in, starts only after a recorded on-map death,
-- returns the respawned character to its own lobby position, and runs once.
root.Position=Vector3.zero;root.CFrame=CFrame.new(root.Position);humanoid.Health=100
AngelHub.setters['Fling Sheriff And Get Gun'](false);AngelHub.setters['Auto Win'](true);heartbeat:Fire(.2)
humanoid.Health=0;heartbeat:Fire(.2)
local nr={Position=Vector3.new(1000,0,0),AssemblyLinearVelocity=Vector3.zero};function nr:IsA(c)return c=='BasePart'end
local nh={Health=100,Sit=false,FloorMaterial=Enum.Material.Ground}
local nc={};function nc:FindFirstChildOfClass(n)if n=='Humanoid'then return nh end end
function nc:FindFirstChild(n)if n=='HumanoidRootPart'then return nr end end
prepare(nc,nh,nr);localPlayer.Character=nc;role='Murderer';fakeNow+=2;heartbeat:Fire(.2)
assert(not AngelHub.mm2FlingBusy)
AngelHub.setters['Fling Murder If Dead'](true);heartbeat:Fire(.2);pin=created[#created]
assert(pin.class=='BodyVelocity' and not pin.destroyed and AngelHub.mm2FlingOwner=='win')
heartbeat:Fire(.2);AngelHub.setters['Fling Murder If Dead'](false)
assert(pin.destroyed and nr.Position.X==1000 and not AngelHub.mm2FlingBusy)
AngelHub.setters['Fling Murder If Dead'](true);fakeNow+=5;heartbeat:Fire(.2);assert(created[#created]==pin)
started.OnClientEvent:Fire(10);fakeNow+=1;heartbeat:Fire(.2);assert(created[#created]==pin)
-- sheriffFling still runs when localPlayer role is nil (not yet populated).
localRole=nil;role='Sheriff'
AngelHub.setters['Auto Win'](false);localPlayer.Character=character;humanoid.Health=100;root.Position=Vector3.zero;root.CFrame=CFrame.new(root.Position)
AngelHub.setters['Fling Murder If Dead'](false);AngelHub.setters['Fling Sheriff And Get Gun'](true)
AngelHub.setters['Auto Win'](true);heartbeat:Fire(.2);fakeNow+=3;heartbeat:Fire(.2)
local nilRolePin=created[#created];assert(nilRolePin~=pin and nilRolePin.class=='BodyVelocity' and not nilRolePin.destroyed)
ended.OnClientEvent:Fire();assert(nilRolePin.destroyed)
screenGui.Destroying:Fire()
