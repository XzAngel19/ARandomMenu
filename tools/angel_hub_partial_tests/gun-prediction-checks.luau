local torso={Position=Vector3.new(20,1,0)};function torso:IsA(k)return k=='BasePart'end
local oldFindEnemy=enemy.FindFirstChild
function enemy:FindFirstChild(name)if name=='UpperTorso'then return torso end;return oldFindEnemy(self,name)end
local measured=110
local pingItem={};function pingItem:GetValue()return measured end
local statsItems={};function statsItems:FindFirstChild(n)if n=='Data Ping'then return pingItem end end
local network={};function network:FindFirstChild(n)if n=='ServerStatsItem'then return statsItems end end
local stats={};function stats:FindFirstChild(n)if n=='Network'then return network end end
services.Stats=stats;function localPlayer:GetNetworkPing()return .5 end
tools.equipped=gunTool;gunTool.Parent=character
installGameplay(screenGui);AngelHub.setters['Auto Shoot'](true)
assert(#remote.shots==1 and math.abs(remote.shots[1][2].Position.X-21.1)<.0001 and remote.shots[1][2].Position.Y==1)
-- A one-off ping spike does not dominate the median of recent samples.
measured=500;fakeNow+=.25;heartbeat:Fire(.11)
assert(#remote.shots==2 and math.abs(remote.shots[2][2].Position.X-21.1)<.0001)
V['Shoot Mode']='Instakill';measured=110;fakeNow+=.25;heartbeat:Fire(.11)
assert(#remote.shots==3 and remote.shots[3][1].Position.Y==1 and math.abs(remote.shots[3][1].Position.X-19)<.0001)
screenGui.Destroying:Fire()
