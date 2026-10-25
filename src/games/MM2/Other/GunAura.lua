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
        studs = 10,
    }

    local gunAuraActive = false
    local gunHitboxes: {[Instance]: BasePart} = {}
    local espParts: {BasePart} = {}

    local function canAct(): boolean
        -- Check if we're in a valid state to act
        local character = LocalPlayer.Character
        if not character then return false end
        
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then return false end
        
        -- Check if we're in lobby (no active map)
        if type(core.findMM2Map) == "function" then
            local map = core.findMM2Map()
            if not map then
                -- No active map = we're in lobby
                return false
            end
        end
        
        -- Check our role - only act if we're Innocent or Hero (can pick up gun)
        if type(core.getPlayerRole) == "function" then
            local role = core.getPlayerRole()
            if role == "Murderer" or role == "Sheriff" then
                -- Don't auto-pickup if we're already murderer or sheriff
                return false
            end
        end
        
        return true
    end

    -- Create a transparent square hitbox around a gun
    local function createGunHitbox(gun: Instance): BasePart?
        local handle = gun:FindFirstChild("Handle")
        if not handle or not handle:IsA("BasePart") then return nil end
        
        local part = Instance.new("Part")
        part.Name = "WurstGunAuraHitbox_" .. gun:GetDebugId()
        part.Size = Vector3.new(settings.studs, settings.studs, settings.studs)
        part.Transparency = 0.7
        part.BrickColor = BrickColor.new("White")
        part.Material = Enum.Material.Neon
        part.CanCollide = false
        part.Anchored = true
        part.CFrame = handle.CFrame
        part.Parent = workspace
        
        return part
    end

    -- Find all dropped guns in the map
    local function findDroppedGuns(): {Instance}
        local guns = {}
        
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("Tool") and obj.Name == "Gun" then
                -- Check if it's a dropped gun (not held by a character)
                local parent = obj.Parent
                if parent and not parent:IsA("Model") then
                    -- Gun is in workspace directly (dropped)
                    table.insert(guns, obj)
                elseif parent and parent:IsA("Model") then
                    -- Check if parent is a character with Humanoid
                    local humanoid = parent:FindFirstChildOfClass("Humanoid")
                    if not humanoid then
                        -- Parent is not a character, so gun is dropped
                        table.insert(guns, obj)
                    end
                end
            end
        end
        
        return guns
    end

    -- Check if our character is touching a gun hitbox
    local function isTouchingHitbox(hitbox: BasePart): boolean
        local character = LocalPlayer.Character
        if not character then return false end
        
        local root = character:FindFirstChild("HumanoidRootPart")
        if not root then return false end
        
        -- Check if root is inside the hitbox bounds
        local hitboxCFrame = hitbox.CFrame
        local hitboxSize = hitbox.Size
        local localPos = hitboxCFrame:PointToObjectSpace(root.Position)
        
        return math.abs(localPos.X) <= hitboxSize.X / 2
            and math.abs(localPos.Y) <= hitboxSize.Y / 2
            and math.abs(localPos.Z) <= hitboxSize.Z / 2
    end

    -- Try to grab a gun using firetouchinterest
    local function tryGrabGun(gun: Instance): boolean
        local handle = gun:FindFirstChild("Handle")
        if not handle or not handle:IsA("BasePart") then return false end
        
        local character = LocalPlayer.Character
        if not character then return false end
        
        local root = character:FindFirstChild("HumanoidRootPart")
        if not root then return false end
        
        -- Use firetouchinterest to grab the gun
        if type(state.fireTouchInterest) == "function" then
            pcall(state.fireTouchInterest, root, handle, 0)
            pcall(state.fireTouchInterest, root, handle, 1)
            return true
        end
        
        return false
    end

    -- Create ESP marker for dead sheriff (hacker detection)
    local function createSheriffESP(player: Player): BasePart?
        local character = player.Character
        if not character then return nil end
        
        local root = character:FindFirstChild("HumanoidRootPart")
        if not root then return nil end
        
        -- Check if this player is supposed to be sheriff but is dead in wrong location
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health > 0 then return nil end
        
        -- Create white ESP marker
        local esp = Instance.new("Part")
        esp.Name = "WurstDeadSheriffESP_" .. player.Name
        esp.Size = Vector3.new(3, 3, 3)
        esp.Transparency = 0.3
        esp.BrickColor = BrickColor.new("White")
        esp.Material = Enum.Material.Neon
        esp.CanCollide = false
        esp.Anchored = true
        esp.CFrame = root.CFrame
        esp.Parent = workspace
        
        return esp
    end

    local function gunAuraTick(): ()
        if not gunAuraActive then return end
        
        -- Check if we can act (not in lobby, not dead, correct role)
        if not canAct() then
            -- Clean up hitboxes when we can't act
            for _, hitbox in pairs(gunHitboxes) do
                if hitbox and hitbox.Parent then
                    hitbox:Destroy()
                end
            end
            gunHitboxes = {}
            return
        end
        
        -- Find all dropped guns
        local guns = findDroppedGuns()
        
        -- Update hitboxes for each gun
        for _, gun in ipairs(guns) do
            if gun and gun.Parent then
                local hitbox = gunHitboxes[gun]
                
                -- Create hitbox if it doesn't exist
                if not hitbox or not hitbox.Parent then
                    hitbox = createGunHitbox(gun)
                    if hitbox then
                        gunHitboxes[gun] = hitbox
                    end
                else
                    -- Update hitbox position to follow the gun
                    local handle = gun:FindFirstChild("Handle")
                    if handle and handle:IsA("BasePart") then
                        hitbox.CFrame = handle.CFrame
                    end
                end
                
                -- Check if we're touching this hitbox
                if hitbox and isTouchingHitbox(hitbox) then
                    tryGrabGun(gun)
                end
            end
        end
        
        -- Clean up hitboxes for guns that no longer exist
        for gun, hitbox in pairs(gunHitboxes) do
            if not gun or not gun.Parent then
                if hitbox and hitbox.Parent then
                    hitbox:Destroy()
                end
                gunHitboxes[gun] = nil
            end
        end
        
        -- Check for dead sheriff ESP (hacker detection)
        -- Only show ESP for players who appear to be sheriff but are dead
        if type(core.getPlayerRole) == "function" then
            for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
                if player ~= LocalPlayer then
                    local role = core.getPlayerRole(player)
                    if role == "Sheriff" then
                        local esp = createSheriffESP(player)
                        if esp then
                            table.insert(espParts, esp)
                        end
                    end
                end
            end
        end
    end

    local function toggleGunAura(enabled: boolean): ()
        gunAuraActive = enabled
        
        -- Clean up all hitboxes and ESP when disabled
        if not enabled then
            for _, hitbox in pairs(gunHitboxes) do
                if hitbox and hitbox.Parent then
                    hitbox:Destroy()
                end
            end
            gunHitboxes = {}
            
            for _, esp in ipairs(espParts) do
                if esp and esp.Parent then
                    esp:Destroy()
                end
            end
            espParts = {}
            
            disconnectFeatureConnection("MM2GunAura")
        else
            featureConnections.MM2GunAura = TaskManager:Connect(gunAuraTick)
            gunAuraTick()
        end
    end

    local GunAuraFeature: any = createUniversalFeature(
        "Gun Aura",
        "Creates a transparent white square around dropped guns. When your character touches this square, automatically grabs the gun. Only works when you're alive, in-round, and an Innocent/Hero. Detects dead sheriff hackers with white ESP.",
        7,
        toggleGunAura,
        {
            categoryName = "Utilities",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    state.mm2GunAuraFeature = GunAuraFeature

    addNumberOption(GunAuraFeature, "Studs", 10, 5, 50,
        function(value: number): ()
            settings.studs = value
            if GunAuraFeature.enabled then
                GunAuraFeature:SetStatus(tostring(value) .. " studs")
            end
        end,
        "Size of the transparent hitbox square around each dropped gun. Your character must touch this square to auto-grab the gun.", 1)

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
