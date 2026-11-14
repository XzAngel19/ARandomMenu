AngelHub.moduleNames['Gun Aimbot']=true;setting('Gun Aimbot',false)
setting('Aim Method','Normal');setting('Aimbot Target','Murder');setting('Target Player','')
setting('Normal WallCheck',true);setting('Aimbot Keybind Value','Q');setting('Aimbot Macro',false)
userInputService.TouchEnabled=mobile;userInputService.KeyboardEnabled=not mobile
local oldNew=Instance.new
Instance.new=function(class)
 local x=oldNew(class)
 if class=='TextButton'then x.Activated=event()end
 return x
end
local key={UserInputType=Enum.UserInputType.Keyboard,KeyCode={Name='Q'}}
tools.equipped=gunTool;gunTool.Parent=character
installGameplay(screenGui)
assert(AngelHub.actions['Fire Gun'] and not V['Gun Aimbot'])
-- The action works regardless of the switch; Normal uses the gun origin and checks walls.
AngelHub.actions['Fire Gun']();drain();assert(#remote.shots==1)
assert(remote.shots[1][1].Position==attachment.WorldCFrame.Position)
assert(math.abs(remote.shots[1][2].Position.X-20.8)<.0001)
fakeNow+=1;workspace.rayMode='wall';AngelHub.actions['Fire Gun']();drain();assert(#remote.shots==1)
-- Silent uses CFrame near the target even behind walls, not Normal's WallCheck.
V['Aim Method']='Silent AIM';fakeNow+=1;AngelHub.actions['Fire Gun']();drain();assert(#remote.shots==2)
assert(math.abs(remote.shots[2][1].Position.X-18.5)<.0001 and math.abs(remote.shots[2][2].Position.X-22.3)<.0001)
assert(workspace.CurrentCamera==camera and camera.CFrame.LookVector.Z==-1)
-- Custom must resolve unambiguously and be a detected Murderer.
V['Aimbot Target']='Custom';V['Target Player']='nobody';fakeNow+=1;AngelHub.actions['Fire Gun']();drain();assert(#remote.shots==2)
V['Target Player']='Alice';fakeNow+=1;AngelHub.actions['Fire Gun']();drain();assert(#remote.shots==3)
-- Module ON does not shoot by itself and needs no executor hook.
AngelHub.setters['Gun Aimbot'](true);heartbeat:Fire(.1);assert(V['Gun Aimbot'] and #remote.shots==3)
local button
for _,object in ipairs(created)do if object.Name=='AngelHubGunFire'then button=object end end
if mobile then
 assert(button and button.Parent==screenGui);fakeNow+=1;button.Activated:Fire();drain();assert(#remote.shots==4)
else
 assert(not button);fakeNow+=1;userInputService.InputBegan:Fire(key,false);drain();assert(#remote.shots==4)
 userInputService.InputBegan:Fire(key,true);drain();assert(#remote.shots==4)
 AngelHub.listening=function()end;userInputService.InputBegan:Fire(key,false);drain();assert(#remote.shots==4);AngelHub.listening=nil
 function userInputService:GetFocusedTextBox()return {}end;userInputService.InputBegan:Fire(key,false);drain();assert(#remote.shots==4)
 function userInputService:GetFocusedTextBox()return nil end
end
if mobile then fakeNow+=1;button.Activated:Fire() end
AngelHub.setters['Gun Aimbot'](false);assert(not V['Gun Aimbot'])
if mobile then assert(button.destroyed);button.Activated:Fire();drain();assert(#remote.shots==4)end
-- Reloading and uncertain dispatch never cause repeated attempts.
gunTool.Reloading=true;fakeNow+=1;AngelHub.actions['Fire Gun']();drain();assert(#remote.shots==4)
gunTool.Reloading=false;remote.fail=true;fakeNow+=1;AngelHub.actions['Fire Gun']();drain();assert(#remote.shots==5)
AngelHub.actions['Fire Gun']();drain();assert(#remote.shots==5);remote.fail=false
-- Pending input is cancelled by unload.
fakeNow+=1;AngelHub.actions['Fire Gun']();screenGui.Destroying:Fire();drain();assert(#remote.shots==5)
