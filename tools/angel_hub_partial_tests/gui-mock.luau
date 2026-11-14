local function event()
 local e={callbacks={}}
 function e:Connect(fn)local c={fn=fn,alive=true};function c:Disconnect()self.alive=false end;table.insert(self.callbacks,c);return c end
 function e:Fire(...)for _,c in ipairs(self.callbacks)do if c.alive then c.fn(...)end end end
 function e:Wait()end
 return e
end
local enums={}
Enum=setmetatable({},{__index=function(_,cat)
 if not enums[cat] then enums[cat]=setmetatable({GetEnumItems=function()return {}end},{__index=function(t,k)local v={Name=k};rawset(t,k,v);return v end})end
 return enums[cat]
end})
local vec={};vec.__index=function(a,k)if k=='Magnitude'then return math.sqrt(a.X*a.X+a.Y*a.Y+(a.Z or 0)^2)end return vec[k]end
vec.__sub=function(a,b)return setmetatable({X=a.X-b.X,Y=a.Y-b.Y,Z=(a.Z or 0)-(b.Z or 0)},vec)end
Vector2={new=function(x,y)return setmetatable({X=x,Y=y},vec)end}
Vector3={new=function(x,y,z)return setmetatable({X=x,Y=y,Z=z},vec)end}
UDim={new=function(a,b)return{Scale=a,Offset=b}end}
UDim2={new=function(xs,xo,ys,yo)return{X={Scale=xs,Offset=xo},Y={Scale=ys,Offset=yo}}end,fromOffset=function(x,y)return UDim2.new(0,x,0,y)end,fromScale=function(x,y)return UDim2.new(x,0,y,0)end}
Color3={new=function(r,g,b)return{R=r,G=g,B=b}end,fromRGB=function(r,g,b)return{R=r/255,G=g/255,B=b/255}end}
ColorSequence={new=function(...)return {...}end};NumberSequence={new=function(...)return {...}end};TweenInfo={new=function(...)return {...}end}
local methods={};local mt={}
local events={InputBegan=true,InputChanged=true,InputEnded=true,MouseButton1Click=true,Activated=true,MouseEnter=true,MouseLeave=true,MouseButton1Down=true,MouseButton1Up=true,FocusLost=true,Focused=true,Destroying=true}
function mt:__index(k)if methods[k]then return methods[k]end;if self._props[k]~=nil then return self._props[k]end;if events[k]then local e=event();self._props[k]=e;return e end;return nil end
function mt:__newindex(k,v)if k=='Parent' and v then table.insert(v._children,self)end;self._props[k]=v;if self._changes[k]then self._changes[k]:Fire()end end
function methods:GetPropertyChangedSignal(k)if not self._changes[k]then self._changes[k]=event()end;return self._changes[k]end
function methods:FindFirstChild(n)for _,x in ipairs(self._children)do if x.Name==n then return x end end end
function methods:FindFirstChildOfClass(n)for _,x in ipairs(self._children)do if x._class==n then return x end end end
function methods:WaitForChild(n)return self:FindFirstChild(n)end
function methods:GetChildren()return self._children end
function methods:GetDescendants()return self._children end
function methods:SetAttribute(k,v)self._attrs[k]=v end
function methods:GetAttribute(k)return self._attrs[k]end
function methods:IsA(n)return self._class==n end
function methods:Destroy()if self._props.Destroying then self.Destroying:Fire()end;self.Parent=nil end
Instance={new=function(c)return setmetatable({_class=c,_children={},_props={AbsoluteSize=Vector2.new(400,400),AbsolutePosition=Vector2.new(0,0)},_attrs={},_changes={}},mt)end}
local gui=Instance.new('PlayerGui');gui.Name='PlayerGui'
local player=Instance.new('Player');gui.Parent=player;player.Character=nil;player.Idled=event()
local players={LocalPlayer=player}
local uis={TouchEnabled=false,KeyboardEnabled=true,InputBegan=event(),InputChanged=event(),InputEnded=event(),JumpRequest=event(),WindowFocusReleased=event(),TextBoxFocused=event()}
function uis:GetFocusedTextBox()return nil end
local tw={};function tw:Create(object,info,goal)local t={Completed=event()};function t:Play()for k,v in goal do object[k]=v end end;return t end
local lighting={Brightness=2,ClockTime=12};local run={Heartbeat=event()}
workspace=Instance.new('Workspace');workspace.Gravity=196.2;workspace.DescendantAdded=event()
local services={Players=players,UserInputService=uis,TweenService=tw,HttpService={},TeleportService={},RunService=run,Lighting=lighting}
game={PlaceId=142823291,JobId='test'};function game:GetService(n)assert(services[n],n);return services[n]end
shared={};task={spawn=function()end,wait=function()end,delay=function()end};warn=function(...)end
