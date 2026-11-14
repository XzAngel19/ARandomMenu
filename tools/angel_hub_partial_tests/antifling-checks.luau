for _,n in ipairs({'Player Shield','Impact Shield','Walk Fling'})do AngelHub.moduleNames[n]=true;V[n]=false;AngelHub.setters[n]=function(v)V[n]=v end end
run.RenderStepped=event();run.Stepped=event()
character.Parent=workspace;root.Parent=character;head.Parent=character;root.AssemblyAngularVelocity=Vector3.new(0,0,0)
root.Velocity=Vector3.new(0,0,0);function character:GetChildren()return self.parts end
local function body(part,parent)
 part.Parent=parent;part.CanCollide=true;part.Anchored=false;part.Size=Vector3.new(2,2,2)
 part.AssemblyLinearVelocity=Vector3.new(0,0,0);part.AssemblyAngularVelocity=Vector3.new(0,0,0)
 function part:IsA(c)return c=='BasePart'end
 function part:FindFirstAncestorOfClass(c)if c=='Tool'then return self.tool end end
 function part:IsDescendantOf(owner)local p=self.Parent;while p do if p==owner then return true end;p=p.Parent end;return false end
 return part
end
body(root,character);body(head,character)
local enemy={Parent=workspace};local eroot=body({Position=Vector3.new(10,0,0)},enemy);local ehead=body({Position=Vector3.new(10,1,0)},enemy)
function enemy:GetDescendants()return {eroot,ehead}end;function enemy:FindFirstChild(n)if n=='HumanoidRootPart'then return eroot end end
other.Character=enemy
local floor=body({Position=Vector3.new(0,-3,0)},workspace)
local debris=body({Position=Vector3.new(2,0,0)},workspace);debris.AssemblyLinearVelocity=Vector3.new(100,0,0)
local toolpart=body({Position=Vector3.new(2,0,0),tool={}},enemy);toolpart.AssemblyLinearVelocity=Vector3.new(100,0,0)
local anchored=body({Position=Vector3.new(1,0,0)},workspace);anchored.Anchored=true;anchored.AssemblyLinearVelocity=Vector3.new(500,0,0)
floor.AssemblyLinearVelocity=Vector3.new(500,0,0)
OverlapParams={new=function()return {}end};workspace.nearby={floor,debris,toolpart,anchored,eroot}
function workspace:GetPartBoundsInRadius()return self.nearby end
function workspace:Raycast()return {Instance=floor}end
local function live(otherPart)local n=0;for _,i in ipairs(created)do if i.class=='NoCollisionConstraint' and not i.destroyed and i.Part1==otherPart then n+=1 end end;return n end
installGameplay(screenGui);heartbeat:Fire(.2);assert(#created==0)
AngelHub.setters['Player Shield'](true);heartbeat:Fire(.2);assert(live(eroot)==2 and live(ehead)==2 and root.CanCollide and eroot.CanCollide)
AngelHub.setters['Impact Shield'](true);heartbeat:Fire(.2);assert(live(eroot)==2 and live(debris)==2 and live(floor)==0 and live(toolpart)==0 and live(anchored)==0)
-- High local velocity is damped only with an actual nearby extreme mover.
root.AssemblyLinearVelocity=Vector3.new(400,300,0);root.AssemblyAngularVelocity=Vector3.new(0,40,0);heartbeat:Fire(.01)
assert(root.AssemblyLinearVelocity.X==16 and root.AssemblyLinearVelocity.Y==200 and root.AssemblyAngularVelocity.Magnitude==0)
-- Disable Impact Shield removes loose-object constraints without mutating collisions.
AngelHub.setters['Impact Shield'](false);assert(live(debris)==0);heartbeat:Fire(.2);assert(live(eroot)==2)
-- Walk Fling suspends shield so intentional contact is possible.
AngelHub.setters['Walk Fling'](true);assert(live(eroot)==0);heartbeat:Fire(.2);assert(live(eroot)==0)
AngelHub.setters['Walk Fling'](false);heartbeat:Fire(.2);assert(live(eroot)==2)
AngelHub.setters['Player Shield'](false);assert(live(eroot)==0)
-- Impact Shield excludes seats and resumes on unseat, cleans up on unload.
AngelHub.setters['Impact Shield'](true);humanoid.Sit=true;heartbeat:Fire(.2);assert(live(debris)==0)
humanoid.Sit=false;heartbeat:Fire(.2);assert(live(debris)==2)
-- A failed support ray must remove impact links rather than damage a platform.
function workspace:Raycast()error('unavailable')end
heartbeat:Fire(.2);assert(live(debris)==0)
AngelHub.setters['Player Shield'](true);heartbeat:Fire(.2);assert(live(eroot)==2 and live(debris)==0)
screenGui.Destroying:Fire();assert(live(debris)==0 and live(eroot)==0 and root.CanCollide and debris.CanCollide)
