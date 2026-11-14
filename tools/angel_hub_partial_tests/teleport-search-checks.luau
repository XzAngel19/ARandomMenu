function workspace:IsA()return false end
local function setting(name,value)V[name]=value;AngelHub.setters[name]=function(x)V[name]=x end end
for n,v in pairs({['Teleport Destination']='Nearest Player',['Teleport Movement']='Instant',['Teleport Search Range']=100,
 ['Teleport Player Offset']=4,['Teleport Height Offset']=3,['Teleport Skip Friends']=false,['Teleport Player']='Alice',['Teleport Item']='Chest'})do setting(n,v)end
localPlayer.Name='Me';localPlayer.UserId=1;other.UserId=2
local targetRoot={Position=Vector3.new(20,0,0),CFrame={LookVector=Vector3.new(0,0,-1)}};function targetRoot:IsA(c)return c=='BasePart'end
local targetHumanoid={Health=100};local target={Parent=workspace}
function target:IsDescendantOf(w)return self.Parent==w end
function target:FindFirstChildOfClass(n)if n=='Humanoid'then return targetHumanoid end end
function target:FindFirstChild(n)if n=='HumanoidRootPart'then return targetRoot end end
other.Character=target
local frameMeta={};frameMeta.__add=function(cf,delta)return setmetatable({Position=cf.Position+delta},frameMeta)end
root.CFrame=setmetatable({Position=root.Position},frameMeta)
function character:PivotTo(cf)self.lastPivot=cf;root.Position=cf.Position;root.CFrame=setmetatable({Position=cf.Position},frameMeta)end
local treasure={Name='TreasureChest',Parent=workspace,Position=Vector3.new(10,0,0)}
function treasure:IsA(c)return c=='BasePart'end
function treasure:IsDescendantOf(w)return self.Parent==w end
table.insert(workspace.objects,treasure)
installGameplay(screenGui)
AngelHub.actions['Teleport To Point']();assert(root.Position.X==20 and root.Position.Y==3 and root.Position.Z==4)
root.Position=Vector3.new(0,0,0);root.CFrame=setmetatable({Position=root.Position},frameMeta);AngelHub.setters['Teleport Destination']('Named Player')
AngelHub.actions['Teleport To Point']();assert(root.Position.X==20 and root.Position.Z==4)
root.Position=Vector3.new(0,0,0);root.CFrame=setmetatable({Position=root.Position},frameMeta);AngelHub.setters['Teleport Destination']('Item');AngelHub.actions['Teleport To Point']()
assert(root.Position.X==10 and root.Position.Y==3)
-- A friend lookup can yield; changing the destination invalidates it.
local queue={};task.spawn=function(fn)table.insert(queue,fn)end
function other:IsFriendsWith()coroutine.yield('friends');return false end
root.Position=Vector3.new(0,0,0);root.CFrame=setmetatable({Position=root.Position},frameMeta);AngelHub.setters['Teleport Destination']('Nearest Player');AngelHub.setters['Teleport Skip Friends'](true)
AngelHub.actions['Teleport To Point']();assert(#queue==1)
local co=coroutine.create(queue[1]);local ok,result=coroutine.resume(co);assert(ok and result=='friends')
AngelHub.setters['Teleport Destination']('Item');assert(coroutine.resume(co));assert(root.Position.X==0)
-- Cancellation on unload prevents delayed lookups from teleporting.
queue={};AngelHub.setters['Teleport Destination']('Nearest Player');AngelHub.actions['Teleport To Point']();co=coroutine.create(queue[1])
ok,result=coroutine.resume(co);assert(ok and result=='friends');screenGui.Destroying:Fire();assert(coroutine.resume(co));assert(root.Position.X==0)
