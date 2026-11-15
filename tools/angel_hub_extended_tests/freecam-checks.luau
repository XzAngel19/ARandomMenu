AngelHub.moduleNames['FreeCam']=true;V['FreeCam']=false;AngelHub.setters['FreeCam']=function(v)V['FreeCam']=v end
V['FreeCam Speed']=50;V['FreeCam Sensitivity']=.2
local keys={};for _,name in ipairs({'W','Up','S','Down','A','Left','D','Right','E','Space','Q','LeftControl'})do keys[name]={Name=name}end
Enum.KeyCode=keys;Enum.ContextActionPriority={High={Value=3000}};Enum.ContextActionResult={Pass='pass',Sink='sink'}
Enum.UserInputState={Begin='begin',Change='change',End='end',Cancel='cancel'}
Enum.UserInputType.MouseButton2='mouse2';Enum.UserInputType.MouseMovement='mousemove'
Enum.CameraType={Scriptable='scriptable',Custom='custom'};Enum.MouseBehavior={LockCurrentPosition='locked',Default='normal'}
Enum.RenderPriority={Camera={Value=200}}
local camMeta={};camMeta.__index=camMeta
function camMeta:VectorToWorldSpace(v)return v end
camMeta.__mul=function(a,b)return setmetatable({Position=a.Position+b.Position,LookVector=b.Position.Magnitude==0 and b.LookVector or a.LookVector},camMeta)end
local function cf(pos,look)return setmetatable({Position=pos,LookVector=look or Vector3.new(0,0,-1)},camMeta)end
CFrame={new=function(a,b,c)if type(a)=='number'then return cf(Vector3.new(a,b,c))end;return cf(a)end,
 fromOrientation=function(p,y)return cf(Vector3.new(0,0,0),Vector3.new(-math.sin(y),math.sin(p),-math.cos(y)))end,
 lookAt=function(pos,target)return cf(pos,(target-pos).Unit)end}
local v2={};v2.__index=function(a,k)if k=='Magnitude'then return math.sqrt(a.X*a.X+a.Y*a.Y)elseif k=='Unit'then local d=math.sqrt(a.X*a.X+a.Y*a.Y);return setmetatable({X=a.X/d,Y=a.Y/d},v2)end return v2[k]end
v2.__add=function(a,b)return setmetatable({X=a.X+b.X,Y=a.Y+b.Y},v2)end
v2.__sub=function(a,b)return setmetatable({X=a.X-b.X,Y=a.Y-b.Y},v2)end
v2.__mul=function(a,b)return setmetatable({X=a.X*b,Y=a.Y*b},v2)end
v2.__div=function(a,b)return setmetatable({X=a.X/b,Y=a.Y/b},v2)end
Vector2.new=function(x,y)return setmetatable({X=x,Y=y},v2)end
UDim2.new=function(...)return {...}end
Color3={new=function(...)return {...}end,fromRGB=function(...)return {...}end}
local baseNew=Instance.new
Instance.new=function(class)local obj=baseNew(class);if class=='TextButton'then obj.InputBegan=event();obj.InputEnded=event();obj.Activated=event();obj.AbsolutePosition=Vector2.new(0,0);obj.AbsoluteSize=Vector2.new(104,104)end;return obj end
local actions={};function actions:BindActionAtPriority(name,fn)self.id=name;self.callback=fn end;function actions:UnbindAction(name)if name==self.id then self.callback=nil;self.unbound=true end end
services.ContextActionService=actions
function run:BindToRenderStep(name,priority,fn)self.renderName=name;self.renderCallback=fn end
function run:UnbindFromRenderStep(name)if self.renderName==name then self.renderCallback=nil end end
local function render(dt)assert(run.renderCallback);run.renderCallback(dt)end
userInputService.InputChanged=event();userInputService.TouchStarted=event();userInputService.TouchMoved=event();userInputService.TouchEnded=event()
userInputService.TouchEnabled=mobile;userInputService.MouseBehavior='normal';userInputService.MouseIconEnabled=true
local focused=false;function userInputService:GetFocusedTextBox()return focused and {} or nil end
local controls={controlsEnabled=true,disabled=0,enabled=0}
function controls:Disable()self.disabled+=1;self.controlsEnabled=false end
function controls:Enable()self.enabled+=1;self.controlsEnabled=true end
local module={data={GetControls=function()return controls end}};local scripts={};function scripts:FindFirstChild(n)if n=='PlayerModule'then return module end end
function localPlayer:FindFirstChild(n)if n=='PlayerScripts'then return scripts end end
local touchGui={Enabled=true};function playerGui:FindFirstChild(n)if n=='TouchGui'then return touchGui end end
camera.CameraType='custom';camera.CFrame=cf(Vector3.new(0,3,0));camera.Focus=cf(Vector3.new(0,3,-16));camera.ViewportSize=Vector2.new(800,600)
local initialFrame,initialFocus=camera.CFrame,camera.Focus
installGameplay(screenGui);heartbeat:Fire(.1);assert(camera.CameraType=='custom' and not actions.callback)
AngelHub.setters['FreeCam'](true);assert(V['FreeCam'] and actions.callback and controls.disabled==1)
assert(AngelHub.setters['Enable Speed'](true)==false and AngelHub.setters['Infinite Jump'](true)==false)
render(.1);assert(camera.CameraType=='scriptable')
local keyboard={KeyCode=keys.W};actions.callback('',Enum.UserInputState.Begin,keyboard);render(.1);assert(camera.CFrame.Position.Z==-5)
actions.callback('',Enum.UserInputState.End,keyboard);render(.1);assert(camera.CFrame.Position.Z==-5)
focused=true;assert(actions.callback('',Enum.UserInputState.Begin,keyboard)=='pass');render(.1);assert(camera.CFrame.Position.Z==-5);focused=false
if mobile then
 assert(touchGui.Enabled==false)
 local pad,up,exit
 for _,obj in ipairs(created)do if obj.Name=='Move'then pad=obj elseif obj.Name=='Up'then up=obj elseif obj.Name=='Exit'then exit=obj end end
 assert(pad and up and exit)
 local look={UserInputType='touch',Position=Vector2.new(600,300),Delta=Vector2.new(20,5)}
 local prevLook=camera.CFrame.LookVector.X;userInputService.TouchStarted:Fire(look,false);userInputService.TouchMoved:Fire(look);render(.1)
 assert(math.abs(camera.CFrame.LookVector.X-prevLook)>.001);userInputService.TouchEnded:Fire(look)
 local finger={UserInputType='touch',Position=Vector2.new(94,52),Delta=Vector2.new(0,0)}
 pad.InputBegan:Fire(finger);local x=camera.CFrame.Position.X;render(.1);assert(camera.CFrame.Position.X>x)
 userInputService.TouchEnded:Fire(finger);local beforeY=camera.CFrame.Position.Y
 local touch={UserInputType='touch'};up.InputBegan:Fire(touch);render(.1);assert(camera.CFrame.Position.Y>beforeY);up.InputEnded:Fire(touch)
 exit.Activated:Fire();assert(not V['FreeCam'] and touchGui.Enabled==true)
else
 local mouse={UserInputType='mouse2'};userInputService.InputBegan:Fire(mouse,false)
 assert(userInputService.MouseBehavior=='locked' and not userInputService.MouseIconEnabled)
 local prevLook=camera.CFrame.LookVector.X
 userInputService.InputChanged:Fire({UserInputType='mousemove',Delta=Vector2.new(15,5)});render(.1);assert(math.abs(camera.CFrame.LookVector.X-prevLook)>.001)
 userInputService.InputEnded:Fire(mouse);assert(userInputService.MouseBehavior=='normal' and userInputService.MouseIconEnabled)
 AngelHub.setters['FreeCam'](false)
end
assert(not run.renderCallback and not actions.callback and camera.CameraType=='custom' and camera.CFrame==initialFrame and camera.Focus==initialFocus and controls.enabled==1)
-- Control ownership: previously disabled controls remain disabled after FreeCam.
controls.controlsEnabled=false;AngelHub.setters['FreeCam'](true);render(.1);AngelHub.setters['FreeCam'](false)
assert(not controls.controlsEnabled and controls.enabled==1);controls.controlsEnabled=true
AngelHub.setters['FreeCam'](true);render(.1)
local oldCamera=camera
local replacement={CameraType='custom',CFrame=cf(Vector3.new(100,3,0)),Focus=cf(Vector3.new(100,3,-16)),ViewportSize=Vector2.new(800,600)}
local replacementFrame=replacement.CFrame;workspace.CurrentCamera=replacement;render(.1)
assert(oldCamera.CameraType=='custom' and oldCamera.CFrame==initialFrame and replacement.CameraType=='scriptable')
screenGui.Destroying:Fire()
assert(not run.renderCallback and not actions.callback and replacement.CameraType=='custom' and replacement.CFrame==replacementFrame and controls.enabled==2)
