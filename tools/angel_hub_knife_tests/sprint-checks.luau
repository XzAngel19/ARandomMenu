installMovementFeatures(screenGui)
local button
for _,x in ipairs(created)do if x.Name=='AngelHubSprintButton'then button=x end end
if mobile then assert(button and button.Parent==screenGui)else assert(not button)end
local input={UserInputType=Enum.UserInputType.Touch}
local function press()
 if mobile then button.InputBegan:Fire(input) else uis.InputBegan:Fire(shift,false) end
end
local function release()
 if mobile then button.InputEnded:Fire(input) else uis.InputEnded:Fire(shift) end
end
-- Sprint Tail is an MM2 action independent of Speed.
assert(not V['Enable Speed']);press();heartbeat:Fire(.1)
assert(humanoid.WalkSpeed==30)
local trail,left,right
for _,x in ipairs(created)do
 if x.Name=='AngelSprintTail'then trail=x elseif x.Name=='AngelSprintLeft'then left=x elseif x.Name=='AngelSprintRight'then right=x end
end
assert(trail and trail.Enabled and trail.Parent==root and left and right)
humanoid.MoveDirection=Vector3.zero;heartbeat:Fire(.1);assert(not trail.Enabled)
humanoid.MoveDirection=Vector3.new(1,0,0);heartbeat:Fire(.1);assert(trail.Enabled)
if mobile then uis.InputEnded:Fire(input) else release() end
assert(humanoid.WalkSpeed==16 and trail.destroyed and left.destroyed and right.destroyed)
-- Speed works without Sprint; Sprint temporarily raises only low speeds.
V['Speed Value']=10;AngelHub.setters['Enable Speed'](true);heartbeat:Fire(.1)
assert(humanoid.WalkSpeed==10 and root.AssemblyLinearVelocity.X>0)
press();heartbeat:Fire(.1);assert(humanoid.WalkSpeed==30)
release();heartbeat:Fire(.1);assert(humanoid.WalkSpeed==10)
V['Speed Value']=54;press();heartbeat:Fire(.1);assert(humanoid.WalkSpeed==54)
AngelHub.setters['Enable Speed'](false);heartbeat:Fire(.1);assert(humanoid.WalkSpeed==30)
release();assert(humanoid.WalkSpeed==16)
-- The same arbitration applies in WalkSpeed and CFrame modes.
for _,mode in ipairs({'WalkSpeed','CFrame'}) do
 V['Speed Mode']=mode;V['Speed Value']=12;AngelHub.setters['Enable Speed'](true)
 heartbeat:Fire(.1);press();heartbeat:Fire(.1)
 if mode=='WalkSpeed' then assert(humanoid.WalkSpeed==30)
 else assert(humanoid.WalkSpeed==16 and root.CFrame.Position.X>0) end
 release();heartbeat:Fire(.1)
 if mode=='WalkSpeed' then assert(humanoid.WalkSpeed==12) end
 AngelHub.setters['Enable Speed'](false);assert(humanoid.WalkSpeed==16)
end
V['Speed Mode']='Velocity';V['Speed Value']=54
-- Rebinding the sprint key releases the old hold without affecting Speed.
press();heartbeat:Fire(.1);assert(humanoid.WalkSpeed==30)
AngelHub.setters['Sprint Key Value']('Q');assert(humanoid.WalkSpeed==16)
AngelHub.setters['Sprint Key Value']('LeftShift')
-- Fly wins while held; releasing Fly restores Sprint if still held.
press();heartbeat:Fire(.1);AngelHub.setters['Enable Fly'](true);heartbeat:Fire(.1)
assert(humanoid.WalkSpeed==16)
AngelHub.setters['Enable Fly'](false);heartbeat:Fire(.1);assert(humanoid.WalkSpeed==30)
release();assert(humanoid.WalkSpeed==16)
-- Death and seated states restore speed and remove effects until valid again.
press();heartbeat:Fire(.1);humanoid.Health=0;heartbeat:Fire(.1);assert(humanoid.WalkSpeed==16)
humanoid.Health=100;humanoid.Sit=true;heartbeat:Fire(.1);assert(humanoid.WalkSpeed==16)
humanoid.Sit=false;heartbeat:Fire(.1);assert(humanoid.WalkSpeed==30);release()
-- Focus loss clears held Sprint, trail and temporary speed.
press();heartbeat:Fire(.1);assert(humanoid.WalkSpeed==30)
uis.WindowFocusReleased:Fire();assert(humanoid.WalkSpeed==16)
-- Respawn replaces owned visual and restores each humanoid's original speed.
press();heartbeat:Fire(.1)
local oldTrail;for _,x in ipairs(created)do if x.Name=='AngelSprintTail' and not x.destroyed then oldTrail=x end end
local newRoot={Position=Vector3.new(3,0,0),Size=Vector3.new(2,2,2),AssemblyMass=6,AssemblyLinearVelocity=Vector3.zero,Anchored=false}
newRoot.CFrame=CFrame.new(newRoot.Position);function newRoot:IsA(n)return n=='BasePart'end
local newHum={Health=100,WalkSpeed=23,HipHeight=2,MoveDirection=Vector3.new(1,0,0),FloorMaterial=Enum.Material.Air}
local newChar={Parent=workspace}
function newChar:FindFirstChildOfClass(n)if n=='Humanoid'then return newHum end end
function newChar:FindFirstChild(n)if n=='HumanoidRootPart'then return newRoot end end
localPlayer.Character=newChar;heartbeat:Fire(.1);assert(humanoid.WalkSpeed==16 and newHum.WalkSpeed==30 and oldTrail.destroyed)
screenGui.Destroying:Fire();assert(newHum.WalkSpeed==23)
for _,x in ipairs(created)do if x.Name=='AngelSprintTail' then assert(x.destroyed)end end
