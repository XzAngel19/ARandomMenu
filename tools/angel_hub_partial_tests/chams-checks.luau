AngelHub.moduleNames['Chams']=true;V['Chams']=false;AngelHub.setters['Chams']=function(v)V['Chams']=v end
V['Chams Fill Colour']='fill';V['Chams Outline Colour']='outline';V['Chams Fill Transparency']=.4
V['Chams Outline Transparency']=.1;V['Chams Through Walls']=true
V['Role Colours']=true;V['Murderer Colour']='red';V['Sheriff Colour']='blue';V['Dead Colour']='grey'
V['Murderer ESP']=true;V['Sheriff ESP']=true;V['Dead ESP']=false;V['Innocent ESP']=false
Enum.HighlightDepthMode.Occluded='occluded'
localPlayer.Name='Me';localPlayer.UserId=1;other.UserId=2
local human={Health=100};local enemy={Parent=workspace}
function enemy:IsDescendantOf(w)return self.Parent==w end
function enemy:FindFirstChildOfClass(n)if n=='Humanoid'then return human end end
other.Character=enemy
local data={Alice={Name='Alice',Role='Murderer'}}
local remote={};function remote:IsA(c)return c=='RemoteFunction'end
function remote:InvokeServer()return data end
local changed={OnClientEvent=event()};function changed:IsA(c)return c=='RemoteEvent'end
local gameplay={};function gameplay:FindFirstChild(n)return ({GetCurrentPlayerData=remote,PlayerDataChanged=changed})[n]end
local remotes={};function remotes:FindFirstChild(n)if n=='Gameplay'then return gameplay end end
local storage={};function storage:FindFirstChild(n)if n=='Remotes'then return remotes end end
services.ReplicatedStorage=storage
installGameplay(screenGui);heartbeat:Fire(.21);assert(#created==0)
AngelHub.setters['Chams'](true);heartbeat:Fire(.21);heartbeat:Fire(.21)
local highlight=created[#created];assert(highlight.class=='Highlight' and highlight.Adornee==enemy and highlight.FillColor=='red' and highlight.OutlineColor=='red' and highlight.DepthMode=='ontop')
-- Role provider still runs when all notifications are off.
changed.OnClientEvent:Fire({Alice={Name='Alice',Role='Sheriff'}});heartbeat:Fire(.21);heartbeat:Fire(.21)
assert(highlight.FillColor=='blue')
V['Role Colours']=false;V['Chams Through Walls']=false;heartbeat:Fire(.21)
assert(highlight.FillColor=='fill' and highlight.OutlineColor=='outline' and highlight.DepthMode=='occluded')
human.Health=0;heartbeat:Fire(.21);assert(highlight.destroyed)
V['Dead ESP']=true;heartbeat:Fire(.21);highlight=created[#created];assert(not highlight.destroyed)
AngelHub.setters['Chams'](false);assert(highlight.destroyed)
-- Universal teammate filtering and team colors.
isMM2=false;human.Health=100;local team={TeamColor={Color='green'}};localPlayer.Team=team;other.Team=team
localPlayer.Neutral=false;other.Neutral=false;V['Chams Teammates']=false;AngelHub.setters['Chams'](true);heartbeat:Fire(.21)
local prior=#created;assert(created[prior].destroyed)
V['Chams Teammates']=true;V['Chams Team Colours']=true;heartbeat:Fire(.21);highlight=created[#created];assert(highlight.FillColor=='green')
other.Character.Parent=nil;heartbeat:Fire(.21);assert(highlight.destroyed)
screenGui.Destroying:Fire();for _,c in ipairs(changed.OnClientEvent.callbacks)do assert(not c.alive)end
