local function event()
 local e={callbacks={}}
 function e:Connect(fn) local c={fn=fn,alive=true};function c:Disconnect()self.alive=false end;table.insert(self.callbacks,c);return c end
 function e:Fire(...) for _,c in ipairs(self.callbacks) do if c.alive then c.fn(...) end end end
 return e
end
local vec={};vec.__index=function(a,k) if k=='Magnitude' then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) elseif k=='Unit' then local n=math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z);return setmetatable({X=a.X/n,Y=a.Y/n,Z=a.Z/n},vec) end return vec[k] end
vec.__mul=function(a,n)return setmetatable({X=a.X*n,Y=a.Y*n,Z=a.Z*n},vec)end
Vector3={new=function(x,y,z)return setmetatable({X=x,Y=y,Z=z},vec)end}
Enum={Material={Air='air',Ground='ground'},CameraMode={Classic='classic'},KeyCode={Space='space',ButtonA='buttona'},UserInputType={Touch='touch',Keyboard='keyboard'},RaycastFilterType={Exclude='exclude'}}
RaycastParams={new=function()return {}end}
Vector2={new=function(x,y)return {X=x,Y=y}end}
local humanoid={Health=100,WalkSpeed=16,UseJumpPower=false,JumpPower=50,FloorMaterial='air',MoveDirection=Vector3.new(1,0,0)}
local root={CanCollide=true,AssemblyLinearVelocity=Vector3.new(0,0,0),Position=Vector3.new(0,0,0),Size=Vector3.new(2,2,2),CFrame={}};function root:IsA(c)return c=='BasePart'end
local head={CanCollide=true};function head:IsA(c)return c=='BasePart'end
local character={parts={root,head}}
function character:FindFirstChildOfClass(name) if name=='Humanoid' then return humanoid end end
function character:FindFirstChild(name) if name=='HumanoidRootPart' then return root end end
function character:GetDescendants() return self.parts end
local isMM2=true
local localPlayer={Idled=event(),Character=character,CameraMinZoomDistance=0.5,CameraMaxZoomDistance=128,CameraMode='lock'}
local jumpButton={Visible=true,AbsolutePosition={X=100,Y=100},AbsoluteSize={X=50,Y=50}}
local touchGui={}; function touchGui:FindFirstChild(n)if n=='JumpButton'then return jumpButton end end
local playerGui={}; function playerGui:FindFirstChild(n)if n=='TouchGui'then return touchGui end end
function localPlayer:FindFirstChildOfClass(n)if n=='PlayerGui'then return playerGui end end
local lighting={Brightness=2,ClockTime=12}
local camera={FieldOfView=70,CFrame={LookVector=Vector3.new(0,0,-1)}}
local prompt={HoldDuration=2,MaxActivationDistance=10}
function prompt:IsA(c)return c=='ProximityPrompt' end
local detector={MaxActivationDistance=15}
function detector:IsA(c)return c=='ClickDetector' end
workspace={Gravity=196.2,CurrentCamera=camera,DescendantAdded=event(),objects={prompt,detector}}
local wall={Name='Wall',Parent=workspace,Anchored=true,CanCollide=true,Transparency=0,LocalTransparencyModifier=0,Size=Vector3.new(2,10,10),Position=Vector3.new(0,0,0)}
function wall:IsA(c)return c=='BasePart'end
function wall:IsDescendantOf(w)return self.Parent==w end
table.insert(workspace.objects,wall)
function workspace:GetDescendants()return self.objects end
local gun={Name='GunDrop',Parent=workspace}
function gun:IsA(c)return c=='BasePart'end
function gun:IsDescendantOf(w)return self.Parent==w end
function workspace:FindFirstChild(n)if n=='GunDrop' then return gun end end
local touches={};firetouchinterest=function(a,b,phase)table.insert(touches,{a,b,phase})end
workspace.hitWall=false;workspace.castCount=0
function workspace:Blockcast()self.castCount+=1;if self.hitWall then return {} end end
task={spawn=function(f) f() end,wait=function()end}
local heartbeat=event();local run={Heartbeat=heartbeat}
local userInputService={JumpRequest=event(), InputBegan=event(), InputEnded=event(), WindowFocusReleased=event(), TextBoxFocused=event()}
function userInputService:GetFocusedTextBox()return nil end
local fakeUser={count=0}
function fakeUser:CaptureController()end
function fakeUser:Button2Down() self.count+=1 end
function fakeUser:Button2Up() end
local services={RunService=run,Lighting=lighting,VirtualUser=fakeUser}
game={};function game:GetService(n)return services[n] end
local screenGui={Destroying=event()}
local AngelHub={values={},setters={},moduleNames={},reports={}}
AngelHub.notify=function(msg) table.insert(AngelHub.reports,msg)end
warn=function(...) end
for _,n in ipairs({'Noclip','Enable Gravity','Enable Speed','Custom Jump Power','Infinite Jump','Fullbright','Time Changer','Fast Time','Custom FOV','Custom Zoom','Instant Prompts','Proximity Prompts','Click Detectors','X-Ray','Anti AFK','Auto Farm'}) do
 AngelHub.moduleNames[n]=true;AngelHub.values[n]=false;AngelHub.setters[n]=function(value) AngelHub.values[n]=value end
end
local V=AngelHub.values
for n,v in pairs({['Gravity Value']=100,['Speed Mode']='WalkSpeed',['Speed Response']=1,['Speed Braking']=0.2,['Speed Keep Vertical']=true,['Speed Wall Check']=false,['Speed Value']=48,['Jump Power']=100,['Infinite Jump Mode']='Normal',['Infinite Jump Interval']=0,['Infinite Jump Power']=75,['Fullbright Brightness']=1.5,['Time Value']=4,['FOV Value']=90,['Zoom Max Distance']=400,['Zoom Min Distance']=5,['Unlock Forced First Person']=false,['High Jump Velocity']=100,['Long Jump Speed']=80,['Long Jump Mode']='Velocity',['Get Gun Key Value']='G',['XRay Scope']='All Map',['XRay Part Names']='',['XRay Keep Visible']='',['XRay Keep Floors']=false,['XRay Collidable Only']=false,['XRay Include Unanchored']=false,['XRay Limit Range']=false,['XRay Range']=500,['XRay Transparency']=0.5,['Interaction Distance']=30,['Zoom Through Walls']=false,['Speed Auto Jump']=false,['Jump Auto Jump']=false}) do V[n]=v;AngelHub.setters[n]=function(value)V[n]=value end end
