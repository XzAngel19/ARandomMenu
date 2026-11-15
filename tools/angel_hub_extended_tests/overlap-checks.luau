V['X-Ray']=false;V['XRay Transparency']=.5;AngelHub.setters['X-Ray']=function(v)V['X-Ray']=v end
V['Hide Distant Scenery']=false;AngelHub.setters['Hide Distant Scenery']=function(v)V['Hide Distant Scenery']=v end
installXRay(screenGui);installFPSOptions(screenGui)
AngelHub.setters['X-Ray'](true);assert(V['X-Ray'])
assert(AngelHub.setters['Hide Distant Scenery'](true)==false and not V['Hide Distant Scenery'])
AngelHub.setters['X-Ray'](false);AngelHub.setters['Hide Distant Scenery'](true);assert(V['Hide Distant Scenery'])
assert(AngelHub.setters['X-Ray'](true)==false and not V['X-Ray'])
screenGui.Destroying:Fire()
