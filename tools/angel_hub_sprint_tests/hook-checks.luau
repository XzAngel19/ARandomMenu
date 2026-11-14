local originalCalls={}
local function base(remote,...)table.insert(originalCalls,{remote,...});return 'sent'end
local current=base
hookmetamethod=function(_,_,next)local old=current;current=next;return old end
getnamecallmethod=function()return 'FireServer'end
local executor=false;checkcaller=function()return executor end
local incomingA=CFrame.new(Vector3.new(0,0,0));local incomingB=CFrame.new(Vector3.new(3,0,0))
tools.equipped=gunTool;gunTool.Parent=character
installGunFeatures(screenGui)
-- The feature does not install a hook at boot or act while disabled.
assert(current==base);userInputService.InputBegan:Fire(key,false);drain();assert(#remote.shots==0)
AngelHub.setters['Gun Aimbot'](true);drain();heartbeat:Fire(.1)
local ourHook=current;assert(ourHook~=base)
local unrelated={Name='Unrelated',__type='Instance'}
local oldBackpackLookup=localPlayer.FindFirstChildOfClass;local lookups=0
function localPlayer:FindFirstChildOfClass(n)lookups+=1;return oldBackpackLookup(self,n)end
current(unrelated,incomingA,incomingB);assert(lookups==0);table.clear(originalCalls)
assert(current(remote,incomingA,incomingB)=='sent' and #originalCalls==1)
assert(originalCalls[1][2].Position==attachment.WorldCFrame.Position and originalCalls[1][3].Position.X>20)
executor=true;current(remote,incomingA,incomingB);assert(originalCalls[2][2]==incomingA)
executor=false;workspace.rayMode='wall';current(remote,incomingA,incomingB);assert(originalCalls[3][2]==incomingA)
workspace.rayMode='clear'
-- Another script's later hook is not removed during unload/disable.
local function thirdParty(obj,...)return ourHook(obj,...)end
current=thirdParty;AngelHub.setters['Gun Aimbot'](false);assert(current==thirdParty)
current(remote,incomingA,incomingB);assert(originalCalls[4][2]==incomingA)
fakeNow+=1;AngelHub.setters['Gun Aimbot'](true);drain();heartbeat:Fire(.1)
current(remote,incomingA,incomingB);assert(originalCalls[5][3].Position.X>20)
screenGui.Destroying:Fire();assert(current==thirdParty)
current(remote,incomingA,incomingB);assert(originalCalls[6][2]==incomingA)
