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

        local function register(option: any): Option
            option.Feature = feature
            created.Options[option.Name] = option
            return option
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
                end,
                definition2.Tooltip
            )
            return register(option)
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
                end,
                definition2.Tooltip
            )
            return register(option)
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
                end,
                definition2.Tooltip
            )
            return register(option)
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
                end,
                definition2.Tooltip
            )
            return register(option)
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
                end,
                definition2.Persist ~= false,
                definition2.Tooltip
            )
            return register(option)
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
                end,
                definition2.Tooltip
            )
            return register(option)
        end

        -- A list is a set, not a choice: "which of the nine swords this game
        -- gave me should the module use" cannot be answered by a dropdown.
        function created:CreateList(definition2: any): Option
            local option: any = newOption(definition2.Name, {})
            option.Selected = {}
            option.Object = host.addListOption(feature, definition2.Name, {
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
                end,
            })
            return register(option)
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
            return register(option)
        end

        function created:CreateSection(name: string): Option
            local option: any = newOption(name, nil)
            option.Object = host.addSectionOption
                and host.addSectionOption(feature, name)
                or nil
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
