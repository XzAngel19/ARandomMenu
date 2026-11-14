AngelHub.moduleNames['Enable Fly']=true
for n,v in pairs({['Enable Fly']=false,['Fly Method']='Velocity',['Fly Float']='Velocity',['Fly Horizontal Speed']=60,
 ['Fly Vertical Speed']=40,['Fly Response Multiplier']=1,['Fly Wall Check']=true,['Fly Face Camera']=false,
 ['Fly Up Key Value']='Space',['Fly Down Key Value']='LeftControl'})do V[n]=v;AngelHub.setters[n]=function(x)V[n]=x end end
local baseNew=Instance.new
Instance.new=function(class)local obj=baseNew(class);if class=='TextButton'then obj.InputBegan=event();obj.InputEnded=event()end;return obj end
Color3={new=function(...)return {...}end,fromRGB=function(...)return {...}end};UDim2.new=function(...)return {...}end
character.Parent=workspace
local up={UserInputType='keyboard',KeyCode={Name='Space'}}
local down={UserInputType='keyboard',KeyCode={Name='LeftControl'}}
installGameplay(screenGui);heartbeat:Fire(.1);assert(root.AssemblyLinearVelocity.X==0)
AngelHub.setters['Enable Fly'](true);assert(root.AssemblyLinearVelocity.X==0)
heartbeat:Fire(.1);assert(root.AssemblyLinearVelocity.X==60 and root.AssemblyLinearVelocity.Y==0)
AngelHub.listening=function()end;userInputService.InputBegan:Fire(up,false);heartbeat:Fire(.1);assert(root.AssemblyLinearVelocity.Y==0);AngelHub.listening=nil
userInputService.InputBegan:Fire(up,false);heartbeat:Fire(.1);assert(root.AssemblyLinearVelocity.Y==40)
userInputService.InputEnded:Fire(up);userInputService.InputBegan:Fire(down,false);heartbeat:Fire(.1);assert(root.AssemblyLinearVelocity.Y==-40)
userInputService.TextBoxFocused:Fire();heartbeat:Fire(.1);assert(root.AssemblyLinearVelocity.Y==0)
workspace.hitWall=true;heartbeat:Fire(.1);assert(root.AssemblyLinearVelocity.Magnitude==0)
workspace.hitWall=false;V['Fly Horizontal Speed']=-20;heartbeat:Fire(.1);assert(root.AssemblyLinearVelocity.X==-20)
assert(AngelHub.setters['Enable Speed'](true)==false and not V['Enable Speed'])
AngelHub.setters['Enable Fly'](false);assert(root.AssemblyLinearVelocity.Magnitude==0)
AngelHub.setters['Fly Method']('CFrame');assert(AngelHub.setters['Enable Fly'](true)==false)
AngelHub.setters['Fly Method']('Velocity');AngelHub.setters['Enable Fly'](true);heartbeat:Fire(.1)
AngelHub.setters['Fly Float']('Hover');assert(not V['Enable Fly'])
AngelHub.setters['Fly Float']('Velocity');V['Fly Horizontal Speed']=60;userInputService.TouchEnabled=true
AngelHub.setters['Enable Fly'](true);local upButton
for _,item in ipairs(created)do if item.class=='TextButton' and item.Name=='Up'then upButton=item end end
assert(upButton);local touch={UserInputType='touch'};upButton.InputBegan:Fire(touch);heartbeat:Fire(.1);assert(root.AssemblyLinearVelocity.Y==40)
userInputService.InputEnded:Fire(touch);heartbeat:Fire(.1);assert(root.AssemblyLinearVelocity.Y==0)
humanoid.SeatPart={};heartbeat:Fire(.1);assert(root.AssemblyLinearVelocity.Magnitude==0);humanoid.SeatPart=nil
heartbeat:Fire(.1);root.AssemblyLinearVelocity=Vector3.new(123,8,0);AngelHub.setters['Enable Fly'](false)
assert(root.AssemblyLinearVelocity.X==123 and root.AssemblyLinearVelocity.Y==8)
screenGui.Destroying:Fire();for _,c in ipairs(upButton.InputBegan.callbacks)do assert(not c.alive)end
