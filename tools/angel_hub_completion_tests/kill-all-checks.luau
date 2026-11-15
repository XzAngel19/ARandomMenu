-- Kill All/Selected use all eligible targets, equip the backpack knife, and return.
root.Parent=character;character.Parent=workspace;humanoid.FloorMaterial=Enum.Material.Ground
workspace.FallenPartsDestroyHeight=-500
local fmt={};fmt.__index=fmt
function CFrame.new(x,y,z)local p=type(x)=='table' and x or Vector3.new(x or 0,y or 0,z or 0);return setmetatable({Position=p,__type='CFrame'},fmt)end
root.CFrame=CFrame.new(root.Position)
function character:GetPivot()return root.CFrame end
function character:PivotTo(cf)self.lastPivot=cf;root.CFrame=cf;root.Position=cf.Position end
local hits={};local hit={};function hit:IsA(n)return n=='RemoteEvent'end
function hit:FireServer(v)table.insert(hits,v)end
local events={};function events:FindFirstChild(n)if n=='HandleTouched'then return hit end end
local handle={};function handle:IsA(n)return n=='BasePart'end
local blade={Name='Knife',Enabled=true,Parent=backpack,activations=0}
function blade:IsA(n)return n=='Tool'end
function blade:GetAttribute(n)return self[n]end
function blade:FindFirstChild(n)if n=='Handle'then return handle elseif n=='Events'then return events end end
function blade:Activate()self.activations+=1 end
tools.Knife=blade;tools.equipped=nil;enemy.knife=nil
local oldFind=character.FindFirstChild
function character:FindFirstChild(n)if n=='Knife'and blade.Parent==character then return blade end;return oldFind(self,n)end
function humanoid:EquipTool(item)item.Parent=character;tools.Knife=nil end
local target2Root={Position=Vector3.new(120,0,0),AssemblyLinearVelocity=Vector3.zero}
function target2Root:IsA(c)return c=='BasePart'end
local target2Human={Health=100};function target2Human:GetState()return {Name='Running'}end
function target2Human:GetAttribute()end
local target2Character={Parent=workspace};function target2Character:GetAttribute()end
function target2Character:FindFirstChild(n)if n=='HumanoidRootPart'then return target2Root end end
function target2Character:FindFirstChildOfClass(n)if n=='Humanoid'then return target2Human end end
local second={Name='Bob',UserId=3,Character=target2Character};function second:FindFirstChildOfClass()end
function playersService:GetPlayers()return {localPlayer,other,second}end
targetRoot.Position=Vector3.new(70,0,0)
local status='';AngelHub.setKnifeStatus=function(s)status=s end
installGunFeatures(screenGui)
AngelHub.actions['Kill All']();assert(AngelHub.mm2KnifeKillBusy and blade.Parent==character)
heartbeat:Fire(.1);assert(root.Position.X==70)
fakeNow+=.1;heartbeat:Fire(.1);drain();assert(#hits==1 and hits[1]==targetRoot)
fakeNow+=.2;heartbeat:Fire(.1);assert(root.Position.X==120)
fakeNow+=1;heartbeat:Fire(.1);drain();assert(#hits==2 and hits[2]==target2Root)
fakeNow+=.2;heartbeat:Fire(.1);assert(not AngelHub.mm2KnifeKillBusy and root.Position.X==0 and status:find('sin confirmar'))
-- No target or no knife is reported; buttons never turn Knife Aura on.
V['Kill Player']='Nobody';AngelHub.actions['Kill Selected']();assert(status:find('Selecciona') and not AngelHub.mm2KnifeKillBusy)
V['Kill Player']='Bob';fakeNow+=1;AngelHub.actions['Kill Selected']();heartbeat:Fire(.1)
fakeNow+=.1;heartbeat:Fire(.1);drain();assert(#hits==3 and hits[3]==target2Root)
fakeNow+=.2;heartbeat:Fire(.1);assert(not V['Knife Aura'] and root.Position.X==0)
-- Busy weapon is retried rather than silently discarding a target.
fakeNow+=2;blade.Enabled=false;V['Kill Player']='Bob';AngelHub.actions['Kill Selected']();heartbeat:Fire(.1)
fakeNow+=.1;heartbeat:Fire(.1);drain();assert(#hits==3 and AngelHub.mm2KnifeKillBusy)
blade.Enabled=true;fakeNow+=.2;heartbeat:Fire(.1);drain();assert(#hits==4)
fakeNow+=.2;heartbeat:Fire(.1);assert(not AngelHub.mm2KnifeKillBusy and root.Position.X==0)
-- Respawn/death, round motion conflicts, cancellation and destruction do not leave a running sequence.
fakeNow+=2;AngelHub.actions['Kill All']();heartbeat:Fire(.1);V['Auto Farm']=true
heartbeat:Fire(.1);assert(not AngelHub.mm2KnifeKillBusy and root.Position.X==0);V['Auto Farm']=false
-- Farm can own a cancellable Kill All sequence, while manual Kill All stays blocked.
fakeNow+=2;V['Auto Farm']=true;local valid=true;AngelHub.farmTargetAllowed=function(player)return player~=second end
AngelHub.actions['Kill All']();assert(not AngelHub.mm2KnifeKillBusy)
assert(AngelHub.mm2StartFarmKills(function()return valid end) and AngelHub.mm2KnifeKillOwner=='farm')
heartbeat:Fire(.1);assert(root.Position.X==70);fakeNow+=1;heartbeat:Fire(.1)
local pendingBefore=#hits;valid=false;AngelHub.mm2CancelFarmKills();drain()
assert(#hits==pendingBefore and not AngelHub.mm2KnifeKillBusy and root.Position.X==0)
V['Auto Farm']=false
fakeNow+=2;AngelHub.actions['Kill All']();heartbeat:Fire(.1);fakeNow+=.1;heartbeat:Fire(.1)
local before=#hits;screenGui.Destroying:Fire();drain()
assert(not AngelHub.mm2KnifeKillBusy and root.Position.X==0 and #hits==before)
