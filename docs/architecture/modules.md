# Module authoring contract

A module is gameplay declaration, not GUI code. The GUI may be replaced without changing a module.

## File and lifecycle

A file under `src/modules/<Category>/<Name>.luau` starts with `--!strict` and returns one table:

```lua
local Module = {
    Name = "Example",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    -- build one card and return it
end

function Module.destroy(): ()
    if activeCleanup then pcall(activeCleanup) end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
```

`init` is idempotent at the loader level. `destroy` must be safe after partial initialization and safe when called twice.

## Allowed context surface

A universal module may use:

- `context.framework.Categories.<OfficialCategory>:CreateModule(...)`;
- `context.entity`, `context.weapons` and `context.render` through their published APIs;
- `context.host` engine services (`Players`, `LocalPlayer`, `UserInputService`, `workspace`, `TaskManager`, `HttpService`, `PRODUCT`);
- documented host helpers such as `getCharacterParts`, `notify` and `isMenuOwned`;
- the grouped `context.services` contracts below;
- card lifecycle methods `Loop`, `Render`, `Event`, `Clean`, `Notify`, `SetStatus`;
- option builders listed below.

A module must not use:

- card internals (`row`, `title`, `arrow`, option labels, windows or pixel sizes);
- `ScreenGui`, `PopupLayer`, page/scroll/tab hosts or WindowManager internals;
- private button/pill/toggle/textbox construction for settings;
- `host.state` or any other shell-state reach-in;
- `configData` except a documented module-owned persistence key when no option can represent the data;
- real `print`/`warn`; the injected shadows are silent and diagnostics belong in status/notify;
- renderer or theme geometry.

World instances created for gameplay are allowed. They must be owned by `Clean` or `destroy`.

## Module context services

`ModuleContext` and the service shapes are exported by `src/core/Framework.luau`.
Services group a decision; they are not one wrapper per shell field.

- `movementInput`: movement vector, held-jump state and filtered jump requests;
- `aim`: the device-correct aim ray;
- `menu`: visibility, input-capture state and explicit visibility changes;
- `mobileActions`: placement of a module action on touch devices;
- `protectedTargets`: one shared protection predicate and its Friend List provider;
- `fovOwnership` / `platformStandOwnership`: last-owner arbitration and exact baseline restore;
- `activity`: cross-module activity flags such as an intentional fling;
- `spoofAvatar`: the avatar description and emote catalog shared by Spoof modules;
- `projectileCalibration`: ownership of the calibration controller used during shell teardown;
- `gameBridge`: game role and ESP bridge events;
- `shortcuts`: module activation binding;
- `registries`: Wurst Options and module-search registration.

Module-local settings, caches, rate limits and captured baselines stay local. A module must not publish them through a service merely to make a test inspect them.

## Card

```lua
local card: any
card = context.framework.Categories.Movement:CreateModule({
    Name = "Example",
    Category = "Movement",
    ConfigKey = "Universal.Example", -- preserve forever once shipped
    Tooltip = "Moves the local character at the selected speed.",
    Function = function(enabled: boolean): ()
        if not enabled then return end
        card:Loop(function(deltaTime: number): ()
            -- gameplay only
        end)
    end,
})
```

A one-shot uses `Action = true`. A module with no options declares none; never add a fake row to obtain a settings arrow.

## Option builders

Every option is created in display order. `Show` is declarative; the framework owns visibility after reparent/reopen.

### Toggle

```lua
card:CreateToggle({
    Name = "Wall check",
    Default = true,
    Function = function(value: boolean): () settings.wallCheck = value end,
})
```

### Slider

```lua
card:CreateSlider({
    Name = "Speed",
    Min = 16,
    Max = 200,
    Step = 1,
    Default = 32,
    Function = function(value: number): () settings.speed = value end,
})
```

### Range

```lua
card:CreateTwoSlider({
    Name = "CPS",
    Min = 1,
    Max = 20,
    Step = 1,
    DefaultMin = 8,
    DefaultMax = 12,
    Function = function(low: number, high: number): ()
        settings.low, settings.high = low, high
    end,
})
```

### Dropdown

```lua
card:CreateDropdown({
    Name = "Mode",
    List = {"Velocity", "CFrame"},
    Index = 1,
    Function = function(value: string): () settings.mode = value end,
})
```

### List

```lua
card:CreateList({
    Name = "Objects",
    Items = function(): {string} return known end,
    Default = {},
    Function = function(_selected: any, names: {string}): () wanted = names end,
})
```

### Textbox

```lua
local query = card:CreateTextBox({
    Name = "Player",
    Default = "",
    Function = function(value: string): () settings.player = value end,
})
query:Set("") -- never write query.Object.Text from the module
```

### Bind

```lua
card:CreateBind({
    Name = "Hold key",
    Default = Enum.KeyCode.Unknown,
    Function = function(value: Enum.KeyCode): () settings.key = value end,
})
```

`Unknown` means unbound. Movement controls such as Flight Up/Down are internal controls, not the module activation bind.

### Color

```lua
card:CreateColor({
    Name = "Colour",
    Default = Color3.fromRGB(255, 255, 255),
    Function = function(value: Color3): () settings.colour = value end,
})
```

### Button/action

```lua
card:CreateButton({
    Name = "Reset",
    Function = function(): () resetModuleState() end,
})
```

Actions use the canonical rectangular action widget. They never masquerade as toggles.

### Note

```lua
card:CreateNote("Empty uses the equipped tool.")
```

A note explains a non-obvious constraint. It is not a section heading or filler.

## Show rules

```lua
card:CreateSlider({
    Name = "Burst delay",
    Show = {Option = "Mode", Values = {"Teleport"}},
    Min = 0.05, Max = 1, Step = 0.05, Default = 0.2,
})
```

A list of rules is AND. Omitted `Values` means a true toggle. `Invert = true` negates one rule. The referenced option must exist. Modules never call row visibility methods.

## Teardown

- Per-frame gameplay: `card:Loop`.
- Camera-aligned drawing: `card:Render`.
- Signals: `card:Event`.
- Instances/functions/handles: `card:Clean`.
- Exact borrowed properties are cached per instance and restored on disable and destroy.
- A direct connection not passed to `Event`/`Clean` is a leak.
- AnimationTracks are stopped **and destroyed**.
- Settings-window close does not disable gameplay; full teardown removes windows, tasks and connections.

Proof lives in `tools/test/suites/clickgui-boot.luau`, the focused module suites and `tools/test/suites/teardown.luau`: all 38 cards open/reopen settings, preserve values/Show/enabled, toggle safely and return task/connection counts to baseline.

## Current audited exceptions

- `AnimationChanger` and `EmotePlayer` use documented module-owned saved-ID keys in `host.configData` because the saved catalog is not one scalar option.

Universal modules have no direct `host.state` access and no row/window/pixel dependency. `tools/check_module_conformance.py` blocks either reach-in.
