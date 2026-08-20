--!strict
--
-- Module framework.
--
-- The menu used to be one 14,000-line file where every module inlined its own
-- UI wiring, its own connection bookkeeping and its own teardown. Vape V4 gets
-- around the same problem with a tiny kernel — categories own modules, modules
-- own options, and everything a module allocates goes on a cleanup list that is
-- emptied the moment it is switched off. This is that kernel, expressed against
-- this menu's own card/option API instead of Vape's GUI library.
--
-- A module file therefore reads as a declaration:
--
--     local Module = framework.Categories.Combat:CreateModule({
--         Name = "TriggerBot",
--         Tooltip = "Fires the equipped tool at whatever the crosshair is on",
--         Function = function(enabled: boolean): ()
--             if not enabled then
--                 return
--             end
--             Module:Loop(function(deltaTime: number): ()
--                 ...
--             end)
--         end,
--     })
--     local Delay = Module:CreateSlider({Name = "Delay", Min = 0, Max = 1})
--
-- and never touches connection tables, config keys or card layout.

export type CleanupItem = any

export type Option = {
    Name: string,
    -- Live value, kept in sync by the option's own callback so a module can
    -- read `Slider.Value` inside a loop instead of caching every setting in a
    -- table of its own.
    Value: any,
    Object: any,
    SetVisible: (self: Option, visible: boolean) -> (),
}

export type Module = {
    Name: string,
    Category: string,
    Enabled: boolean,
    Feature: any,
    Options: {[string]: Option},

    CreateToggle: (self: Module, definition: any) -> Option,
    CreateSlider: (self: Module, definition: any) -> Option,
    CreateTwoSlider: (self: Module, definition: any) -> Option,
    CreateDropdown: (self: Module, definition: any) -> Option,
    CreateBind: (self: Module, definition: any) -> Option,
    CreateTextBox: (self: Module, definition: any) -> Option,
    CreateColor: (self: Module, definition: any) -> Option,
    CreateList: (self: Module, definition: any) -> Option,
    CreateButton: (self: Module, definition: any) -> Option,
    CreateSection: (self: Module, name: string) -> Option,
    CreateNote: (self: Module, text: string) -> (),

    Clean: (self: Module, item: CleanupItem) -> CleanupItem,
    Loop: (self: Module, callback: (number) -> ()) -> any,
    Event: (self: Module, signal: any, callback: (...any) -> ()) -> any,
    CleanAll: (self: Module) -> (),
    Toggle: (self: Module, value: boolean?) -> (),
    Notify: (self: Module, message: string) -> (),
}

export type Category = {
    Name: string,
    Modules: {Module},
    CreateModule: (self: Category, definition: any) -> Module,
}

export type Framework = {
    Categories: {[string]: Category},
    Modules: {[string]: Module},
    Order: {string},
    Host: any,
    GetCategory: (self: Framework, name: string) -> Category,
    GetModule: (self: Framework, name: string) -> Module?,
    DisableAll: (self: Framework) -> (),
    Destroy: (self: Framework) -> (),
}

local Module = {
    Name = "Framework",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

-- The categories a module can be filed under. They mirror the page taxonomy
-- the card grid already sorts by, so a module declaring `Category = "Combat"`
-- lands in the Combat block with no further wiring.
local KNOWN_CATEGORIES: {string} = {
    "Movement",
    "Combat",
    "Visuals",
    "Protection",
    "Utility",
}

local activeFramework: Framework? = nil

local function isKnownCategory(name: string): boolean
    return table.find(KNOWN_CATEGORIES, name) ~= nil
end

-- Cleanup accepts whatever a module happens to be holding: a signal
-- connection, an instance, a task handle or a plain function. Guessing here
-- once is what lets every module stay free of teardown code.
local function disposeItem(item: CleanupItem): ()
    if item == nil then
        return
    end
    local itemType: string = typeof(item)
    if itemType == "function" then
        pcall(item :: any)
        return
    end
    if itemType == "RBXScriptConnection" then
        pcall(function(): ()
            (item :: any):Disconnect()
        end)
        return
    end
    if itemType == "Instance" then
        pcall(function(): ()
            (item :: any):Destroy()
        end)
        return
    end
    if itemType == "table" then
        local candidate: any = item
        if type(candidate.Disconnect) == "function" then
            pcall(candidate.Disconnect, candidate)
            return
        end
        if type(candidate.Destroy) == "function" then
            pcall(candidate.Destroy, candidate)
            return
        end
        if type(candidate.disconnect) == "function" then
            pcall(candidate.disconnect, candidate)
            return
        end
    end
end

function Module.init(context: any): Framework
    local host: any = context
    local framework: any = {
        Categories = {},
        Modules = {},
        Order = {},
        Host = host,
    }

    -- The option table is built before the control, because every builder
    -- replays the stored value through the callback the moment the row is
    -- created — a callback that would otherwise be writing into a table that
    -- does not exist yet.
    local function newOption(name: string, initialValue: any): any
        local option: any = {
            Name = name,
            Value = initialValue,
            Object = nil,
        }
        function option:SetVisible(visible: boolean): ()
            local row: any = self.Object
            if typeof(row) == "Instance" and row.ClassName ~= "Frame" then
                row = row.Parent
            end
            if host.setOptionVisible and row then
                host.setOptionVisible(self.Feature, row, visible)
            end
        end
        return option
    end

    local function createModule(category: any, definition: any): Module
        local moduleName: string = definition.Name
        local categoryName: string = definition.Category or category.Name
        local created: any = {
            Name = moduleName,
            Category = categoryName,
            Enabled = false,
            Options = {},
            Cleanup = {},
        }

        -- The card only ever sees one callback. Enabling runs the module's own
        -- `Function`; disabling runs it too and then empties the cleanup list,
        -- so a module that forgets to disconnect something still cannot leak.
        local function onToggle(enabled: boolean?): ()
            local nextState: boolean = enabled == true
            created.Enabled = nextState
            if not nextState then
                created:CleanAll()
            end
            local handler: any = definition.Function
            if type(handler) == "function" then
                handler(nextState)
            end
            if not nextState then
                -- Anything the disable branch allocated is not part of the
                -- next session either.
                created:CleanAll()
            end
        end

        local kind: string = definition.Kind
            or (definition.Action == true and "action")
            or "toggle"
        local feature: any = host.createUniversalFeature(
            moduleName,
            definition.Tooltip or definition.Description or "",
            definition.Order or (#category.Modules + 1),
            kind == "action" and function(): ()
                if type(definition.Function) == "function" then
                    definition.Function(true)
                end
            end or onToggle,
            {
                categoryName = categoryName,
                kind = kind,
                silentAction = definition.Silent == true,
                registry = definition.Registry,
                parent = definition.Parent,
                configKey = definition.ConfigKey,
            }
        )
        created.Feature = feature

        -- Conditional rows, declared rather than wired.
        --
        -- A module used to hide its own controls by hand: a toggle whose
        -- Function walked a list of other options calling SetVisible. That is
        -- three places to keep in step (the list, the callback, the initial
        -- pass), and it is why panels drifted into showing rows that did
        -- nothing — Click Teleport asked for a player name while you were
        -- teleporting to an item.
        --
        -- An option says what it depends on instead:
        --
        --     teleport:CreateTextBox({
        --         Name = "Player",
        --         Show = {Option = "Destination", Values = {"Named player"}},
        --     })
        --
        -- and the kernel hides it whenever that is not true. `Values` omitted
        -- means "while the other option is on", which covers a toggle gating
        -- a group.
        local function register(option: any, definition2: any?): Option
            option.Feature = feature
            if definition2 and type(definition2.Show) == "table" then
                option.Show = definition2.Show
            end
            created.Options[option.Name] = option
            return option
        end

        -- One rule, or a list of rules that all have to hold — "the advanced
        -- block is open *and* the activation is Hold key" is two facts, and a
        -- row that needs both should not have to pick one.
        local function ruleHolds(rule: any): boolean
            local source: any = created.Options[rule.Option]
            local holds: boolean = false
            if source ~= nil then
                if type(rule.Values) == "table" then
                    for _, wanted: any in ipairs(rule.Values) do
                        if source.Value == wanted then
                            holds = true
                            break
                        end
                    end
                else
                    holds = source.Value == true
                end
            end
            if rule.Invert == true then
                return not holds
            end
            return holds
        end

        function created:RefreshVisibility(): ()
            for _, option: any in pairs(created.Options) do
                local rule: any = option.Show
                if type(rule) ~= "table" then
                    continue
                end
                local visible: boolean = true
                if rule.Option ~= nil then
                    visible = ruleHolds(rule)
                else
                    for _, nested: any in ipairs(rule) do
                        if not ruleHolds(nested) then
                            visible = false
                            break
                        end
                    end
                end
                if option.Visible ~= visible then
                    option.Visible = visible
                    option:SetVisible(visible)
                end
            end
        end

        function created:CreateToggle(definition2: any): Option
            local option: any = newOption(definition2.Name, definition2.Default == true)
            option.Object = host.addToggleOption(
                feature,
                definition2.Name,
                definition2.Default == true,
                function(value: boolean): ()
                    option.Value = value
                    if type(definition2.Function) == "function" then
                        definition2.Function(value)
                    end
                    created:RefreshVisibility()
                end,
                definition2.Tooltip
            )
            return register(option, definition2)
        end

        function created:CreateSlider(definition2: any): Option
            local default: number = definition2.Default or definition2.Min or 0
            local option: any = newOption(definition2.Name, default)
            option.Object = host.addNumberOption(
                feature,
                definition2.Name,
                default,
                definition2.Min or 0,
                definition2.Max or 100,
                function(value: number): ()
                    option.Value = value
                    if type(definition2.Function) == "function" then
                        definition2.Function(value)
                    end
                    created:RefreshVisibility()
                end,
                definition2.Tooltip
            )
            return register(option, definition2)
        end

        -- A range is one setting, not two. `Value` stays a table so a module
        -- reads `CPS.Value.Min`, and `GetRandomValue()` is the whole point of
        -- the control: a rate drawn between the two ends every time it is
        -- asked for, which is what stops a loop from running at a constant,
        -- perfectly machine-shaped interval.
        function created:CreateTwoSlider(definition2: any): Option
            local minimum: number = definition2.Min or 0
            local maximum: number = definition2.Max or 100
            local low: number = definition2.DefaultMin or minimum
            local high: number = definition2.DefaultMax or maximum
            local option: any = newOption(definition2.Name, {Min = low, Max = high})
            local builder: any = host.addRangeOption
                or (host.state and host.state.addRangeOption)
            option.GetRandomValue = function(_self: any): number
                local band: any = option.Value
                local lowValue: number = band.Min
                local highValue: number = math.max(band.Max, lowValue)
                return lowValue + math.random() * (highValue - lowValue)
            end
            if type(builder) ~= "function" then
                return register(option)
            end
            option.Object = builder(feature, definition2.Name, {
                min = minimum,
                max = maximum,
                defaultLow = low,
                defaultHigh = high,
                integer = definition2.Decimal == nil,
                hint = definition2.Tooltip,
                onChanged = function(newLow: number, newHigh: number): ()
                    option.Value = {Min = newLow, Max = newHigh}
                    if type(definition2.Function) == "function" then
                        definition2.Function(newLow, newHigh)
                    end
                    created:RefreshVisibility()
                end,
            })
            return register(option, definition2)
        end

        function created:CreateDropdown(definition2: any): Option
            local list: {string} = definition2.List or {}
            local index: number = definition2.Index or 1
            local option: any = newOption(definition2.Name, list[index])
            option.Object = host.addCycleOption(
                feature,
                definition2.Name,
                list,
                index,
                function(value: string): ()
                    option.Value = value
                    if type(definition2.Function) == "function" then
                        definition2.Function(value)
                    end
                    created:RefreshVisibility()
                end,
                definition2.Tooltip
            )
            return register(option, definition2)
        end

        function created:CreateBind(definition2: any): Option
            local default: Enum.KeyCode = definition2.Default or Enum.KeyCode.Unknown
            local option: any = newOption(definition2.Name, default)
            option.Object = host.addKeyOption(
                feature,
                definition2.Name,
                default,
                function(value: Enum.KeyCode): ()
                    option.Value = value
                    if type(definition2.Function) == "function" then
                        definition2.Function(value)
                    end
                    created:RefreshVisibility()
                end,
                definition2.Tooltip
            )
            return register(option, definition2)
        end

        function created:CreateTextBox(definition2: any): Option
            local default: string = definition2.Default or ""
            local option: any = newOption(definition2.Name, default)
            option.Object = host.addTextOption(
                feature,
                definition2.Name,
                default,
                function(value: string): ()
                    option.Value = value
                    if type(definition2.Function) == "function" then
                        definition2.Function(value)
                    end
                    created:RefreshVisibility()
                end,
                definition2.Persist ~= false,
                definition2.Tooltip
            )
            return register(option, definition2)
        end

        function created:CreateColor(definition2: any): Option
            local default: Color3 = definition2.Default or Color3.new(1, 1, 1)
            local option: any = newOption(definition2.Name, default)
            option.Object = host.addColorOption(
                feature,
                definition2.Name,
                default,
                function(value: Color3): ()
                    option.Value = value
                    if type(definition2.Function) == "function" then
                        definition2.Function(value)
                    end
                    created:RefreshVisibility()
                end,
                definition2.Tooltip
            )
            return register(option, definition2)
        end

        -- A list is a set, not a choice: "which of the nine swords this game
        -- gave me should the module use" cannot be answered by a dropdown.
        function created:CreateList(definition2: any): Option
            local option: any = newOption(definition2.Name, {})
            option.Selected = {}
            -- `state` is the fallback for hosts that expose the builder
            -- there rather than in the module environment.
            local builder: any = host.addListOption
                or (host.state and host.state.addListOption)
            if type(builder) ~= "function" then
                -- A missing builder must cost one row, not the whole panel.
                return register(option)
            end
            local optionKey: string = feature.configKey
                .. "."
                .. definition2.Name:gsub("%W", "")
            option.Object = builder(feature, definition2.Name, {
                items = definition2.Items,
                default = definition2.Default,
                hint = definition2.Tooltip,
                emptyText = definition2.EmptyText,
                onChanged = function(selected: any, names: {string}): ()
                    option.Value = selected
                    option.Selected = names
                    if type(definition2.Function) == "function" then
                        definition2.Function(selected, names)
                    end
                    created:RefreshVisibility()
                end,
            })
            -- Tick, untick and re-read from the module side.
            local controls: any = host.state
                and host.state.listControls
                and host.state.listControls[optionKey]
            option.Set = function(_self: any, item: string, on: boolean): ()
                if controls then
                    controls.set(item, on)
                end
            end
            option.Refresh = function(_self: any): ()
                if controls then
                    controls.refresh()
                end
            end
            option.IsSelected = function(_self: any, item: string): boolean
                if controls then
                    return controls.selected[item] == true
                end
                return false
            end
            return register(option, definition2)
        end

        function created:CreateButton(definition2: any): Option
            local option: any = newOption(definition2.Name, nil)
            option.Object = host.addActionOption(
                feature,
                definition2.Name,
                function(): ()
                    if type(definition2.Function) == "function" then
                        definition2.Function()
                    end
                end,
                definition2.Tooltip
            )
            return register(option, definition2)
        end

        function created:CreateSection(name: string): Option
            local option: any = newOption(name, nil)
            option.Object = host.addSectionOption
                and host.addSectionOption(feature, name)
                or nil
            -- A heading takes no definition; a caller that wants one to follow
            -- a gate sets `.Show` on the option it gets back.
            return register(option)
        end

        function created:CreateNote(text: string): ()
            if host.addInformationOption then
                host.addInformationOption(feature, text)
            end
        end

        function created:Clean(item: CleanupItem): CleanupItem
            table.insert(created.Cleanup, item)
            return item
        end

        function created:Loop(callback: (number) -> ()): any
            return created:Clean(host.TaskManager:Connect(callback))
        end

        function created:Event(signal: any, callback: (...any) -> ()): any
            return created:Clean(signal:Connect(callback))
        end

        function created:CleanAll(): ()
            local items: {CleanupItem} = created.Cleanup
            created.Cleanup = {}
            -- Reverse order: the last thing allocated is usually the thing
            -- depending on everything before it.
            for index: number = #items, 1, -1 do
                disposeItem(items[index])
            end
        end

        function created:Toggle(value: boolean?): ()
            if value ~= nil and value == created.Enabled then
                return
            end
            if feature and type(feature.activate) == "function" then
                feature.activate()
                return
            end
            onToggle(not created.Enabled)
        end

        function created:Notify(message: string): ()
            if host.notify then
                host.notify(moduleName .. ": " .. message)
            end
        end

        table.insert(category.Modules, created)
        framework.Modules[moduleName] = created
        table.insert(framework.Order, moduleName)
        return (created :: any) :: Module
    end

    function framework:GetCategory(name: string): Category
        local existing: any = framework.Categories[name]
        if existing then
            return existing
        end
        local category: any = {
            Name = isKnownCategory(name) and name or "Utility",
            Modules = {},
        }
        function category:CreateModule(definition: any): Module
            return createModule(category, definition)
        end
        framework.Categories[name] = category
        return (category :: any) :: Category
    end

    function framework:GetModule(name: string): Module?
        return framework.Modules[name]
    end

    function framework:DisableAll(): ()
        for _, moduleName: string in ipairs(framework.Order) do
            local entry: any = framework.Modules[moduleName]
            if entry and entry.Enabled then
                pcall(function(): ()
                    entry:Toggle(false)
                end)
            end
            if entry then
                pcall(function(): ()
                    entry:CleanAll()
                end)
            end
        end
    end

    function framework:Destroy(): ()
        framework:DisableAll()
        framework.Categories = {}
        framework.Modules = {}
        framework.Order = {}
        if activeFramework == framework then
            activeFramework = nil
        end
    end

    -- Pre-create the taxonomy so module files can index straight into
    -- `framework.Categories.Combat` without a nil check.
    for _, name: string in ipairs(KNOWN_CATEGORIES) do
        framework:GetCategory(name)
    end

    activeFramework = (framework :: any) :: Framework
    Module.Initialized = true
    return (framework :: any) :: Framework
end

function Module.destroy(): ()
    local framework: Framework? = activeFramework
    if framework then
        framework:Destroy()
    end
    activeFramework = nil
    Module.Initialized = false
end

return Module
