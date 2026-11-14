game.PlaceId=142823291
services.Players=playersService
local oldtype=typeof
function typeof(v)
 if type(v)=='table' and v.__type then return v.__type end
 if getmetatable(v)==vec then return 'Vector3' end
 return oldtype(v)
end
Vector3.zero=Vector3.new(0,0,0)
vec.__unm=function(a)return Vector3.new(-a.X,-a.Y,-a.Z)end
vec.__div=function(a,n)return Vector3.new(a.X/n,a.Y/n,a.Z/n)end
vec.__mul=function(a,b)if type(a)=='number'then return Vector3.new(a*b.X,a*b.Y,a*b.Z)end;return Vector3.new(a.X*b,a.Y*b,a.Z*b)end
function vec:Dot(b)return self.X*b.X+self.Y*b.Y+self.Z*b.Z end
function vec:Cross(b)return Vector3.new(self.Y*b.Z-self.Z*b.Y,self.Z*b.X-self.X*b.Z,self.X*b.Y-self.Y*b.X)end
function vec:Lerp(b,t)return self+(b-self)*t end
CFrame.new=function(x,y,z) local p=type(x)=='table' and x or Vector3.new(x or 0,y or 0,z or 0);return {Position=p,__type='CFrame'}end
CFrame.lookAt=function(a,b)return {Position=a,Target=b,__type='CFrame'}end
Enum.HumanoidStateType={Dead='Dead',Physics='Physics'}
Enum.Material.Neon='neon';Enum.UserInputType.MouseButton2={Name='MouseButton2'}
UDim={new=function(a,b)return{a,b}end}
UDim2.new=function(...)return {...}end
Color3={fromRGB=function(...)return {...}end};BrickColor={new=function(n)return n end}
userInputService.TouchEnabled=mobile;userInputService.KeyboardEnabled=not mobile
function userInputService:GetFocusedTextBox()return self.focused end
local oldNew=Instance.new
Instance.new=function(class)local item=oldNew(class);if class=='TextButton'then item.Activated=event()end;return item end
local function create(class,properties,parent)
 local obj=Instance.new(class);for k,v in pairs(properties)do obj[k]=v end;obj.Parent=parent;return obj
end
local function connectInput(signal,callback)local c=signal:Connect(callback);table.insert(AngelHub.connections,c);return c end
AngelHub.connections={}
local function setting(n,v)V[n]=v;AngelHub.setters[n]=function(x)V[n]=x end end
setting('Gun Aimbot',false);setting('Aim Method','Normal');setting('Aimbot Target','Murder');setting('Target Player','')
setting('WallCheck',true);setting('Macro',false);setting('Aimbot Keybind Value','Q')
setting('Gun Aura',false);setting('Gun Aura Studs',50);setting('Gun Aura Show Hitbox',false)
setting('Auto Shoot',false);setting('Shoot Mode','Normal');setting('Shoot WallCheck',true);setting('Shoot Proximity',false);setting('Shoot Proximity Aura',30)
setting('Knife Aura',false);setting('Knife Aura Range',15);setting('Knife Hold Mouse',false)
setting('Knife Throw',false);setting('Auto Knife Throw',false);setting('Throw WallCheck',true);setting('Throw Delay',1);setting('Knife Tracer',false)
localPlayer.Name='Me';localPlayer.UserId=1;other.UserId=2
localPlayer.ChildAdded=event();localPlayer.CharacterAdded=event();character.ChildAdded=event()
local backpack={ChildAdded=event()};local tools={}
function backpack:FindFirstChild(n)return tools[n]end
function localPlayer:FindFirstChildOfClass(n)if n=='Backpack'then return backpack end end
local oldFind=character.FindFirstChild
function character:FindFirstChild(n)if n=='Gun'then return tools.equipped end;return oldFind(self,n)end
function humanoid:EquipTool(t)tools.Gun=nil;tools.equipped=t;t.Parent=character end
function humanoid:GetState()return {Name='Running'}end
function humanoid:GetAttribute()return nil end
function character:GetAttribute()return nil end
humanoid.Parent=character
local targetRoot={Position=Vector3.new(20,0,0),AssemblyLinearVelocity=Vector3.new(10,0,0)}
function targetRoot:IsA(c)return c=='BasePart'end
local knife={Name='Knife'};function knife:IsA(c)return c=='Tool'end
local enemyHumanoid={Health=100,MoveDirection=Vector3.new(1,0,0)}
function enemyHumanoid:GetState()return {Name='Running'}end
function enemyHumanoid:GetAttribute()return nil end
local enemy={Parent=workspace}
function enemy:GetAttribute()return nil end
function enemy:FindFirstChildOfClass(n)if n=='Humanoid'then return enemyHumanoid end end
function enemy:FindFirstChild(n)if n=='HumanoidRootPart'then return targetRoot elseif n=='Knife'then return self.knife end end
enemyHumanoid.Parent=enemy;enemy.knife=knife;other.Character=enemy
function other:FindFirstChildOfClass()return nil end
local remote={shots={},Name="Shoot",__type="Instance"};function remote:IsA(c)return c=='RemoteEvent'end
function remote:FireServer(a,b)table.insert(self.shots,{a,b})end
local gunTool={Name='Gun',Parent=character,Enabled=true,__type='Instance'}
function gunTool:IsA(c)return c=='Tool'end
function gunTool:FindFirstChild(n)if n=='Shoot'then return remote end end
function gunTool:GetAttribute(n)return self[n]end
local attachment={WorldCFrame=CFrame.new(Vector3.new(2,1,0))}
function attachment:IsA(n)return n=='Attachment'end
function root:FindFirstChild(n)if n=='GunRaycastAttachment'then return attachment end end
workspace.rayMode='clear';function workspace:Raycast(o,d,p)if self.rayMode=='wall'then return {Instance=wall}end end
function gun:FindFirstAncestorOfClass()return nil end
gun.CFrame=CFrame.new(gun.Position);gun.CanCollide=true
local key={UserInputType=Enum.UserInputType.Keyboard,KeyCode={Name='Q'}}
local pendingTasks={};task.spawn=function(f)table.insert(pendingTasks,f)end
task.delay=function(_,f)table.insert(pendingTasks,f)end
local function drain()
 local count=0
 while #pendingTasks>0 do count+=1;assert(count<50);local f=table.remove(pendingTasks,1);f() end
end
