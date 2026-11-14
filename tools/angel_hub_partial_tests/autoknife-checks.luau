AngelHub.moduleNames['Auto Knife Throw']=true;V['Auto Knife Throw']=false;AngelHub.setters['Auto Knife Throw']=function(v)V['Auto Knife Throw']=v end
V['Throw WallCheck']=true;V['Throw Delay']=1
function vec:Dot(b)return self.X*b.X+self.Y*b.Y+self.Z*b.Z end
localPlayer.Name='Me';localPlayer.UserId=1;other.UserId=2
local enemyHuman={Health=100};local enemyRoot={Position=Vector3.new(20,0,0),AssemblyLinearVelocity=Vector3.new(0,0,10)}
function enemyRoot:IsA(c)return c=='BasePart'end
local enemy={Parent=workspace};function enemy:IsDescendantOf(w)return self.Parent==w end;function enemy:FindFirstChildOfClass(n)if n=='Humanoid'then return enemyHuman end end
function enemy:FindFirstChild(n)if n=='HumanoidRootPart'then return enemyRoot end end
function enemyRoot:IsDescendantOf(c)return c==enemy end
other.Character=enemy
local farRoot={Position=Vector3.new(100,0,0),AssemblyLinearVelocity=Vector3.new(0,0,0)};function farRoot:IsA(c)return c=='BasePart'end
local farChar={Parent=workspace};function farChar:IsDescendantOf(w)return self.Parent==w end;function farChar:FindFirstChildOfClass(n)if n=='Humanoid'then return enemyHuman end end
function farChar:FindFirstChild(n)if n=='HumanoidRootPart'then return farRoot end end
function farRoot:IsDescendantOf(c)return c==farChar end
local farPlayer={Name='Bob',UserId=3,Character=farChar};function playersService:GetPlayers()return {localPlayer,other,farPlayer}end
local sent={};local thrown={};function thrown:IsA(c)return c=='RemoteEvent'end
function thrown:FireServer(origin,aim)table.insert(sent,{origin=origin,aim=aim})end
local events={};function events:FindFirstChild(n)if n=='KnifeThrown'then return thrown end end
local handle={CFrame={Position=Vector3.new(0,0,0)}};function handle:IsA(c)return c=='BasePart'end
local knife={Parent=character,Enabled=true};function knife:IsA(c)return c=='Tool'end
function knife:GetAttribute(n)if n=='ThrowSpeed'then return 96 end end
function knife:FindFirstChild(n)return ({Handle=handle,Events=events})[n]end
local originalFind=character.FindFirstChild
function character:FindFirstChild(n)if n=='Knife' and knife.Parent==character then return knife end;return originalFind(self,n)end
local roles={Me={Name='Me',Role='Murderer'},Alice={Name='Alice',Role='Sheriff'},Bob={Name='Bob',Role='Innocent'}}
local fetch={};function fetch:IsA(c)return c=='RemoteFunction'end;function fetch:InvokeServer()return roles end
local ended={OnClientEvent=event()};function ended:IsA(c)return c=='RemoteEvent'end
local started={OnClientEvent=event()};function started:IsA(c)return c=='RemoteEvent'end
local changed={OnClientEvent=event()};function changed:IsA(c)return c=='RemoteEvent'end
local gameplay={};function gameplay:FindFirstChild(n)return ({GetCurrentPlayerData=fetch,PlayerDataChanged=changed,RoundEndFade=ended,RoundStart=started})[n]end
local remotes={};function remotes:FindFirstChild(n)if n=='Gameplay'then return gameplay end end
local storage={};function storage:FindFirstChild(n)if n=='Remotes'then return remotes end end;services.ReplicatedStorage=storage
local obstruction={};function obstruction:IsDescendantOf()return false end
local blocked=false;local predictionBlocked=false
function workspace:Raycast(origin,direction,params)
 if #params.FilterDescendantsInstances==1 then
  if blocked then return {Instance=obstruction}end
  return {Instance=direction.X<50 and enemyRoot or farRoot}
 end
 if predictionBlocked then return {Instance=obstruction}end
end
installGameplay(screenGui);heartbeat:Fire(.21);assert(#sent==0)
AngelHub.setters['Auto Knife Throw'](true);heartbeat:Fire(.21);heartbeat:Fire(.21)
assert(#sent==1 and sent[1].aim.Position.X==20 and sent[1].aim.Position.Z>0)
heartbeat:Fire(.21);assert(#sent==1)
fakeNow+=1;blocked=true;heartbeat:Fire(.21);assert(#sent==1)
blocked=false;predictionBlocked=true;heartbeat:Fire(.21);assert(#sent==1)
predictionBlocked=false;heartbeat:Fire(.21);assert(#sent==2)
-- The live body must be visible even with prediction-path WallCheck off.
fakeNow+=1;blocked=true;V['Throw WallCheck']=false;heartbeat:Fire(.21);assert(#sent==2)
blocked=false;predictionBlocked=true;heartbeat:Fire(.21);assert(#sent==3)
ended.OnClientEvent:Fire();fakeNow+=1;heartbeat:Fire(.21);assert(#sent==3)
started.OnClientEvent:Fire(10,roles);heartbeat:Fire(.21);assert(#sent==4)
-- Equipped tools wait at least one turn and a short settling period before a throw.
local backpack={};function backpack:FindFirstChild(n)if n=='Knife'then return knife end end
local oldClass=localPlayer.FindFirstChildOfClass
function localPlayer:FindFirstChildOfClass(n)if n=='Backpack'then return backpack end;return oldClass(self,n)end
function humanoid:EquipTool(tool)tool.Parent=character;self.equips=(self.equips or 0)+1 end
knife.Parent=backpack;fakeNow+=1;heartbeat:Fire(.21);assert(#sent==4 and humanoid.equips==1)
fakeNow+=.1;heartbeat:Fire(.21);assert(#sent==4)
fakeNow+=.1;heartbeat:Fire(.21);assert(#sent==5)
AngelHub.setters['Auto Knife Throw'](false);fakeNow+=2;heartbeat:Fire(.21);assert(#sent==5)
screenGui.Destroying:Fire()
