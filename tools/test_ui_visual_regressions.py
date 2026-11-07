#!/usr/bin/env python3
"""Exercise the actual booted controls, not just saved numbers.

The mock cannot render pixels: it checks geometry, group composition and input
contracts on mobile-sized viewports, then Roblox/Delta still needs a visual test.
"""
import os
import subprocess
import tempfile
from pathlib import Path
import audit_menu

source = audit_menu.build(debug=True).read_text(encoding='utf-8')
probe = r'''
local function near(a,b,message)
 assert(type(a)=='number' and math.abs(a-b)<0.0001,message..': '..tostring(a)..' expected '..tostring(b))
end
local state=ex.state
local scaleControl=assert(state.valueControls['ClickGUI.Menuscale'])
local opacityControl=assert(state.valueControls['ClickGUI.Opacity'])
local scale=assert(state.clickGui.scale)
local camera=workspace.CurrentCamera
camera.ViewportSize=Vector2.new(640,360)
camera:GetPropertyChangedSignal('ViewportSize'):Fire()
local previous=0
for _,value in ipairs({0.7,0.85,1,1.15,1.3}) do
 scaleControl.apply(value)
 near(scale.Scale,0.7*value,'mobile scale follows slider')
 assert(scale.Scale>previous,'each mobile scale setting must visibly change the UIScale')
 previous=scale.Scale
end
camera.ViewportSize=Vector2.new(1920,1080)
camera:GetPropertyChangedSignal('ViewportSize'):Fire()
scaleControl.apply(0.7);near(scale.Scale,0.84,'desktop low end')
scaleControl.apply(1.3);near(scale.Scale,1.56,'desktop high end')
scaleControl.apply(5)
near(ex.configData.values['UI.MenuScale'],1.3,'typed scale is bounded')
near(ex.configData.values['ClickGUI.Menuscale'],1.3,'displayed/saved value matches applied scale')
opacityControl.apply(-2)
near(ex.configData.values['ClickGUI.Opacity'],0.15,'typed opacity is bounded')
local movement=assert(state.valueControls['Universal.Speed.Speed'])
movement.apply(-12)
near(state.framework:GetModule('Speed Hack').Options.Speed.Value,-12,'movement keeps negative manual values')
movement.apply(300)
near(state.framework:GetModule('Speed Hack').Options.Speed.Value,300,'movement keeps values above slider range')
movement.apply(32)

-- Pointer movement uses the track geometry at the beginning of a drag. Changing
-- scale moves/resizes the track under the finger and must not change the value
-- for the same physical pointer location.
local function descendantNamed(root,name)
 for _,d in ipairs(root:GetDescendants()) do if d.Name==name then return d end end
end
local ui=assert(state.windows.Get('UISettings'))
local row=assert(descendantNamed(ui.root,'Option_Menuscale'),'actual scale row')
local slider=assert(row:FindFirstChild('Slider'))
local track=assert(slider:FindFirstChild('Track'))
track.AbsolutePosition=Vector2.new(100,100);track.AbsoluteSize=Vector2.new(200,10)
slider.InputBegan:Fire({UserInputType=Enum.UserInputType.Touch,Position=Vector3.new(100,100,0)})
track.AbsolutePosition=Vector2.new(500,100);track.AbsoluteSize=Vector2.new(400,10)
UserInputService.InputChanged:Fire({UserInputType=Enum.UserInputType.Touch,Position=Vector3.new(250,100,0)})
near(ex.configData.values['UI.MenuScale'],1.15,'drag follows starting geometry')
UserInputService.InputEnded:Fire({UserInputType=Enum.UserInputType.Touch})
local input=assert(slider:FindFirstChild('NumericValue'))
input.Focused:Fire();input.Text='5';input.FocusLost:Fire()
assert(input.Text=='1.3','out-of-range typed scale must display its actual value')
near(ex.configData.values['UI.MenuScale'],1.3,'typed scale is applied')

-- The modal uses its own unscaled fullscreen root: PopupLayer is scaled from
-- its top left, so parenting the dialog to it visibly offsets its centre.
local yes,no=0,0
local panel=assert(state.confirmDialog({title='Calibration',message='Question',onYes=function() yes+=1 end,onNo=function() no+=1 end}))
local backdrop=assert(panel.Parent)
assert(backdrop.Parent.ClassName=='ScreenGui','modal must not be inside scaled PopupLayer')
near(panel.AnchorPoint.X,0.5,'modal anchor X');near(panel.AnchorPoint.Y,0.5,'modal anchor Y')
near(panel.Position.X.Scale,0.5,'modal centre X');near(panel.Position.Y.Scale,0.5,'modal centre Y')
assert(panel.Size.X.Scale>0,'modal width must shrink on narrow mobile screens')
assert(panel.AutomaticSize==Enum.AutomaticSize.Y,'wrapped text must not push buttons outside a fixed panel')
local sizeLimit=assert(panel:FindFirstChildOfClass('UISizeConstraint'),'responsive modal width cap')
near(sizeLimit.MaxSize.X,340,'maximum modal width')
local actions=assert(panel:FindFirstChild('Actions'))
assert(actions:FindFirstChild('Yes')).MouseButton1Click:Fire()
assert(yes==1 and no==0,'the centred dialog preserves consent callbacks')

-- v191: Opacity is the BACKGROUND only. The panel shell fades; the group stays
-- fully opaque so text, icons and strokes keep their contrast at any setting,
-- and no descendant is individually faded.
local category=assert(state.clickGui.categories.Exploits.window)
local root=category.root
assert(root.ClassName=='CanvasGroup','normal menu window must composite as a group')
near(root.BackgroundTransparency,1-(state.windows.opacity or 0.85),'panel base follows the current opacity')
local header=assert(root:FindFirstChild('Header'))
local baseHeader=header.BackgroundTransparency
local sampleRow=assert(category.body:FindFirstChild('AntiAFKFeature') or category.body:GetChildren()[1])
local baseRow=sampleRow.BackgroundTransparency
for _,value in ipairs({0.15,0.35,0.85,1,0.5}) do
 opacityControl.apply(value)
 near(root.GroupTransparency,0,'content is never faded by the opacity slider')
 near(root.BackgroundTransparency,1-value,'background alpha follows the slider')
 near(header.BackgroundTransparency,baseHeader,'header is not individually faded')
 near(sampleRow.BackgroundTransparency,baseRow,'rows keep their original styling')
end
local created=state.windows.Create({id='OpacityAfter',title='after',position=Vector2.new(10,10),size=Vector2.new(200,100)})
assert(created.root.ClassName=='CanvasGroup')
near(created.root.GroupTransparency,0,'new windows never fade their content')
near(created.root.BackgroundTransparency,0.5,'new windows inherit the background alpha')

-- Different viewport orientations must not put every category title bar on
-- the same spot. Moving back to a large viewport must recover a user's saved
-- home, not the clamped position borrowed for a small viewport.
scaleControl.apply(1)
for _,viewport in ipairs({Vector2.new(640,360),Vector2.new(360,640),Vector2.new(1920,1080)}) do
 camera.ViewportSize=viewport;camera:GetPropertyChangedSignal('ViewportSize'):Fire()
 local seen={}
 for _,name in ipairs(state.clickGui.order) do
  local w=state.clickGui.categories[name].window
  local p=Vector2.new(w.root.Position.X.Offset,w.root.Position.Y.Offset)
  for _,old in ipairs(seen) do
   assert(math.abs(p.X-old.X)>=6 or math.abs(p.Y-old.Y)>=6,'category title bars piled up')
  end
  table.insert(seen,p)
 end
end
local auto=state.windows.Create({id='AutoPlaceProbe',title='auto',position=Vector2.new(400,300),size=Vector2.new(180,90)})
state.windows.PlaceWindow(auto,{force=true});auto.root.Visible=true
local ax,ay=auto.root.Position.X.Offset,auto.root.Position.Y.Offset
state.windows.Reclamp()
near(auto.root.Position.X.Offset,ax,'automatic placement home X')
near(auto.root.Position.Y.Offset,ay,'automatic placement home Y')
local blocker=state.windows.Create({id='BlockerProbe',title='blocker',position=Vector2.new(100,100),size=Vector2.new(180,90)})
blocker.root.Visible=true
state.windows.SetHome(auto,Vector2.new(400,300))
auto.root.Position=UDim2.fromOffset(blocker.root.Position.X.Offset,blocker.root.Position.Y.Offset)
state.windows.ReflowWindow(auto)
ax,ay=auto.root.Position.X.Offset,auto.root.Position.Y.Offset
state.windows.Reclamp()
near(auto.root.Position.X.Offset,ax,'automatic reflow home X')
near(auto.root.Position.Y.Offset,ay,'automatic reflow home Y')
ex.configData.ui.windows.ManualProbe={x=950,y=250}
local manual=state.windows.Create({id='ManualProbe',title='manual',position=Vector2.new(20,20),size=Vector2.new(120,90)})
manual:SetVisible(true)
near(manual.root.Position.X.Offset,950,'saved manual home')
blocker.root.Position=UDim2.fromOffset(950,250)
manual:SetVisible(false);manual:SetVisible(true)
near(manual.root.Position.X.Offset,950,'opening preserves an intentional manual overlap')
blocker.root.Position=UDim2.fromOffset(100,100)
camera.ViewportSize=Vector2.new(640,360);camera:GetPropertyChangedSignal('ViewportSize'):Fire()
assert(manual.root.Position.X.Offset<950,'small viewport temporarily clamps manual window')
camera.ViewportSize=Vector2.new(1920,1080);camera:GetPropertyChangedSignal('ViewportSize'):Fire()
near(manual.root.Position.X.Offset,950,'saved manual home restored after resize')
near(manual.root.Position.Y.Offset,250,'saved manual vertical home restored after resize')
print('PASS GUI visual contracts: scale, drag, centred modal, composited opacity and window reflow')
'''
with tempfile.TemporaryDirectory(prefix='ui-visual-') as tmp:
    path=Path(tmp)/'case.luau';path.write_text(source+probe,encoding='utf-8')
    result=subprocess.run([os.environ.get('LUAU','luau'),str(path)],capture_output=True,text=True)
    if result.returncode: raise SystemExit(result.stdout[-2400:]+'\n'+result.stderr)
    assert 'PASS GUI visual contracts:' in result.stdout
    print(result.stdout[result.stdout.rfind('PASS GUI visual contracts:'):].strip())
