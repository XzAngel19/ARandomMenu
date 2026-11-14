AngelHub.moduleNames['HP Players']=true;V['HP Players']=false;AngelHub.setters['HP Players']=function(v)V['HP Players']=v end
V['HP Health Text']=true;V['HP Through Walls']=true;V['HP Max Distance']=100;V['Murderer ESP']=true
Color3={fromRGB=function(...)return {...}end}
local human={Health=75,MaxHealth=100};local part={Position=Vector3.new(20,0,0)};function part:IsA(c)return c=='BasePart'end
local enemy={Parent=workspace};function enemy:IsDescendantOf(w)return self.Parent==w end
function enemy:FindFirstChildOfClass(n)if n=='Humanoid'then return human end end
function enemy:FindFirstChild(n)if n=='Head' or n=='HumanoidRootPart'then return part end end
other.Character=enemy
installGameplay(screenGui);AngelHub.setters['HP Players'](true);heartbeat:Fire(.21)
local label=created[#created];local fill=created[#created-1];local gui=created[#created-3]
assert(gui.class=='BillboardGui' and gui.Adornee==part and gui.AlwaysOnTop)
assert(label.Text=='75 / 100' and label.Visible and fill.Size.X==.75)
human.Health=30;V['HP Health Text']=false;heartbeat:Fire(.21);assert(fill.Size.X==.3 and label.Text=='30 / 100' and not label.Visible)
V['HP Max Distance']=10;heartbeat:Fire(.21);assert(gui.destroyed)
V['HP Max Distance']=100;heartbeat:Fire(.21);gui=created[#created-3];assert(not gui.destroyed)
human.Health=0;heartbeat:Fire(.21);assert(gui.destroyed)
human.Health=30;isMM2=false;local team={};localPlayer.Team=team;other.Team=team;localPlayer.Neutral=false;other.Neutral=false
V['HP Teammates']=false;heartbeat:Fire(.21);assert(gui.destroyed)
V['HP Teammates']=true;heartbeat:Fire(.21);gui=created[#created-3];assert(not gui.destroyed)
AngelHub.setters['HP Players'](false);assert(gui.destroyed)
screenGui.Destroying:Fire()
