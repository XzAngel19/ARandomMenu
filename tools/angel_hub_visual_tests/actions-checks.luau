AngelHub.actions={};setting('Auto Get Gun',false)
V['High Jump Velocity']=100;V['Long Jump Speed']=80;V['Long Jump Mode']='Velocity';V['Get Gun Key Value']='G'
V['Teleport Player Name']='Alice';root.Parent=character;character.Parent=workspace
root.AssemblyMass=5;root.AssemblyAngularVelocity=Vector3.zero
local cf={};cf.__add=function(a,b)return {Position=a.Position+b,Y=b.Y}end
root.CFrame=setmetatable({Position=root.Position},cf)
function character:PivotTo(c)self.lastPivot=c end
function gun:IsDescendantOf(w)return self.Parent==w end
function mapSpawn:IsDescendantOf(w)return w==workspace end
mapSpawn.CFrame=setmetatable({Position=mapSpawn.Position},cf)
other.Character={};function other.Character:FindFirstChild(n)if n=='HumanoidRootPart'then return mapSpawn end end
AngelHub.findMM2Map=function()return map end;AngelHub.findMM2DroppedGun=function()return gun end
AngelHub.getMM2Role=function()return 'Innocent'end;AngelHub.isMM2RoundActive=function()return true end
installBasicActions(screenGui)
assert(#touches==0 and not character.lastPivot)
AngelHub.actions['High Jump']();assert(root.AssemblyLinearVelocity.Y==100)
AngelHub.actions['Long Jump']();assert(root.AssemblyLinearVelocity.X==80 and root.AssemblyLinearVelocity.Y==100)
root.ApplyImpulse=function(_,v)root.lastImpulse=v end
V['Long Jump Mode']='Impulse';AngelHub.actions['Long Jump']();assert(root.lastImpulse~=nil)
V['Long Jump Mode']='CFrame';AngelHub.actions['Long Jump']();assert(root.CFrame.Position.X>0)
AngelHub.actions['Teleport To Map']();assert(character.lastPivot.Y==3)
character.lastPivot=nil;AngelHub.actions['Teleport To Lobby']();assert(character.lastPivot.Y==3)
character.lastPivot=nil;AngelHub.actions['Teleport To Player']();assert(character.lastPivot.Y==3)
character.lastPivot=nil;V['Teleport Player Name']='Nobody';AngelHub.actions['Teleport To Player']();assert(not character.lastPivot)
V['Enable Fly']=true;AngelHub.actions['Teleport To Map']();assert(not character.lastPivot);V['Enable Fly']=false
AngelHub.actions['Get Gun']();assert(#touches==2 and touches[1][1]==root and touches[1][2]==gun)
uis.InputBegan:Fire({UserInputType=Enum.UserInputType.Keyboard,KeyCode={Name='G'}},false);assert(#touches==4)
uis.InputBegan:Fire({UserInputType=Enum.UserInputType.Keyboard,KeyCode={Name='G'}},true);assert(#touches==4)
AngelHub.setters['Auto Get Gun'](true);heartbeat:Fire(.25);assert(#touches==6)
AngelHub.getMM2Role=function()return 'Murderer'end;heartbeat:Fire(.25);assert(#touches==6)
AngelHub.getMM2Role=function()return 'Innocent'end;root.Position=Vector3.new(1000,0,0);heartbeat:Fire(.25);assert(#touches==6)
screenGui.Destroying:Fire();heartbeat:Fire(.5);AngelHub.actions['Get Gun']();assert(#touches==6)
