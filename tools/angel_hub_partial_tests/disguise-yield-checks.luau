local queue={};task.spawn=function(f)table.insert(queue,f)end
local remoteDesc
function playersService:GetHumanoidDescriptionFromUserId(id)
 coroutine.yield('lookup');local desc={WalkAnimation=456};function desc:Destroy()self.destroyed=true end;remoteDesc=desc;return desc
end
local function takePending(label)
 local q=queue;queue={};local result
 for _,fn in ipairs(q)do local co=coroutine.create(fn);local ok,value=coroutine.resume(co);assert(ok);if value==label then result=co end end
 assert(result);return result
end
installGameplay(screenGui);AngelHub.setters['Disguise Character'](true);heartbeat:Fire(.21)
local pending=takePending('lookup');AngelHub.setters['Disguise Character'](false)
assert(coroutine.resume(pending));assert(remoteDesc.destroyed and #models==0 and shirt.Parent==owner)
-- A changed ID invalidates a response immediately, even before the debounce step.
AngelHub.setters['Disguise Character'](true);heartbeat:Fire(.21);pending=takePending('lookup')
V['Disguise Target ID']='999';assert(coroutine.resume(pending));assert(remoteDesc.destroyed and #models==0 and shirt.Parent==owner)
AngelHub.setters['Disguise Character'](false)
-- A staged model returned after disabling must be destroyed without touching the avatar.
function playersService:GetHumanoidDescriptionFromUserId(id)
 local d={WalkAnimation=456};function d:Destroy()self.destroyed=true end;remoteDesc=d;return d
end
local staged
function playersService:CreateHumanoidModelFromDescription()
 coroutine.yield('stage');staged=node('Model','Staged');return staged
end
queue={};AngelHub.setters['Disguise Character'](true);heartbeat:Fire(.21);pending=takePending('stage')
AngelHub.setters['Disguise Character'](false);assert(coroutine.resume(pending));assert(remoteDesc.destroyed and staged.destroyed and shirt.Parent==owner)
-- Failed lookups and model creation leave the original appearance untouched.
function playersService:GetHumanoidDescriptionFromUserId()error('lookup error')end
queue={};AngelHub.setters['Disguise Character'](true);heartbeat:Fire(.21)
for _,fn in ipairs(queue)do assert(pcall(fn))end;queue={};assert(shirt.Parent==owner)
AngelHub.setters['Disguise Character'](false)
function playersService:GetHumanoidDescriptionFromUserId()local d={};function d:Destroy()self.destroyed=true end;remoteDesc=d;return d end
function playersService:CreateHumanoidModelFromDescription()error('model error')end
AngelHub.setters['Disguise Character'](true);heartbeat:Fire(.21)
for _,fn in ipairs(queue)do assert(pcall(fn))end;assert(remoteDesc.destroyed and shirt.Parent==owner)
AngelHub.setters['Disguise Character'](false)
-- An exception while cloning rolls back originals that were already detached.
function playersService:CreateHumanoidModelFromDescription()
 local m=node('Model','Staged');local item=node('Shirt','Bad');item.Parent=m
 return m
end
methods.Clone=function(self)if self.Name=='Bad'then error('clone failed')end end
queue={};AngelHub.setters['Disguise Character'](true);heartbeat:Fire(.21)
for _,fn in ipairs(queue)do assert(pcall(fn))end
assert(shirt.Parent==owner and accessory.Parent==owner and face.Parent==ownHead)
screenGui.Destroying:Fire()
