export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "MM2 Fling",
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(runtime: any): any
    local host: any = state.frameworkEnvironment
    local core: any = state.mm2Core
    assert(core, "MM2 Fling requires the MM2 core")
    local Players: any = host.Players
    local LocalPlayer: any = host.LocalPlayer
    local getCharacterParts: any = host.getCharacterParts
    local notify: any = host.notify
    local activity: any = services.activity
    local protectedTargets: any = services.protectedTargets
    local gameBridge: any = services.gameBridge
    local createUniversalFeature: any = host.createUniversalFeature
    local addActionOption: any = host.addActionOption
    local addToggleOption: any = host.addToggleOption
    local addTextOption: any = host.addTextOption
    local addInformationOption: any = host.addInformationOption
    local TaskManager: any = host.TaskManager
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local findPlayerByText: any = host.findPlayerByText
    local configData: any = host.configData

    local workspace: any = host.workspace

    local findMurderer: any = core.findMurderer
    local findSheriff: any = core.findSheriff
    local getPlayerRole: any = core.getPlayerRole
    local getPlayerWeapon: any = core.getPlayerWeapon
    local isPlayerAlive: any = core.isPlayerAlive

    local flingRunning: boolean = false
    local flingTargetName: string = ""
    local autoFlingSelected: boolean = false
    local lastAutoFlingAt: number = 0
    local lastSafeOldPos: CFrame? = nil
    local stepAngle: number = 0

    local function setFlingRunning(running: boolean): ()
        flingRunning = running
        activity.set("fling", running)
    end

    -- Single-step helper using YARHM's FPos values for callers that step per frame.
    local function flingSingleStep(
        character: Model,
        humanoid: Humanoid,
        root: BasePart,
        targetPlayer: Player
    ): boolean
        local tChar: Model? = targetPlayer and targetPlayer.Character
        if not tChar then
            return false
        end
        local tHum: Humanoid? = tChar:FindFirstChildOfClass("Humanoid")
        local tRoot: BasePart? = (tHum and tHum.RootPart)
            or (tChar:FindFirstChild("HumanoidRootPart") :: BasePart?)
            or (tChar:FindFirstChild("Head") :: BasePart?)
        if not tRoot or (tHum and tHum.Health <= 0) then
            return false
        end
        activity.set("fling", true)
        stepAngle = (stepAngle + 100) % 360
        local moveDir: Vector3 = if tHum then tHum.MoveDirection else Vector3.zero
        local posOffset: CFrame = CFrame.new(0, 1.5, 0) + moveDir * (tRoot.Velocity.Magnitude / 1.25)
        local angOffset: CFrame = CFrame.Angles(math.rad(stepAngle), 0, 0)
        local targetCF: CFrame = CFrame.new(tRoot.Position) * posOffset * angOffset
        pcall(function(): ()
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
            root.CFrame = targetCF
            character:SetPrimaryPartCFrame(targetCF)
            root.Velocity = Vector3.new(9e7, 9e7 * 10, 9e7)
            root.RotVelocity = Vector3.new(9e8, 9e8, 9e8)
        end)
        return true
    end

    -- YARHM SkidFling / miniFling implementation with return/void safety checks
    -- so the local player is never left flying or killed in the void.
    local function performFling(targetPlayer: Player?, options: {[string]: any}?): boolean
        if not Module.Initialized or not targetPlayer then
            return false
        end
        if protectedTargets.isProtected(targetPlayer) then
            notify("player protected")
            return false
        end
        local silent: boolean = type(options) == "table" and options.silent == true
        local TimeToWait: number = (type(options) == "table" and tonumber(options.duration)) or 2.0
        local shouldStop: (() -> boolean)? = type(options) == "table"
            and type(options.shouldStop) == "function"
            and options.shouldStop
            or nil

        if flingRunning then
            if not silent then
                notify("fling already running")
            end
            return false
        end

        setFlingRunning(true)

        local function runSkidFling(): boolean
            local Character: Model?, Humanoid: Humanoid?, RootPart: BasePart? = getCharacterParts()
            if Character and Humanoid and not RootPart then
                RootPart = Humanoid.RootPart
            end
            if not Character or not Humanoid or not RootPart or Humanoid.Health <= 0 then
                setFlingRunning(false)
                if not silent then
                    notify("character not ready")
                end
                return false
            end

            local TCharacter: Model? = targetPlayer.Character
            if not TCharacter then
                setFlingRunning(false)
                if not silent then
                    notify("No valid character of said target player. May have died.")
                end
                return false
            end

            local THumanoid: Humanoid? = TCharacter:FindFirstChildOfClass("Humanoid")
            local TRootPart: BasePart? = (THumanoid and THumanoid.RootPart)
                or (TCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?)
            local THead: BasePart? = TCharacter:FindFirstChild("Head") :: BasePart?
            local Accessory: Accessory? = TCharacter:FindFirstChildOfClass("Accessory")
            local Handle: BasePart? = (Accessory and Accessory:FindFirstChild("Handle")) :: BasePart?

            if not TCharacter:FindFirstChildWhichIsA("BasePart") then
                setFlingRunning(false)
                return false
            end

            local OldPos: CFrame
            if type(options) == "table" and typeof(options.returnCFrame) == "CFrame" then
                OldPos = options.returnCFrame
                lastSafeOldPos = OldPos
            elseif RootPart.Velocity.Magnitude < 50 then
                OldPos = RootPart.CFrame
                lastSafeOldPos = OldPos
            else
                OldPos = lastSafeOldPos or RootPart.CFrame
            end

            local savedDestroyHeight: number = workspace.FallenPartsDestroyHeight
            if savedDestroyHeight ~= savedDestroyHeight or math.abs(savedDestroyHeight) > 1e6 then
                savedDestroyHeight = -500
            end

            local camera: Camera? = workspace.CurrentCamera
            local savedCameraSubject: any = camera and camera.CameraSubject or nil
            local BV: BodyVelocity? = nil
            local flungTarget: boolean = false

            local ok: boolean, err: any = pcall(function(): ()
                if camera then
                    if THead then
                        camera.CameraSubject = THead
                    elseif not THead and Handle then
                        camera.CameraSubject = Handle
                    elseif THumanoid and TRootPart then
                        camera.CameraSubject = THumanoid
                    end
                end

                -- YARHM FPos: exact CFrame + PrimaryPartCFrame + 9e7/9e8 Velocity & RotVelocity,
                -- guarded so we never teleport our own RootPart into the void/sky after the target
                -- has already been launched.
                local function FPos(BasePart: BasePart, Pos: CFrame, Ang: CFrame): boolean
                    if not flingRunning then
                        return false
                    end
                    if shouldStop and shouldStop() then
                        return false
                    end
                    if not RootPart or not RootPart.Parent or not Character or not Character.Parent then
                        return false
                    end
                    if not BasePart or not BasePart.Parent or BasePart.Parent ~= targetPlayer.Character then
                        return false
                    end
                    local bPos: Vector3 = BasePart.Position
                    if bPos.Y <= savedDestroyHeight + 25 or bPos.Y >= 2500 then
                        flungTarget = true
                        return false
                    end
                    if (bPos - OldPos.Position).Magnitude > 650 then
                        flungTarget = true
                        return false
                    end
                    local targetCF: CFrame = CFrame.new(bPos) * Pos * Ang
                    RootPart.CFrame = targetCF
                    if Character.PrimaryPart == nil then
                        Character.PrimaryPart = RootPart
                    end
                    Character:SetPrimaryPartCFrame(targetCF)
                    RootPart.Velocity = Vector3.new(9e7, 9e7 * 10, 9e7)
                    RootPart.RotVelocity = Vector3.new(9e8, 9e8, 9e8)
                    return true
                end

                local function shouldStopLoop(BasePart: BasePart, startTime: number): boolean
                    if not flingRunning then
                        return true
                    end
                    if shouldStop and shouldStop() then
                        return true
                    end
                    if not BasePart or BasePart.Parent ~= targetPlayer.Character then
                        return true
                    end
                    if targetPlayer.Parent ~= Players or targetPlayer.Character ~= TCharacter then
                        return true
                    end
                    if not THumanoid or THumanoid.Sit or THumanoid.Health <= 0 then
                        if THumanoid and THumanoid.Health <= 0 then
                            flungTarget = true
                        end
                        return true
                    end
                    if not RootPart or not RootPart.Parent or not Humanoid or Humanoid.Health <= 0 then
                        return true
                    end
                    if BasePart.Velocity.Magnitude > 500 then
                        flungTarget = true
                        return true
                    end
                    local bPos: Vector3 = BasePart.Position
                    if bPos.Y <= savedDestroyHeight + 25 or bPos.Y >= 2500 or (bPos - OldPos.Position).Magnitude > 650 then
                        flungTarget = true
                        return true
                    end
                    if tick() > startTime + TimeToWait then
                        return true
                    end
                    return false
                end

                local function stepFPos(
                    BasePart: BasePart,
                    Pos: CFrame,
                    Ang: CFrame,
                    startTime: number
                ): boolean
                    if shouldStopLoop(BasePart, startTime) then
                        return false
                    end
                    if not FPos(BasePart, Pos, Ang) then
                        return false
                    end
                    task.wait()
                    return not shouldStopLoop(BasePart, startTime)
                end

                -- YARHM SFBasePart
                local function SFBasePart(BasePart: BasePart): ()
                    local Time: number = tick()
                    local Angle: number = 0

                    repeat
                        if RootPart and THumanoid then
                            if BasePart.Velocity.Magnitude < 50 then
                                Angle = Angle + 100

                                if not stepFPos(BasePart, CFrame.new(0, 1.5, 0) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle), 0, 0), Time) then break end
                                if not stepFPos(BasePart, CFrame.new(0, -1.5, 0) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle), 0, 0), Time) then break end
                                if not stepFPos(BasePart, CFrame.new(2.25, 1.5, -2.25) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle), 0, 0), Time) then break end
                                if not stepFPos(BasePart, CFrame.new(-2.25, -1.5, 2.25) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle), 0, 0), Time) then break end
                                if not stepFPos(BasePart, CFrame.new(0, 1.5, 0) + THumanoid.MoveDirection, CFrame.Angles(math.rad(Angle), 0, 0), Time) then break end
                                if not stepFPos(BasePart, CFrame.new(0, -1.5, 0) + THumanoid.MoveDirection, CFrame.Angles(math.rad(Angle), 0, 0), Time) then break end
                            else
                                local walkSpd: number = THumanoid.WalkSpeed
                                local tRootVelMag: number = if TRootPart then TRootPart.Velocity.Magnitude else BasePart.Velocity.Magnitude

                                if not stepFPos(BasePart, CFrame.new(0, 1.5, walkSpd), CFrame.Angles(math.rad(90), 0, 0), Time) then break end
                                if not stepFPos(BasePart, CFrame.new(0, -1.5, -walkSpd), CFrame.Angles(0, 0, 0), Time) then break end
                                if not stepFPos(BasePart, CFrame.new(0, 1.5, walkSpd), CFrame.Angles(math.rad(90), 0, 0), Time) then break end
                                if not stepFPos(BasePart, CFrame.new(0, 1.5, tRootVelMag / 1.25), CFrame.Angles(math.rad(90), 0, 0), Time) then break end
                                if not stepFPos(BasePart, CFrame.new(0, -1.5, -tRootVelMag / 1.25), CFrame.Angles(0, 0, 0), Time) then break end
                                if not stepFPos(BasePart, CFrame.new(0, 1.5, tRootVelMag / 1.25), CFrame.Angles(math.rad(90), 0, 0), Time) then break end
                                if not stepFPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(math.rad(90), 0, 0), Time) then break end
                                if not stepFPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(0, 0, 0), Time) then break end
                                if not stepFPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(math.rad(-90), 0, 0), Time) then break end
                                if not stepFPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(0, 0, 0), Time) then break end
                            end
                        else
                            break
                        end
                    until shouldStopLoop(BasePart, Time)
                end

                workspace.FallenPartsDestroyHeight = 0 / 0

                local epixVel: BodyVelocity = Instance.new("BodyVelocity")
                epixVel.Name = "EpixVel"
                epixVel.Parent = RootPart
                epixVel.Velocity = Vector3.new(9e8, 9e8, 9e8)
                epixVel.MaxForce = Vector3.new(1 / 0, 1 / 0, 1 / 0)
                BV = epixVel

                Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)

                if TRootPart and THead then
                    if (TRootPart.CFrame.p - THead.CFrame.p).Magnitude > 5 then
                        SFBasePart(THead)
                    else
                        SFBasePart(TRootPart)
                    end
                elseif TRootPart and not THead then
                    SFBasePart(TRootPart)
                elseif not TRootPart and THead then
                    SFBasePart(THead)
                elseif not TRootPart and not THead and Accessory and Handle then
                    SFBasePart(Handle)
                elseif not silent then
                    notify("Can't find a proper part of target player to fling.")
                end
            end)

            if BV then
                pcall(function(): ()
                    BV:Destroy()
                end)
                BV = nil
            end

            local finalChar: Model?, finalHumanoid: Humanoid?, finalRoot: BasePart? =
                getCharacterParts()
            if finalHumanoid then
                pcall(function(): ()
                    finalHumanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
                end)
                if camera then
                    pcall(function(): ()
                        camera.CameraSubject = savedCameraSubject or finalHumanoid
                    end)
                end
            end

            if finalChar and finalHumanoid and finalRoot and finalRoot.Parent then
                local returnStart: number = tick()
                local returnTargetCF: CFrame = OldPos * CFrame.new(0, 0.5, 0)
                repeat
                    pcall(function(): ()
                        finalRoot.CFrame = returnTargetCF
                        if finalChar.PrimaryPart == nil then
                            finalChar.PrimaryPart = finalRoot
                        end
                        finalChar:SetPrimaryPartCFrame(returnTargetCF)
                        finalHumanoid:ChangeState("GettingUp")
                        for _, x: Instance in ipairs(finalChar:GetDescendants()) do
                            if x:IsA("BasePart") then
                                (x :: BasePart).Velocity = Vector3.new();
                                (x :: BasePart).RotVelocity = Vector3.new();
                                (x :: BasePart).AssemblyLinearVelocity = Vector3.new();
                                (x :: BasePart).AssemblyAngularVelocity = Vector3.new()
                            end
                        end
                    end)
                    task.wait()
                    finalChar, finalHumanoid, finalRoot = getCharacterParts()
                until not finalRoot
                    or not finalRoot.Parent
                    or not finalHumanoid
                    or finalHumanoid.Health <= 0
                    or (finalRoot.Position - OldPos.p).Magnitude < 25
                    or tick() - returnStart > 1.5
            end

            pcall(function(): ()
                workspace.FallenPartsDestroyHeight = savedDestroyHeight
            end)

            setFlingRunning(false)
            if not silent and not ok then
                notify("fling failed: " .. tostring(err))
            end
            return flungTarget
        end

        if type(options) == "table" and options.blocking == true then
            return runSkidFling()
        end
        task.spawn(runSkidFling)
        return true
    end

    state.mm2PerformFling = performFling
    state.mm2FlingStep = flingSingleStep

    local function refreshRoles(): ()
        if type(state.clearRoleMemo) == "function" then
            pcall(state.clearRoleMemo)
        end
        if type(core.requestRoleRefresh) == "function" then
            pcall(core.requestRoleRefresh, false)
        end
    end

    local function resolveMurdererTarget(): Player?
        refreshRoles()
        if type(getPlayerWeapon) == "function" then
            for _, player: Player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer
                    and (type(isPlayerAlive) ~= "function" or isPlayerAlive(player))
                    and getPlayerWeapon(player, "Gun", false) == nil
                    and getPlayerWeapon(player, "Knife", false) ~= nil then
                    return player
                end
            end
        end
        if type(findMurderer) == "function" then
            local target: Player? = findMurderer()
            if target
                and target ~= LocalPlayer
                and (type(isPlayerAlive) ~= "function" or isPlayerAlive(target))
                and (type(getPlayerWeapon) ~= "function"
                    or getPlayerWeapon(target, "Gun", false) == nil) then
                local role: any = type(getPlayerRole) == "function"
                    and getPlayerRole(target)
                    or "Murderer"
                if role ~= "Hero" and role ~= "Sheriff" and role ~= "Dead" then
                    return target
                end
            end
        end
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer
                and (type(isPlayerAlive) ~= "function" or isPlayerAlive(player))
                and (type(getPlayerWeapon) ~= "function"
                    or getPlayerWeapon(player, "Gun", false) == nil) then
                local role: any = type(getPlayerRole) == "function"
                    and getPlayerRole(player)
                    or nil
                if not role and type(gameBridge.playerRole) == "function" then
                    local okRole: boolean, r: any = pcall(gameBridge.playerRole, player)
                    if okRole then
                        role = r
                    end
                end
                if role == "Murderer" then
                    return player
                end
            end
        end
        return nil
    end

    local function resolveSheriffOrHeroTarget(): Player?
        refreshRoles()
        if type(getPlayerWeapon) == "function" then
            for _, player: Player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer
                    and (type(isPlayerAlive) ~= "function" or isPlayerAlive(player))
                    and getPlayerWeapon(player, "Knife", false) == nil
                    and getPlayerWeapon(player, "Gun", false) ~= nil then
                    return player
                end
            end
        end
        if type(findSheriff) == "function" then
            local target: Player? = findSheriff()
            if target
                and target ~= LocalPlayer
                and (type(isPlayerAlive) ~= "function" or isPlayerAlive(target))
                and (type(getPlayerWeapon) ~= "function"
                    or getPlayerWeapon(target, "Knife", false) == nil) then
                local role: any = type(getPlayerRole) == "function"
                    and getPlayerRole(target)
                    or "Sheriff"
                if role ~= "Murderer" and role ~= "Dead" then
                    return target
                end
            end
        end
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer
                and (type(isPlayerAlive) ~= "function" or isPlayerAlive(player))
                and (type(getPlayerWeapon) ~= "function"
                    or getPlayerWeapon(player, "Knife", false) == nil) then
                local role: any = type(getPlayerRole) == "function"
                    and getPlayerRole(player)
                    or nil
                if not role and type(gameBridge.playerRole) == "function" then
                    local okRole: boolean, r: any = pcall(gameBridge.playerRole, player)
                    if okRole then
                        role = r
                    end
                end
                if role == "Sheriff" or role == "Hero" then
                    return player
                end
            end
        end
        return nil
    end

    local function resolveSelectedTargetPlayer(): Player?
        local query: string = string.lower(string.gsub(flingTargetName or "", "^%s*(.-)%s*$", "%1"))
        if query == "" then
            return nil
        end
        if query == "murderer" or query == "murder" then
            return resolveMurdererTarget()
        end
        if query == "sheriff" or query == "hero" then
            return resolveSheriffOrHeroTarget()
        end
        if type(findPlayerByText) == "function" then
            local okFind: boolean, found: any = pcall(findPlayerByText, flingTargetName)
            if okFind and found and found ~= LocalPlayer then
                return found :: Player
            end
        end
        local compactQuery: string = string.gsub(query, "%s+", "")
        local prefixMatch: Player? = nil
        local partialMatch: Player? = nil
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local uName: string = string.lower(tostring(player.Name or ""))
                local dName: string = string.lower(tostring((player :: any).DisplayName or player.Name or ""))
                local uCompact: string = string.gsub(uName, "%s+", "")
                local dCompact: string = string.gsub(dName, "%s+", "")
                if uName == query or dName == query or uCompact == compactQuery or dCompact == compactQuery then
                    return player
                end
                if not prefixMatch and (
                    string.sub(uName, 1, #query) == query
                    or string.sub(dName, 1, #query) == query
                ) then
                    prefixMatch = player
                end
                if not partialMatch and (
                    string.find(uName, query, 1, true) ~= nil
                    or string.find(dName, query, 1, true) ~= nil
                    or string.find(uCompact, compactQuery, 1, true) ~= nil
                    or string.find(dCompact, compactQuery, 1, true) ~= nil
                ) then
                    partialMatch = player
                end
            end
        end
        return prefixMatch or partialMatch
    end

    -- IMPORTANT: FlingFeature has category = true (group card), so its onToggle
    -- MUST be a no-op because Cards.lua invokes onToggle(true) on group cards at boot!
    local FlingFeature: any = createUniversalFeature(
        "Fling",
        "MM2 only: fling the murderer, sheriff or innocents",
        2,
        function(): () end,
        {category = true, categoryName = "Exploits", registry = mm2Features, configKey = "MM2.Fling"}
    )

    addActionOption(FlingFeature, "Fling Murderer", function(): ()
        local target: Player? = resolveMurdererTarget()
        if target then
            performFling(target)
        else
            notify("No murderer was found.")
        end
    end)
    addActionOption(FlingFeature, "Fling Sheriff", function(): ()
        local target: Player? = resolveSheriffOrHeroTarget()
        if target then
            performFling(target)
        else
            notify("No sheriff or hero was found.")
        end
    end)
    addActionOption(FlingFeature, "Fling All Innocents", function(): ()
        refreshRoles()
        task.spawn(function(): ()
            for _, player: Player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer
                    and (type(isPlayerAlive) ~= "function" or isPlayerAlive(player)) then
                    local hasKnife: boolean = type(getPlayerWeapon) == "function"
                        and getPlayerWeapon(player, "Knife", false) ~= nil
                    local hasGun: boolean = type(getPlayerWeapon) == "function"
                        and getPlayerWeapon(player, "Gun", false) ~= nil
                    local role: any = type(getPlayerRole) == "function"
                        and getPlayerRole(player)
                        or nil
                    if not role and type(gameBridge.playerRole) == "function" then
                        local okRole: boolean, r: any = pcall(gameBridge.playerRole, player)
                        if okRole then
                            role = r
                        end
                    end
                    if not hasKnife and not hasGun and role == "Innocent" then
                        performFling(player, {blocking = true})
                        task.wait(0.05)
                    end
                end
            end
        end)
    end)

    local function autoFlingTick(): ()
        if not autoFlingSelected or flingRunning then
            return
        end
        if os.clock() - lastAutoFlingAt < 0.35 then
            return
        end
        local localChar: Model?, localHum: Humanoid?, localRoot: BasePart? = getCharacterParts()
        if not localChar or not localHum or not localRoot or localHum.Health <= 0 then
            return
        end
        local target: Player? = resolveSelectedTargetPlayer()
        if not target or protectedTargets.isProtected(target) then
            return
        end
        if type(isPlayerAlive) == "function" and not isPlayerAlive(target) then
            return
        end
        local targetChar: Model? = target.Character
        local targetHum: Humanoid? = targetChar
            and targetChar:FindFirstChildOfClass("Humanoid")
            :: Humanoid?
        local targetRoot: BasePart? = (targetHum and targetHum.RootPart)
            or (targetChar and targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?)
        if not targetChar or not targetHum or targetHum.Health <= 0 or targetHum.Sit or not targetRoot then
            return
        end
        local destroyHeight: number = workspace.FallenPartsDestroyHeight
        if destroyHeight ~= destroyHeight or math.abs(destroyHeight) > 1e6 then
            destroyHeight = -500
        end
        if targetRoot.Position.Y <= destroyHeight + 45 or targetRoot.Position.Y >= 2500 then
            return
        end
        lastAutoFlingAt = os.clock()
        performFling(target, {
            silent = true,
            duration = 2.0,
            shouldStop = function(): boolean
                return not autoFlingSelected
            end,
        })
    end

    addTextOption(
        FlingFeature,
        "Target player",
        "",
        function(value: string): ()
            flingTargetName = value
        end,
        false,
        "Username, display name, or 'Murderer' / 'Sheriff'"
    )
    addActionOption(FlingFeature, "Fling", function(): ()
        local target: Player? = resolveSelectedTargetPlayer()
        if target then
            performFling(target)
        else
            notify("No valid target player was found.")
        end
    end)

    -- Never auto-enable Auto Fling Selected Target from a persisted config on injection:
    -- it must only turn on when the user explicitly toggles it during the session.
    if configData and type(configData.states) == "table" then
        configData.states["MM2.Fling.AutoFlingSelectedTarget"] = false
    end

    addToggleOption(
        FlingFeature,
        "Auto Fling Selected Target",
        false,
        function(value: boolean): ()
            autoFlingSelected = value == true
            if disconnectFeatureConnection then
                disconnectFeatureConnection("MM2AutoFlingTarget")
            end
            if autoFlingSelected and TaskManager and featureConnections then
                lastAutoFlingAt = 0
                featureConnections.MM2AutoFlingTarget =
                    TaskManager:Connect(autoFlingTick)
                autoFlingTick()
            end
        end,
        "Continuously flings the target entered in Target player whenever they are alive."
    )
    addInformationOption(
        FlingFeature,
        "MM2 only. Pick a role action or enter a target player name."
    )

    activeCleanup = function(): ()
        autoFlingSelected = false
        if disconnectFeatureConnection then
            disconnectFeatureConnection("MM2AutoFlingTarget")
        end
        setFlingRunning(false)
        state.mm2PerformFling = nil
        state.mm2FlingStep = nil
    end
    Module.Initialized = true
    return FlingFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
