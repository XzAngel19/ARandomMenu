installMovementFeatures(screenGui)
V['Speed Mode']='WalkSpeed';AngelHub.setters['Enable Speed'](true);heartbeat:Fire(.1);assert(humanoid.WalkSpeed==54)
V['Gravity Method']='Force';V['Gravity Value']=40;AngelHub.setters['Enable Gravity'](true);heartbeat:Fire(.1)
local oldForce;for _,x in ipairs(created)do if x.Name=='AngelGravityForce'then oldForce=x end end
assert(oldForce and not oldForce.destroyed)
local newRoot={Position=Vector3.new(3,0,0),Size=Vector3.new(2,2,2),AssemblyMass=6,AssemblyLinearVelocity=Vector3.zero,Anchored=false}
newRoot.CFrame=CFrame.new(newRoot.Position);function newRoot:IsA(n)return n=='BasePart'end
local newHum={Health=100,WalkSpeed=23,HipHeight=2,MoveDirection=Vector3.new(1,0,0),FloorMaterial=Enum.Material.Air}
local newChar={Parent=workspace}
function newChar:FindFirstChildOfClass(n)if n=='Humanoid'then return newHum end end
function newChar:FindFirstChild(n)if n=='HumanoidRootPart'then return newRoot end end
localPlayer.Character=newChar;heartbeat:Fire(.1)
assert(humanoid.WalkSpeed==16 and newHum.WalkSpeed==54 and oldForce.destroyed)
local latest;for _,x in ipairs(created)do if x.Name=='AngelGravityForce' and x~=oldForce then latest=x end end
assert(latest and not latest.destroyed and latest.Parent==newRoot)
AngelHub.setters['Enable Speed'](false);assert(newHum.WalkSpeed==23)
V['Speed Mode']='Velocity';AngelHub.setters['Enable Speed'](true);heartbeat:Fire(.1)
assert(newHum.WalkSpeed==54 and newRoot.AssemblyLinearVelocity.X>0)
localPlayer.Character=character;heartbeat:Fire(.1)
assert(newHum.WalkSpeed==23 and humanoid.WalkSpeed==54)
screenGui.Destroying:Fire();assert(humanoid.WalkSpeed==16 and latest.destroyed)
