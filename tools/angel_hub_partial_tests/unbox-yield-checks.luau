local function setting(n,v)V[n]=v;AngelHub.setters[n]=function(x)V[n]=x end end
AngelHub.moduleNames['Auto Unbox']=true
for n,v in pairs({['Auto Unbox']=false,['Box To Open']='Waiting for boxes',['Pay With']='Auto',
 ['Reveal Animation']='Off',['Unbox Delay']=1,['Max Boxes Per Run']=10})do setting(n,v)end
AngelHub.cycleOptions={}
for _,n in ipairs({'Box To Open','Pay With'})do
 AngelHub.cycleOptions[n]=function(items)if not table.find(items,V[n])then V[n]=items[1]end end
end
local profile={Coins=3000}
local sync={MysteryBox={B={Name='Box',Contents={}}},NewShop={B={Price={Coins=1000}}},Weapons={reward={}}}
local sm={data=sync};function sm:IsA(c)return c=='ModuleScript'end
local pm={data=profile};function pm:IsA(c)return c=='ModuleScript'end
local db={};function db:FindFirstChild(n)if n=='Sync'then return sm end end
local mods={};function mods:FindFirstChild(n)if n=='ProfileData'then return pm end end
local calls, completions=0,0
local open={};function open:IsA(c)return c=='RemoteFunction'end
function open:InvokeServer()calls+=1;coroutine.yield('invoke');return 'reward'end
local complete={};function complete:IsA(c)return c=='RemoteEvent'end
function complete:FireServer()completions+=1 end
local shop={};function shop:FindFirstChild(n)return ({OpenCrate=open,CrateComplete=complete})[n]end
local remotes={};function remotes:FindFirstChild(n)if n=='Shop'then return shop end end
local storage={};function storage:FindFirstChild(n)return ({Database=db,Modules=mods,Remotes=remotes})[n]end
services.ReplicatedStorage=storage
local tasks={};task.spawn=function(fn)local co=coroutine.create(fn);table.insert(tasks,co);return co end
local function resume(co)local ok,reason=coroutine.resume(co);assert(ok,tostring(reason));return reason end
local function allTasks()
 local nextTasks={}
 for _,co in ipairs(tasks)do if coroutine.status(co)~='dead'then resume(co)end;if coroutine.status(co)~='dead'then table.insert(nextTasks,co)end end
 tasks=nextTasks
end
installGameplay(screenGui);heartbeat:Fire(.1);allTasks();assert(V['Box To Open']=='Box')
-- Profile require yields before the dispatch. Switching off and on cancels it.
pm.yieldNow=true
AngelHub.setters['Auto Unbox'](true);allTasks();assert(calls==0 and #tasks==1)
AngelHub.setters['Auto Unbox'](false);AngelHub.setters['Auto Unbox'](true)
fakeNow+=3;heartbeat:Fire(.1);assert(calls==0)
pm.yieldNow=false;allTasks();assert(calls==0)
-- While InvokeServer yields, no toggling or heartbeat can dispatch another request.
fakeNow+=3;heartbeat:Fire(.1);allTasks();assert(calls==1 and #tasks==1)
AngelHub.setters['Auto Unbox'](false);AngelHub.setters['Auto Unbox'](true)
fakeNow+=3;heartbeat:Fire(.1);allTasks();assert(calls==1 and completions==1)
fakeNow+=3;heartbeat:Fire(.1);allTasks();assert(calls==1)
screenGui.Destroying:Fire()
