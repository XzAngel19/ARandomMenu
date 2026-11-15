-- Native WeaponService may arrive after the feature was enabled.
local available=false
function folder:FindFirstChild(n)if n=='WeaponService' and available then return weaponService end end
local status='';AngelHub.setThrowStatus=function(s)status=s end
installGunFeatures(screenGui)
AngelHub.setters['Knife Throw'](true)
assert(ws.GetMouseTargetCFrame==originalA and status:find('esperando'))
heartbeat:Fire(.1);assert(ws.GetMouseTargetCFrame==originalA)
available=true;fakeNow+=1.1;heartbeat:Fire(.1)
assert(ws.GetMouseTargetCFrame~=originalA and status:find('preparada'))
local cf=ws:GetMouseTargetCFrame();assert(cf.Position.X>=20)
AngelHub.setters['Knife Throw'](false);assert(ws.GetMouseTargetCFrame==originalA)
screenGui.Destroying:Fire();fakeNow+=2;heartbeat:Fire(.1);assert(ws.GetMouseTargetCFrame==originalA)
