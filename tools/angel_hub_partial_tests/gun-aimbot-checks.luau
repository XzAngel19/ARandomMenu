AngelHub.moduleNames['Gun Aimbot']=true;setting('Gun Aimbot',false)
setting('Aim Method','Normal');setting('Aimbot Target','Murder');setting('Target Player','')
setting('Aimbot WallCheck',true);setting('Aimbot Keybind Value','Q');setting('Aimbot Macro',false)
CFrame.new=function(v)return {Position=v,__cframe=true}end
CFrame.lookAt=function(a,b)return {Position=a,Target=b,__cframe=true}end
local key={UserInputType=Enum.UserInputType.Keyboard,KeyCode={Name='Q'}}
local inputOrigin=CFrame.new(Vector3.new(2,1,0));local inputEnd=CFrame.new(Vector3.new(5,0,0))
tools.equipped=gunTool;gunTool.Parent=character
installGameplay(screenGui)
-- The optional keyboard action works while the switch is off.
userInputService.InputBegan:Fire(key,false);drain();assert(#remote.shots==1)
assert(remote.shots[1][1].Position==attachment.WorldCFrame.Position)
assert(math.abs(remote.shots[1][2].Position.X-20.8)<.0001)
userInputService.InputBegan:Fire(key,true);drain();assert(#remote.shots==1)
AngelHub.listening=function()end;userInputService.InputBegan:Fire(key,false);drain();assert(#remote.shots==1);AngelHub.listening=nil
function userInputService:GetFocusedTextBox()return {}end;userInputService.InputBegan:Fire(key,false);drain();assert(#remote.shots==1)
function userInputService:GetFocusedTextBox()return nil end
-- Activation installs one hook and never automatically shoots.
AngelHub.setters['Gun Aimbot'](true);heartbeat:Fire(.1);assert(V['Gun Aimbot'] and currentHook~=original and #remote.shots==1)
local result=currentHook(remote,inputOrigin,inputEnd,'extra');assert(result=='sent' and #calls==1)
assert(calls[1].remote==remote and calls[1].args.n==3 and calls[1].args[3]=='extra')
assert(calls[1].args[1].Position==inputOrigin.Position and math.abs(calls[1].args[2].Position.X-20.8)<.0001)
assert(workspace.CurrentCamera==camera and camera.CFrame.LookVector.Z==-1)
-- No target, blocked path, unrelated calls and executor-originated requests pass through exactly once.
workspace.rayMode='wall';currentHook(remote,inputOrigin,inputEnd);assert(calls[2].args[1]==inputOrigin and calls[2].args[2]==inputEnd)
workspace.rayMode='clear';executorCaller=true;currentHook(remote,inputOrigin,inputEnd);executorCaller=false;assert(calls[3].args[1]==inputOrigin)
currentHook({},inputOrigin,inputEnd);assert(calls[4].args[1]==inputOrigin)
method='InvokeServer';currentHook(remote,inputOrigin,inputEnd);method='FireServer';assert(calls[5].args[1]==inputOrigin)
currentHook(remote,'bad',inputEnd);assert(calls[6].args[1]=='bad')
V['Aimbot Target']='Custom';V['Target Player']='nobody';currentHook(remote,inputOrigin,inputEnd);assert(calls[7].args[1]==inputOrigin)
V['Target Player']='Alice';V['Aim Method']='Silent AIM';V['Aimbot WallCheck']=false;workspace.rayMode='wall'
currentHook(remote,inputOrigin,inputEnd);assert(math.abs(calls[8].args[1].Position.X-18.5)<.0001 and math.abs(calls[8].args[2].Position.X-22.3)<.0001)
AngelHub.setters['Gun Aimbot'](false);assert(currentHook==original and not V['Gun Aimbot'])
-- The action still works after disabling and respects the separate wall check.
fakeNow+=1;userInputService.InputBegan:Fire(key,false);drain();assert(#remote.shots==2)
V['Aimbot WallCheck']=true;fakeNow+=1;userInputService.InputBegan:Fire(key,false);drain();assert(#remote.shots==2)
-- Another script's hook is not overwritten by cleanup; ours becomes inert.
workspace.rayMode='clear';AngelHub.setters['Gun Aimbot'](true)
local prior=currentHook;local third=function(...)return prior(...)end;currentHook=third
AngelHub.setters['Gun Aimbot'](false);assert(currentHook==third)
currentHook(remote,inputOrigin,inputEnd);assert(calls[#calls].args[1]==inputOrigin)
AngelHub.setters['Gun Aimbot'](true)
fakeNow+=1;local before=#remote.shots;userInputService.InputBegan:Fire(key,false)
screenGui.Destroying:Fire();drain();assert(#remote.shots==before and currentHook==third)
currentHook(remote,inputOrigin,inputEnd);assert(calls[#calls].args[1]==inputOrigin)
