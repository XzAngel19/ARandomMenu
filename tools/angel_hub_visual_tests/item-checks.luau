setting('Gun ESP',false);setting('Trap ESP',false)
V['Item Max Distance']=100;V['Item Text Size']=13;V['Item Outline']=true;V['Item Show Distance']=true
Enum.Font={SourceSansBold='bold'}
AngelHub.findMM2DroppedGun=function()return gun end
installItemESP(screenGui)
AngelHub.setters['Gun ESP'](true)
local function find(name,last)
 local found;for _,v in ipairs(created)do if v.Name==name and not v.destroyed then found=v;if not last then return v end end end;return found
end
local hi=find('AngelHubItemOutline');local bill=find('AngelHubItemLabel')
assert(hi and bill and hi.Adornee==gun and bill.Adornee==gun and hi.Enabled and bill.Enabled)
V['Item Max Distance']=5;heartbeat:Fire(.3);assert(not hi.Enabled and not bill.Enabled)
AngelHub.setters['Gun ESP'](false);assert(hi.destroyed and bill.destroyed)
AngelHub.setters['Trap ESP'](true);heartbeat:Fire(.3)
local th=find('AngelHubItemOutline',true);local tb=find('AngelHubItemLabel',true)
assert(th and tb and th.Adornee==trap and trap.Transparency==.35)
trap.Transparency=.8;AngelHub.setters['Trap ESP'](false);assert(th.destroyed and tb.destroyed and trap.Transparency==.8)
trap.Transparency=1;AngelHub.setters['Trap ESP'](true);assert(trap.Transparency==.35)
th=find('AngelHubItemOutline',true);screenGui.Destroying:Fire();assert(th.destroyed and trap.Transparency==1)
