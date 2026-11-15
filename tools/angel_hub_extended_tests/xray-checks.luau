V['X-Ray']=false;V['XRay Transparency']=.5;AngelHub.setters['X-Ray']=function(v)V['X-Ray']=v end
wall.LocalTransparencyModifier=.1
local dynamic={Parent=workspace,Anchored=false,Transparency=0,LocalTransparencyModifier=0};function dynamic:IsA(c)return c=='BasePart'end;function dynamic:IsDescendantOf(o)return o==workspace end
table.insert(workspace.objects,dynamic)
installXRay(screenGui);heartbeat:Fire(.3);assert(wall.LocalTransparencyModifier==.1)
AngelHub.setters['X-Ray'](true);heartbeat:Fire(.3)
assert(wall.LocalTransparencyModifier==.5 and dynamic.LocalTransparencyModifier==0)
local streamed={Parent=workspace,Anchored=true,Transparency=0,LocalTransparencyModifier=.2}
function streamed:IsA(c)return c=='BasePart'end;function streamed:IsDescendantOf(o)return o==workspace end
workspace.DescendantAdded:Fire(streamed);heartbeat:Fire(.3);assert(streamed.LocalTransparencyModifier==.5)
V['XRay Transparency']=.8;heartbeat:Fire(.3);assert(wall.LocalTransparencyModifier==.8)
wall.LocalTransparencyModifier=.25;heartbeat:Fire(.3);assert(wall.LocalTransparencyModifier==.8)
AngelHub.setters['X-Ray'](false);assert(wall.LocalTransparencyModifier==.25 and streamed.LocalTransparencyModifier==.2)
AngelHub.setters['X-Ray'](true);heartbeat:Fire(.3);assert(wall.LocalTransparencyModifier==.8)
screenGui.Destroying:Fire();assert(wall.LocalTransparencyModifier==.25)
