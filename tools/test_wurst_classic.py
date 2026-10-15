#!/usr/bin/env python3
"""Actual-source classic palette/migration tests; no Roblox visual claim."""
import os
from pathlib import Path
import subprocess
import tempfile
from test_mm2_precision import section

ROOT = Path(__file__).resolve().parents[1]
LOADER = (ROOT / 'src/Wurst.lua').read_text()
SETTINGS = (ROOT / 'src/guis/Wurst/Code/SettingsPage.lua').read_text()


def build():
    return '\n'.join([r'''
local Color3={fromRGB=function(r,g,b) return {R=r/255,G=g/255,B=b/255} end}
local passed=0
local function pass(name) passed+=1;print("PASS",name) end
local function rgb(color,r,g,b)
 assert(math.round(color.R*255)==r and math.round(color.G*255)==g and math.round(color.B*255)==b)
end
''', section(LOADER, 'local THEME_PRESETS:', 'local Theme:'),
section(LOADER, 'local function colorToConfig(color)', 'loadConfig()'),
section(SETTINGS, '    local OPACITY:', '    local HACKLIST_MODE:'),
section(SETTINGS, '    local CLICKGUI_ENABLED:', '    -- Migrate only'), r'''
rgb(THEME_PRESETS.Wurst.background,64,64,64)
rgb(THEME_PRESETS.Wurst.accent,16,16,16)
rgb(THEME_PRESETS.Wurst.text,240,240,240)
rgb(THEME_PRESETS.Wurst.enabled,0,255,0)
rgb(CLICKGUI_BACKGROUND,64,64,64);rgb(CLICKGUI_ACCENT,16,16,16)
rgb(CLICKGUI_TEXT,240,240,240);rgb(CLICKGUI_ENABLED,0,255,0)
assert(OPACITY==.75 and MAX_SETTINGS_HEIGHT==320)
pass("actual Wurst defaults: gray/black/white/lime, translucent body, retained settings capacity")

local function fixture(values)
 local uiPanel={configKey="ClickGUI"}
 local configData={values=values}
 local host={colorToConfig=colorToConfig}
 local saves=0
 local function queueConfigSave() saves+=1 end
''', section(SETTINGS, '    local function migrateV21Palette():', '    local uiPaletteRows:'), r'''
 return configData.values,migrateV21Palette,function() return saves end
end
local function oldPalette()
 return {["ClickGUI.Background"]={17,19,27},["ClickGUI.Accent"]={166,139,250},
 ["ClickGUI.Text"]={237,240,248},["ClickGUI.Enabled"]={166,139,250},["ClickGUI.Opacity"]=.82,
 ["MM2.Shoot.Predictionprofile"]="Experimental",["MM2.Knife.ThrowHz"]=90}
end
local values,again,saves=fixture(oldPalette())
assert(values["ClickGUI.Background"][1]==64 and values["ClickGUI.Accent"][1]==16)
assert(values["ClickGUI.Enabled"][1]==0 and values["ClickGUI.Enabled"][2]==255)
assert(values["ClickGUI.Opacity"]==.75 and saves()==1)
assert(values["MM2.Shoot.Predictionprofile"]=="Experimental" and values["MM2.Knife.ThrowHz"]==90)
again();assert(saves()==1)
values["ClickGUI.Accent"]={166,139,250};again();assert(values["ClickGUI.Accent"][1]==166)
pass("exact Midnight migration is once-only, saves once and leaves weapon configuration untouched")

for _,label in ipairs({"Background","Accent","Text","Enabled"}) do
 local custom=oldPalette();custom["ClickGUI."..label]={12,34,56}
 local before=table.clone(custom)
 local result=fixture(custom)
 assert(result["ClickGUI."..label][1]==12 and result["ClickGUI.Opacity"]==.82)
 for _,other in ipairs({"Background","Accent","Text","Enabled"}) do
  if other~=label then assert(result["ClickGUI."..other]==before["ClickGUI."..other]) end
 end
end
local partial=oldPalette();partial["ClickGUI.Text"]=nil
local result=fixture(partial);assert(result["ClickGUI.Background"][1]==17)
local malformed=oldPalette();malformed["ClickGUI.Accent"]="custom"
assert(fixture(malformed)["ClickGUI.Accent"]=="custom")
local empty=fixture({});assert(empty["ClickGUI.Background"]==nil)
pass("custom/mixed/partial/malformed palettes are never overwritten; empty profiles use defaults")

local customOpacity=oldPalette();customOpacity["ClickGUI.Opacity"]=.6
assert(fixture(customOpacity)["ClickGUI.Opacity"]==.6)
pass("recognized palette migration preserves custom opacity")
print("Wurst Classic regression groups passed:",passed)
'''])


def main():
    with tempfile.TemporaryDirectory(prefix='wurst-classic-') as folder:
        path=Path(folder)/'test.luau'
        path.write_text(build())
        subprocess.run([os.environ.get('LUAU','luau'),str(path)],check=True)


if __name__=='__main__':
    main()
