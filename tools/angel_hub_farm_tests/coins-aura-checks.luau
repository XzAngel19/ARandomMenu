local function setting(n,v)V[n]=v;AngelHub.setters[n]=function(x)V[n]=x end end
setting('Auto Farm',false);setting('Coins Aura',false);setting('Farm Mode','Walk');setting('Farm Speed',16)
setting('Farm Safe Zone',false);setting('Coins Collected',0);setting('Farm Time',0)
local original={Position=Vector3.new(14,0,0)}
local weld={Enabled=true};local visual={Anchored=false}
function visual:IsA(c)return c=='BasePart'end
function visual:GetAttribute()return nil end
function visual:FindFirstChildOfClass(c)if c=='WeldConstraint'then return weld end end
local coin={Name='Coin_Server',Parent=map,Position=original.Position,CFrame=original,CanCollide=true}
function coin:IsA(c)return c=='BasePart'end
function coin:GetAttribute()return nil end
function coin:FindFirstChild(n)if n=='CoinVisual'then return visual end end
function coin:IsDescendantOf(p)return p==map and self.Parent==map end
map.descendants={coin};root.CFrame={Position=root.Position}
installMM2Farm(screenGui)
heartbeat:Fire(.6);assert(#touches==0 and coin.CFrame==original)
AngelHub.setters['Coins Aura'](true);heartbeat:Fire(.6)
assert(#touches==2 and coin.CFrame==root.CFrame and not coin.CanCollide and visual.Anchored and not weld.Enabled)
AngelHub.setters['Coins Aura'](false);assert(coin.CFrame==original and coin.CanCollide and not visual.Anchored and weld.Enabled)
coin.Position=Vector3.new(16,0,0);AngelHub.setters['Coins Aura'](true);heartbeat:Fire(.6);assert(#touches==2)
coin.Position=Vector3.new(14,0,0);heartbeat:Fire(.6);assert(#touches==4)
local external={Position=Vector3.new(12,0,0)};coin.CFrame=external;coin.CanCollide=true
AngelHub.setters['Coins Aura'](false);assert(coin.CFrame==external and coin.CanCollide and not visual.Anchored and weld.Enabled)
coin.CFrame=original;root.Position=Vector3.new(1000,0,0);AngelHub.setters['Coins Aura'](true);heartbeat:Fire(.6);assert(#touches==4)
root.Position=Vector3.zero;V['Auto Win']=true;heartbeat:Fire(.6);assert(#touches==6);V['Auto Win']=false
heartbeat:Fire(.6);assert(#touches==8);screenGui.Destroying:Fire();assert(coin.CFrame==original and coin.CanCollide and not visual.Anchored and weld.Enabled)
