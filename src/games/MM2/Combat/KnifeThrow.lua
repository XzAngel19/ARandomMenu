local Module = {
    Name = "MM2 Knife Throw",
    PlaceId = 142823291,
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
    assert(type(core) == "table", "MM2 Knife Throw requires the MM2 core module")
    Module.Runtime = runtime

    local findMurderer: any = core.findMurderer
    local getPlayerRole: any = core.getPlayerRole
    local getPlayerWeapon: any = core.getPlayerWeapon
    local isPlayerAlive: any = core.isPlayerAlive
    local isProtectedTarget: any = core.isProtectedTarget
    local getEstimatedLatency: any = core.getEstimatedLatency
    local isWeaponPathClear: any = core.isWeaponPathClear
    local prediction: any = state.mm2Prediction

    local settings = {
        enabled = false,
        autoThrow = false,
        wallCheck = true,
        knifeTracer = false,
        delay = 0.6,
    }

    local lastThrowAttempt: number = 0
    local KnifeThrowFeature: any = nil
    local lastKnifeStatus: string? = nil
    local function setKnifeStatus(message: string?): ()
        if KnifeThrowFeature and lastKnifeStatus ~= message then
            lastKnifeStatus = message
            KnifeThrowFeature:SetStatus(message)
        end
    end
    local tracerPart: BasePart? = nil
    local targetDotPart: BasePart? = nil
    local hookedWeaponService: any = nil
    local origGetMouseTargetCFrame: any = nil
    local origGetTargetPosition: any = nil

    local function destroyTracerVisuals(): ()
        if tracerPart then
            pcall(function(): ()
                tracerPart:Destroy()
            end)
            tracerPart = nil
        end
        if targetDotPart then
            pcall(function(): ()
                targetDotPart:Destroy()
            end)
            targetDotPart = nil
        end
    end

    -- Check if player is valid target
    local function isValidTarget(player: Player): boolean
        if not player or player == LocalPlayer then
            return false
        end
        if type(isProtectedTarget) == "function" and isProtectedTarget(player) then
            return false
        end
        if type(isPlayerAlive) == "function" and not isPlayerAlive(player) then
            return false
        end
        if type(getPlayerRole) == "function" and getPlayerRole(player) == "Murderer" then
            return false
        end
        local character: Model? = player.Character
        if not character then
            return false
        end
        local root: BasePart? = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
        if not root or not humanoid or humanoid.Health <= 0 then
            return false
        end
        return true
    end

    -- Get equipped or carried knife when local player is Murderer
    local function getKnife(): Tool?
        local character: Model? = LocalPlayer and LocalPlayer.Character
        if not character then
            return nil
        end
        if type(getPlayerWeapon) == "function" then
            local equippedKnife: Tool? = getPlayerWeapon(LocalPlayer, "Knife", true)
            if equippedKnife then
                return equippedKnife
            end
            local anyKnife: Tool? = getPlayerWeapon(LocalPlayer, "Knife", false)
            if anyKnife then
                return anyKnife
            end
        end
        for _, item: Instance in ipairs(character:GetChildren()) do
            if item:IsA("Tool") then
                local name: string = item.Name:lower()
                if name:find("knife") or item:FindFirstChild("Events") then
                    local events: Instance? = item:FindFirstChild("Events")
                    if name:find("knife") or (events and events:FindFirstChild("KnifeThrown")) then
                        return item :: Tool
                    end
                end
            end
        end
        local backpack: Instance? = LocalPlayer:FindFirstChildOfClass("Backpack")
        if backpack then
            for _, item: Instance in ipairs(backpack:GetChildren()) do
                if item:IsA("Tool") then
                    local name: string = item.Name:lower()
                    local events: Instance? = item:FindFirstChild("Events")
                    if name:find("knife") or (events and events:FindFirstChild("KnifeThrown")) then
                        return item :: Tool
                    end
                end
            end
        end
        return nil
    end

    local function getThrowOriginCFrame(knife: Tool?): CFrame?
        local character: Model? = LocalPlayer and LocalPlayer.Character
        if not character then
            return nil
        end
        local handle: Instance? = knife and knife:FindFirstChild("Handle")
        if handle and handle:IsA("BasePart") and knife and knife.Parent == character then
            return (handle :: BasePart).CFrame
        end
        local hand: Instance? = character:FindFirstChild("RightHand")
            or character:FindFirstChild("Right Arm")
            or character:FindFirstChild("HumanoidRootPart")
        if hand and hand:IsA("BasePart") then
            return (hand :: BasePart).CFrame
        end
        return nil
    end

    local function checkLineOfSight(originPos: Vector3, targetPos: Vector3, targetChar: Model?): boolean
        if not settings.wallCheck then
            return true
        end
        if type(isWeaponPathClear) == "function" and targetChar then
            local okClear: boolean, isClear: any = pcall(
                isWeaponPathClear,
                originPos,
                targetPos,
                targetChar,
                nil,
                { ignoreTarget = true }
            )
            if okClear then
                return isClear == true
            end
        end
        local direction: Vector3 = targetPos - originPos
        if direction.Magnitude < 0.05 then
            return true
        end
        local params: RaycastParams = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local ignoreList: {Instance} = {}
        if LocalPlayer and LocalPlayer.Character then
            table.insert(ignoreList, LocalPlayer.Character)
        end
        if targetChar then
            table.insert(ignoreList, targetChar)
        end
        params.FilterDescendantsInstances = ignoreList
        params.RespectCanCollide = true
        params.IgnoreWater = true
        local result: RaycastResult? = workspace:Raycast(originPos, direction, params)
        return result == nil
    end

    -- Predict target intercept position for MM2 ThrowingKnife (96 studs/s linear projectile)
    local function resolveKnifeAim(target: Player, originPos: Vector3, knife: Tool?): Vector3?
        local character: Model? = target.Character
        if not character then
            return nil
        end
        local root: BasePart? = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then
            return nil
        end

        local speed: number = 96
        if knife then
            pcall(function(): ()
                local attrSpeed: any = knife:GetAttribute("ThrowSpeed")
                if type(attrSpeed) == "number" and attrSpeed >= 24 and attrSpeed <= 300 then
                    speed = attrSpeed
                end
            end)
        end

        local predicted: Vector3? = nil
        local aimInfo: any = nil
        if type(prediction) == "table" and type(prediction.knifeAim) == "function" then
            -- v139.4: the blade speed HAS to reach the predictor. It was read
            -- from the tool above and then only used by the local fallback, so
            -- every knife that is not the default 96 studs/s was solved with
            -- the wrong flight time even though the correct number was in
            -- hand.
            local okPred: boolean, aimPoint: any, info: any =
                pcall(prediction.knifeAim, target, originPos, speed)
            if okPred and typeof(aimPoint) == "Vector3" then
                predicted = aimPoint :: Vector3
                aimInfo = info
            end
        end

        if not predicted then
            local velocity: Vector3 = root.AssemblyLinearVelocity
            local latency: number = 0.06
            if type(getEstimatedLatency) == "function" then
                local okLat: boolean, l: any = pcall(getEstimatedLatency)
                if okLat and type(l) == "number" and l == l then
                    latency = math.clamp(l, 0, 0.5)
                end
            end
            local observed: Vector3 = root.Position + velocity * latency
            local rel: Vector3 = observed - originPos
            local a: number = velocity:Dot(velocity) - speed * speed
            local b: number = 2 * rel:Dot(velocity)
            local c: number = rel:Dot(rel)
            local flight: number? = nil
            if c < 0.0025 then
                flight = 0
            elseif math.abs(a) < 1e-6 then
                if b < -1e-6 then
                    flight = -c / b
                end
            else
                local disc: number = b * b - 4 * a * c
                if disc >= 0 then
                    local sqrtDisc: number = math.sqrt(disc)
                    local t1: number = (-b - sqrtDisc) / (2 * a)
                    local t2: number = (-b + sqrtDisc) / (2 * a)
                    if t1 > 0 then
                        flight = t1
                    end
                    if t2 > 0 and (not flight or t2 < flight) then
                        flight = t2
                    end
                end
            end
            if flight and flight == flight then
                flight = math.clamp(flight, 0, 1.5)
                local horizVel: Vector3 = Vector3.new(velocity.X, 0, velocity.Z)
                local yLead: number = math.clamp(velocity.Y * math.min(flight, 0.28), -3.5, 4.0)
                predicted = observed + horizVel * flight + Vector3.new(0, yLead, 0)
            else
                predicted = observed
            end
        end

        if not predicted then
            return nil
        end

        if checkLineOfSight(originPos, predicted, character) then
            return predicted
        end

        -- Fallback visibility scan across torso/head/limbs if WallCheck blocks primary point
        --
        -- v139.4: only the TIME part of the predictor's displacement may be
        -- reused on another body part. `predicted - root.Position` is lead
        -- PLUS the torso/head offset the predictor itself sampled
        -- (`capturedPosition = last.position + aimOffset`), so adding it to
        -- UpperTorso or Head counted the torso height twice and aimed 2-4
        -- studs above the part it named. Using the predictor's own reference
        -- point keeps the lead and drops the duplicated height.
        local leadOffset: Vector3 = predicted - root.Position
        if aimInfo and typeof(aimInfo.capturedPosition) == "Vector3" then
            leadOffset = predicted - (aimInfo.capturedPosition :: Vector3)
        end
        local candidateNames: {string} = {
            "UpperTorso", "Torso", "HumanoidRootPart", "Head",
            "RightUpperArm", "LeftUpperArm", "Right Arm", "Left Arm",
        }
        for _, partName: string in ipairs(candidateNames) do
            local part: Instance? = character:FindFirstChild(partName)
            if part and part:IsA("BasePart") then
                local candidatePoint: Vector3 = (part :: BasePart).Position + leadOffset
                if checkLineOfSight(originPos, candidatePoint, character) then
                    return candidatePoint
                end
            end
        end

        return nil
    end

    -- Find best target for knife throw
    local function findTarget(): Player?
        local localChar: Model? = LocalPlayer and LocalPlayer.Character
        if not localChar then
            return nil
        end
        local localRoot: BasePart? = localChar:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not localRoot then
            return nil
        end
        local knife: Tool? = getKnife()
        local originCF: CFrame? = getThrowOriginCFrame(knife)
        local originPos: Vector3 = originCF and originCF.Position or localRoot.Position

        local bestTarget: Player? = nil
        local bestScore: number = math.huge

        for _, player: Player in ipairs(Players:GetPlayers()) do
            if isValidTarget(player) then
                local targetChar: Model? = player.Character
                local targetRoot: BasePart? = targetChar
                    and targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?
                if targetRoot then
                    local distance: number = (targetRoot.Position - originPos).Magnitude
                    if distance <= 250 then
                        local aimPoint: Vector3? = resolveKnifeAim(player, originPos, knife)
                        if aimPoint then
                            local roleBonus: number = 0
                            if type(getPlayerRole) == "function" then
                                local role: string? = getPlayerRole(player)
                                if role == "Sheriff" or role == "Hero" then
                                    roleBonus = -35
                                end
                            end
                            local score: number = distance + roleBonus
                            if score < bestScore then
                                bestScore = score
                                bestTarget = player
                            end
                        end
                    end
                end
            end
        end

        return bestTarget
    end

    -- v158: a speculative throw is a LANE decision, never a target decision.
    -- v157 centred the pre-fire points on the nearest hidden opponent and
    -- walked radii around that body: with nobody visible the redirect still
    -- pointed the native throw at a player behind geometry, and a corpse got
    -- the same treatment. This version never reads an opponent position. It
    -- samples bearings around the camera/character forward, keeps only the
    -- directions where the blade would travel down an unobstructed lane into
    -- open, walkable space, and scores them by facing first, then depth and
    -- the width of the doorway the lane threads.
    local speculativeAt: number = -math.huge
    local speculativePoint: Vector3? = nil
    local speculativeOrigin: Vector3? = nil
    local speculativeSequence: number = 0

    local LANE_SAMPLES: number = 16
    local LANE_MIN_STUDS: number = 16
    local LANE_MAX_STUDS: number = 140
    local LANE_SIDE_STUDS: number = 6
    local LANE_HEADROOM_STUDS: number = 8
    local LANE_FLOOR_TOLERANCE: number = 14
    local LANE_GROUND_OFFSET: number = 2.5
    local LANE_MOUTH_STUDS: number = 24
    local LANE_SCORE_CAP: number = 60
    local LANE_FACING_WEIGHT: number = 40

    local function resolveSpeculativeAim(originPos: Vector3): Vector3?
        if type(isPlayerAlive) == "function" and not isPlayerAlive(LocalPlayer) then return nil end
        if type(getPlayerRole) == "function" and getPlayerRole(LocalPlayer) ~= "Murderer" then return nil end
        local currentCore: any = state and state.mm2Core
        if currentCore and type(currentCore.isRoundLifecycleActive) == "function" then
            local ok: boolean, active: any = pcall(currentCore.isRoundLifecycleActive)
            if ok and active == false then return nil end
        end
        local character: Model? = LocalPlayer and LocalPlayer.Character
        local localRoot: BasePart? = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not localRoot then return nil end
        local players: {Player} = Players:GetPlayers()
        for _, player: Player in ipairs(players) do
            if player ~= LocalPlayer and type(isProtectedTarget) == "function" and isProtectedTarget(player) then
                speculativePoint = nil
                return nil
            end
        end
        -- Every character is skipped by the lane probes: an opponent body may
        -- stand in the lane (that would be a hit, not a wall), but no body
        -- position may decide where the lane goes. Corpses are colliders, so
        -- ignoring them keeps a ragdoll from displacing the opening.
        local ignore: {Instance} = {}
        if character then table.insert(ignore, character) end
        for _, player: Player in ipairs(players) do
            local other: Model? = player.Character
            if other and other ~= character then table.insert(ignore, other) end
        end
        local function cast(from: Vector3, to: Vector3): (boolean, RaycastResult?)
            local ok: boolean, result: any = pcall(function(): any
                local params: RaycastParams = RaycastParams.new()
                params.FilterType = Enum.RaycastFilterType.Exclude
                params.FilterDescendantsInstances = ignore
                params.RespectCanCollide = true
                params.IgnoreWater = true
                return workspace:Raycast(from, to - from, params)
            end)
            if not ok then
                return false, nil
            end
            return true, result
        end
        local function laneClear(from: Vector3, to: Vector3): boolean
            local ok: boolean, hit: any = cast(from, to)
            return ok and hit == nil
        end
        local function groundBelow(point: Vector3): Vector3?
            local ok: boolean, hit: any = cast(
                point + Vector3.new(0, LANE_HEADROOM_STUDS, 0),
                point + Vector3.new(0, -10, 0)
            )
            if not ok or not hit or typeof(hit.Position) ~= "Vector3" then
                return nil
            end
            local normal: any = hit.Normal
            if typeof(normal) == "Vector3" and normal.Y < 0.55 then
                return nil
            end
            return hit.Position
        end
        local now: number = os.clock()
        if now - speculativeAt < 0.4 and speculativeOrigin
            and (originPos - speculativeOrigin).Magnitude < 4 then
            if not speculativePoint then return nil end
            if laneClear(originPos, speculativePoint) then return speculativePoint end
        end
        speculativeAt, speculativeOrigin = now, originPos
        local forward: Vector3 = Vector3.new(0, 0, -1)
        pcall(function(): ()
            local sources: {any} = {}
            local camera: any = workspace.CurrentCamera
            if camera then table.insert(sources, camera) end
            table.insert(sources, localRoot)
            for _, source: any in ipairs(sources) do
                local okLook: boolean, look: any = pcall(function(): any
                    return source.CFrame.LookVector
                end)
                if okLook and typeof(look) == "Vector3" then
                    local flat: Vector3 = Vector3.new(look.X, 0, look.Z)
                    if flat.Magnitude > 0.05 then
                        forward = flat.Unit
                        break
                    end
                end
            end
        end)
        -- The hand throws from a little above the pivot; probes start there so
        -- a low railing or a ledge at waist height is part of the lane.
        local eye: Vector3 = originPos + Vector3.new(0, 1.2, 0)
        local referenceFloor: Vector3? = groundBelow(originPos)
        local referenceY: number = referenceFloor and referenceFloor.Y or originPos.Y
        local baseAngle: number = math.atan2(forward.Z, forward.X)
        local step: number = (math.pi * 2) / LANE_SAMPLES
        local bestPoint: Vector3? = nil
        local bestScore: number = -math.huge
        -- The floor can end before the LaneMax ray does (a ledge, a map edge),
        -- so a lane is sampled from far to near and the farthest landing with
        -- solid floor, headroom and a clear hand line wins.
        local laneDistances: {number} = {140, 80, 45, 26, 16}
        for i: number = 0, LANE_SAMPLES - 1 do
            -- Rotating the start only breaks ties between equal lanes; the
            -- chosen opening is stable while the map and the hand are.
            local index: number = (i + speculativeSequence) % LANE_SAMPLES
            local angle: number = baseAngle + index * step
            local direction: Vector3 = Vector3.new(math.cos(angle), 0, math.sin(angle))
            local castOk: boolean, hit: any = cast(eye, eye + direction * LANE_MAX_STUDS)
            if castOk then
                local clearDistance: number = LANE_MAX_STUDS
                if hit and typeof(hit.Position) == "Vector3" then
                    clearDistance = (hit.Position - eye).Magnitude - 1.5
                end
                local point: Vector3? = nil
                local landing: number = 0
                if clearDistance >= LANE_MIN_STUDS then
                    for _, candidate: number in ipairs(laneDistances) do
                        if candidate <= clearDistance and candidate >= LANE_MIN_STUDS then
                            local floor: Vector3? = groundBelow(eye + direction * candidate)
                            if floor and math.abs(floor.Y - referenceY) <= LANE_FLOOR_TOLERANCE then
                                local candidatePoint: Vector3 = floor
                                    + Vector3.new(0, LANE_GROUND_OFFSET, 0)
                                local distance: number = (candidatePoint - originPos).Magnitude
                                if distance >= 3 and distance <= 250
                                    and laneClear(candidatePoint, candidatePoint
                                        + Vector3.new(0, LANE_HEADROOM_STUDS, 0))
                                    and laneClear(originPos, candidatePoint) then
                                    point = candidatePoint
                                    landing = candidate
                                    break
                                end
                            end
                        end
                    end
                end
                if point then
                    -- Facing is what makes an opening strategic: a doorway in
                    -- front beats a wider patch of floor behind the player.
                    -- Depth and width only separate openings that are ahead.
                    local alignment: number = direction:Dot(forward)
                    local baseScore: number = alignment * LANE_FACING_WEIGHT
                        + math.min(landing, LANE_SCORE_CAP) * 0.5
                    -- Only pay for the width probes when the lane can still
                    -- win; a narrow slot scores at most +16.
                    if baseScore + 16 > bestScore then
                        -- Width at the mouth of the lane (a doorway), not the
                        -- size of the room behind it.
                        local side: Vector3 = Vector3.new(-direction.Z, 0, direction.X)
                        local mouth: Vector3 = eye + direction * math.min(landing, LANE_MOUTH_STUDS)
                        local mouthFloor: Vector3? = groundBelow(mouth)
                        local widthScore: number = 0
                        if mouthFloor then
                            local mouthPoint: Vector3 = mouthFloor
                                + Vector3.new(0, LANE_GROUND_OFFSET, 0)
                            if laneClear(mouthPoint, mouthPoint + side * LANE_SIDE_STUDS) then
                                widthScore += 1
                            end
                            if laneClear(mouthPoint, mouthPoint - side * LANE_SIDE_STUDS) then
                                widthScore += 1
                            end
                        end
                        local score: number = baseScore + widthScore * 8
                        if score > bestScore then
                            bestScore, bestPoint = score, point
                        end
                    end
                end
            end
        end
        speculativePoint = bestPoint
        return bestPoint
    end

    local function updateTracerVisual(originPos: Vector3?, aimPos: Vector3?): ()
        if not settings.enabled or not settings.knifeTracer or not originPos or not aimPos then
            destroyTracerVisuals()
            return
        end
        local delta: Vector3 = aimPos - originPos
        local dist: number = delta.Magnitude
        if dist < 0.25 or dist > 400 then
            destroyTracerVisuals()
            return
        end
        pcall(function(): ()
            if not tracerPart or not tracerPart.Parent then
                local beamPart: Part = Instance.new("Part")
                beamPart.Name = "WurstKnifeTracer"
                beamPart.Anchored = true
                beamPart.CanCollide = false
                beamPart.CanQuery = false
                beamPart.CanTouch = false
                beamPart.Material = Enum.Material.Neon
                beamPart.Color = Color3.fromRGB(255, 65, 65)
                beamPart.Transparency = 0.25
                beamPart.Parent = workspace
                tracerPart = beamPart
            end
            if not targetDotPart or not targetDotPart.Parent then
                local dot: Part = Instance.new("Part")
                dot.Name = "WurstKnifeAimDot"
                dot.Shape = Enum.PartType.Ball
                dot.Size = Vector3.new(1.1, 1.1, 1.1)
                dot.Anchored = true
                dot.CanCollide = false
                dot.CanQuery = false
                dot.CanTouch = false
                dot.Material = Enum.Material.Neon
                dot.Color = Color3.fromRGB(255, 220, 60)
                dot.Transparency = 0.15
                dot.Parent = workspace
                targetDotPart = dot
            end
            if tracerPart then
                tracerPart.Size = Vector3.new(0.14, 0.14, dist)
                tracerPart.CFrame = CFrame.lookAt(originPos + delta * 0.5, aimPos)
            end
            if targetDotPart then
                targetDotPart.CFrame = CFrame.new(aimPos)
            end
        end)
    end

    -- Throw knife at predicted target using MM2's Knife.Events.KnifeThrown remote
    -- v139.2: the equip is a round trip, the throw is not. Firing the remote
    -- in the same frame as EquipTool sends a throw from a tool the server still
    -- believes is in the backpack: in the saved session 13 auto throws produced
    -- 9 observed blades (4 vanished) and the 4 that did fire used the RightHand
    -- fallback origin instead of the knife handle. So: equip once, wait for the
    -- tool to actually be in the character, and only then throw.
    local equipRequestedAt: number = -math.huge
    local equipRequestedTool: Tool? = nil

    local function ensureEquipped(knife: Tool, humanoid: Humanoid): boolean
        local character: Model? = LocalPlayer and LocalPlayer.Character
        if not character then
            return false
        end
        if knife.Parent == character then
            equipRequestedAt = -math.huge
            equipRequestedTool = nil
            return true
        end
        local now: number = os.clock()
        -- Re-ask every 0.25 s at most; EquipTool while the previous request is
        -- still travelling just stacks another equip request.
        if equipRequestedTool ~= knife or now - equipRequestedAt >= 0.25 then
            equipRequestedAt = now
            equipRequestedTool = knife
            pcall(function(): ()
                humanoid:EquipTool(knife)
            end)
        end
        return false
    end

    local function throwKnife(target: Player?, knife: Tool): boolean
        local character: Model? = LocalPlayer and LocalPlayer.Character
        if not character then
            return false
        end
        local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 or not ensureEquipped(knife, humanoid) then
            return false
        end
        local originCF: CFrame? = getThrowOriginCFrame(knife)
        if not originCF then
            return false
        end
        if target and not isValidTarget(target) then return false end
        local aimPos: Vector3? = target and resolveKnifeAim(target, originCF.Position, knife)
            or resolveSpeculativeAim(originCF.Position)
        if not aimPos then
            return false
        end

        local fired: boolean = false
        local eventsFolder: Instance? = knife:FindFirstChild("Events")
        local knifeThrownRemote: Instance? = eventsFolder and eventsFolder:FindFirstChild("KnifeThrown")
        if knifeThrownRemote and knifeThrownRemote:IsA("RemoteEvent") then
            local okFire: boolean = pcall(function(): ()
                (knifeThrownRemote :: RemoteEvent):FireServer(originCF, CFrame.new(aimPos))
            end)
            if okFire then
                fired = true
            end
        end

        if not fired then
            pcall(function(): ()
                local rs: Instance? = game:GetService("ReplicatedStorage")
                local remotes: Instance? = rs and rs:FindFirstChild("Remotes")
                local throwRemote: Instance? = remotes and remotes:FindFirstChild("Event")
                if throwRemote and throwRemote:IsA("RemoteEvent") then
                    local dir: Vector3 = (aimPos - originCF.Position).Unit
                    local rem: RemoteEvent = throwRemote :: RemoteEvent
                    rem:FireServer("Throw", aimPos, dir)
                    fired = true
                end
            end)
        end

        return fired
    end

    -- Hook ReplicatedStorage.ClientServices.WeaponService so native PC & Mobile
    -- knife throws (Mouse, Keyboard E, Gamepad, Mobile TouchControls.RightBar.Throw)
    -- automatically redirect to the Knife Predictor's aim point!
    local function installWeaponServiceRedirect(): ()
        if hookedWeaponService then
            return
        end
        pcall(function(): ()
            local rs: Instance? = game:GetService("ReplicatedStorage")
            local clientServices: Instance? = rs and rs:FindFirstChild("ClientServices")
            local wsModule: Instance? = clientServices and clientServices:FindFirstChild("WeaponService")
            if not wsModule then
                return
            end
            local okReq: boolean, wsTable: any = pcall(require, wsModule)
            if not okReq or type(wsTable) ~= "table" then
                return
            end
            origGetMouseTargetCFrame = wsTable.GetMouseTargetCFrame
            origGetTargetPosition = wsTable.GetTargetPosition
            hookedWeaponService = wsTable

            if type(origGetMouseTargetCFrame) == "function" then
                wsTable.GetMouseTargetCFrame = function(self: any, ...: any): any
                    if settings.enabled then
                        local knife: Tool? = getKnife()
                        local character: Model? = LocalPlayer and LocalPlayer.Character
                        if knife and character and knife.Parent == character then
                            local originCF: CFrame? = getThrowOriginCFrame(knife)
                            local target: Player? = findTarget()
                            if originCF then
                                local aim: Vector3? = target and resolveKnifeAim(target, originCF.Position, knife)
                                    or resolveSpeculativeAim(originCF.Position)
                                if aim then return CFrame.new(aim) end
                            end
                        end
                    end
                    return origGetMouseTargetCFrame(self, ...)
                end
            end

            if type(origGetTargetPosition) == "function" then
                wsTable.GetTargetPosition = function(self: any, ...: any): any
                    if settings.enabled then
                        local knife: Tool? = getKnife()
                        local character: Model? = LocalPlayer and LocalPlayer.Character
                        if knife and character and knife.Parent == character then
                            local originCF: CFrame? = getThrowOriginCFrame(knife)
                            local target: Player? = findTarget()
                            if originCF then
                                local aim: Vector3? = target and resolveKnifeAim(target, originCF.Position, knife)
                                    or resolveSpeculativeAim(originCF.Position)
                                -- The captured MM2 WeaponService returns a CFrame here,
                                -- despite the method name. Preserve that native contract
                                -- just as GetMouseTargetCFrame does.
                                if aim then return CFrame.new(aim) end
                            end
                        end
                    end
                    return origGetTargetPosition(self, ...)
                end
            end
        end)
    end

    local function uninstallWeaponServiceRedirect(): ()
        if not hookedWeaponService then
            return
        end
        pcall(function(): ()
            if origGetMouseTargetCFrame then
                hookedWeaponService.GetMouseTargetCFrame = origGetMouseTargetCFrame
            end
            if origGetTargetPosition then
                hookedWeaponService.GetTargetPosition = origGetTargetPosition
            end
        end)
        hookedWeaponService = nil
        origGetMouseTargetCFrame = nil
        origGetTargetPosition = nil
    end

    -- v139.2: this loop used to run every frame and, for EVERY player in the
    -- lobby, ran the aim solver -- and the aim solver casts line-of-sight rays
    -- against the map, then up to 8 more per body part when the first one is
    -- blocked. Ten players meant dozens of raycasts per frame for a number
    -- that only changes a few times per second. The solve is now cached for
    -- 1/15 s, and the throw itself always re-solves so the blade leaves in the
    -- direction the target is actually at right now.
    local AIM_CACHE_SECONDS: number = 1 / 15
    local cachedTarget: Player? = nil
    local cachedAim: Vector3? = nil
    local cachedOrigin: CFrame? = nil
    local cachedAt: number = -math.huge

    local function solveAim(knife: Tool): (Player?, Vector3?, CFrame?)
        local now: number = os.clock()
        if now - cachedAt >= AIM_CACHE_SECONDS then
            cachedAt = now
            cachedTarget = findTarget()
            cachedAim = nil
            cachedOrigin = getThrowOriginCFrame(knife)
            if cachedOrigin then
                cachedAim = cachedTarget and resolveKnifeAim(cachedTarget, cachedOrigin.Position, knife)
                    or resolveSpeculativeAim(cachedOrigin.Position)
            end
        elseif cachedOrigin then
            -- Origin only: the target's predicted point stays cached, but the
            -- handle moves with the character and the tracer must follow it.
            cachedOrigin = getThrowOriginCFrame(knife) or cachedOrigin
        end
        return cachedTarget, cachedAim, cachedOrigin
    end

    local function invalidateAim(): ()
        cachedAt = -math.huge
        cachedTarget = nil
        cachedAim = nil
        cachedOrigin = nil
    end

    -- Main loop for Knife Tracer and Auto Knife Throw
    local function knifeThrowLoop(): ()
        if not settings.enabled then
            setKnifeStatus(nil)
            destroyTracerVisuals()
            invalidateAim()
            return
        end

        local knife: Tool? = getKnife()
        if not knife then
            setKnifeStatus("Waiting for knife")
            destroyTracerVisuals()
            invalidateAim()
            return
        end

        local now: number = os.clock()
        local cooldown: number = math.clamp(tonumber(settings.delay) or 0, 0, 10)
        local wantThrow: boolean = settings.autoThrow
            and now - lastThrowAttempt >= cooldown

        -- The cached pick is at most 1/15 s old, which only decides WHO gets
        -- the blade. throwKnife re-solves the aim from the live handle, so the
        -- direction is always current even when this list is stale.
        local target, aimPos, originCF = solveAim(knife)
        if not aimPos then
            setKnifeStatus("No clear target or lane")
            destroyTracerVisuals()
            return
        end
        setKnifeStatus(target and "Predicted target" or "Opening lane · no visible target")

        if settings.knifeTracer and originCF and aimPos then
            updateTracerVisual(originCF.Position, aimPos)
        else
            destroyTracerVisuals()
        end

        if wantThrow then
            if throwKnife(target, knife) then
                setKnifeStatus(target and "Throw sent · hit unconfirmed" or "Speculative throw sent · hit unconfirmed")
                lastThrowAttempt = now
                if not target then
                    speculativeSequence += 1
                    speculativeAt, speculativePoint = -math.huge, nil
                end
                -- A throw consumes the aim: the next frame re-solves instead of
                -- reusing a point measured before the blade left.
                invalidateAim()
            end
        end
    end

    -- Toggle function
    local function toggleKnifeThrow(enabled: boolean): ()
        settings.enabled = enabled
        disconnectFeatureConnection("MM2KnifeThrow")

        if not enabled then
            uninstallWeaponServiceRedirect()
            setKnifeStatus(nil)
            destroyTracerVisuals()
            invalidateAim()
            speculativeAt, speculativePoint, speculativeOrigin = -math.huge, nil, nil
            return
        end

        installWeaponServiceRedirect()
        featureConnections.MM2KnifeThrow = TaskManager:Connect(knifeThrowLoop)
    end

    -- Create the feature in Combat category
    KnifeThrowFeature = createUniversalFeature(
        "Knife Throw",
        "Redirects PC & Mobile knife throws to the Knife Predictor's aim point, with optional Auto Knife Throw and Knife Tracer.",
        15,
        toggleKnifeThrow,
        {
            categoryName = "Combat",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )

    addToggleOption(
        KnifeThrowFeature,
        "WallCheck",
        true,
        function(value: boolean): ()
            settings.wallCheck = value
        end,
        "Checks line of sight; when nobody is visible, the throw is aimed down a clear opening lane instead of at a hidden player."
    )

    addToggleOption(
        KnifeThrowFeature,
        "Auto Knife Throw",
        false,
        function(value: boolean): ()
            settings.autoThrow = value == true
        end,
        "Throws toward predicted targets; with nobody visible it aims down an open, unobstructed lane. An opening is not a target or a confirmed hit."
    )

    addNumberOption(
        KnifeThrowFeature,
        "Delay",
        0.6,
        0,
        10,
        function(value: number): ()
            settings.delay = math.clamp(tonumber(value) or 0, 0, 10)
        end,
        "Delay in seconds between automatic knife throws (0 to 10 seconds).",
        0.1
    )

    addInformationOption(
        KnifeThrowFeature,
        "Seconds"
    )

    addToggleOption(
        KnifeThrowFeature,
        "Knife Tracer",
        false,
        function(value: boolean): ()
            settings.knifeTracer = value == true
            if not settings.knifeTracer then
                destroyTracerVisuals()
            end
        end,
        "Draws a live 3D trajectory tracer from your hand to the predicted knife impact point."
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
