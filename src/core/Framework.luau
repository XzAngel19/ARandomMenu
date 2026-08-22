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
    OptionMetadata: {any},

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
    Render: (self: Module, callback: (number) -> ()) -> any,
    Event: (self: Module, signal: any, callback: (...any) -> ()) -> any,
    CleanAll: (self: Module) -> (),
    Toggle: (self: Module, value: boolean?) -> (),
    Notify: (self: Module, message: string) -> (),
    SetStatus: (self: Module, status: string?) -> (),
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
-- The shared category contract: official Wurst 7's eight windows, matching
-- the shell's OFFICIAL_CATEGORIES and ClickGui's CATEGORY_ORDER. Pre-created
-- so module files can index straight into `framework.Categories.Combat`
-- without a nil check.
local KNOWN_CATEGORIES: {string} = {
    "Combat",
    "Render",
    "Blocks",
    "Movement",
    "Chat",
    "Fun",
    "Items",
    "Other",
}

local activeFramework: Framework? = nil

local function isKnownCategory(name: string): boolean
    return table.find(KNOWN_CATEGORIES, name) ~= nil
end

-- The port's old names, answering with the official category until D refiles
-- each module (docs/wurst-categories.md is the per-card map). This table must
-- agree with the shell's CATEGORY_ALIASES — it is the same contract, copied
-- because a downloaded core file cannot reach the shell's locals at require
-- time.
local CATEGORY_ALIASES: {[string]: string} = {
    ["Visuals"] = "Render",
    ["Protection"] = "Movement",
    ["Utility"] = "Other",
    ["Spoof"] = "Fun",
    ["General"] = "Other",
    ["Player"] = "Movement",
}

local function canonicalCategory(name: string): string
    if isKnownCategory(name) then
        return name
    end
    return CATEGORY_ALIASES[name] or "Other"
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

    local function normalizeSearchName(value: any): string
        return string.lower(tostring(value or "")):gsub("[%s%-%_]", "")
    end
    local moduleSearch: any = {
        entries = {},
        aliases = {
            esp = "playeresp",
            playeresp = "playeresp",
            itemesp = "itemesp",
            autoclicker = "autoclicker",
            killaura = "killaura",
            fly = "flight",
            speed = "speedhack",
            nofall = "nofall",
        },
    }
    function moduleSearch.Register(feature: any): ()
        if type(feature) ~= "table" then
            return
        end
        local normalized: string = normalizeSearchName(feature.name)
        local entry: any = {
            normalized = normalized,
            displayName = feature.name,
            configKey = feature.configKey,
            aliases = {},
            kind = feature.kind,
            searchable = feature.searchable ~= false,
            feature = feature,
            activate = feature.activate,
        }
        for alias: string, target: string in pairs(moduleSearch.aliases) do
            if target == normalized then
                table.insert(entry.aliases, alias)
            end
        end
        table.sort(entry.aliases)
        function entry.enabled(): boolean
            return feature.enabled == true
        end
        table.insert(moduleSearch.entries, entry)
    end
    function moduleSearch.Unregister(feature: any): ()
        for index: number = #moduleSearch.entries, 1, -1 do
            if moduleSearch.entries[index].feature == feature then
                table.remove(moduleSearch.entries, index)
            end
        end
    end
    function moduleSearch.Resolve(query: any): any
        local normalized: string = normalizeSearchName(query)
        if normalized == "" then
            return {status = "not_found"}
        end
        normalized = moduleSearch.aliases[normalized] or normalized
        local matches: {any} = {}
        for _, entry: any in ipairs(moduleSearch.entries) do
            if entry.searchable and entry.normalized == normalized then
                table.insert(matches, entry)
            end
        end
        if #matches == 0 then
            return {status = "not_found"}
        end
        if #matches > 1 then
            return {status = "ambiguous", matches = matches}
        end
        return {status = "success", entry = matches[1]}
    end
    function moduleSearch.Execute(query: any): any
        local result: any = moduleSearch.Resolve(query)
        if result.status ~= "success" then
            return result
        end
        local entry: any = result.entry
        if entry.kind ~= "toggle" and entry.kind ~= "action" then
            return {status = "not_toggleable", entry = entry}
        end
        if type(entry.activate) ~= "function" then
            return {status = "not_toggleable", entry = entry}
        end
        entry.activate()
        return {
            status = "success",
            entry = entry,
            enabled = entry.enabled(),
        }
    end
    host.state.moduleSearch = moduleSearch

    -- The option table is built before the control, because every builder
    -- replays the stored value through the callback the moment the row is
    -- created — a callback that would otherwise be writing into a table that
    -- does not exist yet.
    local function newOption(
        name: string,
        initialValue: any,
        optionType: string,
        definition: any?
    ): any
        local source: any = definition or {}
        local defaultValue: any = initialValue
        if type(initialValue) == "table" then
            defaultValue = table.clone(initialValue)
        end
        local step: number? = source.Step
        if step == nil and (optionType == "slider" or optionType == "range") then
            local integerOnly: boolean = type(source.Min) == "number"
                and type(source.Max) == "number"
                and source.Min % 1 == 0
                and source.Max % 1 == 0
                and ((type(initialValue) == "number" and initialValue % 1 == 0)
                    or (type(initialValue) == "table"
                        and initialValue.Min % 1 == 0
                        and initialValue.Max % 1 == 0))
            step = integerOnly and 1 or 0
        end
        local option: any = {
            Name = name,
            Value = initialValue,
            Object = nil,
            Metadata = {
                id = "",
                configKey = "",
                label = name,
                type = optionType,
                default = defaultValue,
                current = initialValue,
                min = source.Min,
                max = source.Max,
                step = step,
                values = source.List and table.clone(source.List) or nil,
                callback = source.Function,
                show = source.Show,
                visible = source.Show == nil,
                action = optionType == "action",
                bind = optionType == "bind",
                color = optionType == "color",
                rangeLow = source.DefaultMin,
                rangeHigh = source.DefaultMax,
            },
        }
        function option:SetValue(value: any): ()
            self.Value = value
            self.Metadata.current = value
            if type(value) == "table" and value.Min ~= nil and value.Max ~= nil then
                self.Metadata.rangeLow = value.Min
                self.Metadata.rangeHigh = value.Max
            end
        end
        function option:SetVisible(visible: boolean): ()
            self.Metadata.visible = visible
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
            OptionMetadata = {},
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
                searchable = definition.Searchable ~= false,
                registry = definition.Registry,
                parent = definition.Parent,
                configKey = definition.ConfigKey,
            }
        )
        created.Feature = feature
        feature.frameworkModule = true

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
            local optionId: string = option.Name:gsub("%W", "")
            option.Metadata.id = optionId
            option.Metadata.configKey = feature.configKey .. "." .. optionId
            local gated: boolean = false
            if definition2 and type(definition2.Show) == "table" then
                option.Show = definition2.Show
                gated = true
            end
            created.Options[option.Name] = option
            table.insert(created.OptionMetadata, option.Metadata)
            feature.optionMetadata = created.OptionMetadata
            -- A rule arriving is itself a reason to run the pass.
            --
            -- Rules used to be evaluated only when some option's *value*
            -- changed, and a rule is attached after its own builder has
            -- finished — so the last gated row of a panel stayed on screen
            -- until something else moved. Every module worked around it by
            -- ending its panel with an ungated row, or by calling
            -- `RefreshVisibility()` by hand: an ordering rule nobody can see
            -- in the code and everybody has to remember.
            if gated then
                created:RefreshVisibility()
            end
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

        local function valueCallback(option: any, definition2: any): (any) -> ()
            local function changed(value: any): ()
                option:SetValue(value)
                if type(definition2.Function) == "function" then
                    definition2.Function(value)
                end
                created:RefreshVisibility()
            end
            option.Metadata.callback = changed
            return changed
        end

        function created:CreateToggle(definition2: any): Option
            local option: any = newOption(definition2.Name, definition2.Default == true, "toggle", definition2)
            option.Object = host.addToggleOption(
                feature,
                definition2.Name,
                definition2.Default == true,
                valueCallback(option, definition2),
                definition2.Tooltip
            )
            return register(option, definition2)
        end

        function created:CreateSlider(definition2: any): Option
            local default: number = definition2.Default or definition2.Min or 0
            local option: any = newOption(definition2.Name, default, "slider", definition2)
            option.Object = host.addNumberOption(
                feature,
                definition2.Name,
                default,
                definition2.Min or 0,
                definition2.Max or 100,
                valueCallback(option, definition2),
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
            local option: any = newOption(definition2.Name, {Min = low, Max = high}, "range", definition2)
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
            local function rangeChanged(newLow: number, newHigh: number): ()
                option:SetValue({Min = newLow, Max = newHigh})
                if type(definition2.Function) == "function" then
                    definition2.Function(newLow, newHigh)
                end
                created:RefreshVisibility()
            end
            option.Metadata.callback = rangeChanged
            option.Object = builder(feature, definition2.Name, {
                min = minimum,
                max = maximum,
                step = definition2.Step,
                defaultLow = low,
                defaultHigh = high,
                integer = definition2.Decimal == nil,
                hint = definition2.Tooltip,
                onChanged = rangeChanged,
            })
            return register(option, definition2)
        end

        function created:CreateDropdown(definition2: any): Option
            local list: {string} = definition2.List or {}
            local index: number = definition2.Index or 1
            local option: any = newOption(definition2.Name, list[index], "dropdown", definition2)
            option.Object = host.addCycleOption(
                feature,
                definition2.Name,
                list,
                index,
                valueCallback(option, definition2),
                definition2.Tooltip
            )
            return register(option, definition2)
        end

        function created:CreateBind(definition2: any): Option
            local default: Enum.KeyCode = definition2.Default or Enum.KeyCode.Unknown
            local option: any = newOption(definition2.Name, default, "bind", definition2)
            option.Object = host.addKeyOption(
                feature,
                definition2.Name,
                default,
                valueCallback(option, definition2),
                definition2.Tooltip
            )
            return register(option, definition2)
        end

        function created:CreateTextBox(definition2: any): Option
            local default: string = definition2.Default or ""
            local option: any = newOption(definition2.Name, default, "text", definition2)
            option.Object = host.addTextOption(
                feature,
                definition2.Name,
                default,
                valueCallback(option, definition2),
                definition2.Persist ~= false,
                definition2.Tooltip
            )
            return register(option, definition2)
        end

        function created:CreateColor(definition2: any): Option
            local default: Color3 = definition2.Default or Color3.new(1, 1, 1)
            local option: any = newOption(definition2.Name, default, "color", definition2)
            option.Object = host.addColorOption(
                feature,
                definition2.Name,
                default,
                valueCallback(option, definition2),
                definition2.Tooltip
            )
            return register(option, definition2)
        end

        -- A list is a set, not a choice: "which of the nine swords this game
        -- gave me should the module use" cannot be answered by a dropdown.
        function created:CreateList(definition2: any): Option
            local option: any = newOption(definition2.Name, {}, "list", definition2)
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
            local function listChanged(selected: any, names: {string}): ()
                option:SetValue(selected)
                option.Selected = names
                if type(definition2.Function) == "function" then
                    definition2.Function(selected, names)
                end
                created:RefreshVisibility()
            end
            option.Metadata.callback = listChanged
            option.Object = builder(feature, definition2.Name, {
                items = definition2.Items,
                default = definition2.Default,
                hint = definition2.Tooltip,
                emptyText = definition2.EmptyText,
                onChanged = listChanged,
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
            local option: any = newOption(definition2.Name, nil, "action", definition2)
            local function run(): ()
                if type(definition2.Function) == "function" then
                    definition2.Function()
                end
            end
            option.Metadata.callback = run
            option.Object = host.addActionOption(
                feature,
                definition2.Name,
                run,
                definition2.Tooltip
            )
            return register(option, definition2)
        end

        function created:CreateSection(name: string): Option
            local option: any = newOption(name, nil, "section", nil)
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

        -- Anything that draws from the camera belongs here rather than on
        -- `Loop`. Heartbeat runs after the frame has been rendered, so an
        -- overlay built there is always showing the previous frame's camera
        -- and swims behind the world whenever the player turns.
        function created:Render(callback: (number) -> ()): any
            return created:Clean(host.TaskManager:Connect(callback, "render"))
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

        -- The status belongs to the card, which every module has, rather than
        -- to this wrapper, which only eighteen of them do. This forwards.
        function created:SetStatus(status: string?): ()
            created.Status = status
            if feature and type(feature.SetStatus) == "function" then
                feature:SetStatus(status)
            end
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
        -- One category object per official window. Asking for an old port
        -- name ("Visuals") answers with the official category it maps to, so
        -- a module that has not been refiled yet lands in one of Wurst's
        -- eight windows instead of dying on a nil index.
        local canonical: string = canonicalCategory(name)
        local category: any = framework.Categories[canonical]
        if not category then
            category = {
                Name = canonical,
                Modules = {},
            }
            function category:CreateModule(definition: any): Module
                return createModule(category, definition)
            end
            framework.Categories[canonical] = category
        end
        if name ~= canonical then
            framework.Categories[name] = category
        end
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
        if host.state.moduleSearch == moduleSearch then
            host.state.moduleSearch = nil
        end
        table.clear(moduleSearch.entries)
        if activeFramework == framework then
            activeFramework = nil
        end
    end

    -- Pre-create the taxonomy so module files can index straight into
    -- `framework.Categories.Combat` without a nil check — including the old
    -- port names, which answer with the official category they map to.
    for _, name: string in ipairs(KNOWN_CATEGORIES) do
        framework:GetCategory(name)
    end
    for oldName: string in pairs(CATEGORY_ALIASES) do
        framework:GetCategory(oldName)
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
