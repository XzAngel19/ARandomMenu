export type CleanupItem = any

export type MovementInputService = {
    getVector: () -> (number, number),
    isJumpHeld: () -> boolean,
    onJumpRequest: ((() -> ())) -> RBXScriptConnection,
}

export type OwnershipService<T> = {
    set: (ownerId: string, value: T?) -> (),
    apply: (instance: Instance?) -> (),
}

export type ModuleServices = {
    movementInput: MovementInputService,
    aim: {getRay: () -> Ray?},
    screenCapture: {
        isAvailable: () -> boolean,
        capture: (string) -> (boolean, string?),
        writeText: (string, string) -> boolean,
    },
    menu: {
        isVisible: () -> boolean,
        isCapturingInput: () -> boolean,
        setVisible: (boolean) -> (),
    },
    mobileActions: {bindPlacement: (...any) -> any},
    protectedTargets: {
        isProtected: (Player?) -> boolean,
        setProvider: (((Player?) -> boolean)?) -> (),
    },
    fovOwnership: OwnershipService<number>,
    platformStandOwnership: OwnershipService<boolean>,
    activity: {
        set: (string, boolean) -> (),
        isActive: (string) -> boolean,
    },
    spoofAvatar: any,
    projectileCalibration: any,
    gameBridge: any,
    shortcuts: any,
    registries: any,
}

export type ModuleContext = {
    framework: Framework,
    entity: any,
    weapons: any,
    render: any,
    libraries: {[string]: any},
    host: any,
    services: ModuleServices,
}

export type Option = {
    Name: string,

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

local KNOWN_CATEGORIES: {string} = {
    "Combat",
    "Blatant",
    "Render",
    "Blocks",
    "Movement",
    "Fun",
    "Items",
    "Other",
}

local activeFramework: Framework? = nil

local function isKnownCategory(name: string): boolean
    return table.find(KNOWN_CATEGORIES, name) ~= nil
end

local CATEGORY_ALIASES: {[string]: string} = {
    ["Visuals"] = "Render",
    ["Protection"] = "Movement",
    ["Utility"] = "Other",
    ["World"] = "Other",
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
        local binding: any = host.state.shortcutBindings
            and host.state.shortcutBindings[feature.configKey]
        local entry: any = {
            normalized = normalized,
            displayName = feature.name,
            configKey = feature.configKey,
            actionId = feature.configKey,
            aliases = {},
            kind = feature.kind,
            searchable = feature.searchable ~= false,
            feature = feature,
            activate = feature.activate,
            invoke = feature.activate,
        }
        function entry.currentKey(): any
            return binding and binding.key or Enum.KeyCode.Unknown
        end
        function entry.conflict(): boolean
            local key: any = entry.currentKey()
            if key == nil or key == Enum.KeyCode.Unknown then
                return false
            end
            local uses: number = 0
            for _, candidate: any in pairs(host.state.shortcutBindings or {}) do
                if candidate.key == key then
                    uses += 1
                end
            end
            return uses > 1
        end
        function entry.capture(key: Enum.KeyCode): boolean
            return binding ~= nil and binding.assign(key) == true
        end
        function entry.remove(): ()
            if binding and binding.key ~= Enum.KeyCode.Unknown then
                binding.assign(binding.key)
            end
        end
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

            if gated then
                created:RefreshVisibility()
            end
            return option
        end

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
                definition2.Tooltip,
                definition2.Step
            )
            return register(option, definition2)
        end

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
            option.Set = function(self: any, value: string): ()
                self.Metadata.callback(value)
                if self.Object then
                    self.Object.Text = value
                end
            end
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

        function created:CreateList(definition2: any): Option
            local option: any = newOption(definition2.Name, {}, "list", definition2)
            option.Selected = {}

            local builder: any = host.addListOption
                or (host.state and host.state.addListOption)
            if type(builder) ~= "function" then

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

        function created:Render(callback: (number) -> ()): any
            return created:Clean(host.TaskManager:Connect(callback, "render"))
        end

        function created:Event(signal: any, callback: (...any) -> ()): any
            return created:Clean(signal:Connect(callback))
        end

        function created:CleanAll(): ()
            local items: {CleanupItem} = created.Cleanup
            created.Cleanup = {}

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
