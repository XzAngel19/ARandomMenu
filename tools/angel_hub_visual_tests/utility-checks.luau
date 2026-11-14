for _,n in ipairs({'Noclip','Custom Jump Power','Fullbright','Time Changer','Fast Time','Custom FOV','Custom Zoom','Anti AFK','Infinite Jump'})do setting(n,false)end
V['Jump Power']=75;V['Fullbright Brightness']=1.5;V['Time Value']=7;V['FOV Value']=90
V['Zoom Max Distance']=400;V['Zoom Min Distance']=1;V['Unlock Forced First Person']=true
character.Parent=workspace;root.Parent=character;head.Parent=character
function root:IsDescendantOf(x)return self.Parent==x end
function head:IsDescendantOf(x)return self.Parent==x end
humanoid.Health=100;humanoid.JumpPower=50;humanoid.UseJumpPower=false
localPlayer.CameraMinZoomDistance=.5;localPlayer.CameraMaxZoomDistance=128;localPlayer.CameraMode='lock'
camera.FieldOfView=70
installBasicUtilities(screenGui);heartbeat:Fire(.1)
assert(root.CanCollide and humanoid.JumpPower==50 and lighting.Brightness==2 and camera.FieldOfView==70)
AngelHub.setters['Noclip'](true);heartbeat:Fire(.1);assert(not root.CanCollide and not head.CanCollide)
local outsider={CanCollide=true};assert(outsider.CanCollide)
AngelHub.setters['Noclip'](false);assert(root.CanCollide and head.CanCollide)
AngelHub.setters['Custom Jump Power'](true);AngelHub.setters['Fullbright'](true)
AngelHub.setters['Time Changer'](true);AngelHub.setters['Custom FOV'](true);AngelHub.setters['Custom Zoom'](true)
heartbeat:Fire(.1)
assert(humanoid.JumpPower==75 and humanoid.UseJumpPower and lighting.Brightness==1.5 and lighting.ClockTime==7)
assert(camera.FieldOfView==90 and localPlayer.CameraMaxZoomDistance==400 and localPlayer.CameraMinZoomDistance==1)
humanoid.JumpPower=42;lighting.Brightness=4;camera.FieldOfView=80;heartbeat:Fire(.1)
AngelHub.setters['Custom Jump Power'](false);AngelHub.setters['Fullbright'](false);AngelHub.setters['Custom FOV'](false)
assert(humanoid.JumpPower==42 and not humanoid.UseJumpPower and lighting.Brightness==4 and camera.FieldOfView==80)
AngelHub.setters['Time Changer'](false);AngelHub.setters['Custom Zoom'](false)
assert(lighting.ClockTime==12 and localPlayer.CameraMaxZoomDistance==128 and localPlayer.CameraMode=='lock')
V['Infinite Jump Mode']='Normal';V['Infinite Jump Power']=75;V['Infinite Jump Interval']=.1
AngelHub.setters['Infinite Jump'](true);humanoid.FloorMaterial=Enum.Material.Air
root.AssemblyLinearVelocity=Vector3.new(2,0,3);uis.JumpRequest:Fire();assert(root.AssemblyLinearVelocity.Y==75)
root.AssemblyLinearVelocity=Vector3.new(2,0,3);uis.JumpRequest:Fire();assert(root.AssemblyLinearVelocity.Y==0)
fakeNow+=.2;uis.JumpRequest:Fire();assert(root.AssemblyLinearVelocity.Y==75)
V['Infinite Jump Mode']='Rise';local key={KeyCode=Enum.KeyCode.Space,UserInputType=Enum.UserInputType.Keyboard}
uis.InputBegan:Fire(key,false);root.AssemblyLinearVelocity=Vector3.zero;heartbeat:Fire(.1);assert(root.AssemblyLinearVelocity.Y==75)
uis.InputEnded:Fire(key);root.AssemblyLinearVelocity=Vector3.zero;heartbeat:Fire(.1);assert(root.AssemblyLinearVelocity.Y==0)
local touch={UserInputType=Enum.UserInputType.Touch,Position={X=120,Y=120}}
uis.InputBegan:Fire(touch,true);heartbeat:Fire(.1);assert(root.AssemblyLinearVelocity.Y==75)
uis.WindowFocusReleased:Fire();root.AssemblyLinearVelocity=Vector3.zero;heartbeat:Fire(.1);assert(root.AssemblyLinearVelocity.Y==0)
AngelHub.setters['Infinite Jump'](false)
AngelHub.setters['Noclip'](true);heartbeat:Fire(.1)
local newRoot={CanCollide=true};function newRoot:IsA(n)return n=='BasePart'end
local newChar={Parent=workspace};newRoot.Parent=newChar
function newRoot:IsDescendantOf(x)return self.Parent==x end
function newChar:GetDescendants()return {newRoot}end
function newChar:FindFirstChildOfClass()return humanoid end
localPlayer.Character=newChar;heartbeat:Fire(.1);assert(root.CanCollide and not newRoot.CanCollide)
V['Anti AFK']=true;localPlayer.Idled:Fire();assert(fakeUser.count==1)
V['Anti AFK']=false;localPlayer.Idled:Fire();assert(fakeUser.count==1)
AngelHub.setters['Custom FOV'](true);heartbeat:Fire(.1);screenGui.Destroying:Fire()
assert(newRoot.CanCollide and camera.FieldOfView==80)
