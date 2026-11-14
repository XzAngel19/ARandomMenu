local function setting(n,v)V[n]=v;AngelHub.setters[n]=function(x)V[n]=x end end
setting('Anti Fling',false);setting('Player Shield',true);setting('Impact Shield',true);setting('Walk Fling',false)
character.Parent=workspace;root.Parent=character;head.Parent=character
local function body(part,parent)
 part.Parent=parent;part.CanCollide=true;part.Anchored=false;part.Size=Vector3.new(2,2,2)
 part.AssemblyLinearVelocity=Vector3.zero;part.AssemblyAngularVelocity=Vector3.zero
 function part:IsA(c)return c=='BasePart'end
 function part:FindFirstAncestorOfClass()return nil end
 function part:IsDescendantOf(owner)local p=self.Parent;while p do if p==owner then return true end;p=p.Parent end;return false end
 return part
end
body(root,character);body(head,character)
function character:GetDescendants()return {root,head}end
local enemy={Parent=workspace};local eroot=body({Position=Vector3.new(10,0,0)},enemy)
function enemy:GetDescendants()return {eroot}end;function enemy:FindFirstChild(n)if n=='HumanoidRootPart'then return eroot end end
other.Character=enemy
local floor=body({Position=Vector3.new(0,-3,0)},workspace)
local debris=body({Position=Vector3.new(2,0,0)},workspace);debris.AssemblyLinearVelocity=Vector3.new(100,0,0)
OverlapParams={new=function()return {}end}
function workspace:GetPartBoundsInRadius()return {floor,debris,eroot}end
function workspace:Raycast()return {Instance=floor}end
local function live(part)local n=0;for _,i in ipairs(created)do if i.class=='NoCollisionConstraint' and not i.destroyed and i.Part1==part then n+=1 end end;return n end
installAntiFlingFeatures(screenGui);heartbeat:Fire(.1);assert(live(eroot)==0)
AngelHub.setters['Anti Fling'](true);heartbeat:Fire(.1);assert(live(eroot)==2 and live(debris)==2 and live(floor)==0)
AngelHub.mm2FlingBusy=true;heartbeat:Fire(.1);assert(live(eroot)==0 and live(debris)==0)
AngelHub.mm2FlingBusy=false;fakeNow+=.2;heartbeat:Fire(.1);assert(live(eroot)==2 and live(debris)==2)
function workspace:Raycast()error('unavailable')end
fakeNow+=.2;heartbeat:Fire(.1);assert(live(debris)==0 and live(eroot)==2)
AngelHub.setters['Anti Fling'](false);assert(live(eroot)==0)
AngelHub.setters['Anti Fling'](true);fakeNow+=.2;heartbeat:Fire(.1);assert(live(eroot)==2)
screenGui.Destroying:Fire();assert(live(eroot)==0 and root.CanCollide and debris.CanCollide)
