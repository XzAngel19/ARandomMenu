local function setting(name, value)
 V[name]=value;AngelHub.setters[name]=function(newValue)V[name]=newValue end
end
AngelHub.moduleNames['Auto Shoot']=true
setting('Auto Shoot',false);setting('Shoot Mode','Normal');setting('Shoot WallCheck',true)
setting('Shoot Proximity',false);setting('Shoot Proximity Aura',30)
localPlayer.ChildAdded=event();localPlayer.CharacterAdded=event();character.ChildAdded=event()
local backpack={ChildAdded=event()};local tools={}
function backpack:FindFirstChild(n)return tools[n]end
function localPlayer:FindFirstChildOfClass(n)if n=='Backpack'then return backpack end end
local oldFind=character.FindFirstChild
function character:FindFirstChild(n)if n=='Gun'then return tools.equipped end;return oldFind(self,n)end
function humanoid:EquipTool(tool)self.equips=(self.equips or 0)+1;tools.Gun=nil;tools.equipped=tool;tool.Parent=character end
local targetRoot={Position=Vector3.new(20,0,0),AssemblyLinearVelocity=Vector3.new(10,0,0)}
function targetRoot:IsA(c)return c=='BasePart'end
local knife={Name='Knife'};function knife:IsA(c)return c=='Tool'end
local enemyHumanoid={Health=100};local enemy={}
function enemy:FindFirstChildOfClass(n)if n=='Humanoid'then return enemyHumanoid end end
function enemy:FindFirstChild(n)if n=='HumanoidRootPart'then return targetRoot elseif n=='Knife'then return self.knife end end
enemy.knife=knife;other.Character=enemy
function other:FindFirstChildOfClass()return nil end
localPlayer.Neutral=false;localPlayer.Team='same';other.Team='same'
local remote={shots={}};function remote:IsA(c)return c=='RemoteEvent'end
function remote:FireServer(a,b)table.insert(self.shots,{a,b});if self.fail then error('uncertain')end end
local gunTool={Name='Gun',Parent=backpack,Enabled=true}
function gunTool:IsA(c)return c=='Tool'end
function gunTool:FindFirstChild(n)if n=='Shoot'then return remote end end
function gunTool:GetAttribute(n)return self[n]end
local attachment={WorldCFrame={Position=Vector3.new(2,1,0)}}
function attachment:IsA(n)return n=='Attachment'end
function root:FindFirstChild(n)if n=='GunRaycastAttachment'then return attachment end end
CFrame.lookAt=function(a,b)return {Position=a,Target=b}end
Color3={fromRGB=function(...)return {...}end}
workspace.rays={};workspace.rayMode='clear'
function workspace:Raycast(o,d,p)
 table.insert(self.rays,{o,d,p})
 if self.rayMode=='wall'then return {Instance=wall}end
 if self.rayMode=='transparent' and #p.FilterDescendantsInstances==1 then
  return {Instance=self.transparent}
 end
 return nil
end
local transparent={Transparency=1};function transparent:IsA(c)return c=='BasePart'end
function transparent:IsDescendantOf()return false end
workspace.transparent=transparent
wall.Transparency=0
local pending={};task.defer=function(f)table.insert(pending,f)end
local function drain()local list=pending;pending={};for _,f in ipairs(list)do f()end end
installGameplay(screenGui)
AngelHub.setters['Shoot Mode']('Experimental')
assert(AngelHub.setters['Auto Shoot'](true)==false and not V['Auto Shoot'])
AngelHub.setters['Shoot Mode']('Normal')
AngelHub.setters['Auto Shoot'](true);assert(V['Auto Shoot'] and #remote.shots==0)
tools.Gun=gunTool;backpack.ChildAdded:Fire(gunTool);drain()
assert(#remote.shots==1 and humanoid.equips==1)
assert(remote.shots[1][1].Position==attachment.WorldCFrame.Position)
assert(math.abs(remote.shots[1][2].Position.X-20.8)<0.0001)
heartbeat:Fire(.1);assert(#remote.shots==1)
fakeNow+=.23;workspace.rayMode='wall';heartbeat:Fire(.1);assert(#remote.shots==1)
workspace.rayMode='transparent';fakeNow+=.11;heartbeat:Fire(.1);assert(#remote.shots==2)
assert(#workspace.rays>=3)
fakeNow+=.23;V['Shoot Proximity']=true;V['Shoot Proximity Aura']=5;heartbeat:Fire(.1);assert(#remote.shots==2)
local radius=created[#created];assert(radius.class=='SphereHandleAdornment' and radius.Adornee==root and radius.Radius==5)
fakeNow+=.11;V['Shoot Proximity Aura']=30;V['Shoot WallCheck']=false;workspace.rayMode='wall';remote.fail=true
heartbeat:Fire(.1);assert(#remote.shots==3);heartbeat:Fire(.1);assert(#remote.shots==3)
remote.fail=false;fakeNow+=.23;enemyHumanoid.Health=0;heartbeat:Fire(.1);assert(#remote.shots==3)
fakeNow+=.11;enemyHumanoid.Health=100;gunTool.Reloading=true;heartbeat:Fire(.1);assert(#remote.shots==3)
fakeNow+=.11;gunTool.Reloading=false;enemy.knife=nil;heartbeat:Fire(.1);assert(#remote.shots==3)
fakeNow+=.11;enemy.knife=knife;heartbeat:Fire(.1);assert(#remote.shots==4)
AngelHub.setters['Shoot Mode']('Experimental');assert(not V['Auto Shoot'] and radius.destroyed)
fakeNow+=1;heartbeat:Fire(.1);assert(#remote.shots==4)
AngelHub.setters['Shoot Mode']('Instakill');V['Shoot WallCheck']=true;workspace.rayMode='wall'
AngelHub.setters['Auto Shoot'](true);assert(#remote.shots==5)
assert(math.abs(remote.shots[5][1].Position.X-19)<0.0001)
assert(math.abs(remote.shots[5][2].Position.X-21.8)<0.0001)
screenGui.Destroying:Fire();fakeNow+=1;heartbeat:Fire(.1);assert(#remote.shots==5)
for _,connection in ipairs(backpack.ChildAdded.callbacks) do assert(not connection.alive) end
