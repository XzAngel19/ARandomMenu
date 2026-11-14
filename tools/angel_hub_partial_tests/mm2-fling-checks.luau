AngelHub.moduleNames['Auto Fling Selected Target']=true
V['Auto Fling Selected Target']=false;AngelHub.setters['Auto Fling Selected Target']=function(v)V['Auto Fling Selected Target']=v end
V['Fling Target']='Alice';V['Fling Power']=6;V['Fling Retries']=1
local fmt={}
fmt.__mul=function(a,b)return setmetatable({Position=a.Position+b.Position},fmt)end
function CFrame.new(x,y,z)
 local p=type(x)=='table' and x or Vector3.new(x or 0,y or 0,z or 0)
 return setmetatable({Position=p},fmt)
end
function CFrame.Angles()return CFrame.new(0,0,0)end
Enum.HumanoidStateType={Seated='seated'}
humanoid.seated=true;function humanoid:GetStateEnabled()return self.seated end
function humanoid:SetStateEnabled(_,v)self.seated=v end
character.Parent=workspace;root.Parent=character;root.CFrame=CFrame.new(0,0,0)
root.Velocity=Vector3.new(0,0,0);root.RotVelocity=Vector3.new(0,0,0)
local victimHuman={Health=100,Sit=false};local victimRoot={Position=Vector3.new(20,0,0),AssemblyLinearVelocity=Vector3.new(0,0,0)}
function victimRoot:IsA(c)return c=='BasePart'end
local target={Parent=workspace};victimRoot.Parent=target
function target:FindFirstChildOfClass(n)if n=='Humanoid'then return victimHuman end end
function target:FindFirstChild(n)if n=='HumanoidRootPart'then return victimRoot end end
other.Character=target;local home=root.CFrame
installGameplay(screenGui)
AngelHub.actions['Fling']()
local pin=created[#created];assert(pin.class=='BodyVelocity' and pin.Parent==root and not humanoid.seated)
heartbeat:Fire(.1);assert(root.CFrame.Position.X==20 and root.Velocity.X==180000000 and not pin.destroyed)
-- A conflicting module cancels and restores before it is enabled.
AngelHub.setters['Noclip'](true);assert(pin.destroyed and humanoid.seated and character.lastPivot==home and root.AssemblyLinearVelocity.Magnitude==0)
AngelHub.actions['Fling']();assert(created[#created]==pin) -- no reentry while noclip is enabled
AngelHub.setters['Noclip'](false)
-- High target speed, target death and unload all clean up.
AngelHub.actions['Fling']();pin=created[#created];victimRoot.AssemblyLinearVelocity=Vector3.new(600,0,0)
heartbeat:Fire(.1);assert(pin.destroyed and humanoid.seated)
victimRoot.AssemblyLinearVelocity=Vector3.new(0,0,0)
AngelHub.setters['Auto Fling Selected Target'](true);fakeNow+=2;heartbeat:Fire(.1)
pin=created[#created];assert(pin.class=='BodyVelocity' and not pin.destroyed)
V['Fling Target']='Nobody';heartbeat:Fire(.1);assert(pin.destroyed and humanoid.seated)
V['Fling Target']='Alice';fakeNow+=2;heartbeat:Fire(.1);pin=created[#created];assert(not pin.destroyed)
victimHuman.Health=0;heartbeat:Fire(.1);assert(pin.destroyed)
victimHuman.Health=100;fakeNow+=2;heartbeat:Fire(.1);pin=created[#created];assert(not pin.destroyed)
AngelHub.setters['Auto Fling Selected Target'](false);assert(pin.destroyed)
-- Role buttons request MM2 role data before choosing a victim.
localPlayer.Name='Me';localPlayer.UserId=1;other.UserId=2
local role={};function role:IsA(c)return c=='RemoteFunction'end
function role:InvokeServer()return {Alice={Name='Alice',Role='Murderer'}}end
local ended={OnClientEvent=event()};function ended:IsA(c)return c=='RemoteEvent'end
local started={OnClientEvent=event()};function started:IsA(c)return c=='RemoteEvent'end
local gameplay={};function gameplay:FindFirstChild(n)return ({GetCurrentPlayerData=role,RoundEndFade=ended,RoundStart=started})[n] end
local remotes={};function remotes:FindFirstChild(n)if n=='Gameplay'then return gameplay end end
local storage={};function storage:FindFirstChild(n)if n=='Remotes'then return remotes end end
services.ReplicatedStorage=storage
AngelHub.actions['Fling Murderer']();heartbeat:Fire(.21);heartbeat:Fire(.21)
pin=created[#created];assert(pin.class=='BodyVelocity' and not pin.destroyed)
-- Retry one 3-second pass, then stop rather than running forever.
fakeNow+=3.1;heartbeat:Fire(.21);assert(not pin.destroyed)
fakeNow+=3.1;heartbeat:Fire(.21);assert(pin.destroyed and humanoid.seated)
AngelHub.actions['Fling']();pin=created[#created];assert(pin.class=='BodyVelocity' and not pin.destroyed)
ended.OnClientEvent:Fire();assert(pin.destroyed and humanoid.seated)
AngelHub.actions['Fling']();assert(created[#created]==pin) -- no fling after round end
started.OnClientEvent:Fire(10);AngelHub.actions['Fling']();pin=created[#created];assert(pin.class=='BodyVelocity' and not pin.destroyed)
screenGui.Destroying:Fire();assert(pin.destroyed and humanoid.seated)
