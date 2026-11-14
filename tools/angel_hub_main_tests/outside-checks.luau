game.PlaceId=1;tools.equipped=gunTool;gunTool.Parent=character
installGunFeatures(screenGui)
AngelHub.setters['Gun Aimbot'](true);AngelHub.setters['Gun Aura'](true);AngelHub.setters['Auto Shoot'](true);AngelHub.setters['Knife Aura'](true);drain()
assert(not V['Gun Aimbot'] and not V['Gun Aura'] and not V['Auto Shoot'] and not V['Knife Aura'])
userInputService.InputBegan:Fire(key,false);heartbeat:Fire(.2);drain()
assert(#remote.shots==0 and #touches==0)
screenGui.Destroying:Fire()
