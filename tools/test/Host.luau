--!strict
--
-- Host stand-in for the headless module tests.
--
-- Mirrors the environment `ARandomMenu.luau` hands to downloaded files: the
-- card factory, the option builders, the task manager and the shared `state`
-- helpers. Every option builder records what it was asked for, so a test can
-- assert that a module declared the controls it claims to have — and every
-- builder invokes the module's callback exactly like the real one does, which
-- is how a mismatched default or a callback that throws gets caught here
-- instead of in a game.

local Mock = require("./Roblox")

export type HostStub = {
    env: any,
    features: {any},
    notifications: {string},
    step: (deltaTime: number) -> (),
    taskCount: () -> number,
}

local Host = {}

function Host.create(world: any): HostStub
    local tasks: {any} = {}
    local features: {any} = {}
    local notifications: {string} = {}

    local function create(className: string, properties: any): any
        local instance: any = Mock.newInstance(className)
        local parent: any = nil
        for key: string, value: any in pairs(properties or {}) do
            if key == "Parent" then
                parent = value
            else
                instance[key] = value
            end
        end
        if parent then
            instance.Parent = parent
        end
        return instance
    end

    local function makeTextLabel(parent: any, text: string, size: number): any
        return create("TextLabel", {
            Parent = parent,
            Text = text,
            TextSize = size,
        })
    end

    local function makeButton(parent: any, text: string, size: number): any
        return create("TextButton", {
            Parent = parent,
            Text = text,
            TextSize = size,
        })
    end

    local screenGui: any = Mock.newInstance("ScreenGui")

    local function optionRow(feature: any, label: string): any
        local row: any = create("Frame", {Parent = screenGui, Name = label})
        table.insert(feature.optionRows, row)
        return row
    end

    local host: any = {}

    host.createUniversalFeature = function(
        name: string,
        description: string,
        order: number,
        onToggle: any,
        configuration: any
    ): any
        local feature: any = {
            name = name,
            description = description,
            order = order,
            configKey = "Universal." .. name:gsub("%W", ""),
            categoryName = (configuration or {}).categoryName or "General",
            kind = (configuration or {}).kind or "toggle",
            enabled = false,
            onToggle = onToggle,
            optionRows = {},
            options = {},
        }
        function feature.activate(): ()
            -- Action cards run and keep no state, exactly like the real card.
            if feature.kind == "action" then
                onToggle(true)
                return
            end
            feature.enabled = not feature.enabled
            onToggle(feature.enabled)
        end
        table.insert(features, feature)
        return feature
    end

    host.addToggleOption = function(
        feature: any,
        label: string,
        default: boolean,
        callback: any,
        _hint: string?
    ): any
        local button: any = makeButton(optionRow(feature, label), label, 11)
        feature.options[label] = {kind = "toggle", value = default}
        -- The real builder replays the stored value so panels that fold
        -- controls away start in the right shape.
        callback(default)
        return button
    end

    host.addNumberOption = function(
        feature: any,
        label: string,
        default: number,
        minimum: number,
        maximum: number,
        callback: any,
        _hint: string?
    ): any
        assert(
            default >= minimum and default <= maximum,
            label .. ": default " .. tostring(default) .. " is outside its range"
        )
        feature.options[label] = {kind = "number", value = default}
        callback(default)
        return optionRow(feature, label)
    end

    host.addCycleOption = function(
        feature: any,
        label: string,
        values: {string},
        index: number,
        callback: any,
        _hint: string?
    ): any
        assert(#values > 0, label .. ": empty cycle list")
        assert(values[index] ~= nil, label .. ": index outside the list")
        feature.options[label] = {kind = "cycle", value = values[index], list = values}
        callback(values[index])
        return makeButton(optionRow(feature, label), values[index], 11)
    end

    host.addKeyOption = function(
        feature: any,
        label: string,
        default: any,
        callback: any,
        _hint: string?
    ): any
        feature.options[label] = {kind = "key", value = default}
        callback(default)
        return makeButton(optionRow(feature, label), "KEY", 9)
    end

    host.addTextOption = function(
        feature: any,
        label: string,
        default: string,
        callback: any,
        _persist: boolean?,
        _hint: string?
    ): any
        feature.options[label] = {kind = "text", value = default}
        callback(default)
        return create("TextBox", {Parent = optionRow(feature, label)})
    end

    host.addColorOption = function(
        feature: any,
        label: string,
        default: any,
        callback: any,
        _hint: string?
    ): any
        feature.options[label] = {kind = "colour", value = default}
        callback(default)
        return makeButton(optionRow(feature, label), "", 10)
    end

    host.addActionOption = function(
        feature: any,
        label: string,
        callback: any,
        _hint: string?
    ): any
        feature.options[label] = {kind = "action", run = callback}
        return makeButton(optionRow(feature, label), "RUN", 11)
    end

    host.addListOption = function(feature: any, label: string, definition: any): any
        local selected: {[string]: boolean} = {}
        for _, name: string in ipairs(definition.default or {}) do
            selected[name] = true
        end
        local button: any = makeButton(optionRow(feature, label), "", 11)
        local entry: any = {
            kind = "list",
            selected = selected,
            items = definition.items,
            changed = definition.onChanged,
        }
        function entry.set(name: string, on: boolean): ()
            selected[name] = on or nil
            local names: {string} = {}
            for value: string, isOn: boolean in pairs(selected) do
                if isOn then
                    table.insert(names, value)
                end
            end
            table.sort(names)
            if definition.onChanged then
                definition.onChanged(selected, names)
            end
        end
        feature.options[label] = entry
        if definition.onChanged then
            definition.onChanged(selected, {})
        end
        return button
    end

    host.addSectionOption = function(feature: any, label: string): any
        return optionRow(feature, label)
    end

    host.addInformationOption = function(feature: any, text: string): ()
        feature.description = feature.description .. "\n" .. text
    end

    host.setOptionVisible = function(_feature: any, row: any, visible: boolean): ()
        if row then
            row.Visible = visible
        end
    end

    host.TaskManager = {
        Connect = function(_self: any, callback: any): any
            local handle: any = {callback = callback, Connected = true}
            function handle:Disconnect(): ()
                handle.Connected = false
                local index: number? = table.find(tasks, handle)
                if index then
                    table.remove(tasks, index)
                end
            end
            table.insert(tasks, handle)
            return handle
        end,
    }

    host.notify = function(message: string): ()
        table.insert(notifications, message)
    end

    host.create = create
    host.makeTextLabel = makeTextLabel
    host.makeButton = makeButton
    host.ScreenGui = screenGui
    host.Players = world.players
    host.LocalPlayer = world.localPlayer
    host.workspace = world.workspace
    host.UserInputService = {
        IsKeyDown = function(_self: any, _key: any): boolean
            return world.keyDown == true
        end,
        GetMouseLocation = function(): any
            return world.vector2(640, 360)
        end,
        KeyboardEnabled = true,
        TouchEnabled = false,
    }
    host.UserInputService.InputBegan = Mock.signal()
    host.state = {
        menuVisible = true,
        setMenuVisible = function(visible: boolean): ()
            host.state.menuVisible = visible
        end,
        keyCaptureCallback = nil,
        waitingForKey = false,
        -- Modules bind their card's key slot through this; the stub records
        -- the pair so a test can arm and release a hold binding directly.
        bindFeatureActivationKey = function(
            feature: any,
            _key: any,
            press: any,
            release: any
        ): ()
            world.bindings = world.bindings or {}
            world.bindings[feature.name] = {press = press, release = release}
        end,
        getAimRay = function(): any
            return world.aimRay
        end,
        getMoveInput = function(): (number, number)
            return 0, 0
        end,
        isJumpHeld = function(): boolean
            return false
        end,
    }

    return {
        env = host,
        features = features,
        notifications = notifications,
        step = function(deltaTime: number): ()
            for _, handle: any in ipairs(table.clone(tasks)) do
                if handle.Connected then
                    handle.callback(deltaTime)
                end
            end
        end,
        taskCount = function(): number
            return #tasks
        end,
    }
end

return Host
