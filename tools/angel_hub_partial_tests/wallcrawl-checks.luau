AngelHub.moduleNames['Wall Crawl State']=true;V['Wall Crawl State']=false;AngelHub.setters['Wall Crawl State']=function(v)V['Wall Crawl State']=v end
for n,v in pairs({['Wall Crawl Mode']='Velocity',['Wall Crawl Speed']=16,['Wall Crawl Impulse Interval']=.1})do V[n]=v;AngelHub.setters[n]=function(x)V[n]=x end end
Enum.HumanoidStateType={Climbing='climb',Freefall='fall',Running='run'}
function vec:Dot(b)return self.X*b.X+self.Y*b.Y+self.Z*b.Z end
character.Parent=workspace;humanoid.Parent=character;humanoid.HipHeight=2;humanoid.state='run'
function humanoid:GetState()return self.state end;function humanoid:ChangeState(s)self.state=s end
root.CollisionGroup='Default';root.AssemblyMass=2
function root:ApplyImpulse(v)self.lastImpulse=v;self.impulses=(self.impulses or 0)+1 end
local cf={};setmetatable(cf,{__add=function(_,v)return {rise=v.Y}end});root.CFrame=cf
local wallHit={Normal=Vector3.new(-1,0,0)};local ceiling
function workspace:Raycast(origin,direction,params)if direction.Y>0 then return ceiling end;return wallHit end
installGameplay(screenGui);heartbeat:Fire(.05);assert(humanoid.state=='run')
AngelHub.setters['Wall Crawl State'](true);heartbeat:Fire(.05);assert(root.AssemblyLinearVelocity.Y==16 and humanoid.state=='climb')
wallHit=nil;heartbeat:Fire(.05);assert(humanoid.state=='fall')
wallHit={Normal=Vector3.new(0,1,0)};heartbeat:Fire(.05);assert(humanoid.state=='fall')
wallHit={Normal=Vector3.new(1,0,0)};heartbeat:Fire(.05);assert(humanoid.state=='fall')
wallHit={Normal=Vector3.new(-1,0,0)};V['Wall Crawl Mode']='Impulse';root.AssemblyLinearVelocity=Vector3.new(0,0,0)
heartbeat:Fire(.05);assert(root.impulses==1 and root.lastImpulse.Y==32)
heartbeat:Fire(.05);assert(root.impulses==1);heartbeat:Fire(.05);assert(root.impulses==2)
V['Wall Crawl Mode']='CFrame';root.CFrame=cf;ceiling={Distance=3.2};heartbeat:Fire(.1)
assert(math.abs(root.CFrame.rise-.2)<.001 and root.AssemblyLinearVelocity.Y==0)
humanoid.MoveDirection=Vector3.new(0,0,0);heartbeat:Fire(.05);assert(humanoid.state=='fall')
assert(AngelHub.setters['Auto Farm'](true)==false);assert(AngelHub.setters['Air Walk']==nil or AngelHub.setters['Air Walk'](true)==false)
AngelHub.setters['Wall Crawl State'](false);assert(humanoid.state=='fall')
humanoid.MoveDirection=Vector3.new(1,0,0);V['Wall Crawl Mode']='Velocity';AngelHub.setters['Wall Crawl State'](true);heartbeat:Fire(.1);assert(humanoid.state=='climb')
screenGui.Destroying:Fire();assert(humanoid.state=='fall')
