local function setting(n,v)V[n]=v;AngelHub.setters[n]=function(x)V[n]=x end end
AngelHub.moduleNames['Auto Unbox']=true;setting('Auto Unbox',false)
setting('Box To Open','Waiting for boxes');setting('Pay With','Auto');setting('Reveal Animation','Off')
setting('Unbox Delay',1);setting('Max Boxes Per Run',10)
AngelHub.cycleOptions={}
for _,name in ipairs({'Box To Open','Pay With'}) do
 AngelHub.cycleOptions[name]=function(items)
  if name=='Box To Open' then assert(not table.find(items,'Box 1')) end
  if name=='Pay With' then assert(not table.find(items,'Robux')) end
  if not table.find(items,V[name])then V[name]=items[1]end
 end
end
local calls={};local finish={}
local open={};function open:IsA(c)return c=='RemoteFunction'end
function open:InvokeServer(id,category,currency)
 table.insert(calls,{id,category,currency})
 if self.fail then error('unknown dispatch')end
 return 'Reward1'
end
local complete={};function complete:IsA(c)return c=='RemoteEvent'end
function complete:FireServer(reward)table.insert(finish,reward)end
local boxController={fired=0};function boxController:IsA(c)return c=='BindableEvent'end
function boxController:Fire(items)assert(items[1].RewardedItemId=='Reward1');self.fired+=1 end
local shop={};function shop:FindFirstChild(n)return ({OpenCrate=open,CrateComplete=complete,BoxController=boxController})[n]end
local gameplay={};function gameplay:FindFirstChild()return nil end
local remotes={};function remotes:FindFirstChild(n)return ({Shop=shop,Gameplay=gameplay})[n]end
local profile={Coins=500,Gems=1000}
local sync={MysteryBox={MysteryBox1={Name='Mystery Box #1',Contents={}}},Eggs={},Weapons={Reward1={}},
 NewShop={MysteryBox1={Price={Coins=1000,Gems=100,Robux=1}}}}
local sm={data=sync};function sm:IsA(c)return c=='ModuleScript'end
local pm={data=profile};function pm:IsA(c)return c=='ModuleScript'end
local db={};function db:FindFirstChild(n)if n=='Sync'then return sm end end
local modules={};function modules:FindFirstChild(n)if n=='ProfileData'then return pm end end
local storage={};function storage:FindFirstChild(n)return ({Database=db,Modules=modules,Remotes=remotes})[n]end
services.ReplicatedStorage=storage
local pending={};task.spawn=function(fn)table.insert(pending,fn)end
local function drain()local run=pending;pending={};for _,fn in ipairs(run)do fn()end end
installGameplay(screenGui);heartbeat:Fire(.1);drain()
assert(V['Box To Open']=='Mystery Box #1')
AngelHub.setters['Auto Unbox'](true);drain();assert(V['Auto Unbox'] and #calls==0)
-- Insufficient Coins must wait even when Gems could afford it: Auto never uses Gems.
fakeNow+=2;heartbeat:Fire(.1);drain();assert(#calls==0 and V['Auto Unbox'])
profile.Coins=2500;pm.data=nil;fakeNow+=2;heartbeat:Fire(.1);drain();assert(#calls==0)
pm.data=profile;sync.NewShop.MysteryBox1.Price.Coins=2000;fakeNow+=2;heartbeat:Fire(.1);drain();assert(#calls==0)
sync.NewShop.MysteryBox1.Price.Coins=1000;sync.MysteryBox.MysteryBox1=nil
fakeNow+=2;heartbeat:Fire(.1);drain();assert(#calls==0)
sync.MysteryBox.MysteryBox1={Name='Mystery Box #1',Contents={}}
fakeNow+=2;heartbeat:Fire(.1)
assert(#calls==0 and #pending>=1)
-- Off/on cannot bypass the inflight lock.
AngelHub.setters['Auto Unbox'](false);AngelHub.setters['Auto Unbox'](true)
fakeNow+=2;heartbeat:Fire(.1);drain();assert(#calls==0)
fakeNow+=2;heartbeat:Fire(.1);drain();assert(#calls==1 and calls[1][1]=='MysteryBox1' and calls[1][3]=='Coins' and #finish==1)
fakeNow+=2;heartbeat:Fire(.1);drain();assert(#calls==1)
profile.Coins=1500;V['Reveal Animation']='On';fakeNow+=2;heartbeat:Fire(.1);drain()
assert(#calls==2 and boxController.fired==1 and #finish==1)
profile.Coins=500;fakeNow+=2;heartbeat:Fire(.1);drain();assert(#calls==2)
fakeNow+=5;V['Pay With']='Gems';heartbeat:Fire(.1);drain();assert(#calls==3 and calls[3][3]=='Gems')
-- If dispatch raises an error the result is uncertain: stop instead of retrying.
profile.Gems=900;V['Reveal Animation']='Off';open.fail=true;fakeNow+=6;heartbeat:Fire(.1);drain()
assert(#calls==4 and not V['Auto Unbox'])
AngelHub.setters['Auto Unbox'](true);fakeNow+=5;heartbeat:Fire(.1);drain()
assert(#calls==4 and V['Auto Unbox'])
-- A new run with a one-box limit stops after one confirmed reward.
open.fail=false;profile.Gems=800;V['Max Boxes Per Run']=1;fakeNow+=5;heartbeat:Fire(.1);drain()
assert(#calls==5 and not V['Auto Unbox'])
screenGui.Destroying:Fire();profile.Gems=700;fakeNow+=20;heartbeat:Fire(.1);drain();assert(#calls==5)
