-- Auto Shoot uses Murder independently from Aimbot Custom and does not require Aimbot enabled.
tools.equipped=gunTool;gunTool.Parent=character
V['Aimbot Target']='Custom';V['Target Player']='Nobody'
installGunFeatures(screenGui);AngelHub.setters['Auto Shoot'](true);drain();heartbeat:Fire(.1);drain()
assert(not V['Gun Aimbot'] and #remote.shots==1)
fakeNow+=.2;heartbeat:Fire(.1);drain();assert(#remote.shots==1)
fakeNow+=1;workspace.rayMode='wall';heartbeat:Fire(.1);assert(#remote.shots==1)
V['Shoot Mode']='Instakill';fakeNow+=1;heartbeat:Fire(.1);assert(#remote.shots==1)
-- Muzzle ray may be clear while the near-target silent segment is obstructed.
local oldRay=workspace.Raycast;local rayCount=0
function workspace:Raycast(o,d,p)rayCount+=1;if rayCount==2 then return {Instance=wall}end end
fakeNow+=1;heartbeat:Fire(.1);assert(rayCount==2 and #remote.shots==1);workspace.Raycast=oldRay
V['Shoot WallCheck']=false;fakeNow+=1;heartbeat:Fire(.1);assert(#remote.shots==2)
V['Shoot Proximity']=true;V['Shoot Proximity Aura']=10;fakeNow+=1;heartbeat:Fire(.1);assert(#remote.shots==2)
local radius;for _,v in ipairs(created)do if v.Name=='AngelHubShootRadius'then radius=v end end
assert(radius and radius.Radius==10 and radius.Adornee==root)
V['Shoot Proximity Aura']=30;fakeNow+=1;heartbeat:Fire(.1);assert(#remote.shots==3 and radius.Radius==30)
gunTool.Reloading=true;fakeNow+=2;heartbeat:Fire(.1);assert(#remote.shots==3);gunTool.Reloading=false
AngelHub.setters['Auto Shoot'](false);assert(radius.destroyed)
fakeNow+=2;heartbeat:Fire(.1);drain();assert(#remote.shots==3)
-- Knife Aura activates the equipped knife, waits and sends HandleTouched to a nearby living target.
local hit={calls={}};function hit:IsA(n)return n=='RemoteEvent'end;function hit:FireServer(v)table.insert(self.calls,v)end
local events={};function events:FindFirstChild(n)if n=='HandleTouched'then return hit end end
local handle={};function handle:IsA(n)return n=='BasePart'end
local blade={Name='Knife',Enabled=true,Parent=character,activations=0}
function blade:IsA(n)return n=='Tool'end
function blade:GetAttribute(n)return self[n]end
function blade:FindFirstChild(n)if n=='Handle'then return handle elseif n=='Events'then return events end end
function blade:Activate()self.activations+=1 end
local oldFindChar=character.FindFirstChild
function character:FindFirstChild(n)if n=='Knife'then return blade end;return oldFindChar(self,n)end
tools.equipped=nil;enemy.knife=nil;targetRoot.Position=Vector3.new(10,0,0)
AngelHub.setters['Knife Aura'](true);drain();heartbeat:Fire(.1);assert(blade.activations==1);drain();assert(#hit.calls==1 and hit.calls[1]==targetRoot)
fakeNow+=1;heartbeat:Fire(.1);assert(blade.activations==2)
AngelHub.setters['Knife Aura'](false);drain();assert(#hit.calls==1)
fakeNow+=1;heartbeat:Fire(.1);assert(blade.activations==2)
-- Hold mode starts only on a non-processed game input and stops on release.
V['Knife Hold Mouse']=true;AngelHub.setters['Knife Aura'](true);drain();heartbeat:Fire(.1);assert(blade.activations==2)
local press={UserInputType=mobile and Enum.UserInputType.Touch or Enum.UserInputType.MouseButton1}
userInputService.InputBegan:Fire(press,true);drain();assert(blade.activations==2)
userInputService.InputBegan:Fire(press,false);drain();assert(blade.activations==3 and #hit.calls==2)
userInputService.InputEnded:Fire(press);fakeNow+=2;heartbeat:Fire(.1);drain();assert(blade.activations==3)
AngelHub.setters['Knife Aura'](false);screenGui.Destroying:Fire();fakeNow+=2;heartbeat:Fire(.1);assert(blade.activations==3 and #remote.shots==3)
