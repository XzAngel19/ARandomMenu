Color3={fromRGB=function(...)return {...}end}
for _,name in ipairs({'Gun Aura','Auto Get Gun'})do AngelHub.moduleNames[name]=true;V[name]=false;AngelHub.setters[name]=function(v)V[name]=v end end
V['Gun Aura Studs']=50;V['Gun Aura Show Hitbox']=true
gun.CFrame={Position=gun.Position};gun.CanCollide=true
local original=gun.CFrame;root.CFrame={Position=root.Position}
local warnText;warn=function(x)warnText=x end;installGameplay(screenGui)
AngelHub.setters['Gun Aura'](true);heartbeat:Fire(.11)
assert(#touches==2 and gun.CFrame==root.CFrame and not gun.CanCollide, tostring(warnText)..' touches='..#touches..' enabled='..tostring(V['Gun Aura']))
assert(created[#created].class=='SphereHandleAdornment' and created[#created].Radius==50)
AngelHub.setters['Gun Aura'](false);assert(gun.CFrame==original and gun.CanCollide and created[#created].destroyed)
-- Automatic touch does not move the drop or the player.
AngelHub.setters['Auto Get Gun'](true);local before=#touches;heartbeat:Fire(.31)
assert(#touches==before+2 and gun.CFrame==original and character.lastPivot==nil)
-- A lobby character never touches or moves a drop.
root.Position=Vector3.new(1000,0,0);before=#touches;heartbeat:Fire(.4);assert(#touches==before)
AngelHub.setters['Auto Get Gun'](false);root.Position=Vector3.new(0,0,0)
AngelHub.setters['Gun Aura'](true);heartbeat:Fire(.11);assert(gun.CFrame==root.CFrame)
-- Don't overwrite external changes made while aura is on.
local external={Position=Vector3.new(8,0,0)};gun.CFrame=external;gun.CanCollide=true
AngelHub.setters['Gun Aura'](false);assert(gun.CFrame==external and gun.CanCollide)
gun.CFrame=original;AngelHub.setters['Gun Aura'](true);heartbeat:Fire(.11)
screenGui.Destroying:Fire();assert(gun.CFrame==original and gun.CanCollide)
