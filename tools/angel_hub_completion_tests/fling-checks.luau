local errors={};warn=function(s)table.insert(errors,s)end
setting('Auto Fling Selected Target',false);V['Fling Target']='Alice';V['Fling Retries']=1
AngelHub.setters['Enable Fly']=function(v)V['Enable Fly']=v end
AngelHub.setters['Auto Vote']=function(v)V['Auto Vote']=v end
local fmt={};fmt.__index=fmt
fmt.__mul=function(a,b)return setmetatable({Position=a.Position+b.Position},fmt)end
function fmt:ToObjectSpace(b)return CFrame.new(b.Position-self.Position)end
function CFrame.new(x,y,z)local p=type(x)=='table' and x or Vector3.new(x or 0,y or 0,z or 0);return setmetatable({Position=p},fmt)end
function CFrame.Angles()return CFrame.new(0,0,0)end
Enum.HumanoidStateType.Seated='seated'
humanoid.FloorMaterial=Enum.Material.Ground;humanoid.seated=true;function humanoid:GetStateEnabled()return self.seated end
function humanoid:SetStateEnabled(_,v)self.seated=v end
character.Parent=workspace;root.Parent=character;root.CFrame=CFrame.new(0,0,0)
root.Velocity=Vector3.zero;root.RotVelocity=Vector3.zero;root.AssemblyAngularVelocity=Vector3.zero
function character:GetPivot()return root.CFrame end
function character:PivotTo(frame)self.lastPivot=frame;root.CFrame=frame end
local victimHuman={Health=100,Sit=false};local victimRoot={Position=Vector3.new(20,0,0),AssemblyLinearVelocity=Vector3.zero}
function victimRoot:IsA(c)return c=='BasePart'end
local target={Parent=workspace};victimRoot.Parent=target
function target:FindFirstChildOfClass(n)if n=='Humanoid'then return victimHuman end end
function target:FindFirstChild(n)if n=='HumanoidRootPart'then return victimRoot end end
other.Character=target;local home=root.CFrame
workspace.FallenPartsDestroyHeight=-500
AngelHub.findMM2Map=function()return map end
local roleCalls,released,shieldCalls=0,0,0
AngelHub.getMM2Role=function(p)return p==other and 'Murderer' end
AngelHub.refreshMM2Roles=function()roleCalls+=1 end
AngelHub.releaseMM2Roles=function()released+=1 end
AngelHub.suspendAntiFling=function()assert(AngelHub.mm2FlingBusy);shieldCalls+=1 end
local ended={OnClientEvent=event()};function ended:IsA(c)return c=='RemoteEvent'end
local started={OnClientEvent=event()};function started:IsA(c)return c=='RemoteEvent'end
local gameplay={};function gameplay:FindFirstChild(n)return ({RoundEndFade=ended,RoundStart=started})[n] end
local remotes={};function remotes:FindFirstChild(n)if n=='Gameplay'then return gameplay end end
local storage={};function storage:FindFirstChild(n)if n=='Remotes'then return remotes end end
services.ReplicatedStorage=storage
local status='';AngelHub.setFlingStatus=function(s)status=s end
installMM2Fling(screenGui)
assert(#created==0 and not AngelHub.mm2FlingBusy)
-- Missing map/lobby refs no longer silently reject selected targets.
AngelHub.findMM2Map=function()return nil end
AngelHub.actions['Fling']();local first=created[#created];assert(first and first.Parent==root and status:find('Alice'))
heartbeat:Fire(.1);assert(root.Velocity.X==240)
AngelHub.setters['Noclip'](true);assert(first.destroyed and character.lastPivot==home);AngelHub.setters['Noclip'](false)
AngelHub.findMM2Map=function()return map end
V['Fling Target']='Nobody';AngelHub.actions['Fling']();assert(status:find('Selecciona'))
V['Fling Target']='Alice';humanoid.FloorMaterial=Enum.Material.Air;AngelHub.actions['Fling']();assert(status:find('suelo'))
humanoid.FloorMaterial=Enum.Material.Ground

AngelHub.actions['Fling']();local pin=created[#created]
assert(pin.class=='BodyVelocity' and pin.Parent==root and not humanoid.seated and shieldCalls==2)
assert(pin.Velocity.X==240 and pin.Velocity.Y==160 and pin.MaxForce.X<=60000 and pin.P==400)
heartbeat:Fire(.1);assert(character.lastPivot.Position.X==20 and root.Velocity.X==240 and root.RotVelocity.Magnitude<150 and not pin.destroyed)
local previousPose=character.lastPivot;heartbeat:Fire(.1);assert(character.lastPivot==previousPose) -- max 30 poses/second
head.AssemblyLinearVelocity=Vector3.new(900,0,0);head.AssemblyAngularVelocity=Vector3.new(0,900,0)
AngelHub.setters['Noclip'](true);assert(pin.destroyed and humanoid.seated and character.lastPivot==home and not AngelHub.mm2FlingBusy)
assert(root.AssemblyLinearVelocity.Magnitude==0 and root.AssemblyAngularVelocity.Magnitude==0 and head.AssemblyLinearVelocity.Magnitude==0 and head.AssemblyAngularVelocity.Magnitude==0)
AngelHub.actions['Fling']();assert(created[#created]==pin and status:find('Apaga'))
AngelHub.setters['Noclip'](false)
AngelHub.actions['Fling']();pin=created[#created];victimRoot.AssemblyLinearVelocity=Vector3.new(600,0,0)
heartbeat:Fire(.1);assert(pin.destroyed and humanoid.seated)
victimRoot.AssemblyLinearVelocity=Vector3.zero
-- Excess local speed or spin cancels promptly and clears assembly motion.
AngelHub.actions['Fling']();pin=created[#created];root.AssemblyAngularVelocity=Vector3.new(0,350,0)
heartbeat:Fire(.1);assert(pin.destroyed and root.AssemblyAngularVelocity.Magnitude==0 and root.AssemblyLinearVelocity.Magnitude==0)
AngelHub.setters['Auto Fling Selected Target'](true);fakeNow+=5;heartbeat:Fire(.1)
pin=created[#created];assert(not pin.destroyed)
V['Fling Target']='Nobody';heartbeat:Fire(.1);assert(pin.destroyed)
V['Fling Target']='Alice';fakeNow+=5;heartbeat:Fire(.1);pin=created[#created];assert(not pin.destroyed)
victimHuman.Health=0;heartbeat:Fire(.1);assert(pin.destroyed)
victimHuman.Health=100;fakeNow+=5;heartbeat:Fire(.1);pin=created[#created];assert(not pin.destroyed)
AngelHub.setters['Auto Fling Selected Target'](false);assert(pin.destroyed)
AngelHub.actions['Fling Murderer']();assert(roleCalls==1);heartbeat:Fire(.1);pin=created[#created];assert(not pin.destroyed and released>0)
fakeNow+=3.1;heartbeat:Fire(.1);assert(not pin.destroyed)
fakeNow+=3.1;heartbeat:Fire(.1);assert(pin.destroyed)
AngelHub.actions['Fling']();pin=created[#created];ended.OnClientEvent:Fire();assert(pin.destroyed)
AngelHub.actions['Fling']();pin=created[#created];assert(not pin.destroyed)
started.OnClientEvent:Fire(10);AngelHub.actions['Fling']();pin=created[#created];assert(not pin.destroyed)
started.OnClientEvent:Fire(0);assert(pin.destroyed)
started.OnClientEvent:Fire(10);root.Position=Vector3.new(1000,0,0);AngelHub.actions['Fling']();pin=created[#created];assert(not pin.destroyed);AngelHub.setters['Noclip'](true);assert(pin.destroyed);AngelHub.setters['Noclip'](false)
root.Position=Vector3.zero;victimRoot.Position=Vector3.new(20,-480,0);AngelHub.actions['Fling']();assert(created[#created]==pin)
victimRoot.Position=Vector3.new(20,0,0);AngelHub.actions['Fling']();pin=created[#created];assert(not pin.destroyed)
function playersService:GetPlayers()return {localPlayer}end
heartbeat:Fire(.1);assert(pin.destroyed)
function playersService:GetPlayers()return {localPlayer,other}end
-- Like the supplied SkidFling, fall back to a head if root is unavailable.
local originalFind=target.FindFirstChild
function target:FindFirstChild(n)if n=='Head'then return victimRoot end end
AngelHub.actions['Fling']();pin=created[#created];assert(not pin.destroyed)
AngelHub.setters['Noclip'](true);assert(pin.destroyed);AngelHub.setters['Noclip'](false)
target.FindFirstChild=originalFind
AngelHub.actions['Fling']();pin=created[#created];screenGui.Destroying:Fire();assert(pin.destroyed and humanoid.seated)
assert(#errors==0)
