AngelHub.moduleNames['FreeCam']=true;V['FreeCam']=false;AngelHub.setters['FreeCam']=function(v)V['FreeCam']=v end
V['FreeCam Speed']=50;V['FreeCam Sensitivity']=.2
Enum.KeyCode={W={},Up={},S={},Down={},A={},Left={},D={},Right={},E={},Space={},Q={},LeftControl={}}
Enum.ContextActionPriority={High={Value=100}};Enum.ContextActionResult={Pass='pass',Sink='sink'}
Enum.UserInputState={Begin='begin',Change='change'};Enum.RenderPriority={Camera={Value=100}}
local actions={};function actions:BindActionAtPriority()end;function actions:UnbindAction()end;services.ContextActionService=actions
function run:BindToRenderStep()end;function run:UnbindFromRenderStep()end
userInputService.InputChanged=event();local queue={};task.spawn=function(f)table.insert(queue,f)end
local control={controlsEnabled=true,enables=0};function control:Disable()self.controlsEnabled=false;coroutine.yield('disable');self.controlsEnabled=false end
function control:Enable()self.controlsEnabled=true;self.enables+=1 end
local module={};local scripts={};function scripts:FindFirstChild(n)if n=='PlayerModule'then return module end end
function localPlayer:FindFirstChild(n)if n=='PlayerScripts'then return scripts end end
controlRequire=function(m)assert(m==module);coroutine.yield('require');return {GetControls=function()return control end}end
installGameplay(screenGui);AngelHub.setters['FreeCam'](true)
local thread
for _,fn in ipairs(queue)do local co=coroutine.create(fn);local ok,result=coroutine.resume(co);assert(ok)
 if result=='require'then thread=co end end
assert(thread);AngelHub.setters['FreeCam'](false);assert(coroutine.resume(thread));assert(control.controlsEnabled and control.enables==0)
queue={};AngelHub.setters['FreeCam'](true);thread=nil
for _,fn in ipairs(queue)do local co=coroutine.create(fn);local ok,result=coroutine.resume(co);assert(ok);if result=='require'then thread=co end end
assert(thread);local ok,result=coroutine.resume(thread);assert(ok and result=='disable' and not control.controlsEnabled)
AngelHub.setters['FreeCam'](false);assert(control.controlsEnabled);assert(coroutine.resume(thread));assert(control.controlsEnabled and control.enables==2)
-- A slow Disable finishing during a new FreeCam session must not lose the original enabled state.
queue={};AngelHub.setters['FreeCam'](true);thread=nil
for _,fn in ipairs(queue)do local co=coroutine.create(fn);local ok,result=coroutine.resume(co);assert(ok);if result=='require'then thread=co end end
assert(thread);local ok,result=coroutine.resume(thread);assert(ok and result=='disable')
AngelHub.setters['FreeCam'](false);queue={};AngelHub.setters['FreeCam'](true)
assert(coroutine.resume(thread));assert(control.controlsEnabled)
local second
for _,fn in ipairs(queue)do local co=coroutine.create(fn);local ok2,result2=coroutine.resume(co);assert(ok2);if result2=='require'then second=co end end
assert(second);local ok2,result2=coroutine.resume(second);assert(ok2 and result2=='disable');assert(coroutine.resume(second))
AngelHub.setters['FreeCam'](false);assert(control.controlsEnabled)
screenGui.Destroying:Fire()
