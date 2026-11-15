local cm={};cm.__index=cm
function cm:Lerp(other,t)return setmetatable({R=self.R+(other.R-self.R)*t,G=self.G+(other.G-self.G)*t,B=self.B+(other.B-self.B)*t},cm)end
Color3={fromRGB=function(r,g,b)return setmetatable({R=r/255,G=g/255,B=b/255},cm)end}
Enum.HumanoidRigType={R6='R6',R15='R15'};Enum.Font={SourceSansBold='bold'}
root.Position=Vector3.zero;root.Size=Vector3.new(2,2,1);root.Parent=character;character.Parent=workspace
humanoid.MaxHealth=100;humanoid.Health=80
local enemy={}
other.Name='Alice';other.DisplayName='Alice Display';other.Character=enemy
local eroot={Position=Vector3.new(10,0,0),Size=Vector3.new(2,2,1),Parent=enemy}
function eroot:IsA(c)return c=='BasePart'end
local eh={Health=50,MaxHealth=100,HipHeight=2,RigType='R15'}
enemy.Parent=workspace
function enemy:FindFirstChild(n)if n=='HumanoidRootPart'then return eroot end end
function enemy:FindFirstChildOfClass(n)if n=='Humanoid'then return eh end end
local cam={ViewportSize=Vector2.new(800,600),CFrame={Position=Vector3.zero}}
function cam:WorldToViewportPoint(v)return {X=400+v.X*10,Y=300-v.Y*10,Z=10}end
workspace.CurrentCamera=cam
workspace.blocked=false
function workspace:Raycast()if self.blocked then return {Instance=wall}end end
wall.Transparency=0;wall.CanCollide=true;function wall:IsDescendantOf()return false end
run.RenderStepped=event();playersService.PlayerRemoving=event()
local names={'Player ESP','Nametags','HP Players','Self HP','Chams'}
for _,name in ipairs(names)do setting(name,false) end
V['ESP Boxes']='Corner';V['Box Thickness']=1;V['ESP Max Distance']=1;V['Nametag Max Distance']=1
V['Display Name']=true;V['Nametag Distance']=true;V['Nametag Through Walls']=false;V['Show Role']=true
V['HP Max Distance']=1;V['HP Through Walls']=true;V['HP Health Text']=true;V['Role Colours']=true
V['Murderer Colour']=Color3.fromRGB(255,70,70);V['Murderer ESP']=true;V['Self HP Scale']=1
local queries=0;AngelHub.getMM2Role=function(p)assert(p==other);queries+=1;return 'Murderer'end
local roleRefreshes=0;AngelHub.refreshMM2Roles=function()roleRefreshes+=1 end
installPlayerVisuals(screenGui);installChams(screenGui)
local function find(name,last)
 local found;for _,v in ipairs(created)do if v.Name==name and not v.destroyed then found=v;if not last then return v end end end;return found
end
run.RenderStepped:Fire(.1);assert(not find('PlayerVisual'))
AngelHub.setters['Player ESP'](true);AngelHub.setters['Nametags'](true);AngelHub.setters['HP Players'](true)
AngelHub.setters['Self HP'](true);run.RenderStepped:Fire(.1)
local container=find('PlayerVisual');local name=find('Name');local detail=find('Details');local bar=find('HPBar');local number=find('HPText')
assert(container and container.Visible and name.Visible and name.Text=='Alice Display')
assert(detail.Visible and detail.Text:find('Murderer') and detail.Text:find('studs'))
assert(find('Box1').Visible and find('BoxOutline1').Visible and not find('Box5').destroyed)
assert(bar.Visible and number.Visible and number.Text=='50' and find('AngelSelfHP').Text=='80')
assert(roleRefreshes>=3 and queries==1)
-- Spectator camera near the victim while the player's body is over 5000 studs away.
root.Position=Vector3.new(9000,0,0);cam.CFrame.Position=Vector3.new(9,0,0)
run.RenderStepped:Fire(.1);assert(container.Visible and name.Visible and bar.Visible)
assert(detail.Text:find('1 studs'))
-- Legacy distance settings must not filter even when the camera is far away.
cam.CFrame.Position=Vector3.new(-9000,0,0);run.RenderStepped:Fire(.1)
assert(container.Visible and name.Visible and bar.Visible)
cam.CFrame.Position=Vector3.zero;root.Position=Vector3.zero

-- Shared role filter, wall checks and role colours apply equally in MM2.
V['Murderer ESP']=false;run.RenderStepped:Fire(.1);assert(not container.Visible)
V['Murderer ESP']=true;workspace.blocked=true;fakeNow+=1;run.RenderStepped:Fire(.1)
assert(container.Visible and not name.Visible and bar.Visible)
V['Nametag Through Walls']=true;run.RenderStepped:Fire(.1);assert(name.Visible)
V['ESP Boxes']='Full';run.RenderStepped:Fire(.1);assert(find('Box4').Visible and not find('Box5').Visible)
V['ESP Boxes']='Off';run.RenderStepped:Fire(.1);assert(not find('Box1').Visible)
AngelHub.setters['Nametags'](false);assert(not name.Visible)
AngelHub.setters['HP Players'](false);assert(not bar.Visible)
AngelHub.setters['Player ESP'](false);assert(container.destroyed)
AngelHub.setters['Self HP'](false);assert(not find('AngelSelfHP').Visible)
AngelHub.setters['Player ESP'](true);run.RenderStepped:Fire(.1);local current=find('PlayerVisual',true);assert(current and current~=container)
AngelHub.setters['Chams'](true);heartbeat:Fire(.2)
local h=find('AngelHubChams');assert(h and h.Adornee==enemy and h.FillColor==V['Murderer Colour'])
V['Murderer ESP']=false;heartbeat:Fire(.2);assert(h.destroyed)
V['Murderer ESP']=true;heartbeat:Fire(.2);h=find('AngelHubChams',true);assert(h and not h.destroyed)
playersService.PlayerRemoving:Fire(other);assert(current.destroyed and h.destroyed)
run.RenderStepped:Fire(.1);local last=find('PlayerVisual',true);heartbeat:Fire(.2);h=find('AngelHubChams',true);screenGui.Destroying:Fire();assert(last.destroyed and h.destroyed)
