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
        studs = 15,
    }

    local gunAuraActive = false
    local hitboxPart = nil

    -- Create a white hitbox part that will be attached to the gun
    local function createHitbox(): BasePart
        local part = Instance.new("Part")
        part.Name = "WurstGunAuraHitbox"
        part.Size = Vector3.new(3, 3, 3)
        part.Transparency = 0.5
        part.BrickColor = BrickColor.new("White")
        part.Material = Enum.Material.Neon
        part.CanCollide = false
        part.Anchored = false
        part.Massless = true
        return part
    end

    -- Find dropped guns within range
    local function findDroppedGuns(): {BasePart}
        local guns = {}
        local localRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not localRoot then return guns end

        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("Tool") and obj.Name == "Gun" then
                -- Check if it's a dropped gun (in workspace, not in a character)
                if not obj:FindFirstAncestorOfClass("Model") or not obj:FindFirstAncestorOfClass("Model"):FindFirstChildOfClass("Humanoid") then
                    local handle = obj:FindFirstChild("Handle")
                    if handle and handle:IsA("BasePart") then
                        local distance = (handle.Position - localRoot.Position).Magnitude
                        if distance <= settings.studs then
                            table.insert(guns, handle)
                        end
                    end
                end
            end
        end

        return guns
    end

    -- Touch the gun with our hitbox to pick it up
    local function touchGun(gunPart: BasePart): boolean
        if not hitboxPart or not hitboxPart.Parent then return false end
        
        -- Position hitbox at gun location
        hitboxPart.CFrame = gunPart.CFrame
        
        -- Use firetouchinterest to pick up the gun
        if type(state.fireTouchInterest) == "function" then
            local localRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if localRoot then
                pcall(state.fireTouchInterest, localRoot, gunPart, 0)
                pcall(state.fireTouchInterest, localRoot, gunPart, 1)
                return true
            end
        end
        
        return false
    end

    local function gunAuraTick(): ()
        if not gunAuraActive then return end
        
        local character = LocalPlayer.Character
        if not character then return end
        
        local root = character:FindFirstChild("HumanoidRootPart")
        if not root then return end
        
        -- Ensure hitbox exists and is parented to character
        if not hitboxPart or not hitboxPart.Parent then
            hitboxPart = createHitbox()
            hitboxPart.Parent = character
        end
        
        -- Find and touch all guns in range
        local guns = findDroppedGuns()
        for _, gun in ipairs(guns) do
            touchGun(gun)
        end
    end

    local function toggleGunAura(enabled: boolean): ()
        gunAuraActive = enabled
        
        -- Clean up hitbox when disabled
        if not enabled and hitboxPart then
            hitboxPart:Destroy()
            hitboxPart = nil
        end
        
        if enabled then
            featureConnections.MM2GunAura = TaskManager:Connect(gunAuraTick)
            gunAuraTick()
        else
            disconnectFeatureConnection("MM2GunAura")
        end
    end

    local GunAuraFeature: any = createUniversalFeature(
        "Gun Aura",
        "Creates a white hitbox around dropped guns. When your character touches this hitbox, automatically picks up the gun. Works like Grab Gun but for all guns in range.",
        7,
        toggleGunAura,
        {
            categoryName = "Utilities",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    state.mm2GunAuraFeature = GunAuraFeature

    addNumberOption(GunAuraFeature, "Studs", 15, 5, 100,
        function(value: number): ()
            settings.studs = value
            if GunAuraFeature.enabled then
                GunAuraFeature:SetStatus(tostring(value) .. " studs")
            end
        end,
        "Distance in studs to detect and pick up dropped guns. Higher values can reach more guns but may cause kicks at extreme values.", 1)

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
