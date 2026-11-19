V['Auto Win']=true;V['Insta Kill As Sheriff']=true;V['Win Sheriff WallCheck']=true
AngelHub.winSafe=function()return true end
tools.equipped=gunTool;gunTool.Parent=character
installGunFeatures(screenGui)
workspace.rayMode='wall';AngelHub.winShoot();drain();assert(#remote.shots==0)
workspace.rayMode='clear';AngelHub.winShoot();drain();assert(#remote.shots==1)
AngelHub.winShoot();drain();assert(#remote.shots==1)
fakeNow+=1;heartbeat:Fire(.1);AngelHub.winSafe=function()return false end;AngelHub.winShoot();drain();assert(#remote.shots==1)
AngelHub.winSafe=function()return true end;AngelHub.winShoot();V['Auto Win']=false;AngelHub.cancelWinShot();V['Auto Win']=true;drain();assert(#remote.shots==1)
V['Auto Win']=true;V['Win Sheriff WallCheck']=false;workspace.rayMode='wall';AngelHub.winShoot();assert(#pendingTasks>0, 'not queued');drain();assert(#remote.shots==2, 'shots='..#remote.shots)
screenGui.Destroying:Fire();fakeNow+=2;if AngelHub.winShoot then AngelHub.winShoot()end;drain();assert(#remote.shots==2, 'shots='..#remote.shots)
