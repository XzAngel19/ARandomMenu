AngelHub.moduleNames['Gun Aimbot']=true;setting('Gun Aimbot',false)
setting('Aim Method','Normal');setting('Aimbot Target','Murder');setting('Target Player','')
setting('WallCheck',true);setting('Aimbot Keybind Value','Q');setting('Macro',false)
userInputService.TouchEnabled=mobile;userInputService.KeyboardEnabled=not mobile
local oldNew=Instance.new
Instance.new=function(class)local x=oldNew(class);if class=='TextButton'then x.Activated=event()end;return x end
local key={UserInputType=Enum.UserInputType.Keyboard,KeyCode={Name='Q'}}
tools.equipped=gunTool;gunTool.Parent=character
installGameplay(screenGui)
assert(not AngelHub.actions['Fire Gun'] and not V['Gun Aimbot'])
AngelHub.setters['Gun Aimbot'](true);heartbeat:Fire(.1);assert(V['Gun Aimbot'] and #remote.shots==0)
local button;for _,object in ipairs(created)do if object.Name=='AngelHubGunFire'then button=object end end
if mobile then assert(button and button.Parent==screenGui)else assert(not button)end
local function fire()
 if mobile then button.Activated:Fire() else userInputService.InputBegan:Fire(key,false)end
 drain()
end
-- Normal uses the gun origin and checks walls.
fire();assert(#remote.shots==1 and remote.shots[1][1].Position==attachment.WorldCFrame.Position)
assert(math.abs(remote.shots[1][2].Position.X-20.8)<.0001)
fakeNow+=1;workspace.rayMode='wall';fire();assert(#remote.shots==1)
-- Instakill uses the Through CFrame approximation even behind walls.
V['Aim Method']='Instakill';fakeNow+=1;fire();assert(#remote.shots==2)
assert(math.abs(remote.shots[2][1].Position.X-19)<.0001 and math.abs(remote.shots[2][2].Position.X-21.8)<.0001)
assert(workspace.CurrentCamera==camera and camera.CFrame.LookVector.Z==-1)
V['Aimbot Target']='Custom';V['Target Player']='nobody';fakeNow+=1;fire();assert(#remote.shots==2)
V['Target Player']='Alice';fakeNow+=1;fire();assert(#remote.shots==3)
if not mobile then
 userInputService.InputBegan:Fire(key,true);drain();assert(#remote.shots==3)
 AngelHub.listening=function()end;userInputService.InputBegan:Fire(key,false);drain();assert(#remote.shots==3);AngelHub.listening=nil
 function userInputService:GetFocusedTextBox()return {}end;userInputService.InputBegan:Fire(key,false);drain();assert(#remote.shots==3)
 function userInputService:GetFocusedTextBox()return nil end
end
-- Reload and send errors never trigger an extra request.
gunTool.Reloading=true;fakeNow+=1;fire();assert(#remote.shots==3)
gunTool.Reloading=false;remote.fail=true;fakeNow+=1;fire();assert(#remote.shots==4)
fire();assert(#remote.shots==4);remote.fail=false
-- Macro unequips after a successful manual request and is optional.
V['Macro']=true;fakeNow+=1;fire();assert(#remote.shots==5 and gunTool.Parent==backpack)
V['Macro']=false;tools.equipped=gunTool;gunTool.Parent=character
if mobile then fakeNow+=1;button.Activated:Fire()end
AngelHub.setters['Gun Aimbot'](false);assert(not V['Gun Aimbot'])
if mobile then assert(button.destroyed);button.Activated:Fire();drain();assert(#remote.shots==5)
else fakeNow+=1;userInputService.InputBegan:Fire(key,false);drain();assert(#remote.shots==6)end
screenGui.Destroying:Fire()
