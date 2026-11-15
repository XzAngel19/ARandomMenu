V['Auto Farm']=true;V['Auto Grab Gun And Shoot']=true
local ticket=1;local allowed=true
AngelHub.farmFullAllowed=function()return allowed end
AngelHub.farmFullTicket=function()return ticket end
tools.equipped=gunTool;gunTool.Parent=character
installGunFeatures(screenGui)
workspace.rayMode='wall';AngelHub.farmGrabShoot();drain();assert(#remote.shots==1)
fakeNow+=1;heartbeat:Fire(.1);allowed=false;AngelHub.farmGrabShoot();drain();assert(#remote.shots==1)
allowed=true;AngelHub.farmGrabShoot();ticket+=1;drain();assert(#remote.shots==1)
AngelHub.farmGrabShoot();drain();assert(#remote.shots==2)
fakeNow+=1;heartbeat:Fire(.1);AngelHub.farmGrabShoot();V['Auto Farm']=false;drain();assert(#remote.shots==2)
screenGui.Destroying:Fire()
