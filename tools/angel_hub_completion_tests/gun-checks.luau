tools.equipped=gunTool;gunTool.Parent=character
local gunStatus='';AngelHub.setGunStatus=function(s)gunStatus=s end
function run.Heartbeat:Wait()return .016 end
installGunFeatures(screenGui)
userInputService.InputBegan:Fire(key,false);drain();assert(#remote.shots==0)
AngelHub.setters['Gun Aimbot'](true);drain();assert(V['Gun Aimbot'] and gunStatus:find('hook nativo no disponible'))
local button;for _,v in ipairs(created)do if v.Name=='AngelHubGunFire'then button=v end end
if mobile then assert(button and button.Visible)else assert(not button)end
local function fire()if mobile then button.Activated:Fire()else userInputService.InputBegan:Fire(key,false)end;drain()end
heartbeat:Fire(.1);fire();assert(#remote.shots==1 and gunStatus:find('sin confirmar'))
assert(remote.shots[1][1].Position==attachment.WorldCFrame.Position and remote.shots[1][2].Position.X>20)
fakeNow+=1;heartbeat:Fire(.1);workspace.rayMode='wall';fire();assert(#remote.shots==1)
V['Aim Method']='Instakill';fakeNow+=1;heartbeat:Fire(.1);fire();assert(#remote.shots==1)
V['WallCheck']=false;fakeNow+=1;heartbeat:Fire(.1);fire();assert(#remote.shots==2 and remote.shots[2][1].Position.X<20 and remote.shots[2][2].Position.X>20)
V['Aimbot Target']='Custom';V['Target Player']='Nobody';fakeNow+=1;heartbeat:Fire(.1);fire();assert(#remote.shots==2)
V['Target Player']='Alice';enemy.knife=nil;fakeNow+=1;heartbeat:Fire(.1);fire();assert(#remote.shots==3 and gunStatus:find('sin confirmar'))
if not mobile then
 V['Aimbot Keybind Value']='MouseButton2';fakeNow+=1;heartbeat:Fire(.1)
 userInputService.InputBegan:Fire({UserInputType=Enum.UserInputType.MouseButton2},false);drain();assert(#remote.shots==4)
 V['Aimbot Keybind Value']='Q'
 userInputService.InputBegan:Fire(key,true);drain();assert(#remote.shots==4)
 AngelHub.listening=function()end;userInputService.InputBegan:Fire(key,false);drain();assert(#remote.shots==4);AngelHub.listening=nil
 userInputService.focused={};userInputService.InputBegan:Fire(key,false);drain();assert(#remote.shots==4);userInputService.focused=nil
end
local beforeReload=#remote.shots
gunTool.Reloading=true;fakeNow+=1;heartbeat:Fire(.1);fire();assert(#remote.shots==beforeReload);gunTool.Reloading=false
V['Macro']=true;fakeNow+=1;heartbeat:Fire(.1);fire();assert(#remote.shots==beforeReload+1 and gunTool.Parent==backpack)
V['Macro']=false;gunTool.Parent=character
AngelHub.setters['Gun Aimbot'](false);fakeNow+=1;heartbeat:Fire(.1);fire();assert(#remote.shots==beforeReload+1)
if mobile then assert(not button.Visible)end
-- A delayed equip/shot cannot finish after the module was disabled.
tools.equipped=nil;tools.Gun=gunTool;gunTool.Parent=backpack
AngelHub.setters['Gun Aimbot'](true);fakeNow+=1
if mobile then button.Activated:Fire()else userInputService.InputBegan:Fire(key,false)end
AngelHub.setters['Gun Aimbot'](false);drain();assert(#remote.shots==beforeReload+1 and gunTool.Parent==backpack and tools.equipped==nil)
-- Aura uses Wurst scanning, range, visual, touch, and restoration.
tools.Gun=nil
local original=gun.CFrame
AngelHub.setters['Gun Aura'](true);drain();heartbeat:Fire(.2);drain()
assert(V['Gun Aura'] and gun.CFrame==root.CFrame and not gun.CanCollide and #touches>=2)
AngelHub.setters['Gun Aura'](false);assert(gun.CFrame==original and gun.CanCollide)
-- An equipped gun prevents pickup and an externally changed position is not overwritten.
tools.equipped=gunTool;gunTool.Parent=character
local touchesBefore=#touches;fakeNow+=1;AngelHub.setters['Gun Aura'](true);drain();heartbeat:Fire(.2);drain();assert(#touches==touchesBefore)
AngelHub.setters['Gun Aura'](false);tools.equipped=nil;gunTool.Parent=backpack
fakeNow+=1;AngelHub.setters['Gun Aura'](true);drain();heartbeat:Fire(.2);drain()
local external=CFrame.new(Vector3.new(99,0,0));gun.CFrame=external
AngelHub.setters['Gun Aura'](false);assert(gun.CFrame==external and gun.CanCollide)
gun.CFrame=original
AngelHub.setters['Gun Aura Show Hitbox'](true);fakeNow+=1;AngelHub.setters['Gun Aura'](true);drain();heartbeat:Fire(.2);drain()
local box;for _,v in ipairs(created)do if v.Name=='WurstGunAuraHitbox'then box=v end end
assert(box and box.Parent==workspace and box.Size.X==50)
AngelHub.setters['Gun Aura Studs'](20);fakeNow+=1;heartbeat:Fire(.2);drain();assert(box.Size.X==20)
AngelHub.setters['Gun Aura'](false);assert(box.destroyed and gun.CFrame==original)
-- The key can equip a backpack gun and send after the equip frame.
tools.equipped=nil;tools.Gun=gunTool;gunTool.Parent=backpack
AngelHub.setters['Gun Aimbot'](true);fakeNow+=2;heartbeat:Fire(.1);fire()
assert(gunTool.Parent==character and #remote.shots==beforeReload+2 and gunStatus:find('sin confirmar'))
AngelHub.setters['Gun Aimbot'](false)
screenGui.Destroying:Fire();fakeNow+=1;userInputService.InputBegan:Fire(key,false);drain();assert(#remote.shots==beforeReload+2)
