AngelHub.moduleNames['Nametags']=true;V['Nametags']=false;AngelHub.setters['Nametags']=function(v)V['Nametags']=v end
for n,v in pairs({['Display Name']=true,['Account Name']=true,['Nametag Distance']=true,['Show Role']=true,['Held Tool']=true,
 ['Nametag Background']=true,['Nametag Text Size']=16,['Nametag Max Distance']=100,['Nametag Through Walls']=true,
 ['Nametag Colour']='white',['Role Colours']=true,['Murderer Colour']='red',['Murderer ESP']=true,['Dead ESP']=false})do V[n]=v end
Color3={fromRGB=function(...)return {...}end}
localPlayer.Name='Me';localPlayer.UserId=1;other.UserId=2
local human={Health=100};local part={Position=Vector3.new(20,0,0)};function part:IsA(c)return c=='BasePart'end
local tool={Name='Knife'};local enemy={Parent=workspace}
function enemy:IsDescendantOf(w)return self.Parent==w end
function enemy:FindFirstChildOfClass(n)if n=='Humanoid'then return human elseif n=='Tool'then return tool end end
function enemy:FindFirstChild(n)if n=='Head' or n=='HumanoidRootPart'then return part end end
other.Character=enemy
local data={Alice={Name='Alice',Role='Murderer'}}
local remote={};function remote:IsA(c)return c=='RemoteFunction'end;function remote:InvokeServer()return data end
local gameplay={};function gameplay:FindFirstChild(n)if n=='GetCurrentPlayerData'then return remote end end
local remotes={};function remotes:FindFirstChild(n)if n=='Gameplay'then return gameplay end end
local storage={};function storage:FindFirstChild(n)if n=='Remotes'then return remotes end end
services.ReplicatedStorage=storage
installGameplay(screenGui);AngelHub.setters['Nametags'](true);heartbeat:Fire(.21);heartbeat:Fire(.21)
local label=created[#created];local billboard=created[#created-1]
assert(label.class=='TextLabel' and billboard.class=='BillboardGui' and billboard.Adornee==part and billboard.AlwaysOnTop)
assert(label.Text=='Ally @Alice [Murderer] 20 studs [Knife]' and label.TextColor3=='red' and label.TextSize==16 and label.BackgroundTransparency==.4)
V['Nametag Max Distance']=10;heartbeat:Fire(.21);assert(billboard.destroyed)
V['Nametag Max Distance']=100;V['Role Colours']=false;V['Nametag Background']=false;heartbeat:Fire(.21)
label=created[#created];billboard=created[#created-1];assert(label.TextColor3=='white' and label.BackgroundTransparency==1)
AngelHub.setters['Nametags'](false);assert(billboard.destroyed)
-- Universal team filter and character removal.
isMM2=false;local team={};localPlayer.Team=team;other.Team=team;localPlayer.Neutral=false;other.Neutral=false
V['Nametag Teammates']=false;AngelHub.setters['Nametags'](true);heartbeat:Fire(.21);assert(billboard.destroyed)
V['Nametag Teammates']=true;heartbeat:Fire(.21);billboard=created[#created-1];assert(not billboard.destroyed)
other.Character.Parent=nil;heartbeat:Fire(.21);assert(billboard.destroyed)
screenGui.Destroying:Fire()
