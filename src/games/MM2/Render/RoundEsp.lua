local Module = {
    Name = "MM2 Round ESP",
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}

local activeCleanup: () -> () = function(): () end

function Module.init(runtime: any): any
    if Module.Initialized then
        return Module
    end
    local core: any = state.mm2Core
    assert(type(core) == "table", "MM2 Round ESP requires the MM2 core module")
    Module.Runtime = runtime
    local GunEffects: any = core.GunEffects
    local TrapEffects: any = core.TrapEffects
    local clearEffects: any = core.clearEffects
    local createMM2Cham: any = core.createMM2Cham
    local createMM2Marker: any = core.createMM2Marker
    local findDroppedGun: any = core.findDroppedGun
    local findMM2Map: any = core.findMM2Map
    local mm2Settings: any = core.mm2Settings

    local function toggleGunEsp(enabled: boolean): ()
        disconnectFeatureConnection("MM2GunESP")
        clearEffects(GunEffects)

        if not enabled then
            return
        end

        local elapsed: number = 1
        local markedGun: Instance? = nil
        featureConnections.MM2GunESP = TaskManager:Connect(function(deltaTime: number): ()
            elapsed += deltaTime
            if elapsed < 0.4 then
                return
            end
            elapsed = 0
            local gun: any = findDroppedGun()
            if gun == markedGun and (gun == nil or gun.Parent ~= nil) then
                return
            end
            markedGun = gun
            clearEffects(GunEffects)
            if gun then
                createMM2Marker(
                    GunEffects,
                    gun,
                    "Gun",
                    mm2Settings.gunColor,
                    mm2Settings.gunTransparency
                )
            end
        end, nil, "MM2 Gun ESP")
    end

    local savedTrapTransparency: {[Instance]: number} =
        setmetatable({}, {__mode = "k"}) :: any

    local function restoreTrapTransparency(): ()
        for part: Instance, orig: number in pairs(savedTrapTransparency) do
            (part :: BasePart).Transparency = orig
        end
        table.clear(savedTrapTransparency)
    end

    local function revealTrapPart(part: Instance): ()
        if not part:IsA("BasePart") then return end
        local current: number = (part :: BasePart).Transparency
        if current >= 0.95 then
            if savedTrapTransparency[part] == nil then
                savedTrapTransparency[part] = current
            end
            (part :: BasePart).Transparency = 0.35
        end
    end

    local function toggleTrapEsp(enabled: boolean): ()
        disconnectFeatureConnection("MM2TrapAdded")
        restoreTrapTransparency()
        clearEffects(TrapEffects)

        if not enabled then
            return
        end

        local marked = setmetatable({}, {__mode = "k"})
        local function addTrap(object: Instance): ()
            if marked[object] then
                return
            end
            if (object.Name == "TrapVisual" or object.Name == "Trap")
                and (object:IsA("Model") or object:IsA("BasePart")) then
                local parent: Instance? = (object :: any).Parent
                if parent and marked[parent] then
                    revealTrapPart(object)
                    return
                end
                marked[object] = true
                revealTrapPart(object)
                for _, child: Instance in ipairs(object:GetDescendants()) do
                    revealTrapPart(child)
                end
                createMM2Cham(
                    TrapEffects,
                    object,
                    mm2Settings.trapColor,
                    mm2Settings.trapTransparency
                )
            end
        end

        local map = findMM2Map()
        for _, object in ipairs((map or workspace):GetDescendants()) do
            addTrap(object)
        end
        if map then
            for _, child: Instance in ipairs(workspace:GetChildren()) do
                addTrap(child)
            end
        end
        featureConnections.MM2TrapAdded = workspace.DescendantAdded:Connect(addTrap)
    end

    core.toggleGunEsp = toggleGunEsp
    core.toggleTrapEsp = toggleTrapEsp

    local unregister = {}
    local itemEsp = services and services.itemEsp
    assert(itemEsp and type(itemEsp.register) == "function", "MM2 item ESP requires the provider service")
    for _, provider in ipairs({
        {name = "Gun ESP", tooltip = "Highlights the dropped MM2 gun while ItemESP is ON.", setEnabled = toggleGunEsp},
        {name = "Trap ESP", tooltip = "Highlights existing and newly placed MM2 traps while ItemESP is ON.", setEnabled = toggleTrapEsp},
    }) do
        local release = itemEsp.register(provider)
        if release then table.insert(unregister, release) end
    end

    activeCleanup = function(): ()
        for _, release in ipairs(unregister) do pcall(release) end
        table.clear(unregister)
        toggleGunEsp(false)
        toggleTrapEsp(false)
    end

    Module.Events = featureConnections
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    if not Module.Initialized then
        return
    end
    Module.Initialized = false
    pcall(activeCleanup)
    activeCleanup = function(): () end
    Module.Events = {}
    Module.Runtime = nil
end

return Module
