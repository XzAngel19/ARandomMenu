local wsOriginalCalls=0
local originalA=function(self,...)wsOriginalCalls+=1;return CFrame.new(Vector3.new(-1,0,0)),'other'end
local originalB=function(self,...)wsOriginalCalls+=1;return Vector3.new(-2,0,0),'other'end
local ws=setmetatable({GetMouseTargetCFrame=originalA},{__index={GetTargetPosition=originalB}})
local weaponService={}
local folder={};function folder:FindFirstChild(n)if n=='WeaponService'then return weaponService end end
local replicated={};function replicated:FindFirstChild(n)if n=='ClientServices'then return folder end end
services.ReplicatedStorage=replicated
local function require(m)if m==weaponService then return ws end;error('unexpected')end
local thrown={shots={}};function thrown:IsA(n)return n=='RemoteEvent'end
function thrown:FireServer(a,b)table.insert(self.shots,{a,b})end
local events={};function events:FindFirstChild(n)if n=='KnifeThrown'then return thrown end end
local heldKnife={Name='Knife',Parent=character};function heldKnife:IsA(n)return n=='Tool'end
local handle={Parent=heldKnife,CFrame=CFrame.new(Vector3.new(1,0,0))};function handle:IsA(n)return n=='BasePart'end
function heldKnife:FindFirstChild(n)if n=='Handle'then return handle elseif n=='Events'then return events end end
function heldKnife:GetAttribute()return nil end
function character:GetChildren()if heldKnife.Parent==character then return {heldKnife} end return {} end
function backpack:GetChildren()if heldKnife.Parent==backpack then return {heldKnife}end return {} end
root.CFrame=CFrame.new(root.Position)
enemy.knife=nil;targetRoot.Parent=enemy
function targetRoot:IsDescendantOf(model)return model==enemy end
workspace.rayMode='body'
function workspace:Raycast(o,d,p)
 if self.rayMode=='wall'then return {Instance=wall} end
 if self.rayMode=='body'then
  local ignore=false;for _,x in ipairs(p.FilterDescendantsInstances)do if x==enemy then ignore=true end end
  if not ignore then return {Instance=targetRoot} end
 end
end
