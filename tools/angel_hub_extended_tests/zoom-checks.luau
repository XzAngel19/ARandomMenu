AngelHub.setters['Zoom Through Walls']=function(v)V['Zoom Through Walls']=v end
local original=function()end
local module={Update=original,on=true}
function module:GetEnabled()return self.on end
function module:Enable(value)self.on=value end
local cameras={activeOcclusionModule=module}
local playerModule={data={GetCameras=function()return cameras end}}
function playerModule:FindFirstChild()return nil end
local scripts={};function scripts:FindFirstChild(n)if n=='PlayerModule'then return playerModule end end
local oldFind=localPlayer.FindFirstChildOfClass
function localPlayer:FindFirstChild(n)if n=='PlayerScripts'then return scripts end end
local queue={};task.spawn=function(f)table.insert(queue,f)end
local function drain()local q=queue;queue={};for _,f in ipairs(q)do f()end end
installZoomThroughWalls(screenGui)
AngelHub.setters['Zoom Through Walls'](true);assert(#queue==1)
AngelHub.setters['Zoom Through Walls'](false);drain();assert(module.Update==original and module.on)
AngelHub.setters['Zoom Through Walls'](true);drain();assert(module.Update~=original and not module.on)
local instance={};function instance:Cleanup()self.cleaned=true end
local a,b=module.Update(instance,0,'camera','focus');assert(a=='camera' and b=='focus' and instance.cleaned)
AngelHub.setters['Zoom Through Walls'](false);assert(module.Update==original and module.on)
AngelHub.setters['Zoom Through Walls'](true);drain();local foreign=function()end;module.Update=foreign
AngelHub.setters['Zoom Through Walls'](false);assert(module.Update==foreign)
module.Update=original;module.on=true
AngelHub.setters['Zoom Through Walls'](true);drain();screenGui.Destroying:Fire();assert(module.Update==original and module.on)
