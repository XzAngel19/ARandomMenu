# D → A visual integration notes

Base composed from `b47dd40` plus A core `52a02ee`.

## Settings-window internals

- Module option rows remain owned by the canonical builders and are reparented by `WindowManager.OpenFeatureSettings`; D added no second container.
- Category rows remain fixed-height. Settings windows reuse `FeatureSettings_<configKey>`, preserve values/Show/enabled, and release their own connections on teardown.
- No module now creates decorative section rows or parents options to legacy scrolls.
- Rejoin Server is registered once through Wurst Options and is absent from Other when that API exists.

## Composition fixes consumed from A

- `ClickGui.Retile()` now calls the manager clamp after assigning each slot, so A's physical-pixel snap covers reset layout as well as create/drag/reflow.
- Cards keybind tooltip width/wrap now uses `bitmapText.measure` and `bitmapText.wrap`; bitmap draw uses `ellipsis=true`.
- Furniture dock tooltip uses the same measure/wrap/draw contract.

## Shared behaviour

- `state.SetMenuStyle(style, openImmediately)` is the one surface switch.
- `state.moduleSearch` is the one command resolver/executor; the old shell function is only a notification wrapper.
- Dock and HackList visibility are independent of module state.

No renderer, Widgets geometry, WindowManager geometry, keybind-square geometry, atlas, font tool or module gameplay was changed in this pass.
