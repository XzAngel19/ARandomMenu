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
    local espParts: {[Player]: BasePart} = {}

    local function resolveGunTouchPart(gun: Instance?): BasePart?
        if not gun then
            return nil
        end
        if gun:IsA("BasePart") then
            return gun :: BasePart
        end
        local handle: Instance? = gun:FindFirstChild("Handle", true)
            or gun:FindFirstChildWhichIsA("BasePart", true)
        if handle and handle:IsA("BasePart") then
            return handle :: BasePart
        end
        return nil
    end

    local function canAct(): boolean
        local character = LocalPlayer and LocalPlayer.Character
        if not character then
            return false
        end

        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then
            return false
        end

        if type(core.findMM2Map) == "function" then
            local map = core.findMM2Map()
            if not map then
                return false
            end
        end

        if type(core.isRoundLifecycleActive) == "function"
            and core.isRoundLifecycleActive() == false then
            return false
        end

        if type(core.getPlayerRole) == "function" then
            local role = core.getPlayerRole(LocalPlayer)
            if role == "Murderer" or role == "Sheriff" or role == "Hero" then
                return false
            end
        end

        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        if (backpack and backpack:FindFirstChild("Gun"))
            or character:FindFirstChild("Gun") then
            return false
        end

        return true
    end

    local function createGunHitbox(gun: Instance): BasePart?
        local handle = resolveGunTouchPart(gun)
        if not handle then
            return nil
        end

        local part = Instance.new("Part")
        part.Name = "WurstGunAuraHitbox"
        part.Size = Vector3.new(settings.studs, settings.studs, settings.studs)
        part.Transparency = 0.7
        part.BrickColor = BrickColor.new("White")
        part.Material = Enum.Material.Neon
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
        part.Anchored = true
        part.CFrame = handle.CFrame
        part.Parent = workspace

        return part
    end

    -- Find all dropped guns in the map using core.findDroppedGun + fast GunDrop/tag checks
    local function findDroppedGuns(): {Instance}
        local guns: {Instance} = {}
        local seen: {[Instance]: boolean} = {}

        local function addGun(candidate: Instance?): ()
            if not candidate or seen[candidate] or not candidate.Parent then
                return
            end
            if resolveGunTouchPart(candidate) then
                seen[candidate] = true
                table.insert(guns, candidate)
            end
        end

        if type(core.findDroppedGun) == "function" then
            local ok: boolean, drop: any = pcall(core.findDroppedGun)
            if ok and drop then
                addGun(drop)
            end
        end

        if type(core.findMM2Map) == "function" then
            local okMap: boolean, map: any = pcall(core.findMM2Map)
            if okMap and map then
                local gunDrop = map:FindFirstChild("GunDrop")
                if gunDrop then
                    addGun(gunDrop)
                end
            end
        end

        local wsDrop = workspace:FindFirstChild("GunDrop")
        if wsDrop then
            addGun(wsDrop)
        end

        local okTagged: boolean, tagged: any = pcall(function(): any
            return game:GetService("CollectionService"):GetTagged("Weapon_Gun")
        end)
        if okTagged and type(tagged) == "table" then
            for _, obj: Instance in ipairs(tagged) do
                if obj:IsA("Tool") and obj:IsDescendantOf(workspace)
                    and not obj:FindFirstAncestorOfClass("Backpack") then
                    local parent = obj.Parent
                    if parent and not parent:FindFirstChildOfClass("Humanoid") then
                        addGun(obj)
                    end
                end
            end
        end

        return guns
    end

    local function isTouchingHitbox(hitbox: BasePart): boolean
        local character = LocalPlayer and LocalPlayer.Character
        if not character then
            return false
        end

        local root = character:FindFirstChild("HumanoidRootPart")
        if not root or not root:IsA("BasePart") then
            return false
        end

        local hitboxCFrame = hitbox.CFrame
        local hitboxSize = hitbox.Size
        local localPos = hitboxCFrame:PointToObjectSpace(root.Position)

        return math.abs(localPos.X) <= hitboxSize.X / 2
            and math.abs(localPos.Y) <= hitboxSize.Y / 2
            and math.abs(localPos.Z) <= hitboxSize.Z / 2
    end

    local function tryGrabGun(gun: Instance): boolean
        local handle = resolveGunTouchPart(gun)
        if not handle then
            return false
        end

        local character = LocalPlayer and LocalPlayer.Character
        if not character then
            return false
        end

        local root = character:FindFirstChild("HumanoidRootPart")
        if not root or not root:IsA("BasePart") then
            return false
        end

        if type(state.fireTouchInterest) == "function" then
            pcall(state.fireTouchInterest, root, handle, 0)
            pcall(state.fireTouchInterest, root, handle, 1)
            return true
        end

        return false
    end

    local function clearAllHitboxes(): ()
        for gun, hitbox in pairs(gunHitboxes) do
            if hitbox and hitbox.Parent then
                pcall(function(): ()
                    hitbox:Destroy()
                end)
            end
            gunHitboxes[gun] = nil
        end
    end

    local function clearAllEsp(): ()
        for player, esp in pairs(espParts) do
            if esp and esp.Parent then
                pcall(function(): ()
                    esp:Destroy()
                end)
            end
            espParts[player] = nil
        end
    end

    local function updateSheriffESP(player: Player): ()
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not character or not root or not root:IsA("BasePart")
            or not humanoid or humanoid.Health > 0 then
            local existing = espParts[player]
            if existing then
                if existing.Parent then
                    pcall(function(): ()
                        existing:Destroy()
                    end)
                end
                espParts[player] = nil
            end
            return
        end

        local esp = espParts[player]
        if not esp or not esp.Parent then
            esp = Instance.new("Part")
            esp.Name = "WurstDeadSheriffESP_" .. player.Name
            esp.Size = Vector3.new(3, 3, 3)
            esp.Transparency = 0.3
            esp.BrickColor = BrickColor.new("White")
            esp.Material = Enum.Material.Neon
            esp.CanCollide = false
            esp.CanQuery = false
            esp.CanTouch = false
            esp.Anchored = true
            esp.Parent = workspace
            espParts[player] = esp
        end
        esp.CFrame = (root :: BasePart).CFrame
    end

    local function gunAuraTick(): ()
        if not gunAuraActive then
            return
        end

        if not canAct() then
            clearAllHitboxes()
            return
        end

        local guns = findDroppedGuns()
        local activeGuns: {[Instance]: boolean} = {}

        for _, gun in ipairs(guns) do
            if gun and gun.Parent then
                activeGuns[gun] = true
                local hitbox = gunHitboxes[gun]

                if not hitbox or not hitbox.Parent then
                    hitbox = createGunHitbox(gun)
                    if hitbox then
                        gunHitboxes[gun] = hitbox
                    end
                else
                    local handle = resolveGunTouchPart(gun)
                    if handle then
                        hitbox.Size = Vector3.new(settings.studs, settings.studs, settings.studs)
                        hitbox.CFrame = handle.CFrame
                    end
                end

                if hitbox and isTouchingHitbox(hitbox) then
                    tryGrabGun(gun)
                end
            end
        end

        for gun, hitbox in pairs(gunHitboxes) do
            if not activeGuns[gun] or not gun or not gun.Parent then
                if hitbox and hitbox.Parent then
                    pcall(function(): ()
                        hitbox:Destroy()
                    end)
                end
                gunHitboxes[gun] = nil
            end
        end

        if type(core.getPlayerRole) == "function" then
            local seenSheriffs: {[Player]: boolean} = {}
            for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
                if player ~= LocalPlayer then
                    local role = core.getPlayerRole(player)
                    if role == "Sheriff" then
                        seenSheriffs[player] = true
                        updateSheriffESP(player)
                    end
                end
            end
            for player, esp in pairs(espParts) do
                if not seenSheriffs[player] then
                    if esp and esp.Parent then
                        pcall(function(): ()
                            esp:Destroy()
                        end)
                    end
                    espParts[player] = nil
                end
            end
        end
    end

    local GunAuraFeature: any = nil

    local function toggleGunAura(enabled: boolean): ()
        gunAuraActive = enabled

        if not enabled then
            clearAllHitboxes()
            clearAllEsp()
            disconnectFeatureConnection("MM2GunAura")
            if GunAuraFeature then
                GunAuraFeature:SetStatus(nil)
            end
        else
            if GunAuraFeature then
                GunAuraFeature:SetStatus(tostring(math.round(settings.studs)) .. " studs")
            end
            featureConnections.MM2GunAura = TaskManager:Connect(gunAuraTick)
            gunAuraTick()
        end
    end

    GunAuraFeature = createUniversalFeature(
        "Gun Aura",
        "Creates a transparent white square around dropped guns. When your character touches this square, automatically grabs the gun. Only works when you're alive, in-round, and an Innocent. Detects dead sheriff hackers with white ESP.",
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
                GunAuraFeature:SetStatus(tostring(math.round(value)) .. " studs")
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
