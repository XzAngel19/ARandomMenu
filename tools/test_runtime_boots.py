#!/usr/bin/env python3
"""Boot the real bundle in each registered place and a universal-only place.

These are simulated Roblox/executor environments, not live gameplay tests.
"""
import os
import subprocess
import tempfile
from pathlib import Path
import audit_menu
import build_bundle
import gen_full_boot_harness as harness

# v185 removes three universal cards; BedFight keeps its own Anti Void.
CASES = [
    # v198 adds the universal "Animations" card (World).
    ('Universal', 1, 35, None, None),
    # v190 restores the MM2 Fling card (one more card in MM2 only).
    ('MM2', 142823291, 49, 'MM2', 'MM2.AutoFarm'),
    ('BedFight', 71480482338212, 45, 'BedFight', 'BedFight.AutoSwing'),
    ('TRS', 14315258385, 46, 'TRS', 'TRS.AutoHeader'),
    ('VD', 93978595733734, 49, 'VD', 'VD.AutoGenerator'),
    ('X2 Legacy', 92876937625630, 40, 'X2Duels', 'MVSD.AutoFarm'),
    ('X2', 135856908115931, 40, 'X2Duels', 'MVSD.AutoFarm'),
]

source = audit_menu.build(debug=True).read_text(encoding='utf-8')
anchor = '\nlocal ok, err = pcall(function()\n'
assert source.count(anchor) == 1
# Simulate an unavailable bundle with HttpGet serving only the current source
# files. Game-specific modules are fetched on demand, not in the preload list.
files = build_bundle.collect_sources()
fallback_sources = '\nSOURCES["src/libraries/bundle.lua"] = nil\n' + ''.join(
    f'SOURCES["{path}"] = {harness.long_bracket(text)}\n'
    for path, text in files.items()
)
probe = r'''
assert(ex.state.menuReady==true, 'boot must release the launcher even with no game-specific sections')
if FALLBACK then
    assert(ex.state.boot.bundle==nil, 'fallback unexpectedly used a bundle')
    assert(type(ex.state.boot.sources['src/libraries/Manifest.lua'])=='string',
        'manifest was not downloaded individually')
    for _, path in ipairs(EXPECTED_GAME_SOURCES) do
        assert(type(ex.state.boot.sources[path])=='string', 'game source not fetched: '..path)
    end
else
    assert(type(ex.state.boot.bundle)=='table', 'real bundle was not accepted')
end
assert(ex.state.boot.timing.moduleCount==ex.state.boot.timing.moduleTotal,
    'a universal module did not load')
local root=CoreGui:FindFirstChild('Wurst');assert(root, 'menu GUI missing')
local button=root:FindFirstChild('MobileMenuButton');assert(button, 'launcher missing')
if MOBILE then
    assert(ex.state.dock and ex.state.dock.root.Visible==true, 'mobile dock should be visible')
    assert(button.Visible==false, 'the fallback launcher stays hidden while the dock exists')
    local dockButton=ex.state.dock.root:FindFirstChild('PillButton1');assert(dockButton)
    dockButton.MouseButton1Click:Fire()
    assert(ex.state.visible==true, 'mobile dock should open the menu')
    ex.state.setMenuVisible(false)
    -- Exercise the fallback if Furniture is unavailable or has been cleaned up.
    ex.state.pill=nil
    ex.state.refreshLauncher()
    assert(button.Visible==true, 'fallback launcher must be available after boot')
    button.MouseButton1Click:Fire()
    assert(ex.state.visible==true, 'fallback launcher should open the menu')
    assert(button.Visible==false, 'fallback hides while the menu is open')
    ex.state.setMenuVisible(false)
    assert(button.Visible==true, 'fallback returns when the menu closes')
else
    assert(button.Visible==false, 'desktop with a toggle key does not need the launcher')
end
print('[BOOT-MATRIX] ok')
'''

with tempfile.TemporaryDirectory(prefix='wurst-boot-') as tmp:
    for name, place, count, active, required_key in CASES:
        desktop_cards = None
        game_sources = [path for path in files if active and path.startswith(f'src/games/{active}/')]
        expected_game_sources = '{' + ','.join(f'"{path}"' for path in game_sources) + '}'
        for mobile, fallback in ((False, False), (True, False), (False, True)):
            setup = (f'\ngame.PlaceId={place}\nMOBILE={str(mobile).lower()}\n'
                     f'FALLBACK={str(fallback).lower()}\n'
                     f'EXPECTED_GAME_SOURCES={expected_game_sources}\n'
                     f'UserInputService.TouchEnabled={str(mobile).lower()}\n'
                     f'UserInputService.KeyboardEnabled={str(not mobile).lower()}\n')
            if fallback:
                setup += fallback_sources
            script = source.replace(anchor, setup + anchor, 1) + probe
            mode = 'fallback' if fallback else ('mobile' if mobile else 'desktop')
            path = Path(tmp) / (name.replace(' ', '-') + '-' + mode + '.luau')
            path.write_text(script, encoding='utf-8')
            run = subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], capture_output=True, text=True)
            if run.returncode:
                raise SystemExit(f'{name} {mode}:\n{run.stdout[-2000:]}\n{run.stderr}')
            assert '[BOOT-MATRIX] ok' in run.stdout, f'{name} {mode}: probe did not run'
            assert 'Load complete · failures=0' in run.stdout, f'{name} {mode}: boot did not complete cleanly'
            for error in ('[Wurst:Bootstrap] Skipped ', '[Wurst:Bootstrap] Module failed (',
                          '[Wurst:Bootstrap] Invalid module:', '[HARNESS] task.spawn error:',
                          '[HARNESS] task.defer error:'):
                assert error not in run.stdout, f'{name} {mode}: {error} appeared during boot'
            cards = audit_menu.parse(run.stdout)
            assert len(cards) == count, f'{name} {mode}: expected {count} cards, got {len(cards)}'
            assert not [card for card in cards if card['configKey'] == 'Universal.Shaders'], (
                f'{name} {mode}: the removed Shaders card must not boot'
            )
            assert not [card for card in cards if card['configKey'] in
                        {'Universal.Fling', 'Universal.SwimWalk', 'Universal.AntiVoid'}], (
                f'{name} {mode}: a removed universal card returned'
            )
            prompts = [card for card in cards if card['configKey'] == 'Universal.InteractExtender']
            assert len(prompts) == 1 and prompts[0]['name'] == 'Proximity Prompts', (
                f'{name} {mode}: prompts rename/config compatibility missing'
            )
            if active == 'BedFight':
                assert any(card['name'] == 'Anti Void' and card['section'] == 'BedFight' for card in cards), (
                    'BedFight-specific Anti Void must not be removed with the universal card'
                )
            renamed = {card['name'] for card in cards}
            if active == 'MM2':
                # v190: the two renames and the restored MM2-only Fling card.
                for wanted in ('Invisibility', 'Freeze Animations', 'Fling'):
                    assert wanted in renamed, f'MM2 {mode}: v190 card missing: {wanted}'
                assert 'Ghost' not in renamed and 'Motion Lock' not in renamed, (
                    f'MM2 {mode}: the old card names must be gone'
                )
            for wanted in ('Speed Settings', 'Jump Settings', 'Proximity Prompts', 'Speed Hack', 'Jump Hack'):
                if wanted in renamed:
                    break
            else:
                raise SystemExit(f'{name} {mode}: renamed cards missing: {sorted(renamed)}')
            if not mobile and not fallback:
                desktop_cards = cards
            elif fallback:
                assert cards == desktop_cards, f'{name}: fallback changed cards or option rows'
            if required_key:
                section = 'MVSD' if active == 'X2Duels' else active
                assert any(card['configKey'] == required_key and card['section'] == section for card in cards), (
                    f'{name} {mode}: missing {required_key} in {section}'
                )
            assert f'module={active or "Universal"}' in run.stdout, f'{name} {mode}: wrong game selected'
        print(f'PASS {name}: {count} cards; desktop/mobile and per-source fallback (mock)')

    # Exercise the actual fallback path during boot, not just a manually cleared
    # pill: make the real bundle's Furniture library fail to initialize. The
    # universal-only menu should still release its mobile fallback launcher.
    broken = dict(files)
    broken['src/guis/Wurst/Code/Furniture.lua'] = (
        'return {init=function() error("furniture unavailable") end, '
        'destroy=function() end}'
    )
    stamp, _ = build_bundle.parse_bundle(
        (Path(__file__).resolve().parents[1] / 'src/libraries/bundle.lua').read_text(encoding='utf-8')
    )
    broken_bundle = build_bundle.render(broken, stamp)
    setup = ('\ngame.PlaceId=1\nUserInputService.TouchEnabled=true\n'
             'UserInputService.KeyboardEnabled=false\n'
             'SOURCES["src/libraries/bundle.lua"] = ' + harness.long_bracket(broken_bundle) + '\n')
    broken_probe = r'''
assert(ex.state.pill==nil, 'broken Furniture must not publish a dock')
assert(ex.state.menuReady==true, 'universal boot did not release its fallback')
local root=CoreGui:FindFirstChild('Wurst'); assert(root)
local button=root:FindFirstChild('MobileMenuButton'); assert(button and button.Visible==true)
button.MouseButton1Click:Fire()
assert(ex.state.visible==true, 'fallback launcher should open the universal menu')
print('[BROKEN-DOCK] ok')
'''
    path = Path(tmp) / 'universal-furniture-failure.luau'
    path.write_text(source.replace(anchor, setup + anchor, 1) + broken_probe, encoding='utf-8')
    run = subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], capture_output=True, text=True)
    if run.returncode:
        raise SystemExit(f'Universal with failed dock:\n{run.stdout[-2000:]}\n{run.stderr}')
    assert 'Library failed (src/guis/Wurst/Code/Furniture.lua)' in run.stdout
    assert '[BROKEN-DOCK] ok' in run.stdout
    print('PASS Universal: real mobile fallback after Furniture initialization failure (mock)')

    # The full boot harness runs task.defer immediately. Independently exercise
    # the actual section manager with queued tasks to verify readiness ordering.
    wurst = (Path(__file__).resolve().parents[1] / 'src/Wurst.lua').read_text(encoding='utf-8')
    manager = 'local SectionManager = {' + wurst.split('local SectionManager = {', 1)[1].split(
        '\nlocal function create(className, properties)', 1
    )[0]
    before = r'''
local spawned, deferred = {}, {}
local refreshes, notices = 0, 0
local state = {frameworkEnvironment={notify=function() notices+=1 end},
               refreshLauncher=function() refreshes+=1 end}
local PRODUCT = {name='Wurst', logPrefix='Wurst'}
task = {spawn=function(fn) table.insert(spawned,fn) end,
        defer=function(fn) table.insert(deferred,fn) end}
function warn(...) end
'''
    after = r'''
local function flush(queue) local fn=table.remove(queue,1); assert(fn); fn() end
-- Universal: no game sections, but readiness is still deferred one turn.
SectionManager.initializeAllAsync()
assert(state.menuReady~=true and #deferred==1 and refreshes==0)
flush(deferred); assert(state.menuReady==true and refreshes==1)
-- Known game: the launcher must wait for every registered section.
state.menuReady=nil; SectionManager.entries={}
local built={}
SectionManager.register('A',function() table.insert(built,'A') end)
SectionManager.register('B',function() table.insert(built,'B') end)
SectionManager.initializeAllAsync()
assert(#spawned==2 and state.menuReady~=true and #deferred==0)
flush(spawned); assert(#built==1 and state.menuReady~=true and #deferred==0)
flush(spawned); assert(#built==2 and state.menuReady~=true and #deferred==1)
flush(deferred); assert(state.menuReady==true and refreshes==2)
-- A failed section reports the problem but must not strand the launcher.
state.menuReady=nil; SectionManager.entries={}
SectionManager.register('Fail',function() error('deliberate') end)
SectionManager.initializeAllAsync(); flush(spawned)
assert(notices==1 and state.menuReady~=true and #deferred==1)
flush(deferred); assert(state.menuReady==true and refreshes==3)
print('[ASYNC-READY] ok')
'''
    path = Path(tmp) / 'section-manager-scheduling.luau'
    path.write_text(before + manager + after, encoding='utf-8')
    run = subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], capture_output=True, text=True)
    if run.returncode:
        raise SystemExit(f'Section manager scheduling:\n{run.stdout}\n{run.stderr}')
    assert '[ASYNC-READY] ok' in run.stdout
    print('PASS readiness is deferred until all sections finish, even on failure')
