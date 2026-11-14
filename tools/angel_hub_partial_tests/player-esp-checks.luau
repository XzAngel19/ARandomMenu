AngelHub.moduleNames['Player ESP']=true;V['Player ESP']=false;AngelHub.setters['Player ESP']=function(v)V['Player ESP']=v end
local function color(name)local c={name=name};function c:Lerp(_,_)return color(self.name..'-dim')end;return c end
Color3={new=function()return color('black')end}
for n,v in pairs({['ESP Boxes']='Corner',['Box Thickness']=2,['Filled Box']=true,['Skeleton']=true,['Tracers']='Bottom',
 ['ESP Team Check']=true,['ESP Visibility Check']=false,['ESP Max Distance']=100,['ESP Colour']=color('white'),
 ['Role Colours']=true,['Murderer Colour']=color('red'),['Murderer ESP']=true,['Dead Colour']=color('grey'),['Dead ESP']=false})do V[n]=v end
localPlayer.Name='Me';localPlayer.UserId=1;other.UserId=2
local human={Health=100};local target={Position=Vector3.new(20,0,0)};function target:IsA(n)return n=='BasePart'end
local torso={Position=Vector3.new(20,1,0)};function torso:IsA(n)return n=='BasePart'end
local headpart={Position=Vector3.new(20,3,0)};function headpart:IsA(n)return n=='BasePart'end
local enemy={Parent=workspace}
function enemy:IsDescendantOf(w)return self.Parent==w end
function enemy:FindFirstChildOfClass(n)if n=='Humanoid'then return human end end
function enemy:FindFirstChild(n)return ({HumanoidRootPart=target,Torso=torso,Head=headpart})[n]end
local frame={};function frame:PointToWorldSpace(v)return Vector3.new(20+v.X,v.Y,v.Z)end
function enemy:GetBoundingBox()return frame,Vector3.new(4,6,2)end
other.Character=enemy;camera.ViewportSize=Vector2.new(800,600);camera.CFrame.Position=Vector3.new(0,0,0)
function camera:WorldToViewportPoint(p)return {X=400+p.X*5,Y=300-p.Y*5,Z=100+p.Z}end
function userInputService:GetMouseLocation()return Vector2.new(123,234)end
local remote={};function remote:IsA(c)return c=='RemoteFunction'end;function remote:InvokeServer()return {Alice={Name='Alice',Role='Murderer'}}end
local gameplay={};function gameplay:FindFirstChild(n)if n=='GetCurrentPlayerData'then return remote end end
local remotes={};function remotes:FindFirstChild(n)if n=='Gameplay'then return gameplay end end
local storage={};function storage:FindFirstChild(n)if n=='Remotes'then return remotes end end;services.ReplicatedStorage=storage
local function find(name)for i=#created,1,-1 do if created[i].Name==name then return created[i] end end end
installGameplay(screenGui);heartbeat:Fire(.21);assert(not find('AngelHubPlayerESP'))
AngelHub.setters['Player ESP'](true);heartbeat:Fire(.21);heartbeat:Fire(.21)
local layer,fill,edge,bone,tracer=find('AngelHubPlayerESP'),find('Fill'),find('Edge1'),find('Bone1'),find('Tracer')
assert(layer and fill.Visible and edge.Visible and bone.Visible and tracer.Visible)
assert(fill.Position.X==490 and fill.Position.Y==285 and fill.Size.X==20 and fill.Size.Y==30)
assert(edge.BackgroundColor3.name=='red' and edge.Size.Y==2 and tracer.Position.Y==457.5)
V['ESP Boxes']='Full';V['Box Thickness']=3;V['Skeleton']=false;V['Tracers']='Cursor';heartbeat:Fire(.1)
assert(edge.Size.X==20 and edge.Size.Y==3 and not bone.Visible and tracer.Position.X==(123+500)/2)
assert(not find('Edge5').Visible)
V['ESP Boxes']='Off';V['Tracers']='Off';heartbeat:Fire(.1);assert(not fill.Visible and not edge.Visible and not tracer.Visible)
local obstruction={};function obstruction:IsDescendantOf()return false end
function workspace:Raycast()return {Instance=obstruction}end
V['ESP Visibility Check']=true;V['ESP Boxes']='Full';heartbeat:Fire(.1);assert(edge.BackgroundColor3.name=='red-dim')
V['ESP Max Distance']=10;heartbeat:Fire(.1);assert(layer.destroyed)
V['ESP Max Distance']=100;V['ESP Visibility Check']=false;heartbeat:Fire(.1);layer=find('AngelHubPlayerESP')
AngelHub.setters['Player ESP'](false);assert(layer.destroyed)
-- Universal team filtering, team colors, offscreen and missing camera/character cleanup.
isMM2=false;local team={TeamColor={Color=color('green')}};localPlayer.Team=team;other.Team=team;localPlayer.Neutral=false;other.Neutral=false
AngelHub.setters['Player ESP'](true);heartbeat:Fire(.1);assert(layer.destroyed)
V['ESP Team Check']=false;V['ESP Team Colours']=true;heartbeat:Fire(.1);layer=find('AngelHubPlayerESP');edge=find('Edge1');assert(not layer.destroyed and edge.BackgroundColor3.name=='green')
function camera:WorldToViewportPoint()return {X=2000,Y=300,Z=5}end
heartbeat:Fire(.1);assert(layer.destroyed)
screenGui.Destroying:Fire()
