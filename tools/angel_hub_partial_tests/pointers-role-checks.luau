AngelHub.moduleNames['Player Pointers']=true;V['Player Pointers']=false;AngelHub.setters['Player Pointers']=function(v)V['Player Pointers']=v end
V['Pointer Max Distance']=100;V['Pointer Distance']=true;V['Pointer Colour']='white';V['Role Colours']=true
V['Murderer ESP']=true;V['Murderer Colour']='red';V['Sheriff ESP']=false
localPlayer.Name='Me';localPlayer.UserId=1;other.UserId=2
camera.ViewportSize=Vector2.new(800,600);function camera:WorldToViewportPoint()return {X=900,Y=300,Z=5}end
local human={Health=100};local part={Position=Vector3.new(20,0,0)};function part:IsA(c)return c=='BasePart'end
local target={Parent=workspace};function target:IsDescendantOf(w)return self.Parent==w end
function target:FindFirstChildOfClass(n)if n=='Humanoid'then return human end end
function target:FindFirstChild(n)if n=='HumanoidRootPart'then return part end end
other.Character=target
local remote={};function remote:IsA(c)return c=='RemoteFunction'end;function remote:InvokeServer()return {Alice={Name='Alice',Role='Murderer'}}end
local changed={OnClientEvent=event()};function changed:IsA(c)return c=='RemoteEvent'end
local gameplay={};function gameplay:FindFirstChild(n)return ({GetCurrentPlayerData=remote,PlayerDataChanged=changed})[n]end
local remotes={};function remotes:FindFirstChild(n)if n=='Gameplay'then return gameplay end end
local storage={};function storage:FindFirstChild(n)if n=='Remotes'then return remotes end end
services.ReplicatedStorage=storage
installGameplay(screenGui);AngelHub.setters['Player Pointers'](true);heartbeat:Fire(.21)
local frame=created[#created-2];local arrow=created[#created-1];assert(arrow.TextColor3=='red')
changed.OnClientEvent:Fire({Alice={Name='Alice',Role='Sheriff'}});heartbeat:Fire(.21);assert(frame.destroyed)
screenGui.Destroying:Fire()
