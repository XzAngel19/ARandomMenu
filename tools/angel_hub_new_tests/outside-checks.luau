game.PlaceId=1;tools.equipped=gunTool;gunTool.Parent=character
installGunFeatures(screenGui)
AngelHub.setters['Gun Aimbot'](true);AngelHub.setters['Gun Aura'](true);drain()
assert(not V['Gun Aimbot'] and not V['Gun Aura'])
userInputService.InputBegan:Fire(key,false);heartbeat:Fire(.2);drain()
assert(#remote.shots==0 and #touches==0)
screenGui.Destroying:Fire()
