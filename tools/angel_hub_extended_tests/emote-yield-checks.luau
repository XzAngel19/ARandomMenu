V['Select Emote']='Sit'
function humanoid:FindFirstChildOfClass()return nil end
local animationTrack={played=false,stopped=false,destroyed=false}
function animationTrack:Play()self.played=true end
function animationTrack:Stop()self.stopped=true end
function animationTrack:Destroy()self.destroyed=true end
function humanoid:LoadAnimation()coroutine.yield('load');return animationTrack end
installEmotes(screenGui)
local co=coroutine.create(AngelHub.actions['Play Emote'])
local ok,result=coroutine.resume(co);assert(ok and result=='load')
screenGui.Destroying:Fire();assert(coroutine.resume(co))
assert(animationTrack.stopped and animationTrack.destroyed and not animationTrack.played)
