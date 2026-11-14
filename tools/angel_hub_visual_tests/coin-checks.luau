AngelHub.moduleNames['Coin ESP']=true;V['Coin ESP']=false;AngelHub.setters['Coin ESP']=function(v)V['Coin ESP']=v end
V['Coin Colour']={r=1};V['Coin Transparency']=.2;V['Coin In Use']='Auto (Server)'
local started={OnClientEvent=event()};function started:IsA(c)return c=='RemoteEvent'end
local ended={OnClientEvent=event()};function ended:IsA(c)return c=='RemoteEvent'end
local gameplay={};function gameplay:FindFirstChild(n)return ({CoinsStarted=started,RoundEndFade=ended})[n]end
local remotes={};function remotes:FindFirstChild(n)if n=='Gameplay'then return gameplay end end
local storage={};function storage:FindFirstChild(n)if n=='Remotes'then return remotes end end
services.ReplicatedStorage=storage
local server={Name='Coin_Server',Parent=map,attributes={}};function server:IsA(c)return c=='BasePart'end
function server:GetAttribute(n)return self.attributes[n]end
function server:FindFirstChildOfClass()return nil end
function server:IsDescendantOf(o)return o==map or o==workspace end
local visual={Name='CoinVisual',Parent=server,Size=Vector3.new(2,1,2),attributes={},descendants={}}
function visual:IsA(c)return c=='BasePart'end
function visual:GetAttribute(n)return self.attributes[n]end
function visual:IsDescendantOf(o)return o==map or o==workspace end
function visual:GetDescendants()return self.descendants end
function server:FindFirstChild(n)if n=='CoinVisual'then return visual end end
map.descendants={server,visual}
local decoration={Name='CoinStatue',Parent=map};function decoration:IsA(c)return c=='BasePart'end
function decoration:GetAttribute()return nil end
table.insert(map.descendants,decoration)
installCoinESP(screenGui)
AngelHub.setters['Coin ESP'](true);heartbeat:Fire(.1)
local box=created[#created];assert(box.class=='BoxHandleAdornment' and box.Adornee==visual and box.Transparency==.2 and box.Size.X==2.6)
started.OnClientEvent:Fire({Candy=1});heartbeat:Fire(.1);assert(not box.destroyed)
V['Coin In Use']='Coin';heartbeat:Fire(1);assert(box.destroyed)
V['Coin In Use']='Candy';heartbeat:Fire(1);box=created[#created];assert(box.Adornee==visual and not box.destroyed)
server.attributes.Collected=true;heartbeat:Fire(1);assert(box.destroyed)
server.attributes.Collected=false;heartbeat:Fire(1);box=created[#created];assert(not box.destroyed)
AngelHub.setters['Coin ESP'](false);assert(box.destroyed)
for _,c in ipairs(started.OnClientEvent.callbacks)do assert(not c.alive)end
AngelHub.setters['Coin ESP'](true);heartbeat:Fire(.1);box=created[#created]
screenGui.Destroying:Fire();assert(box.destroyed)
