installGunFeatures(screenGui)
assert(ws.GetMouseTargetCFrame==originalA and ws.GetTargetPosition==originalB)
assert(#thrown.shots==0)
AngelHub.setters['Knife Throw'](true)
assert(ws.GetMouseTargetCFrame~=originalA and ws.GetTargetPosition~=originalB)
local cf,extra=ws:GetMouseTargetCFrame();assert(typeof(cf)=='CFrame' and cf.Position.X>=20 and extra=='other')
local point,extra2=ws:GetTargetPosition();assert(typeof(point)=='Vector3' and point.X>=20 and extra2=='other')
assert(wsOriginalCalls==2)
workspace.rayMode='wall';cf=ws:GetMouseTargetCFrame();assert(cf.Position.X==-1)
AngelHub.setters['Throw WallCheck'](false);cf=ws:GetMouseTargetCFrame();assert(cf.Position.X>=20)
heldKnife.Parent=backpack;cf=ws:GetMouseTargetCFrame();assert(cf.Position.X==-1)
heldKnife.Parent=character
local replacement=function()return 'new hook'end
ws.GetMouseTargetCFrame=replacement
AngelHub.setters['Knife Throw'](false)
assert(ws.GetMouseTargetCFrame==replacement and rawget(ws,'GetTargetPosition')==nil and ws.GetTargetPosition==originalB)
-- The automatic action is independent of manual redirect, only sends with an equipped knife.
AngelHub.setters['Throw WallCheck'](true)
AngelHub.setters['Auto Knife Throw'](true);fakeNow+=2;heartbeat:Fire(.1);assert(#thrown.shots==0)
AngelHub.setters['Throw WallCheck'](false);fakeNow+=2;heartbeat:Fire(.1)
assert(#thrown.shots==1 and thrown.shots[1][2].Position.X>=20)
heldKnife.Parent=backpack;fakeNow+=2;heartbeat:Fire(.1);assert(#thrown.shots==1)
AngelHub.setters['Auto Knife Throw'](false);screenGui.Destroying:Fire()
assert(ws.GetMouseTargetCFrame==replacement and rawget(ws,'GetTargetPosition')==nil)
