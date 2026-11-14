local function setting(name,value)V[name]=value;AngelHub.setters[name]=function(v)V[name]=v end end
AngelHub.moduleNames['Auto Vote']=true;setting('Auto Vote',false);setting('Select Map','Waiting for maps')
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
services.ReplicatedStorage=storage
local name1={Text='  Hospital  '};function name1:IsA(c)return c=='TextLabel'end
local name2={Text='Factory'};function name2:IsA(c)return c=='TextLabel'end
local surface={Enabled=true};function surface:IsA(c)return c=='SurfaceGui'end
local framePad={Position=Vector3.new(1000,0,0)};local frameDetector={Position=Vector3.new(1000,0,0)}
local votePad={Name='Pad',Parent=workspace,CFrame=framePad,CanCollide=true,Position=framePad.Position}
function votePad:IsA(c)return c=='BasePart'end
function votePad:IsDescendantOf(w)return w==workspace end
local detector={Name='Detector1',Parent=workspace,CFrame=frameDetector,CanCollide=true,Position=frameDetector.Position}
function detector:IsA(c)return c=='BasePart'end
function detector:IsDescendantOf(w)return w==workspace end
local model1={Name='VotePad1',Parent=lobby};function model1:FindFirstChild(n)
 return ({MapName=name1,Pad=votePad,VoteInfoGui=surface})[n]
end
local model2={Name='VotePad2',Parent=lobby};function model2:FindFirstChild(n)if n=='MapName'then return name2 end end
local votePads={};function votePads:FindFirstChild(n)if n=='Detector1'then return detector end end
local count={Value=1};function count:IsA(c)return c=='IntValue'end
local icon={};function icon:FindFirstChild(n)if n=='Votes'then return count end end
local icons={};function icons:FindFirstChild(n)if n=='VotePad1'then return icon end end
local originalLobbyFind=lobby.FindFirstChild
function lobby:FindFirstChild(n,deep)
 if n=='VotePad1'then return model1 elseif n=='VotePad2'then return model2 elseif n=='VotePads'then return votePads elseif n=='VoteIcons'then return icons end
 return originalLobbyFind(self,n,deep)
end
local timer={time=0};function timer:GetAttribute(n)if n=='Time'then return self.time end end
local originalWorkspaceFind=workspace.FindFirstChild
function workspace:FindFirstChild(n,deep)if n=='RoundTimerPart'then return timer end;return originalWorkspaceFind(self,n,deep)end
Enum.HumanoidStateType={Dead='dead'};function humanoid:ChangeState(s)self.lastState=s end
root.Position=Vector3.new(1000,0,0);root.CFrame={Position=root.Position}
-- Mock the teleport's destination frame arithmetic.
setmetatable(framePad,{__add=function(_,v)return {Y=v.Y}end})
installGameplay(screenGui)
heartbeat:Fire(1);assert(selectedOptions[1]=='Hospital' and selectedOptions[2]=='Factory' and V['Select Map']=='Hospital')
local previous=#touches;AngelHub.setters['Auto Vote'](true)
assert(V['Auto Vote'] and #touches==previous+4 and character.lastPivot.Y==3 and humanoid.Health==100)
assert(votePad.CFrame==root.CFrame and detector.CFrame==root.CFrame and not votePad.CanCollide)
fakeNow+=.23;heartbeat:Fire(.3);assert(humanoid.Health==0 and humanoid.lastState=='dead')
assert(votePad.CFrame==framePad and detector.CFrame==frameDetector and votePad.CanCollide and detector.CanCollide)
previous=#touches;heartbeat:Fire(.3);assert(#touches==previous) -- dead until respawn
-- A fresh character can cast another vote and reset after the hold.
local oldCharacter=character
local newCharacter={};function newCharacter:FindFirstChildOfClass(n)if n=='Humanoid'then return humanoid end end
function newCharacter:FindFirstChild(n)if n=='HumanoidRootPart'then return root end end
function newCharacter:PivotTo(cf)self.lastPivot=cf end
function newCharacter:GetDescendants()return {root,head}end
localPlayer.Character=newCharacter;humanoid.Health=100
fakeNow+=.3;heartbeat:Fire(.3);assert(#touches==previous+4 and humanoid.Health==100)
fakeNow+=.23;heartbeat:Fire(.3);assert(humanoid.Health==0)
-- Round-start cancels pending vote and restores pads, without resetting again.
localPlayer.Character=oldCharacter;humanoid.Health=100;fakeNow+=.3;heartbeat:Fire(.3)
assert(votePad.CFrame==root.CFrame);started.OnClientEvent:Fire(10)
assert(votePad.CFrame==framePad and detector.CFrame==frameDetector)
previous=#touches;fakeNow+=1;heartbeat:Fire(.3);assert(#touches==previous and humanoid.Health==100)
ended.OnClientEvent:Fire();timer.time=100;heartbeat:Fire(.3);assert(#touches==previous and humanoid.Health==100)
timer.time=0;surface.Enabled=false;heartbeat:Fire(.3);assert(#touches==previous)
surface.Enabled=true;fakeNow+=.3;heartbeat:Fire(.3);assert(#touches==previous+4 and humanoid.Health==100)
AngelHub.setters['Auto Vote'](false);assert(votePad.CFrame==framePad and detector.CFrame==frameDetector)
fakeNow+=1;heartbeat:Fire(.3);assert(humanoid.Health==100)
name1.Text='Bank';heartbeat:Fire(1);assert(selectedOptions[1]=='Bank' and V['Select Map']=='Bank')
-- The displayed vote count can trigger a reset before the hold expires.
AngelHub.setters['Auto Vote'](true);assert(humanoid.Health==100)
count.Value=2;fakeNow+=.01;heartbeat:Fire(.3);assert(humanoid.Health==0)
AngelHub.setters['Auto Vote'](false);humanoid.Health=100
-- Missing remotes or touch API does not prevent physical pad contact.
services.ReplicatedStorage=nil;firetouchinterest=nil;surface.Enabled=false;timer.time=0
AngelHub.setters['Auto Vote'](true);assert(humanoid.Health==100)
fakeNow+=.23;heartbeat:Fire(.3);assert(humanoid.Health==0)
AngelHub.setters['Auto Vote'](false);humanoid.Health=100
-- Preserve external writes to either detector when turning off.
surface.Enabled=true;AngelHub.setters['Auto Vote'](true)
local external={Position=Vector3.new(1010,0,0)};votePad.CFrame=external;votePad.CanCollide=true
AngelHub.setters['Auto Vote'](false);assert(votePad.CFrame==external and votePad.CanCollide)
votePad.CFrame=framePad;screenGui.Destroying:Fire();previous=#touches;heartbeat:Fire(1);assert(#touches==previous and humanoid.Health==100)
print('vote reset/respawn/cancel mock PASS')
