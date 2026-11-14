installMovementFeatures(screenGui)
-- Start passive; no movement or gravity changes on injection.
heartbeat:Fire(.1);assert(humanoid.WalkSpeed==16 and workspace.Gravity==196.2)
AngelHub.setters['Enable Speed'](true);heartbeat:Fire(.1)
if mobile then assert(root.AssemblyLinearVelocity.X>0)else assert(root.AssemblyLinearVelocity.X==0)end
if not mobile then uis.InputBegan:Fire(shift,false);heartbeat:Fire(.1);assert(root.AssemblyLinearVelocity.X>0)end
if not mobile then
 AngelHub.setters['Sprint Key Value']('Other');heartbeat:Fire(.1);assert(root.AssemblyLinearVelocity.X==0)
 AngelHub.setters['Sprint Key Value']('LeftShift');uis.InputBegan:Fire(shift,false)
end

-- Velocity mode respects wall check and keeps vertical speed.
root.AssemblyLinearVelocity=Vector3.new(0,7,0);workspace.hitWall=true;heartbeat:Fire(.1)
assert(root.AssemblyLinearVelocity.X==0 and root.AssemblyLinearVelocity.Y==7)
workspace.hitWall=false
-- WalkSpeed restores only our value; respawns can have a different original.
V['Speed Mode']='WalkSpeed';V['Speed Auto Jump']=true;humanoid.FloorMaterial=Enum.Material.Ground;heartbeat:Fire(.1);assert(humanoid.WalkSpeed==54 and humanoid.Jump==true)
V['Speed Auto Jump']=false;humanoid.FloorMaterial=Enum.Material.Air
humanoid.WalkSpeed=37;heartbeat:Fire(.1);assert(humanoid.WalkSpeed==54)
AngelHub.setters['Enable Speed'](false);assert(humanoid.WalkSpeed==37)
-- CFrame is implemented and negative manual values move in reverse.
V['Speed Mode']='CFrame';V['Speed Value']=-10;AngelHub.setters['Enable Speed'](true)
heartbeat:Fire(.1);assert(root.CFrame.Position.X<0)
AngelHub.setters['Enable Speed'](false)
-- Empty Sprint Key makes the speed module usable without a held key.
if not mobile then
 AngelHub.setters['Sprint Key Value']('');V['Speed Mode']='Velocity';V['Speed Value']=35
 AngelHub.setters['Enable Speed'](true);heartbeat:Fire(.1);assert(root.AssemblyLinearVelocity.X>0)
 AngelHub.setters['Enable Speed'](false);AngelHub.setters['Sprint Key Value']('LeftShift');uis.InputBegan:Fire(shift,false)
end
-- Fly works on PC and mobile and takes priority over Speed.
V['Speed Mode']='Velocity';V['Speed Value']=54;AngelHub.setters['Enable Speed'](true)
AngelHub.setters['Enable Fly'](true)
local controls,up,down
for _,x in ipairs(created)do if x.Name=='AngelHubFlyControls'then controls=x elseif x.Name=='Up'then up=x elseif x.Name=='Down'then down=x end end
if mobile then assert(controls and up and down);up.InputBegan:Fire({UserInputType=Enum.UserInputType.Touch})
else uis.InputBegan:Fire(space,false) end
heartbeat:Fire(.1);assert(root.AssemblyLinearVelocity.Y>0)
V['Fly Float']='Platform';heartbeat:Fire(.1)
local platform;for _,x in ipairs(created)do if x.Name=='AngelFlyPlatform'then platform=x end end
assert(platform and not platform.destroyed and platform.CanCollide)
V['Fly Float']='Hover';heartbeat:Fire(.1);assert(platform.destroyed)
V['Fly Method']='CFrame';local x=root.CFrame.Position.X;heartbeat:Fire(.1);assert(root.CFrame.Position.X~=x)
AngelHub.setters['Enable Fly'](false);if mobile then assert(controls.destroyed)end
AngelHub.setters['Enable Speed'](false)
-- Gravity workspace changes are conditionally restored; Force leaves workspace untouched.
V['Gravity Value']=50;AngelHub.setters['Enable Gravity'](true);heartbeat:Fire(.1);assert(workspace.Gravity==50)
workspace.Gravity=75;heartbeat:Fire(.1);assert(workspace.Gravity==50)
AngelHub.setters['Enable Gravity'](false);assert(workspace.Gravity==75)
V['Gravity Method']='Force';V['Gravity Value']=25;AngelHub.setters['Enable Gravity'](true);heartbeat:Fire(.1)
local force,attachment;for _,x in ipairs(created)do if x.Name=='AngelGravityForce'then force=x elseif x.Name=='AngelGravityAtt'then attachment=x end end
assert(force and attachment and workspace.Gravity==75 and force.Force.Y==250)
workspace.Gravity=100;heartbeat:Fire(.1);assert(workspace.Gravity==100 and force.Force.Y==375)
AngelHub.setters['Enable Gravity'](false);assert(force.destroyed and attachment.destroyed and workspace.Gravity==100)
AngelHub.resetGravity();assert(workspace.Gravity==196.2 and V['Gravity Value']==196.2)
V['Gravity Method']='Workspace';V['Gravity Value']=80;AngelHub.setters['Enable Gravity'](true);heartbeat:Fire(.1);assert(workspace.Gravity==80)
screenGui.Destroying:Fire();assert(workspace.Gravity==196.2);heartbeat:Fire(.1);assert(workspace.Gravity==196.2)
