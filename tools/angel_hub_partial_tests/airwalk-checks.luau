AngelHub.moduleNames['Air Walk']=true;V['Air Walk']=false;AngelHub.setters['Air Walk']=function(v)V['Air Walk']=v end
Enum.KeyCode.LeftControl='leftctrl';Enum.KeyCode.RightControl='rightctrl'
CFrame.new=function(x,y,z)if y then return {Position=Vector3.new(x,y,z)}end;return {Position=x}end
local originalNew=Instance.new
Instance.new=function(class)
 local object=originalNew(class)
 if class=='TextButton'then object.InputBegan=event();object.InputEnded=event()end
 return object
end
Color3={new=function(...)return {...}end,fromRGB=function(...)return {...}end}
UDim2.new=function(...)return {...}end
local space={UserInputType='keyboard',KeyCode='space'}
local down={UserInputType='keyboard',KeyCode='leftctrl'}
installGameplay(screenGui);heartbeat:Fire(.1);assert(#created==0)
AngelHub.setters['Air Walk'](true);heartbeat:Fire(.1)
local platform=created[#created];assert(platform.Name=='AngelHubAirWalkPlatform' and platform.Parent==workspace and platform.CanCollide)
userInputService.InputBegan:Fire(space,false);heartbeat:Fire(.1);assert(root.AssemblyLinearVelocity.Y==22)
userInputService.InputEnded:Fire(space);root.AssemblyLinearVelocity=Vector3.new(0,0,0)
userInputService.InputBegan:Fire(down,false);heartbeat:Fire(.1);assert(root.AssemblyLinearVelocity.Y==-22)
userInputService.WindowFocusReleased:Fire();root.AssemblyLinearVelocity=Vector3.new(0,0,0);heartbeat:Fire(.1);assert(root.AssemblyLinearVelocity.Y==0)
assert(AngelHub.setters['Noclip'](true)==false and not V['Noclip'])
humanoid.SeatPart={};heartbeat:Fire(.1);assert(platform.destroyed);humanoid.SeatPart=nil
heartbeat:Fire(.1);platform=created[#created];assert(not platform.destroyed)
AngelHub.setters['Air Walk'](false);assert(platform.destroyed)
-- Mobile buttons track individual input and release on focus loss.
userInputService.TouchEnabled=true;AngelHub.setters['Air Walk'](true)
local upButton, downButton
for _,item in ipairs(created)do if item.class=='TextButton' and item.Name=='Up'then upButton=item elseif item.class=='TextButton' and item.Name=='Down'then downButton=item end end
assert(upButton and downButton)
local touch={UserInputType='touch'};root.AssemblyLinearVelocity=Vector3.new(0,0,0)
downButton.InputBegan:Fire(touch);heartbeat:Fire(.1);assert(root.AssemblyLinearVelocity.Y==-22)
userInputService.InputEnded:Fire(touch);root.AssemblyLinearVelocity=Vector3.new(0,0,0);heartbeat:Fire(.1);assert(root.AssemblyLinearVelocity.Y==0)
platform=created[#created];screenGui.Destroying:Fire();assert(platform.destroyed)
for _,c in ipairs(downButton.InputBegan.callbacks)do assert(not c.alive)end
