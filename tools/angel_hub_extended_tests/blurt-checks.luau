AngelHub.moduleNames['Auto Blurt']=true;V['Auto Blurt']=false;AngelHub.setters['Auto Blurt']=function(v)V['Auto Blurt']=v end
V['Blurt Delay']=3;V['Repeat On Change']=false;V['Fake Blurt Roles']=false
localPlayer.Name='Me';localPlayer.UserId=1;other.UserId=2
local enemyHuman={Health=100};local enemy={};function enemy:FindFirstChildOfClass(n)if n=='Humanoid'then return enemyHuman end end
function enemy:FindFirstChild()return nil end;other.Character=enemy
local data={Me={Name='Me',Role='Sheriff'},Alice={Name='Alice',Role='Murderer'}}
local fetch={};function fetch:IsA(c)return c=='RemoteFunction'end;function fetch:InvokeServer()return data end
local changed={OnClientEvent=event()};function changed:IsA(c)return c=='RemoteEvent'end
local ended={OnClientEvent=event()};function ended:IsA(c)return c=='RemoteEvent'end
local started={OnClientEvent=event()};function started:IsA(c)return c=='RemoteEvent'end
local gameplay={};function gameplay:FindFirstChild(n)return ({GetCurrentPlayerData=fetch,PlayerDataChanged=changed,RoundEndFade=ended,RoundStart=started})[n]end
local remotes={};function remotes:FindFirstChild(n)if n=='Gameplay'then return gameplay end end
local storage={};function storage:FindFirstChild(n)if n=='Remotes'then return remotes end end;services.ReplicatedStorage=storage
Enum.ChatVersion={TextChatService='modern'}
local messages={};local channel={};function channel:IsA(c)return c=='TextChannel'end;function channel:SendAsync(s)table.insert(messages,s)end
local channels={};function channels:FindFirstChild(n)if n=='RBXGeneral'then return channel end end
local chat={ChatVersion='modern'};function chat:FindFirstChild(n)if n=='TextChannels'then return channels end end;services.TextChatService=chat
AngelHub.mm2RoundEpoch=0
local active=true
AngelHub.isMM2RoundActive=function()return active end
AngelHub.getMM2Role=function(p)return active and data[p.Name] and data[p.Name].Role or nil end
AngelHub.refreshMM2Roles=function()end;AngelHub.releaseMM2Roles=function()end
ended.OnClientEvent:Connect(function()active=false;AngelHub.mm2RoundEpoch+=1 end)
started.OnClientEvent:Connect(function()active=true;AngelHub.mm2RoundEpoch+=1 end)
installBlurt(screenGui);heartbeat:Fire(.21);assert(#messages==0)
AngelHub.setters['Auto Blurt'](true);heartbeat:Fire(.21);assert(#messages==0)
fakeNow+=2;heartbeat:Fire(.21);assert(#messages==0)
fakeNow+=1;heartbeat:Fire(.21);assert(#messages==1 and messages[1]=='Murder; "Alice" Sheriff; "Me"')
fakeNow+=5;heartbeat:Fire(.21);assert(#messages==1)
V['Repeat On Change']=true;V['Fake Blurt Roles']=true;heartbeat:Fire(.21);fakeNow+=3;heartbeat:Fire(.21)
assert(#messages==2 and messages[2]=='Murder; "Me" Sheriff; "Alice"')
ended.OnClientEvent:Fire();fakeNow+=4;heartbeat:Fire(.21);assert(#messages==2)
started.OnClientEvent:Fire(10,data);heartbeat:Fire(.21);AngelHub.setters['Auto Blurt'](false);fakeNow+=4;heartbeat:Fire(.21);assert(#messages==2)
AngelHub.actions['Blurt Roles']();heartbeat:Fire(.21);assert(#messages==3)
-- If chat is unavailable, do not fall back after a modern send was attempted.
local legacy={count=0};function legacy:IsA(c)return c=='RemoteEvent'end;function legacy:FireServer()self.count+=1 end
local events={};function events:FindFirstChild(n)if n=='SayMessageRequest'then return legacy end end
function storage:FindFirstChild(n)if n=='Remotes'then return remotes elseif n=='DefaultChatSystemChatEvents'then return events end end
function channel:SendAsync()error('refused')end
fakeNow+=3;AngelHub.actions['Blurt Roles']();heartbeat:Fire(.21);assert(legacy.count==0)
-- The legacy path works when modern chat is not configured.
chat.ChatVersion='legacy';fakeNow+=3;AngelHub.actions['Blurt Roles']();heartbeat:Fire(.21);assert(legacy.count==1)
-- Queued chat work is invalidated by disabling the module, by round end, and by unload.
local queue={};task.spawn=function(f)table.insert(queue,f)end
local function flush()local pending=queue;queue={};for _,f in ipairs(pending)do f()end end
started.OnClientEvent:Fire(10,data);AngelHub.setters['Auto Blurt'](true);heartbeat:Fire(.21)
fakeNow+=4;heartbeat:Fire(.21);AngelHub.setters['Auto Blurt'](false);flush();assert(legacy.count==1)
started.OnClientEvent:Fire(10,data);AngelHub.setters['Auto Blurt'](true);heartbeat:Fire(.21)
fakeNow+=4;heartbeat:Fire(.21);ended.OnClientEvent:Fire();flush();assert(legacy.count==1)
started.OnClientEvent:Fire(10,data);heartbeat:Fire(.21);fakeNow+=4;heartbeat:Fire(.21)
screenGui.Destroying:Fire();flush();assert(legacy.count==1)
