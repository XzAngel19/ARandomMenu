for _,n in ipairs({'Air Swim','Wall Crawl State'})do AngelHub.moduleNames[n]=true;V[n]=false;AngelHub.setters[n]=function(v)V[n]=v end end
character.Parent=workspace
Enum.Material.Water='water';Enum.Material.Rock='rock'
Region3={new=function(a,b)local r={lo=a,hi=b};function r:ExpandToGrid()self.key=string.format('%d:%d:%d',self.lo.X,self.lo.Y,self.lo.Z);return self end;return r end}
local terrain={Parent=workspace,regions={},writes=0}
local function copy(t)local out={};for k,v in pairs(t)do out[k]=type(v)=='table' and copy(v) or v end;return out end
local function get(region)
 if not terrain.regions[region.key]then terrain.regions[region.key]={materials={{{'air','water','rock','air'}}},occupancy={{{0,1,1,0}}}}end
 return terrain.regions[region.key]
end
function terrain:ReadVoxels(region,res)if self.fail then error("terrain unavailable")end;assert(res==4);local data=get(region);return copy(data.materials),copy(data.occupancy)end
function terrain:WriteVoxels(region,res,materials,occupancy)assert(res==4);self.writes+=1;local data=get(region);data.materials=copy(materials);data.occupancy=copy(occupancy)end
function workspace:FindFirstChildOfClass(n)if n=='Terrain'then return terrain end end
installAirSwim(screenGui);heartbeat:Fire(.3);assert(terrain.writes==0)
AngelHub.setters['Air Swim'](true);heartbeat:Fire(.3);assert(terrain.writes==1)
local first;for _,r in pairs(terrain.regions)do first=r end
assert(first.materials[1][1][1]=='water' and first.materials[1][1][2]=='water' and first.materials[1][1][3]=='rock')
heartbeat:Fire(.3);assert(terrain.writes==1)
-- Preserve a concurrent external change and natural water on restoration.
first.materials[1][1][4]='rock';first.occupancy[1][1][4]=1
root.Position=Vector3.new(20,0,0);heartbeat:Fire(.3)
assert(first.materials[1][1][1]=='air' and first.occupancy[1][1][1]==0 and first.materials[1][1][2]=='water' and first.materials[1][1][4]=='rock')
local second;for _,r in pairs(terrain.regions)do if r~=first then second=r end end;assert(second.materials[1][1][1]=='water')
assert(AngelHub.setters['Air Walk'](true)==false and not V['Air Walk'])
AngelHub.setters['Air Swim'](false);assert(second.materials[1][1][1]=='air' and second.materials[1][1][2]=='water')
AngelHub.setters['Air Swim'](true);heartbeat:Fire(.3);assert(second.materials[1][1][1]=='water')
humanoid.Sit=true;heartbeat:Fire(.3);assert(second.materials[1][1][1]=='air')
humanoid.Sit=false;heartbeat:Fire(.3);assert(second.materials[1][1][1]=='water')
humanoid.Health=0;heartbeat:Fire(.3);assert(second.materials[1][1][1]=='air')
humanoid.Health=100;heartbeat:Fire(.3);assert(second.materials[1][1][1]=='water')
terrain.fail=true;AngelHub.setters['Air Swim'](false);assert(not V['Air Swim'] and second.materials[1][1][1]=='water')
terrain.fail=false;heartbeat:Fire(1.1);assert(second.materials[1][1][1]=='air')
AngelHub.setters['Air Swim'](true);heartbeat:Fire(.3);assert(second.materials[1][1][1]=='water')
screenGui.Destroying:Fire();assert(second.materials[1][1][1]=='air' and second.materials[1][1][2]=='water')
