local function event()
 local e={callbacks={}}
 function e:Connect(fn) local c={fn=fn,alive=true};function c:Disconnect()self.alive=false end;table.insert(self.callbacks,c);return c end
 function e:Fire(...) for _,c in ipairs(self.callbacks) do if c.alive then c.fn(...) end end end
 return e
end
local vec={};vec.__index=function(a,k) if k=='Magnitude' then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) elseif k=='Unit' then local n=math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z);return setmetatable({X=a.X/n,Y=a.Y/n,Z=a.Z/n},vec) end return vec[k] end
vec.__mul=function(a,n)return setmetatable({X=a.X*n,Y=a.Y*n,Z=a.Z*n},vec)end
Vector3={new=function(x,y,z)return setmetatable({X=x,Y=y,Z=z},vec)end}
Enum={Material={Air='air',Ground='ground'},CameraMode={Classic='classic'}}
local humanoid={Health=100,WalkSpeed=16,UseJumpPower=false,JumpPower=50,FloorMaterial='air',MoveDirection=Vector3.new(1,0,0)}
local root={CanCollide=true,AssemblyLinearVelocity=Vector3.new(0,0,0)};function root:IsA(c)return c=='BasePart'end
local head={CanCollide=true};function head:IsA(c)return c=='BasePart'end
local character={parts={root,head}}
function character:FindFirstChildOfClass(name) if name=='Humanoid' then return humanoid end end
function character:FindFirstChild(name) if name=='HumanoidRootPart' then return root end end
function character:GetDescendants() return self.parts end
local localPlayer={Character=character,CameraMinZoomDistance=0.5,CameraMaxZoomDistance=128,CameraMode='lock'}
local lighting={Brightness=2,ClockTime=12}
local camera={FieldOfView=70,CFrame={LookVector=Vector3.new(0,0,-1)}}
local prompt={HoldDuration=2,MaxActivationDistance=10}
function prompt:IsA(c)return c=='ProximityPrompt' end
local detector={MaxActivationDistance=15}
function detector:IsA(c)return c=='ClickDetector' end
workspace={Gravity=196.2,CurrentCamera=camera,DescendantAdded=event(),objects={prompt,detector}}
function workspace:GetDescendants()return self.objects end
task={spawn=function(f) f() end,wait=function()end}
local heartbeat=event();local run={Heartbeat=heartbeat}
local userInputService={JumpRequest=event()}
local services={RunService=run,Lighting=lighting}
game={};function game:GetService(n)return services[n] end
local screenGui={Destroying=event()}
local AngelHub={values={},setters={},moduleNames={},reports={}}
AngelHub.notify=function(msg) table.insert(AngelHub.reports,msg)end
warn=function(...) end
for _,n in ipairs({'Noclip','Enable Gravity','Enable Speed','Custom Jump Power','Infinite Jump','Fullbright','Time Changer','Fast Time','Custom FOV','Custom Zoom','Instant Prompts','Proximity Prompts','Click Detectors','Auto Farm'}) do
 AngelHub.moduleNames[n]=true;AngelHub.values[n]=false;AngelHub.setters[n]=function(value) AngelHub.values[n]=value end
end
local V=AngelHub.values
for n,v in pairs({['Gravity Value']=100,['Speed Mode']='WalkSpeed',['Speed Value']=48,['Jump Power']=100,['Infinite Jump Mode']='Normal',['Infinite Jump Interval']=0,['Infinite Jump Power']=75,['Fullbright Brightness']=1.5,['Time Value']=4,['FOV Value']=90,['Zoom Max Distance']=400,['Zoom Min Distance']=5,['Unlock Forced First Person']=false,['High Jump Velocity']=100,['Long Jump Speed']=80,['Long Jump Mode']='Velocity',['Interaction Distance']=30,['Zoom Through Walls']=false,['Speed Auto Jump']=false,['Jump Auto Jump']=false}) do V[n]=v;AngelHub.setters[n]=function(value)V[n]=value end end
