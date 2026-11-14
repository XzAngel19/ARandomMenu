local function setting(name,value)V[name]=value;AngelHub.setters[name]=function(v)V[name]=v end end
AngelHub.moduleNames['Auto Vote']=true;setting('Auto Vote',false)
setting('Select Map','Waiting for maps')
local selectedOptions={}
AngelHub.cycleOptions={['Select Map']=function(items)
 selectedOptions=items
 if not table.find(items,V['Select Map']) then V['Select Map']=items[1] or 'Waiting for maps' end
end}
local started={OnClientEvent=event()};function started:IsA(c)return c=='RemoteEvent'end
local ended={OnClientEvent=event()};function ended:IsA(c)return c=='RemoteEvent'end
local gameplay={};function gameplay:FindFirstChild(n)return ({RoundStart=started,RoundEndFade=ended})[n] end
local remotes={};function remotes:FindFirstChild(n)if n=='Gameplay'then return gameplay end end
local storage={};function storage:FindFirstChild(n)if n=='Remotes'then return remotes end end
local name1={Text='  Hospital  '};function name1:IsA(c)return c=='TextLabel'end
local name2={Text='Factory'};function name2:IsA(c)return c=='TextLabel'end
local surface={Enabled=true};function surface:IsA(c)return c=='SurfaceGui'end
local votePad={Name='Pad',Parent=workspace,CFrame=frame,Position=Vector3.new(1000,0,0)}
function votePad:IsA(c)return c=='BasePart'end
function votePad:IsDescendantOf(w)return w==workspace end
local detector={Name='Detector1',Parent=workspace,Position=Vector3.new(1000,0,0)}
function detector:IsA(c)return c=='BasePart'end
function detector:IsDescendantOf(w)return w==workspace end
local model1={Name='VotePad1',Parent=lobby};function model1:FindFirstChild(n)
 return ({MapName=name1,Pad=votePad,VoteInfoGui=surface})[n]
end
local model2={Name='VotePad2',Parent=lobby};function model2:FindFirstChild(n)if n=='MapName'then return name2 end end
local votePads={};function votePads:FindFirstChild(n)if n=='Detector1'then return detector end end
local originalLobbyFind=lobby.FindFirstChild
function lobby:FindFirstChild(n,deep)
 if n=='VotePad1'then return model1 elseif n=='VotePad2'then return model2 elseif n=='VotePads'then return votePads end
 return originalLobbyFind(self,n,deep)
end
local timer={time=0};function timer:GetAttribute(n)if n=='Time'then return self.time end end
local originalWorkspaceFind=workspace.FindFirstChild
function workspace:FindFirstChild(n,deep)if n=='RoundTimerPart'then return timer end;return originalWorkspaceFind(self,n,deep)end
root.Position=Vector3.new(1000,0,0)
installGameplay(screenGui)
assert(AngelHub.setters['Auto Vote'](true)==false and not V['Auto Vote'])
services.ReplicatedStorage=storage
heartbeat:Fire(1);assert(selectedOptions[1]=='Hospital' and selectedOptions[2]=='Factory' and V['Select Map']=='Hospital')
local previous=#touches;AngelHub.setters['Auto Vote'](true)
assert(V['Auto Vote'] and #touches==previous+4 and character.lastPivot.Y==3 and humanoid.Health==100)
started.OnClientEvent:Fire(10);previous=#touches;heartbeat:Fire(0.3);assert(#touches==previous)
ended.OnClientEvent:Fire();timer.time=100;heartbeat:Fire(0.3);assert(#touches==previous)
timer.time=0;surface.Enabled=false;heartbeat:Fire(0.3);assert(#touches==previous)
surface.Enabled=true;heartbeat:Fire(0.3);assert(#touches==previous+4 and humanoid.Health==100)
previous=#touches;root.Position=Vector3.new(0,0,0);heartbeat:Fire(0.3);assert(#touches==previous)
AngelHub.setters['Auto Vote'](false);name1.Text='Bank';heartbeat:Fire(1)
assert(selectedOptions[1]=='Bank' and V['Select Map']=='Bank')
screenGui.Destroying:Fire();previous=#touches;heartbeat:Fire(1);assert(#touches==previous)
print('vote mock PASS')
