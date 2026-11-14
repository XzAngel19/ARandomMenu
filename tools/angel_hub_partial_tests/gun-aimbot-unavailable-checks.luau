AngelHub.moduleNames['Gun Aimbot']=true;setting('Gun Aimbot',false)
setting('Aim Method','Normal');setting('Aimbot Target','Murder');setting('Target Player','')
setting('Aimbot WallCheck',false);setting('Aimbot Keybind Value','Q')
CFrame.new=function(v)return {Position=v}end
CFrame.lookAt=function(a,b)return {Position=a,Target=b}end
tools.equipped=gunTool;gunTool.Parent=character
userInputService.TouchEnabled=mobile;userInputService.KeyboardEnabled=not mobile
installGameplay(screenGui)
assert(AngelHub.setters['Gun Aimbot'](true)==false and not V['Gun Aimbot'])
userInputService.InputBegan:Fire({UserInputType=Enum.UserInputType.Keyboard,KeyCode={Name='Q'}},false);drain()
assert(#remote.shots==(mobile and 0 or 1))
screenGui.Destroying:Fire()
