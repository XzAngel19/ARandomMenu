local cm={};cm.__index=cm
function cm:Lerp(other,t)return setmetatable({R=self.R+(other.R-self.R)*t,G=self.G+(other.G-self.G)*t,B=self.B+(other.B-self.B)*t},cm)end
Color3={fromRGB=function(r,g,b)return setmetatable({R=r/255,G=g/255,B=b/255},cm)end}
Enum.HumanoidRigType={R6='R6',R15='R15'}
run.RenderStepped=event();playersService.PlayerRemoving=event()
for _,name in ipairs({'Player ESP','Nametags','HP Players','Self HP','Chams'})do setting(name,false) end
V['Nametag Max Distance']=1000;V['Display Name']=true;V['Nametag Through Walls']=true;V['Show Role']=true
V['Role Colours']=true;V['Murderer ESP']=true;V['Sheriff ESP']=true
local red=Color3.fromRGB(255,70,70);local blue=Color3.fromRGB(70,160,255)
V['Murderer Colour']=red;V['Sheriff Colour']=blue
root.Position=Vector3.zero;root.Size=Vector3.new(2,2,1);root.Parent=character;character.Parent=workspace
humanoid.MaxHealth=100;targetRoot.Parent=enemy;targetRoot.Size=Vector3.new(2,2,1)
enemyHumanoid.HipHeight=2;enemyHumanoid.RigType='R15';enemy.knife=nil
camera.ViewportSize=Vector2.new(800,600);camera.CFrame={Position=Vector3.zero}
function camera:WorldToViewportPoint(v)return {X=400+v.X*5,Y=300-v.Y*10,Z=20}end
local events={}
for _,name in ipairs({'PlayerDataChanged','RoundStart','RoundEndFade'})do local e={OnClientEvent=event()};function e:IsA(c)return c=='RemoteEvent'end;events[name]=e end
local fetch={};local calls=0;function fetch:IsA(c)return c=='RemoteFunction'end
function fetch:InvokeServer()calls+=1;return {Alice={Name='Alice',Role='Murderer'}}end
events.GetCurrentPlayerData=fetch
local g={};function g:FindFirstChild(n)return events[n]end
local remotes={};function remotes:FindFirstChild(n)if n=='Gameplay'then return g end end
local storage={};function storage:FindFirstChild(n)if n=='Remotes'then return remotes end end
services.ReplicatedStorage=storage
installGunFeatures(screenGui);installPlayerVisuals(screenGui)
AngelHub.setters['Nametags'](true);drain();run.RenderStepped:Fire(.1)
local label,detail;for _,x in ipairs(created)do if x.Name=='Name'then label=x elseif x.Name=='Details'then detail=x end end
assert(calls==1 and label.TextColor3==red and detail.Text=='Murderer')
events.PlayerDataChanged.OnClientEvent:Fire({Alice={Name='Alice',Role='Sheriff'}})
run.RenderStepped:Fire(.1);assert(label.TextColor3==blue and detail.Text=='Sheriff')
events.RoundEndFade.OnClientEvent:Fire();run.RenderStepped:Fire(.1);assert(label.TextColor3~=blue and not detail.Visible)
AngelHub.setters['Nametags'](false);screenGui.Destroying:Fire()
for _,e in pairs(events)do if e.OnClientEvent then for _,c in ipairs(e.OnClientEvent.callbacks)do assert(not c.alive)end end end
