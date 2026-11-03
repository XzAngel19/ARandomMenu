#!/usr/bin/env python3
"""MM2 camera changes must not strand the real ClickGui at a tiny scale."""
import os
import subprocess
import tempfile
from pathlib import Path
import audit_menu

source = audit_menu.build(debug=True).read_text(encoding='utf-8')
probe = r'''
assert(ex.state.activeGameName=='MM2' and not ex.state.isMobile)
local scale=assert(ex.state.clickGui.scale)
local function near(a,b,msg) assert(math.abs(a-b)<0.00001,msg..': '..tostring(a)..' ~= '..tostring(b)) end
local camera=workspace.CurrentCamera
near(scale.Scale,0.8*SAVED_SCALE,'1280x720 initial scale (including saved preference)')
camera.ViewportSize=Vector2.new(1920,1080)
camera:GetPropertyChangedSignal('ViewportSize'):Fire()
near(scale.Scale,1.2*SAVED_SCALE,'a viewport resize must refresh the scale')
-- Round changes can hand the client a new camera before it has a viewport.
local sampleWindow=ex.state.windows.list[1]
local oldPos=sampleWindow.root.Position
local replacement=newInst('Camera');replacement.ViewportSize=Vector2.new(0,0)
workspace.CurrentCamera=replacement
workspace:GetPropertyChangedSignal('CurrentCamera'):Fire()
near(scale.Scale,1.2*SAVED_SCALE,'a temporary zero viewport must not shrink the menu')
assert(sampleWindow.root.Position==oldPos,'a zero viewport must not move the windows')
camera.ViewportSize=Vector2.new(640,360)
camera:GetPropertyChangedSignal('ViewportSize'):Fire()
near(scale.Scale,1.2*SAVED_SCALE,'the old camera must be disconnected')
replacement.ViewportSize=Vector2.new(1280,720)
replacement:GetPropertyChangedSignal('ViewportSize'):Fire()
near(scale.Scale,0.8*SAVED_SCALE,'scale follows the replacement camera after it is ready')
replacement.ViewportSize=Vector2.new(0,0)
replacement:GetPropertyChangedSignal('ViewportSize'):Fire()
near(scale.Scale,0.8*SAVED_SCALE,'a transient zero size on the same camera must not shrink the menu')
ex.ThemeEngine.shape.scale=1.1
assert(not ex.state.refreshLayout(true),'forced layout waits for a valid viewport')
near(scale.Scale,0.8*SAVED_SCALE,'manual preference does not cause a zero-size reflow')
replacement.ViewportSize=Vector2.new(1280,720)
replacement:GetPropertyChangedSignal('ViewportSize'):Fire()
near(scale.Scale,0.88,'a manual change during an invalid viewport is applied on recovery')
print('PASS MM2 menu scale: resize, camera replacement, transient zero and saved manual scale')
'''
boot_zero = r'''
local scale=assert(ex.state.clickGui.scale)
local function near(a,b) assert(math.abs(a-b)<0.00001,tostring(a)..' ~= '..tostring(b)) end
near(scale.Scale,0.8)
assert(ex.state.layoutViewport.X==1280 and ex.state.layoutViewport.Y==720)
workspace.CurrentCamera.ViewportSize=Vector2.new(1920,1080)
workspace.CurrentCamera:GetPropertyChangedSignal('ViewportSize'):Fire()
near(scale.Scale,1.2)
print('PASS MM2 menu scale: zero viewport at boot recovers')
'''
saved_anchor = '["Universal.Speed.Speed"] = 5000'
viewport_anchor = 'ViewportSize = Vector2.new(1280, 720),'
assert source.count(saved_anchor) == 1 and source.count(viewport_anchor) == 1
with tempfile.TemporaryDirectory(prefix='mm2-menu-scale-') as tmp:
    for name, case, extra in (
        ('default', source, '\nSAVED_SCALE=1\n' + probe),
        ('saved', source.replace(saved_anchor, saved_anchor + ', ["UI.MenuScale"] = 1.2', 1),
            '\nSAVED_SCALE=1.2\n' + probe),
        ('zero-at-boot', source.replace(viewport_anchor, 'ViewportSize = Vector2.new(0, 0),', 1), boot_zero),
    ):
        path = Path(tmp) / f'{name}.luau'
        path.write_text(case + extra, encoding='utf-8')
        result = subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], capture_output=True, text=True)
        if result.returncode:
            raise SystemExit(name + ':\n' + result.stdout[-1800:] + '\n' + result.stderr)
        assert 'PASS MM2 menu scale:' in result.stdout
        print(f'PASS MM2 menu scale: {name}')
