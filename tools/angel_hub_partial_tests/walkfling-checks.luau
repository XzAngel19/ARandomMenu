AngelHub.moduleNames['Walk Fling']=true;V['Walk Fling']=false;AngelHub.setters['Walk Fling']=function(v)V['Walk Fling']=v end
AngelHub.moduleNames['Enable Fly']=true
for n,v in pairs({['Enable Fly']=false,['Fly Method']='Velocity',['Fly Float']='Velocity',['Fly Horizontal Speed']=60,['Fly Vertical Speed']=40})do V[n]=v;AngelHub.setters[n]=function(x)V[n]=x end end
run.RenderStepped=event();run.Stepped=event();character.Parent=workspace
function character:GetChildren()return self.parts end
root.Velocity=Vector3.new(0,0,0)
installGameplay(screenGui);heartbeat:Fire(.1)
assert(root.CanCollide and head.CanCollide and root.AssemblyLinearVelocity.Magnitude==0)
AngelHub.setters['Walk Fling'](true);assert(root.CanCollide and head.CanCollide)
heartbeat:Fire(.1);assert(not root.CanCollide and not head.CanCollide and root.AssemblyLinearVelocity.Y==30000)
run.RenderStepped:Fire();assert(root.AssemblyLinearVelocity.Magnitude==0)
run.Stepped:Fire();assert(root.AssemblyLinearVelocity.Y==.1)
AngelHub.setters['Walk Fling'](false);assert(root.CanCollide and head.CanCollide and root.AssemblyLinearVelocity.Magnitude==0)
root.AssemblyLinearVelocity=Vector3.new(3,4,5);heartbeat:Fire(.1);assert(root.AssemblyLinearVelocity.Y==4)
AngelHub.setters['Walk Fling'](true);heartbeat:Fire(.1);assert(root.AssemblyLinearVelocity.Y==150000)
assert(AngelHub.setters['Enable Speed'](true)==false and not V['Enable Speed'])
assert(AngelHub.setters['Enable Fly'](true)==false and not V['Enable Fly'])
-- Off in the middle of a spike restores the previous motion and collision.
AngelHub.setters['Walk Fling'](false);assert(root.AssemblyLinearVelocity.X==3 and root.AssemblyLinearVelocity.Y==4 and root.CanCollide)
run.RenderStepped:Fire();run.Stepped:Fire();assert(root.AssemblyLinearVelocity.Y==4)
-- External changes during the pulse are not overwritten on stop.
AngelHub.setters['Walk Fling'](true);heartbeat:Fire(.1);root.AssemblyLinearVelocity=Vector3.new(99,1,0)
AngelHub.setters['Walk Fling'](false);assert(root.AssemblyLinearVelocity.X==99 and root.CanCollide)
-- Fly and Walk Fling cannot take control at the same time.
AngelHub.setters['Enable Fly'](true);assert(AngelHub.setters['Walk Fling'](true)==false);AngelHub.setters['Enable Fly'](false)
-- An active pulse is cleaned up on unload.
AngelHub.setters['Walk Fling'](true);heartbeat:Fire(.1);screenGui.Destroying:Fire()
assert(root.CanCollide and head.CanCollide and root.AssemblyLinearVelocity.X==99)
for _,c in ipairs(run.RenderStepped.callbacks)do assert(not c.alive)end
