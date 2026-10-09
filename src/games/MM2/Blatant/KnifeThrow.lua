local Module = {
    Name = "MM2 Knife Throw",
    PlaceId = 142823291,
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}

local activeCleanup: () -> () = function(): () end

--[[
    MM2 Knife Throw

    Automatically throws the knife at the nearest valid target — the murderer's
    counterpart to the gun's Auto Shoot.

    Normal throws from the murderer's hand and leads the target by the blade's
    flight time (distance / throw speed), so the target has to be roughly in the
    open. Silent authors the throw so the blade spawns right beside the target
    (origin placed next to them, aim at them): the server spawns the projectile
    at that origin, so it connects at any distance or through walls — the same
    trick the gun's silent shot uses, and reliable because the knife's hitbox is
    long.

    Remote (confirmed against YARHM's "knife throw to closest"):
      KnifeThrown:FireServer(CFrame.new(origin), CFrame.new(aim))
]]
function Module.init(runtime: any): any
    if Module.Initialized then
        return Module
    end
    local core: any = state.mm2Core
    assert(type(core) == "table", "MM2 Knife Throw requires the MM2 core module")
    Module.Runtime = runtime
    local findMurderer: any = core.findMurderer
    local getPlayerRole: any = core.getPlayerRole
    local getPlayerWeapon: any = core.getPlayerWeapon
    local isPlayerAlive: any = core.isPlayerAlive
    local isProtectedTarget: any = core.isProtectedTarget
    local getFilteredVelocity: any = core.getFilteredVelocity
    local trajectoryCalibration: any = core.trajectoryCalibration

    local knifeThrowSettings = {
        enabled = false,
        mode = "Normal",
        fireDelay = 1,
        range = 120,
        spawnOffset = 5,
    }
    local lastThrow = -math.huge

    local function isValidTarget(player: Player): boolean
        if player == LocalPlayer
            or isProtectedTarget(player)
            or not isPlayerAlive(player)
            or getPlayerRole(player) == "Murderer" then
            return false
        end
        return player.Character ~= nil
            and player.Character:FindFirstChild("HumanoidRootPart") ~= nil
    end

    local function findNearestTarget(maxDistance: number): Player?
        local localRoot: BasePart? = LocalPlayer.Character
            and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not localRoot then
            return nil
        end
        local closest: Player? = nil
        local closestDistance: number = maxDistance
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if isValidTarget(player) then
                local targetRoot: BasePart? = player.Character
                    and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
                if targetRoot then
                    local distance: number =
                        (targetRoot.Position - localRoot.Position).Magnitude
                    if distance <= closestDistance then
                        closest = player
                        closestDistance = distance
                    end
                end
            end
        end
        return closest
    end

    -- The murderer role is required, and the knife must be equipped and off its
    -- post-throw cooldown (the tool flags itself Disabled while it respawns).
    local function getReadyKnife(): Tool?
        if findMurderer() ~= LocalPlayer then
            return nil
        end
        local character: Model? = LocalPlayer.Character
        if not character then
            return nil
        end
        -- Search backpack too: an unequipped knife must be equipped before the
        -- next tick, exactly like Shoot does with the gun.
        local knife: Tool? = getPlayerWeapon(LocalPlayer, "Knife")
        if not knife or knife:GetAttribute("Disabled") == true then
            return nil
        end
        if knife.Parent ~= character then
            local humanoid: Humanoid? =
                character:FindFirstChildOfClass("Humanoid") :: Humanoid?
            if humanoid then
                humanoid:EquipTool(knife)
            end
            return nil
        end
        return knife
    end

    -- Lead the target by the blade's flight time so a moving target is still
    -- where the knife arrives. Uses the calibrated throw speed when available.
    local function predictAim(target: Player, originPos: Vector3): Vector3
        local root: BasePart =
            target.Character:FindFirstChild("HumanoidRootPart") :: BasePart
        local knifeSpeed: number = 96
        local estimates: any = trajectoryCalibration
            and trajectoryCalibration.getEstimates
            and trajectoryCalibration.getEstimates()
        if estimates and estimates.knifeSpeed and estimates.knifeSpeed > 1 then
            knifeSpeed = estimates.knifeSpeed
        end
        local flightTime: number =
            (root.Position - originPos).Magnitude / knifeSpeed
        local velocity: Vector3 = getFilteredVelocity(target, root)
        return root.Position + velocity * flightTime
    end

    local function throwKnife(): ()
        if os.clock() - lastThrow < knifeThrowSettings.fireDelay then
            return
        end
        local silent: boolean = knifeThrowSettings.mode == "Silent"
        local knife: Tool? = getReadyKnife()
        if not knife then
            return
        end
        local events: Instance? = knife:FindFirstChild("Events")
        local remote: Instance? = events and events:FindFirstChild("KnifeThrown")
        if not remote or not remote:IsA("RemoteEvent") then
            return
        end
        local character: Model? = LocalPlayer.Character
        local throwerPart: BasePart? = character
            and (character:FindFirstChild("RightHand")
                or character:FindFirstChild("HumanoidRootPart")) :: BasePart?
        if not throwerPart then
            return
        end

        -- Silent ignores range: the whole point is to reach a target anywhere.
        local target: Player? =
            findNearestTarget(silent and 100000 or knifeThrowSettings.range)
        if not target then
            return
        end
        local targetRoot: BasePart =
            target.Character:FindFirstChild("HumanoidRootPart") :: BasePart

        local originPos: Vector3
        if silent then
            -- Spawn the blade just beside the target, on the thrower's side, so
            -- it travels a few studs into them and connects regardless of walls.
            local toThrower: Vector3 = throwerPart.Position - targetRoot.Position
            if toThrower.Magnitude > 0.1 then
                toThrower = toThrower.Unit
            else
                toThrower = Vector3.new(0, 0, 1)
            end
            originPos = targetRoot.Position + toThrower * knifeThrowSettings.spawnOffset
        else
            originPos = throwerPart.Position
        end

        local aimPos: Vector3 = predictAim(target, originPos)
        remote:FireServer(CFrame.new(originPos), CFrame.new(aimPos))
        lastThrow = os.clock()
    end

    local function toggleKnifeThrow(enabled: boolean): ()
        knifeThrowSettings.enabled = enabled
        disconnectFeatureConnection("MM2KnifeThrow")
        if not enabled then
            return
        end
        lastThrow = -math.huge
        local elapsed: number = 0
        featureConnections.MM2KnifeThrow =
            TaskManager:Connect(function(deltaTime: number): ()
                elapsed += deltaTime
                if elapsed < 1 / 30 then
                    return
                end
                elapsed = 0
                throwKnife()
            end)
    end

    local KnifeThrowFeature = createUniversalFeature(
        "Knife Throw",
        "Auto-throws the knife at the nearest target. Silent spawns the blade"
            .. " beside the target so it connects at any distance or through walls.",
        7,
        toggleKnifeThrow,
        {
            categoryName = "Blatant",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    addCycleOption(
        KnifeThrowFeature,
        "Mode",
        {"Normal", "Silent"},
        1,
        function(value: string): ()
            knifeThrowSettings.mode = value
        end
    )
    addNumberOption(
        KnifeThrowFeature,
        "Fire delay",
        knifeThrowSettings.fireDelay,
        0.2,
        3,
        function(value: number): ()
            knifeThrowSettings.fireDelay = value
        end,
        "Seconds between automatic throws.",
        0.1
    )
    addNumberOption(
        KnifeThrowFeature,
        "Range",
        knifeThrowSettings.range,
        10,
        400,
        function(value: number): ()
            knifeThrowSettings.range = value
        end,
        "Maximum target distance for normal throws. Silent ignores this.",
        5
    )
    addNumberOption(
        KnifeThrowFeature,
        "Spawn offset",
        knifeThrowSettings.spawnOffset,
        1,
        15,
        function(value: number): ()
            knifeThrowSettings.spawnOffset = value
        end,
        "Silent only: how far beside the target the blade spawns.",
        1
    )

    activeCleanup = function(): ()
        toggleKnifeThrow(false)
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
