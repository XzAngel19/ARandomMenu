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
    }

    local gunAuraActive = false
    local gunHitboxes: {[Instance]: BasePart} = {}
    local espParts: {[Player]: BasePart} = {}
    local savedGunStates: {[BasePart]: {cframe: CFrame, canCollide: boolean}} = {}
    local trackedDrops: {[Instance]: boolean} = {}
    local lastDeepScanAt: number = -math.huge

    local function isInsideCharacterOrBackpack(instance: Instance): boolean
        if instance:FindFirstAncestorOfClass("Backpack") then
            return true
        end
        local current: Instance? = instance.Parent
        while current and current ~= workspace do
            local okHum: boolean, hum: any = pcall(function(): any
                return current:FindFirstChildOfClass("Humanoid")
            end)
            if okHum and hum then
                return true
            end
            current = current.Parent
        end
        return false
    end

    local function resolveGunTouchPart(gun: Instance?): BasePart?
        if not gun then
            return nil
        end
        if gun:IsA("BasePart") then
            return gun :: BasePart
        end
        local handle: Instance? = gun:FindFirstChild("Handle", true)
            or gun:FindFirstChild("GunDrop", true)
            or gun:FindFirstChildWhichIsA("BasePart", true)
        if handle and handle:IsA("BasePart") then
            return handle :: BasePart
        end
        return nil
    end

    local function collectGunBaseParts(gun: Instance): {BasePart}
        local parts: {BasePart} = {}
        if gun:IsA("BasePart") then
            table.insert(parts, gun :: BasePart)
        end
        local okDesc: boolean, descendants: any = pcall(function(): any
            return gun:GetDescendants()
        end)
        if okDesc and type(descendants) == "table" then
            for _, obj: Instance in ipairs(descendants) do
                if obj:IsA("BasePart") then
                    table.insert(parts, obj :: BasePart)
                end
            end
        end
        return parts
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
            local okSnap: boolean, pos: any = pcall(function(): any
                return snap.cframe.Position
            end)
            if okSnap and typeof(pos) == "Vector3" then
                return pos :: Vector3
            end
        end
        local okPos: boolean, pos: any = pcall(function(): any
            return part.Position
        end)
        if okPos and typeof(pos) == "Vector3" then
            return pos :: Vector3
        end
        return nil
    end

    -- Check if the local player is eligible to pick up the dropped gun.
    -- Intentionally does NOT gate on findMM2Map() or isRoundLifecycleActive(),
    -- because if a GunDrop physically exists in workspace, a round is active.
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

    local function isCandidateGunDrop(obj: Instance?): boolean
        if not obj or not obj.Parent then
            return false
        end
        if obj.Name == "WurstGunAuraHitbox" or string.sub(obj.Name, 1, 18) == "WurstDeadSheriffESP" then
            return false
        end
        local okDesc: boolean, inWs: boolean = pcall(function(): boolean
            return obj:IsDescendantOf(workspace)
        end)
        if okDesc and not inWs then
            return false
        end
        if isInsideCharacterOrBackpack(obj) then
            return false
        end
        if obj.Name == "GunDrop" and (obj:IsA("BasePart") or obj:IsA("Model")) then
            return resolveGunTouchPart(obj) ~= nil
        end
        if obj:IsA("Tool") and obj.Name == "Gun" then
            return resolveGunTouchPart(obj) ~= nil
        end
        return false
    end

    -- Create an upright transparent white square around a dropped gun
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

    -- Find all dropped guns in the map without relying solely on findMM2Map()
    local function findDroppedGuns(): {Instance}
        local guns: {Instance} = {}
        local seen: {[Instance]: boolean} = {}

        local function addGun(candidate: Instance?): ()
            if not candidate or seen[candidate] or not isCandidateGunDrop(candidate) then
                return
            end
            -- If a child part inside a GunDrop Model was passed, normalize to the GunDrop container
            local parent = candidate.Parent
            if parent and parent.Name == "GunDrop" and (parent:IsA("Model") or parent:IsA("BasePart")) then
                candidate = parent
                if seen[candidate] then
                    return
                end
            end
            local touchPart = resolveGunTouchPart(candidate)
            if touchPart then
                rememberGunPartState(touchPart)
                seen[candidate] = true
                trackedDrops[candidate] = true
                table.insert(guns, candidate)
            end
        end

        -- 1. Previously tracked drops from DescendantAdded or prior scans
        for tracked in pairs(trackedDrops) do
            if isCandidateGunDrop(tracked) then
                addGun(tracked)
            else
                trackedDrops[tracked] = nil
            end
        end

        -- 2. Core findDroppedGun
        if type(core.findDroppedGun) == "function" then
            local ok: boolean, drop: any = pcall(core.findDroppedGun)
            if ok and drop then
                addGun(drop)
            end
        end

        -- 3. Direct workspace GunDrop + top-level Model/Folder children
        local wsDrop = workspace:FindFirstChild("GunDrop")
        if wsDrop then
            addGun(wsDrop)
        end
        local okChildren: boolean, wsChildren: any = pcall(function(): any
            return workspace:GetChildren()
        end)
        if okChildren and type(wsChildren) == "table" then
            for _, child: Instance in ipairs(wsChildren) do
                if child:IsA("Model") or child:IsA("Folder") then
                    local gd = child:FindFirstChild("GunDrop")
                    if gd then
                        addGun(gd)
                    end
                elseif isCandidateGunDrop(child) then
                    addGun(child)
                end
            end
        end

        -- 4. CollectionService Weapon_Gun / GunDrop tags
        local cs: any = game:GetService("CollectionService")
        for _, tagName: string in ipairs({"Weapon_Gun", "GunDrop"}) do
            local okTagged: boolean, tagged: any = pcall(function(): any
                return cs:GetTagged(tagName)
            end)
            if okTagged and type(tagged) == "table" then
                for _, obj: Instance in ipairs(tagged) do
                    addGun(obj)
                end
            end
        end

        -- 5. Throttled recursive workspace:FindFirstChild("GunDrop", true)
        local now: number = os.clock()
        if #guns == 0 and now - lastDeepScanAt >= 0.35 then
            lastDeepScanAt = now
            local okDeep: boolean, deepDrop: any = pcall(function(): any
                return workspace:FindFirstChild("GunDrop", true)
            end)
            if okDeep and deepDrop then
                addGun(deepDrop)
            end
        end

        return guns
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

    local function tryGrabGun(gun: Instance): boolean
        local character = LocalPlayer and LocalPlayer.Character
        if not character then
            return false
        end

        local root = character:FindFirstChild("HumanoidRootPart")
        if not root or not root:IsA("BasePart") then
            return false
        end

        local parts = collectGunBaseParts(gun)
        local primary = resolveGunTouchPart(gun)
        if primary and not table.find(parts, primary) then
            table.insert(parts, 1, primary)
        end
        if #parts == 0 then
            return false
        end

        local fireTouch: any = state.fireTouchInterest
        for _, part: BasePart in ipairs(parts) do
            rememberGunPartState(part)
            pcall(function(): ()
                part.CanCollide = false
                if (root :: BasePart).CFrame then
                    part.CFrame = (root :: BasePart).CFrame
                end
            end)
            if type(fireTouch) == "function" then
                pcall(fireTouch, root, part, 0)
                pcall(fireTouch, root, part, 1)
            end
        end

        return true
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

        local character = LocalPlayer and LocalPlayer.Character
        local root: BasePart? = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
        local guns = findDroppedGuns()
        local activeGuns: {[Instance]: boolean} = {}
        local canGrab = canGrabGun()
        local touchedParts: {[BasePart]: boolean} = {}

        for _, gun in ipairs(guns) do
            if gun and gun.Parent then
                activeGuns[gun] = true
                local handle = resolveGunTouchPart(gun)
                local truePos: Vector3? = handle and trueGunPartPosition(handle) or nil

                local hitbox = gunHitboxes[gun]
                if not hitbox or not hitbox.Parent then
                    hitbox = createGunHitbox(gun)
                    if hitbox then
                        gunHitboxes[gun] = hitbox
                    end
                elseif truePos then
                    hitbox.Size = Vector3.new(settings.studs, settings.studs, settings.studs)
                    hitbox.CFrame = CFrame.new(truePos)
                end

                if canGrab and root and truePos and isWithinAura(truePos, root.Position) then
                    for _, p in ipairs(collectGunBaseParts(gun)) do
                        touchedParts[p] = true
                    end
                    if handle then
                        touchedParts[handle] = true
                    end
                    tryGrabGun(gun)
                end
            end
        end

        -- Restore any gun part that is not actively being pulled this tick
        for part in pairs(savedGunStates) do
            if not touchedParts[part] then
                restoreGunPartState(part)
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

        if #guns > 0 then
            setStatus("Gun detected · " .. tostring(math.round(settings.studs)) .. " studs")
        else
            setStatus(tostring(math.round(settings.studs)) .. " studs")
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

    local function toggleGunAura(enabled: boolean): ()
        gunAuraActive = enabled
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

        lastDeepScanAt = -math.huge
        pcall(function(): ()
            for _, obj: Instance in ipairs(workspace:GetDescendants()) do
                if obj.Name == "GunDrop" or (obj:IsA("Tool") and obj.Name == "Gun") then
                    if isCandidateGunDrop(obj) then
                        trackedDrops[obj] = true
                    end
                end
            end
        end)

        if workspace.DescendantAdded then
            featureConnections.MM2GunAuraDescendant = workspace.DescendantAdded:Connect(function(obj: Instance): ()
                if obj.Name == "GunDrop" or (obj:IsA("Tool") and obj.Name == "Gun") then
                    trackedDrops[obj] = true
                end
            end)
        end

        setStatus(tostring(math.round(settings.studs)) .. " studs")
        featureConnections.MM2GunAura = TaskManager:Connect(gunAuraTick)
        gunAuraTick()
    end

    GunAuraFeature = createUniversalFeature(
        "Gun Aura",
        "Detects dropped guns anywhere in the map, draws a white aura hitbox around them, and automatically grabs the gun within Studs range.",
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
        "Distance in studs around each dropped gun to automatically grab it (draws the visual aura square and pulls the gun trigger on enter).", 1)

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
