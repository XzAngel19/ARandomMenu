local Module = {
    Name = "MM2 Gun Aura",
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
    assert(type(core) == "table", "MM2 Gun Aura requires the MM2 core module")
    Module.Runtime = runtime

    local settings = {
        radius = 15,
    }

    -- Resolve the physical part of the gun that we can touch.
    local function resolveGunPart(object: Instance): BasePart?
        if object:IsA("BasePart") then
            return object :: BasePart
        end
        local handle: Instance? = object:FindFirstChild("Handle")
            or object:FindFirstChildWhichIsA("BasePart")
        if handle and handle:IsA("BasePart") then
            return handle :: BasePart
        end
        return nil
    end

    -- Check if this is a loose gun (not in someone's inventory)
    local function isLooseGun(object: Instance): boolean
        if not object:IsA("Tool") then
            return false
        end
        if object.Name ~= "Gun" and not game:GetService("CollectionService"):HasTag(object, "Weapon_Gun") then
            return false
        end
        return object:IsDescendantOf(workspace)
            and not object:FindFirstAncestorOfClass("Backpack")
            and (object.Parent == workspace
                or object.Parent == game:GetService("Workspace"):FindFirstChildOfClass("Model")
                or (object.Parent ~= nil and not object.Parent:FindFirstChildOfClass("Humanoid")))
    end

    -- Pulse the touch between our root and the gun's handle,
    -- like CoinsAura: fire 0 then 1 so the server sees the full
    -- Touched/TouchEnded pair.
    local function touchGun(root: BasePart, gunPart: BasePart): boolean
        if type(state.fireTouchInterest) ~= "function" then
            return false
        end
        pcall(state.fireTouchInterest, root, gunPart, 0)
        pcall(state.fireTouchInterest, root, gunPart, 1)
        return true
    end

    local function characterRoot(): BasePart?
        local character: Model? = LocalPlayer and LocalPlayer.Character
        if not character then
            return nil
        end
        return character:FindFirstChild("HumanoidRootPart") :: BasePart?
    end

    local function toggleGunAura(enabled: boolean): ()
        disconnectFeatureConnection("MM2GunAura")

        if not enabled then
            return
        end

        local lastPulseAt: number = -math.huge

        local function auraTick(): ()
            local root: BasePart? = characterRoot()
            if not root then
                return
            end

            -- Throttle: 0.25 s matches CoinsAura and AutoFarm pulse intervals
            local now: number = os.clock()
            if now - lastPulseAt < 0.25 then
                return
            end

            -- Collect all loose guns in the workspace
            local guns: {BasePart} = {}
            local tagged = game:GetService("CollectionService"):GetTagged("Weapon_Gun")
            for _, object: Instance in ipairs(tagged) do
                if isLooseGun(object) then
                    local part = resolveGunPart(object)
                    if part then
                        table.insert(guns, part)
                    end
                end
            end

            -- Also check direct GunDrop children (faster path)
            local map = game:GetService("Workspace"):FindFirstChildOfClass("Model")
            if map then
                local gunDrop = map:FindFirstChild("GunDrop")
                if gunDrop and (gunDrop:IsA("Model") or gunDrop:IsA("BasePart")) then
                    local part = resolveGunPart(gunDrop)
                    if part then
                        table.insert(guns, part)
                    end
                end
            end

            local rootPos: Vector3 = root.Position
            local radius: number = settings.radius
            local pulsed: boolean = false
            
            for _, gunPart: BasePart in ipairs(guns) do
                if not gunPart.Parent then
                    continue
                end
                local gunPos: Vector3 = gunPart.Position
                if (gunPos - rootPos).Magnitude <= radius then
                    if touchGun(root, gunPart) then
                        pulsed = true
                    end
                end
            end

            if pulsed then
                lastPulseAt = now
            end
        end

        featureConnections.MM2GunAura = TaskManager:Connect(auraTick)
        auraTick()
    end

    local GunAuraFeature: any = createUniversalFeature(
        "Gun Aura",
        "Pulses the touch between your character and every loose gun within the aura radius, grabbing them without moving.",
        7,
        toggleGunAura,
        {
            categoryName = "Utilities",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    state.mm2GunAuraFeature = GunAuraFeature

    addNumberOption(GunAuraFeature, "Aura Radius", 15, 5, 50,
        function(value: number): ()
            settings.radius = value
            if GunAuraFeature.enabled then
                GunAuraFeature:SetStatus(tostring(math.round(value)) .. " studs")
            end
        end,
        "Distance from your character at which guns are touched and grabbed. Higher values reach more guns at once.", 1)

    activeCleanup = function(): ()
        toggleGunAura(false)
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
