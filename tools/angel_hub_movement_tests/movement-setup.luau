localPlayer.Name='Me';localPlayer.UserId=1
local os={clock=function()return fakeNow end}
local uis=userInputService
uis.TouchEnabled=mobile;uis.KeyboardEnabled=not mobile
uis.focused=nil;function uis:GetFocusedTextBox()return self.focused end
local oldNew=Instance.new
Instance.new=function(class)
 local obj=oldNew(class);obj.InputBegan=event();obj.InputEnded=event()
 return obj
end
local function create(class,properties,parent)
 local obj=Instance.new(class);for k,v in pairs(properties)do obj[k]=v end;obj.Parent=parent;return obj
end
local function connectInput(signal,callback)local c=signal:Connect(callback);table.insert(AngelHub.connections,c);return c end
AngelHub.connections={}
local function setting(n,v)V[n]=v;AngelHub.setters[n]=function(x)V[n]=x end end
setting('Enable Fly',false);setting('Fly Method','Velocity');setting('Fly Float','Velocity')
setting('Fly Horizontal Speed',173);setting('Fly Vertical Speed',60);setting('Fly Response Multiplier',1)
setting('Fly Burst Interval',0);setting('Fly Wall Check',true);setting('Fly Face Camera',false)
setting('Fly Up Key Value','Space');setting('Fly Down Key Value','LeftControl')
setting('Enable Speed',false);setting('Speed Mode','Velocity');setting('Speed Value',54)
setting('Speed Response',1);setting('Speed Braking',.2);setting('Speed Keep Vertical',true)
setting('Speed Wall Check',true);setting('Speed Burst Delay',0);setting('Speed Auto Jump',false);setting('Sprint Key Value','LeftShift')
setting('Enable Gravity',false);setting('Gravity Method','Workspace');setting('Gravity Value',workspace.Gravity)
Vector3.zero=Vector3.new(0,0,0)
vec.__div=function(a,n)return Vector3.new(a.X/n,a.Y/n,a.Z/n)end
function vec:Dot(b)return self.X*b.X+self.Y*b.Y+self.Z*b.Z end
function vec:Lerp(b,t)return self+(b-self)*t end
UDim={new=function(a,b)return {a,b}end}
UDim2.new=function(...)return {...}end
Color3={fromRGB=function(...)return {...}end}
Enum.ActuatorRelativeTo={World='World'}
root.AssemblyMass=5;root.Anchored=false;humanoid.Sit=false;humanoid.HipHeight=2
local cf={};cf.__add=function(c,v)return setmetatable({Position=c.Position+v},cf)end
CFrame.new=function(p)return setmetatable({Position=p},cf)end
root.CFrame=CFrame.new(root.Position)
local shift={UserInputType=Enum.UserInputType.Keyboard,KeyCode={Name='LeftShift'}}
local space={UserInputType=Enum.UserInputType.Keyboard,KeyCode={Name='Space'}}
