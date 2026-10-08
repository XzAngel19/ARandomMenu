--!nocheck

--[[
    MM2 Knife Throw
    Place ID: 142823291

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

local Module = {
    Name = "MM2 Knife Throw",
    PlaceId = 142823291,
    Version = "1.0.0",
    Description = "Automatic and silent knife throwing.",
}

function Module.init(runtime: any)
    local state: any = runtime.state
    local createUniversalFeature: any = state.createUniversalFeature
    local addCycleOption: any = state.addCycleOption
    local addNumberOption: any = state.addNumberOption
    local disconnectFeatureConnection: any = state.disconnectFeatureConnection
    local featureConnections: any = state.featureConnections
    local mm2Features: any = state.mm2Features
    local MM2Scroll: any = state.MM2Scroll
    local TaskManager: any = state.TaskManager

    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer

    local core: any = state.mm2Core
    if not core then
        warn("MM2 Knife Throw could not find the shared MM2 core.")
        return
    end
    local findMurderer = core.findMurderer
    local getPlayerRole = core.getPlayerRole
    local getPlayerWeapon = core.getPlayerWeapon
    local isPlayerAlive = core.isPlayerAlive
    local isProtectedTarget = core.isProtectedTarget
    local getFilteredVelocity = core.getFilteredVelocity
    local trajectoryCalibration = core.trajectoryCalibration

    local knifeThrowSettings = {
        enabled = false,
        mode = "Normal",
        fireDelay = 1,
        range = 120,
        spawnOffset = 5,
    }
    local lastThrow = -math.huge

    local function isValidTarget(player)
        return player ~= LocalPlayer
            and not isProtectedTarget(player)
            and isPlayerAlive(player)
            and getPlayerRole(player) ~= "Murderer"
            and player.Character ~= nil
            and player.Character:FindFirstChild("HumanoidRootPart") ~= nil
    end

    local function findNearestTarget(maxDistance: number)
        local localRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not localRoot then
            return nil
        end
        local closest = nil
        local closestDistance = maxDistance
        for _, player in ipairs(Players:GetPlayers()) do
            if isValidTarget(player) then
                local root = player.Character:FindFirstChild("HumanoidRootPart")
                local distance = (root.Position - localRoot.Position).Magnitude
                if distance <= closestDistance then
                    closest = player
                    closestDistance = distance
                end
            end
        end
        return closest
    end

    -- The murderer role is required, and the knife must be equipped and off its
    -- post-throw cooldown (the tool flags itself Disabled while it respawns).
    local function getReadyKnife()
        if findMurderer() ~= LocalPlayer then
            return nil
        end
        local character = LocalPlayer.Character
        if not character then
            return nil
        end
        local knife = getPlayerWeapon(LocalPlayer, "Knife", true)
        if not knife or knife:GetAttribute("Disabled") == true then
            return nil
        end
        if knife.Parent ~= character then
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid:EquipTool(knife)
            end
            return nil
        end
        return knife
    end

    -- Lead the target by the blade's flight time so a moving target is still
    -- where the knife arrives. Uses the calibrated throw speed when available.
    local function predictAim(target, originPos: Vector3): Vector3
        local root = target.Character:FindFirstChild("HumanoidRootPart")
        local knifeSpeed = 96
        local estimates = trajectoryCalibration and trajectoryCalibration.getEstimates and trajectoryCalibration.getEstimates()
        if estimates and estimates.knifeSpeed and estimates.knifeSpeed > 1 then
            knifeSpeed = estimates.knifeSpeed
        end
        local flightTime = (root.Position - originPos).Magnitude / knifeSpeed
        local velocity = getFilteredVelocity(target, root)
        return root.Position + velocity * flightTime
    end

    local function throwKnife()
        if os.clock() - lastThrow < knifeThrowSettings.fireDelay then
            return
        end
        local silent = knifeThrowSettings.mode == "Silent"
        local knife = getReadyKnife()
        if not knife then
            return
        end
        local events = knife:FindFirstChild("Events")
        local remote = events and events:FindFirstChild("KnifeThrown")
        if not remote or not remote:IsA("RemoteEvent") then
            return
        end
        local character = LocalPlayer.Character
        local throwerPart = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("HumanoidRootPart"))
        if not throwerPart then
            return
        end

        -- Silent ignores range: the whole point is to reach a target anywhere.
        local target = findNearestTarget(silent and 100000 or knifeThrowSettings.range)
        if not target then
            return
        end
        local targetRoot = target.Character:FindFirstChild("HumanoidRootPart")

        local originPos: Vector3
        if silent then
            -- Spawn the blade just beside the target, on the thrower's side, so
            -- it travels a few studs into them and connects regardless of walls.
            local toThrower = throwerPart.Position - targetRoot.Position
            if toThrower.Magnitude > 0.1 then
                toThrower = toThrower.Unit
            else
                toThrower = Vector3.new(0, 0, 1)
            end
            originPos = targetRoot.Position + toThrower * knifeThrowSettings.spawnOffset
        else
            originPos = throwerPart.Position
        end

        local aimPos = predictAim(target, originPos)
        remote:FireServer(CFrame.new(originPos), CFrame.new(aimPos))
        lastThrow = os.clock()
    end

    local function toggle(enabled: boolean)
        knifeThrowSettings.enabled = enabled
        disconnectFeatureConnection("MM2KnifeThrow")
        if not enabled then
            return
        end
        lastThrow = -math.huge
        local elapsed = 0
        featureConnections.MM2KnifeThrow = TaskManager:Connect(function(deltaTime: number)
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
        "Auto-throws the knife at the nearest target. Silent spawns the blade beside the target so it connects at any distance or through walls.",
        7,
        toggle,
        {
            categoryName = "Blatant",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    addCycleOption(KnifeThrowFeature, "Mode", { "Normal", "Silent" }, 1, function(value: string)
        knifeThrowSettings.mode = value
    end)
    addNumberOption(KnifeThrowFeature, "Fire delay", "Seconds between automatic throws", 1, 0.2, 3, function(value: number)
        knifeThrowSettings.fireDelay = value
    end, 0.1, "s")
    addNumberOption(KnifeThrowFeature, "Range", "Maximum target distance for normal throws", 120, 10, 400, function(value: number)
        knifeThrowSettings.range = value
    end, 5, " studs")
    addNumberOption(KnifeThrowFeature, "Spawn offset", "Silent only: how far beside the target the blade spawns", 5, 1, 15, function(value: number)
        knifeThrowSettings.spawnOffset = value
    end, 1, " studs")

    mm2Features["Knife Throw"] = KnifeThrowFeature

    table.insert(state.activeCleanup, function()
        knifeThrowSettings.enabled = false
        disconnectFeatureConnection("MM2KnifeThrow")
    end)
end

return Module
