AngelHub.moduleNames['Player Pointers']=true;V['Player Pointers']=false;AngelHub.setters['Player Pointers']=function(v)V['Player Pointers']=v end
V['Pointer Max Distance']=100;V['Pointer Distance']=true;V['Pointer Colour']='white';V['Murderer ESP']=true
camera.ViewportSize=Vector2.new(800,600);local depth=5
function camera:WorldToViewportPoint()return {X=900,Y=300,Z=depth}end
local human={Health=100};local part={Position=Vector3.new(20,0,0)};function part:IsA(c)return c=='BasePart'end
local characterOther={Parent=workspace};function characterOther:IsDescendantOf(w)return self.Parent==w end
function characterOther:FindFirstChildOfClass(n)if n=='Humanoid'then return human end end
function characterOther:FindFirstChild(n)if n=='HumanoidRootPart'then return part end end
other.Character=characterOther
installGameplay(screenGui);heartbeat:Fire(.1);assert(#created==0)
AngelHub.setters['Player Pointers'](true);heartbeat:Fire(.1)
local frame=created[#created-2];local arrow=created[#created-1];local label=created[#created]
assert(frame.class=='Frame' and frame.Position.X==764 and frame.Position.Y==300 and arrow.Rotation==90)
assert(arrow.TextColor3=='white' and label.Text=='20 studs' and label.Visible)
depth=-5;V['Pointer Distance']=false;heartbeat:Fire(.1)
assert(frame.Position.X==36 and not label.Visible)
V['Pointer Max Distance']=10;heartbeat:Fire(.1);assert(frame.destroyed)
V['Pointer Max Distance']=100;depth=5;heartbeat:Fire(.1);frame=created[#created-2]
AngelHub.setters['Player Pointers'](false);assert(frame.destroyed)
-- Universal teammate filter and team colors.
isMM2=false;local team={TeamColor={Color='green'}};localPlayer.Team=team;other.Team=team;localPlayer.Neutral=false;other.Neutral=false
V['Pointer Teammates']=false;AngelHub.setters['Player Pointers'](true);heartbeat:Fire(.1);assert(frame.destroyed)
V['Pointer Teammates']=true;V['Pointer Team Colours']=true;heartbeat:Fire(.1);frame=created[#created-2];arrow=created[#created-1]
assert(arrow.TextColor3=='green');characterOther.Parent=nil;heartbeat:Fire(.1);assert(frame.destroyed)
screenGui.Destroying:Fire()
