# C7 — permissive historical tests

Active suites must not convert missing behaviour into a green check.
`tools/check_permissive_tests.py` holds that. The allowlist at
`tools/test/permissive-allowlist.txt` is empty: every staged gap on this
tip already has a real contract.

`C_PERMISSIVE_RETIRED`

## Retired branches

| Suite | Old green | Now |
| --- | --- | --- |
| clickgui-boot | ClickGui is not on disk yet | require fails the suite |
| chrome | ClickGui not on disk; Combat waits; pin/collapse "not yet"; closable still green | on disk; pin/collapse/no-close are hard when Combat exists |
| autolocalize | helpers do not yet disable AutoLocalize | helpers disable AutoLocalize |
| clickgui | windows / HUD / filled row "not published yet" | windows + hudList published; rows use applyCardSkin |
| slider-numeric | framework not on the host yet | boot asserts the framework |
| keybind-square | square waits on A; live square waits on Cards | toggle + live square must exist |
| navigator-escape | back-button row waits on A | the dock is Navigator's return control |
| furniture | HackList / wordmark / pill / tooltip "not published yet" | host stub no longer greens; boot holds list, delay, Position=Left |
| command-dock | dock not published; Execute / Return / KeypadEnter wait on A | dock published; FocusLost(true) is Enter; one submit = one Execute |
| dock-visibility | Show dock waits on A; mobile setter not published | Show dock setting/setter required; mobile setter required |
| empty-categories | empty windows still pre-created; hide waits on A | empty Blocks/Chat/Items are not visible windows |
| bitmap-quality | pickAtlas ceiling waits on A | covering-size rule is required |
| navigator | preference sorting waits on a populated grid | grid must be populated |
| visual-rc | P2 / APPLY-4 "demonstrated debt" | no disabled-option API; owner lifetime is watchPopupOwner |
| placement-final | ChoiceList / owner-close / scroll-clip wait | opener published; owner close hard; scroll-clip held in source |
| ui-settings | UI Settings is not published yet | boots the shell and reads defaults |

## Remaining allowlist

None. Scroll-clip cannot be exercised in the mock (`AbsolutePosition` stays
0); the suite holds `watchPopupOwner` + `CanvasPosition` in the bundle
instead of a green skip.

## Analyzer baseline (no typing pass)

`luau-analyze --defs=env.d.luau` without Roblox instance defs. Unknown
globals that the shell actually publishes are filtered by validate's
existing lint step. Counts below are raw analyzer lines (type errors +
unknown globals + lints) per subsystem, taken on this tip. They are a
report, not a gate. Context types wait until D removes the direct
`host.state` surface.

Raw analyzer lines on this tip (mostly missing Roblox instance types,
not unknown-global defects validate already gates):

| subsystem | files | analyzer lines |
| --- | ---: | ---: |
| src/core | 2 | 41 |
| src/library | 11 | 2142 |
| src/modules | 38 | 1130 |
| src/games | 5 | 2515 |
| tools/test | 59 | 16596 |

Regenerate with:

```
for d in src/core src/library src/modules src/games tools/test; do
  find "$d" -name '*.luau' | while read f; do
    luau-analyze --defs=env.d.luau "$f" 2>&1 | wc -l
  done | awk -v d="$d" '{s+=$1} END {print d, s}'
done
```
