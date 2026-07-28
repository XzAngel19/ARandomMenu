# ARandomMenu
Just a Normal Random Menu Nothing else.

## Source layout

```text
src/
├── Supported/
│   ├── MM2.luau
│   └── TRS.luau
├── gui/
│   └── Current/
│       ├── Images/
│       │   └── manifest.json
│       └── gui.lua
├── library/
│   ├── AssetRegistry.luau
│   └── ProfileRegistry.luau
└── Profile/
    ├── 142823291.lua
    └── 14315258385.lua
```

`Supported` contains the game modules enabled by default. Images belong in
`src/gui/Current/Images`, while `src/gui/Current/gui.lua` contains the complete
active interface. Profiles are named after their numeric game ID.
