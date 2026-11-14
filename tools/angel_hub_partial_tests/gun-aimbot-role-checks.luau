AngelHub.moduleNames['Gun Aimbot']=true;setting('Gun Aimbot',false)
setting('Aim Method','Normal');setting('Aimbot Target','Murder');setting('Target Player','')
setting('Normal WallCheck',false);setting('Aimbot Keybind Value','Q')
installGameplay(screenGui)
AngelHub.setters['Gun Aimbot'](true);assert(fetch.count==1 and remote.shots==0)
AngelHub.actions['Fire Gun']();assert(remote.shots==1)
changed.OnClientEvent:Fire({Alice={Name='Alice',Role='Murderer',Dead=true}})
fakeNow+=1;AngelHub.actions['Fire Gun']();assert(remote.shots==1)
changed.OnClientEvent:Fire({Alice={Name='Alice',Role='Murderer'}})
ended.OnClientEvent:Fire();fakeNow+=1;AngelHub.actions['Fire Gun']();assert(remote.shots==1)
started.OnClientEvent:Fire(10,data);fakeNow+=1;AngelHub.actions['Fire Gun']();assert(remote.shots==2)
-- Silent can select fresh round role data while the local player is far from the map.
V['Aim Method']='Silent AIM';root.Position=Vector3.new(2000,0,0);root.CFrame={Position=root.Position}
fakeNow+=1;AngelHub.actions['Fire Gun']();assert(remote.shots==3)
root.Position=Vector3.new(0,0,0);root.CFrame={Position=root.Position};V['Aim Method']='Normal'
-- Auto Shoot attempts immediately when enabled and keeps its watcher when Aimbot turns off.
fakeNow+=1;AngelHub.setters['Auto Shoot'](true);assert(remote.shots==4)
AngelHub.setters['Gun Aimbot'](false)
fakeNow+=.3;heartbeat:Fire(.1);assert(remote.shots==5)
changed.OnClientEvent:Fire({Alice={Name='Alice',Role='Murderer',Dead=true}})
fakeNow+=.3;heartbeat:Fire(.1);assert(remote.shots==5)
screenGui.Destroying:Fire()
