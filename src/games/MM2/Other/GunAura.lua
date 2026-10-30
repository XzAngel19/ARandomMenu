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
        studs = 25,
        showHitbox = true,
    }

    local TICK_INTERVAL: number = 0.08
    local SCAN_INTERVAL: number = 0.4
    local ESP_INTERVAL: number = 0.5

    local gunAuraActive = false
    local gunHitboxes: {[Instance]: BasePart} = {}
    local espParts: {[Player]: BasePart} = {}
    local savedGunStates: {[BasePart]: {cframe: CFrame, canCollide: boolean}} = {}
    local trackedDrops: {[Instance]: boolean} = {}
    local lastScanAt: number = -math.huge
    local lastTickAt: number = -math.huge
    local lastEspAt: number = -math.huge

    local function resolveGunTouchPart(gun: Instance?): BasePart?
        if not gun then
            return nil
        end
        if gun:IsA("BasePart") then
            return gun :: BasePart
        end
        local handle: Instance? = gun:FindFirstChild("Handle")
            or gun:FindFirstChild("GunDrop")
            or gun:FindFirstChildWhichIsA("BasePart")
        if handle and handle:IsA("BasePart") then
            return handle :: BasePart
        end
        return nil
    end

    local function rememberGunPartState(part: BasePart): {cframe: CFrame, canCollide: boolean}?
        local existing = savedGunStates[part]
        if existing then
            return existing
        end
        local ok: boolean, snap: any = pcall(function(): any
            return {
                cframe = part.CFrame,
                canCollide = part.CanCollide,
            }
        end)
        if ok and type(snap) == "table" then
            savedGunStates[part] = snap
            return snap
        end
        return nil
    end

    local function restoreGunPartState(part: BasePart): ()
        local snap = savedGunStates[part]
        if not snap then
            return
        end
        if part and part.Parent then
            pcall(function(): ()
                part.CFrame = snap.cframe
                part.CanCollide = snap.canCollide
            end)
        end
        savedGunStates[part] = nil
    end

    local function restoreAllGunPartStates(): ()
        for part in pairs(savedGunStates) do
            restoreGunPartState(part)
        end
        table.clear(savedGunStates)
    end

    local function trueGunPartPosition(part: BasePart): Vector3?
        local snap = savedGunStates[part]
        if snap and snap.cframe then
            return snap.cframe.Position
        end
        local okPos: boolean, pos: any = pcall(function(): any
            return part.Position
        end)
        if okPos and typeof(pos) == "Vector3" then
            return pos :: Vector3
        end
        return nil
    end

    local function canGrabGun(): boolean
        local character = LocalPlayer and LocalPlayer.Character
        if not character then
            return false
        end

        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then
            return false
        end

        if type(core.getPlayerRole) == "function" then
            local role = core.getPlayerRole(LocalPlayer)
            if role == "Murderer" or role == "Sheriff" or role == "Hero" then
                return false
            end
        end

        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        if (backpack and (backpack:FindFirstChild("Gun") or backpack:FindFirstChild("Knife")))
            or character:FindFirstChild("Gun")
            or character:FindFirstChild("Knife") then
            return false
        end

        return true
    end

    local function isValidGunDrop(obj: Instance?): boolean
        if not obj or not obj.Parent then
            return false
        end
        if obj.Name == "GunDrop" and (obj:IsA("BasePart") or obj:IsA("Model")) then
            return resolveGunTouchPart(obj) ~= nil
        end
        return false
    end

    local function createGunHitbox(gun: Instance): BasePart?
        local handle = resolveGunTouchPart(gun)
        if not handle then
            return nil
        end
        rememberGunPartState(handle)
        local pos = trueGunPartPosition(handle)
        if not pos then
            return nil
        end

        local part = Instance.new("Part")
        part.Name = "WurstGunAuraHitbox"
        part.Size = Vector3.new(settings.studs, settings.studs, settings.studs)
        part.Transparency = 0.65
        part.BrickColor = BrickColor.new("White")
        part.Material = Enum.Material.Neon
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
        part.Anchored = true
        part.CFrame = CFrame.new(pos)
        part.Parent = workspace

        return part
    end

    -- Lightweight GunDrop discovery: uses DescendantAdded events + top-level
    -- workspace children every 0.4s (never recursive GetDescendants).
    local function refreshTrackedDrops(now: number): ()
        if now - lastScanAt < SCAN_INTERVAL then
            return
        end
        lastScanAt = now

        local wsDrop: Instance? = workspace:FindFirstChild("GunDrop")
        if wsDrop and isValidGunDrop(wsDrop) then
            trackedDrops[wsDrop] = true
        end

        local okChildren: boolean, children: any = pcall(function(): any
            return workspace:GetChildren()
        end)
        if okChildren and type(children) == "table" then
            for _, child: Instance in ipairs(children) do
                if child.Name == "GunDrop" and isValidGunDrop(child) then
                    trackedDrops[child] = true
                elseif child:IsA("Model") or child:IsA("Folder") then
                    local gd: Instance? = child:FindFirstChild("GunDrop")
                    if gd and isValidGunDrop(gd) then
                        trackedDrops[gd] = true
                    end
                end
            end
        end

        if type(core.findDroppedGun) == "function" then
            local okCore: boolean, drop: any = pcall(core.findDroppedGun)
            if okCore and drop and isValidGunDrop(drop) then
                trackedDrops[drop] = true
            end
        end
    end

    local function isWithinAura(truePos: Vector3, rootPos: Vector3): boolean
        local diff = rootPos - truePos
        local radius = settings.studs
        if diff.X * diff.X + diff.Y * diff.Y + diff.Z * diff.Z <= radius * radius then
            return true
        end
        local half = radius * 0.5
        return math.abs(diff.X) <= half
            and math.abs(diff.Y) <= math.max(half, 8)
            and math.abs(diff.Z) <= half
    end

    local function tryGrabGun(root: BasePart, handle: BasePart): ()
        rememberGunPartState(handle)
        handle.CanCollide = false
        local rootCF: CFrame? = root.CFrame
        if rootCF then
            handle.CFrame = rootCF
        end
        local fireTouch: any = state.fireTouchInterest
        if type(fireTouch) == "function" then
            pcall(fireTouch, root, handle, 0)
            pcall(fireTouch, root, handle, 1)
        end
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

    local GunAuraFeature: any = nil
    local lastStatus: string? = nil

    local function setStatus(text: string?): ()
        if text == lastStatus then
            return
        end
        lastStatus = text
        if GunAuraFeature then
            GunAuraFeature:SetStatus(text)
        end
    end

    local function gunAuraTick(): ()
        if not gunAuraActive then
            return
        end
        local now: number = os.clock()
        if now - lastTickAt < TICK_INTERVAL then
            return
        end
        lastTickAt = now

        refreshTrackedDrops(now)

        local character = LocalPlayer and LocalPlayer.Character
        local root: BasePart? = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
        local canGrab = canGrabGun()
        local activeGuns: {[Instance]: boolean} = {}
        local touchedParts: {[BasePart]: boolean} = {}
        local gunCount: number = 0

        for gun in pairs(trackedDrops) do
            if isValidGunDrop(gun) then
                local handle: BasePart? = resolveGunTouchPart(gun)
                if handle then
                    gunCount += 1
                    activeGuns[gun] = true
                    rememberGunPartState(handle)
                    local truePos: Vector3? = trueGunPartPosition(handle)

                    if settings.showHitbox then
                        local hitbox = gunHitboxes[gun]
                        if not hitbox or not hitbox.Parent then
                            hitbox = createGunHitbox(gun)
                            if hitbox then
                                gunHitboxes[gun] = hitbox
                            end
                        elseif truePos then
                            local targetSize = Vector3.new(settings.studs, settings.studs, settings.studs)
                            if hitbox.Size ~= targetSize then
                                hitbox.Size = targetSize
                            end
                            hitbox.CFrame = CFrame.new(truePos)
                        end
                    end

                    if canGrab and root and truePos and isWithinAura(truePos, root.Position) then
                        touchedParts[handle] = true
                        pcall(tryGrabGun, root, handle)
                    end
                end
            else
                trackedDrops[gun] = nil
            end
        end

        for part in pairs(savedGunStates) do
            if not touchedParts[part] then
                restoreGunPartState(part)
            end
        end

        for gun, hitbox in pairs(gunHitboxes) do
            if not activeGuns[gun] then
                if hitbox and hitbox.Parent then
                    pcall(function(): ()
                        hitbox:Destroy()
                    end)
                end
                gunHitboxes[gun] = nil
            end
        end

        if gunCount > 0 then
            setStatus("Gun detected · " .. tostring(math.round(settings.studs)) .. " studs")
        else
            setStatus(tostring(math.round(settings.studs)) .. " studs")
        end

        if now - lastEspAt >= ESP_INTERVAL and type(core.getPlayerRole) == "function" then
            lastEspAt = now
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

    local function toggleGunAura(enabled: boolean): ()
        gunAuraActive = enabled
        state.mm2GunAuraEnabled = enabled == true
        disconnectFeatureConnection("MM2GunAura")
        disconnectFeatureConnection("MM2GunAuraDescendant")

        if not enabled then
            clearAllHitboxes()
            clearAllEsp()
            restoreAllGunPartStates()
            table.clear(trackedDrops)
            setStatus(nil)
            return
        end

        lastScanAt = -math.huge
        lastTickAt = -math.huge
        lastEspAt = -math.huge

        if workspace.DescendantAdded then
            featureConnections.MM2GunAuraDescendant = workspace.DescendantAdded:Connect(function(obj: Instance): ()
                if obj.Name == "GunDrop" then
                    trackedDrops[obj] = true
                end
            end)
        end

        setStatus(tostring(math.round(settings.studs)) .. " studs")
        featureConnections.MM2GunAura =
            TaskManager:Connect(gunAuraTick, nil, "MM2 Gun Aura")
        gunAuraTick()
    end

    GunAuraFeature = createUniversalFeature(
        "Gun Aura",
        "Detects dropped guns in the map with event-driven tracking, draws a white aura box around them, and automatically grabs the gun within Studs range.",
        7,
        toggleGunAura,
        {
            categoryName = "Utilities",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    state.mm2GunAuraFeature = GunAuraFeature

    addNumberOption(GunAuraFeature, "Studs", 25, 5, 250,
        function(value: number): ()
            settings.studs = math.clamp(tonumber(value) or 25, 5, 250)
            if GunAuraFeature.enabled then
                setStatus(tostring(math.round(settings.studs)) .. " studs")
            end
        end,
        "Distance in studs around each dropped gun to automatically grab it.", 1)
    addToggleOption(GunAuraFeature, "Show Hitbox", true,
        function(value: boolean): ()
            settings.showHitbox = value == true
            if not settings.showHitbox then
                clearAllHitboxes()
            end
        end,
        "Shows or hides the white aura hitbox square around dropped guns.")

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
