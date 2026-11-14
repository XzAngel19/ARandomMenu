V['Self HP']=false;V['Self HP Position']='Center';V['Self HP Scale']=1
AngelHub.setters['Self HP']=function(v)V['Self HP']=v end
Color3={fromRGB=function(r,g,b)return {r,g,b}end};UDim2.new=function(...)return {...}end
character.Parent=workspace;humanoid.MaxHealth=100;humanoid.Health=75;camera.ViewportSize=Vector2.new(800,600)
local function find(n)for i=#created,1,-1 do if created[i].Name==n then return created[i]end end end
installGameplay(screenGui);heartbeat:Fire(.2);assert(not find('AngelHubSelfHP'))
AngelHub.setters['Self HP'](true);heartbeat:Fire(.2)
local label=find('AngelHubSelfHP');local scale=created[#created]
assert(label and label.Visible and label.Text=='75 ♥' and scale.class=='UIScale' and scale.Scale==1)
assert(label.Position[1]==.5 and label.Position[3]==.5)
humanoid.Health=10;V['Self HP Position']='Bottom';V['Self HP Scale']=1.6;heartbeat:Fire(.2)
assert(label.Text=='10 ♥' and label.Position[3]==1 and scale.Scale==1.6)
camera.ViewportSize=Vector2.new(100,100);heartbeat:Fire(.2);assert(scale.Scale<.8)
humanoid.Health=0;heartbeat:Fire(.2);assert(label.Text=='0 ♥')
character.Parent=nil;heartbeat:Fire(.2);assert(not label.Visible)
character.Parent=workspace;humanoid.Health=100;heartbeat:Fire(.2);assert(label.Visible)
AngelHub.setters['Self HP'](false);assert(label.destroyed)
AngelHub.setters['Self HP'](true);heartbeat:Fire(.2);label=find('AngelHubSelfHP');screenGui.Destroying:Fire();assert(label.destroyed)
