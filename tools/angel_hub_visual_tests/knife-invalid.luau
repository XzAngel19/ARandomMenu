installGunFeatures(screenGui)
local test=AngelHub._knifeTest
AngelHub.setters['Throw WallCheck'](false)
local origin=Vector3.zero
-- Predictor errors and non-finite points take the safe kinematic fallback.
test.prediction.knifeAim=function() error('unavailable')end
local aim,flight=test.resolve(other,origin,heldKnife)
assert(aim and aim.X>=20 and flight==flight)
test.prediction.knifeAim=function() return Vector3.new(0/0,0,0) end
aim,flight=test.resolve(other,origin,heldKnife)
assert(aim and aim.X>=20 and flight==flight)
test.prediction.knifeAim=function() return Vector3.new(20,0,0),{flightSeconds=0/0} end
aim,flight=test.resolve(other,origin,heldKnife)
assert(aim and flight==flight and flight>0)
-- Invalid position must never reach CFrame or be sent.
targetRoot.Position=Vector3.new(0/0,0,0)
test.prediction.knifeAim=function()error('unavailable')end
assert(test.resolve(other,origin,heldKnife)==nil)
screenGui.Destroying:Fire()
