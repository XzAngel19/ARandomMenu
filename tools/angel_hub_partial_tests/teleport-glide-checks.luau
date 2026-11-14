game.PlaceId=142823291
for n,v in pairs({['Teleport Destination']='Waypoint',['Teleport Movement']='Glide',['Teleport Glide Speed']=10,
 ['Teleport Height Offset']=3,['Teleport Keep Momentum']=false,['Air Walk']=false})do V[n]=v;AngelHub.setters[n]=function(x)V[n]=x end end
AngelHub.moduleNames['Air Walk']=true
AngelHub.listOptions={};for _,name in ipairs({'Marker Point','Teleport Point'})do
 local items={};AngelHub.setters[name]=function(x)if table.find(items,x)then V[name]=x end end
 AngelHub.listOptions[name]=function(x)items=table.clone(x);V[name]=items[1]end
end
local frameMeta={};frameMeta.__add=function(cf,delta)return setmetatable({Position=cf.Position+delta},frameMeta)end
root.CFrame=setmetatable({Position=root.Position},frameMeta);root.AssemblyAngularVelocity=Vector3.new(0,0,0)
function character:PivotTo(cf)self.lastPivot=cf;root.Position=cf.Position;root.CFrame=setmetatable({Position=cf.Position},frameMeta)end
installGameplay(screenGui)
AngelHub.setters['Marker Points by Place']({['142823291']={Far={10,0,0}}})
AngelHub.actions['Teleport To Point']();assert(root.Position.X==0)
heartbeat:Fire(.1);assert(math.abs(root.Position.X-1)<.0001)
heartbeat:Fire(.1);assert(math.abs(root.Position.X-2)<.0001)
-- Changing mode cancels an in-flight glide.
AngelHub.setters['Teleport Movement']('Instant');heartbeat:Fire(.1);assert(math.abs(root.Position.X-2)<.0001)
AngelHub.setters['Teleport Movement']('Glide');AngelHub.actions['Teleport To Point']();heartbeat:Fire(.1);assert(root.Position.X>2)
-- Motion modules take ownership and cancel it, rather than fighting it.
AngelHub.setters['Air Walk'](true);local x=root.Position.X;heartbeat:Fire(.1);assert(root.Position.X==x)
AngelHub.setters['Air Walk'](false);AngelHub.actions['Teleport To Point']()
for i=1,20 do heartbeat:Fire(.1)end
assert(math.abs(root.Position.X-10)<.001)
-- No movement after cleanup.
AngelHub.actions['Teleport To Point']();screenGui.Destroying:Fire();local at=root.Position.X;heartbeat:Fire(.2);assert(root.Position.X==at)
