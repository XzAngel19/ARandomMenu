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

    local originHandleTool: Tool? = nil
    local originHandle: BasePart? = nil
    local function getThrowOriginCFrame(knife: Tool?): CFrame?
        local character: Model? = LocalPlayer and LocalPlayer.Character
        if not character then
            return nil
        end
        if knife and knife.Parent == character then
            if originHandleTool ~= knife or not originHandle or originHandle.Parent ~= knife then
                local handle: Instance? = knife:FindFirstChild("Handle")
                originHandleTool = knife
                originHandle = handle and handle:IsA("BasePart") and (handle :: BasePart) or nil
            end
            if originHandle then return originHandle.CFrame end
        end
        local hand: Instance? = character:FindFirstChild("RightHand")
            or character:FindFirstChild("Right Arm")
            or character:FindFirstChild("HumanoidRootPart")
        if hand and hand:IsA("BasePart") then
            return (hand :: BasePart).CFrame
        end
        return nil
    end

    -- v159: WallCheck is now the only guarantee, so it has to be honest:
    --  * the shared helper is called with `strict`, which makes a fully
    --    transparent but SOLID barrier stop the blade. The gun's first pass
    --    skips those; the knife must not.
    --  * the segment is tested as a thin corridor, not one mathematical line,
    --    so a railing edge cannot slip between samples.
    --  * the body has to be visible from the hand RIGHT NOW, not only at the
    --    predicted point. A predicted point that peeks around a corner is not
    --    reachable by a straight blade, and aiming at it is what looked like
    --    "knife through the wall".
    local CORRIDOR_STUDS: number = 0.45
    local function raycastClear(
        from: Vector3,
        to: Vector3,
        ignoreList: {Instance},
        requireBody: Model?
    ): boolean
        local ok: boolean, clear: any = pcall(function(): boolean
            local params: RaycastParams = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = ignoreList
            params.RespectCanCollide = true
            params.IgnoreWater = true
            local hit: RaycastResult? = workspace:Raycast(from, to - from, params)
            if requireBody then
                return hit ~= nil and hit.Instance:IsDescendantOf(requireBody)
            end
            return hit == nil
        end)
        return ok and clear == true
    end

    local function sharedPathClear(
        from: Vector3,
        to: Vector3,
        targetChar: Model?,
        requireBody: boolean
    ): boolean?
        if type(isWeaponPathClear) ~= "function" or not targetChar then
            return nil
        end
        local options: any = requireBody and { requireTarget = true } or { ignoreTarget = true }
        local ok: boolean, clear: any = pcall(isWeaponPathClear, from, to, targetChar, true, options)
        if not ok or type(clear) ~= "boolean" then
            return nil
        end
        return clear
    end

    local function ignoreListFor(targetChar: Model?): {Instance}
        local list: {Instance} = {}
        local localChar: Model? = LocalPlayer and LocalPlayer.Character
        if localChar then table.insert(list, localChar) end
        if targetChar then table.insert(list, targetChar) end
        return list
    end

    -- "I can see that body from the hand": the ray must END on the body.
    local function bodyVisible(originPos: Vector3, bodyPos: Vector3, targetChar: Model?): boolean
        if not settings.wallCheck then
            return true
        end
        local from: Vector3 = originPos
        local to: Vector3 = bodyPos
        if (to - from).Magnitude < 0.05 then
            return true
        end
        local shared: boolean? = sharedPathClear(from, to, targetChar, true)
        if shared ~= nil then
            return shared
        end
        return raycastClear(from, to, ignoreListFor(nil), targetChar)
    end

    -- "Nothing solid between the hand and that point": corridor of five rays.
    local function checkLineOfSight(originPos: Vector3, targetPos: Vector3, targetChar: Model?): boolean
        if not settings.wallCheck then
            return true
        end
        local direction: Vector3 = targetPos - originPos
        local length: number = direction.Magnitude
        if length < 0.05 then
            return true
        end
        local unit: Vector3 = direction / length
        local side: Vector3 = unit:Cross(Vector3.new(0, 1, 0))
        if side.Magnitude < 0.05 then
            side = Vector3.new(1, 0, 0)
        end
        side = side.Unit
        local up: Vector3 = side:Cross(unit).Unit
        local offsets: {Vector3} = {
            Vector3.zero,
            side * CORRIDOR_STUDS,
            side * -CORRIDOR_STUDS,
            up * CORRIDOR_STUDS,
            up * -CORRIDOR_STUDS,
        }
        for _index: number, offset: Vector3 in ipairs(offsets) do
            local from: Vector3 = originPos + offset
            local to: Vector3 = targetPos + offset
            -- Every corridor ray uses the same strict rule as the centre one.
            -- A raw raycast here would let an invisible decoration that the
            -- shared helper skips block the throw, which made WallCheck say no
            -- for geometry the blade would have flown through.
            local shared: boolean? = sharedPathClear(from, to, targetChar, false)
            if shared ~= nil then
                if not shared then
                    return false
                end
            elseif not raycastClear(from, to, ignoreListFor(targetChar), nil) then
                return false
            end
        end
        return true
    end

    -- Predict target intercept position for MM2 ThrowingKnife (96 studs/s linear projectile)
    -- Returns the point and the blade's flight time, which is what makes one
    -- target a sooner hit than another.
    -- `cheap` is for target SELECTION: it still requires the body to be
    -- visible, but skips the five-ray corridor, which is re-checked with the
    -- live origin right before the packet leaves.
    local function resolveKnifeAim(
        target: Player,
        originPos: Vector3,
        knife: Tool?,
        cheap: boolean?
    ): (Vector3?, number?)
        local character: Model? = target.Character
        if not character then
            return nil, nil
        end
        local root: BasePart? = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root then
            return nil, nil
        end
        -- Check the live body before doing the more expensive intercept/ground
        -- work; hidden candidates cannot become speculative shots.
        if not bodyVisible(originPos, root.Position, character) then
            return nil, nil
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
            if velocity.X ~= velocity.X or velocity.Y ~= velocity.Y or velocity.Z ~= velocity.Z
                or math.abs(velocity.X) == math.huge or math.abs(velocity.Y) == math.huge
                or math.abs(velocity.Z) == math.huge then
                velocity = Vector3.zero
            end
            local latency: number = 0.06
            if type(getEstimatedLatency) == "function" then
                local okLat: boolean, l: any = pcall(getEstimatedLatency)
                if okLat and type(l) == "number" and l == l then
                    latency = math.clamp(l, 0, 0.5)
                end
            end
            -- This is only the fallback when the shared predictor is absent or
            -- cannot solve. Previously `velocity * latency` applied unbounded
            -- vertical lead BEFORE the later 3.5 stud drop clamp: a replicated
            -- -120 Y velocity at 0.5 s already aimed 60 studs below the body.
            -- Keep horizontal transport and cap the *entire* vertical lead.
            -- The body's actual height is never clamped against the thrower:
            -- an enemy on a lower floor still produces a downward shot.
            local horizVel: Vector3 = Vector3.new(velocity.X, 0, velocity.Z)
            local observed: Vector3 = root.Position + horizVel * latency
            local rel: Vector3 = observed - originPos
            local a: number = horizVel:Dot(horizVel) - speed * speed
            local b: number = 2 * rel:Dot(horizVel)
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
                local yLead: number = math.clamp(
                    velocity.Y * math.min(latency + flight, 0.28), -2.0, 4.0
                )
                predicted = observed + horizVel * flight + Vector3.new(0, yLead, 0)
            else
                local yLead: number = math.clamp(velocity.Y * math.min(latency, 0.28), -2.0, 4.0)
                predicted = observed + Vector3.new(0, yLead, 0)
            end
        end

        if not predicted then
            return nil, nil
        end

        local flight: number? = nil
        if aimInfo and type(aimInfo.flightSeconds) == "number" then
            flight = math.max(0, aimInfo.flightSeconds)
        else
            flight = (predicted - originPos).Magnitude / speed
        end

        -- The current body was already checked before prediction: a future
        -- point peeking around a corner cannot make a hidden body eligible.
        if cheap or checkLineOfSight(originPos, predicted, character) then
            return predicted, flight
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
                local partPosition: Vector3 = (part :: BasePart).Position
                local candidatePoint: Vector3 = partPosition + leadOffset
                if bodyVisible(originPos, partPosition, character)
                    and (cheap or checkLineOfSight(originPos, candidatePoint, character)) then
                    return candidatePoint, flight
                end
            end
        end

        return nil, nil
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
                        local aimPoint: Vector3?, flight: number? =
                            resolveKnifeAim(player, originPos, knife, true)
                        if aimPoint then
                            -- v159: score by the blade's FLIGHT TIME, not raw
                            -- distance. The nearest body is not the soonest hit:
                            -- a target running towards the throw intercepts in
                            -- a fraction of the time a farther one standing
                            -- still does, and the sooner the blade lands, the
                            -- smaller every prediction error is.
                            local score: number = flight or (distance / 96)
                            if type(getPlayerRole) == "function" then
                                local role: string? = getPlayerRole(player)
                                if role == "Sheriff" or role == "Hero" then
                                    score -= 0.08
                                end
                            end
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

    -- The solve is throttled, but its result used to jump at each update. This is
    -- visual-only: the native redirects and throwKnife always solve separately
    -- and never read this smoothed point.
    local TRACER_SMOOTH_RATE: number = 26
    local TRACER_SNAP_DISTANCE: number = 20
    local tracerPoint: Vector3? = nil
    local tracerTarget: Player? = nil
    local tracerShown: boolean = false
    local tracerOpacity: number = 0
    local drawnOpacity: number = -1
    local drawnOrigin: Vector3? = nil
    local drawnPoint: Vector3? = nil

    local function hideTracerParts(): ()
        if tracerPart and tracerPart.Parent then tracerPart.Transparency = 1 end
        if targetDotPart and targetDotPart.Parent then targetDotPart.Transparency = 1 end
    end

    local function hideTracerVisuals(): ()
        -- Do not tween a stale point after the next visibility check fails.
        -- Reuse the two invisible parts if a target reappears; destroy them
        -- when the option/module is turned off.
        if tracerShown then pcall(hideTracerParts) end
        tracerShown = false
        tracerOpacity = 0
        drawnOpacity = -1
        tracerPoint = nil
        tracerTarget = nil
        drawnOrigin = nil
        drawnPoint = nil
    end

    local function drawTracerParts(
        originPos: Vector3, point: Vector3, delta: Vector3, dist: number,
        updateGeometry: boolean, opacity: number, updateOpacity: boolean
    ): ()
        if not tracerPart or not tracerPart.Parent then
            local beamPart: Part = Instance.new("Part")
            beamPart.Name = "WurstKnifeTracer"
            beamPart.Anchored = true
            beamPart.CanCollide = false
            beamPart.CanQuery = false
            beamPart.CanTouch = false
            beamPart.Material = Enum.Material.Neon
            beamPart.Color = Color3.fromRGB(255, 65, 65)
            beamPart.Transparency = 1
            beamPart.Parent = workspace
            tracerPart = beamPart
            tracerShown = false
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
            dot.Transparency = 1
            dot.Parent = workspace
            targetDotPart = dot
            tracerShown = false
        end
        if updateGeometry then
            tracerPart.Size = Vector3.new(0.14, 0.14, dist)
            tracerPart.CFrame = CFrame.lookAt(originPos + delta * 0.5, point)
            targetDotPart.CFrame = CFrame.new(point)
        end
        if updateOpacity or not tracerShown then
            tracerPart.Transparency = 1 - 0.75 * opacity
            targetDotPart.Transparency = 1 - 0.85 * opacity
            tracerShown = true
        end
    end

    local function updateTracerVisual(
        originPos: Vector3?, aimPos: Vector3?, target: Player?, deltaTime: number?
    ): ()
        if not settings.enabled or not settings.knifeTracer then
            hideTracerVisuals()
            destroyTracerVisuals()
            return
        end
        if not originPos or not aimPos or not target then
            hideTracerVisuals()
            return
        end
        local dt: number = tonumber(deltaTime) or (1 / 60)
        if dt ~= dt then dt = 1 / 60 end
        local alpha: number = 1 - math.exp(-TRACER_SMOOTH_RATE * math.clamp(dt, 0, 0.25))
        local previous: Vector3? = tracerPoint
        if not previous or tracerTarget ~= target
            or (aimPos - previous).Magnitude > TRACER_SNAP_DISTANCE then
            -- Never sweep a line across different players or a teleport. A
            -- short fade-in still softens the appearance of the new point.
            tracerPoint = aimPos
            tracerOpacity = 0
        else
            local nextPoint: Vector3 = previous + (aimPos - previous) * alpha
            tracerPoint = (aimPos - nextPoint).Magnitude < 0.002 and aimPos or nextPoint
        end
        tracerOpacity += (1 - tracerOpacity) * alpha
        if tracerOpacity > 0.998 then tracerOpacity = 1 end
        tracerTarget = target
        local point: Vector3 = tracerPoint :: Vector3
        local delta: Vector3 = point - originPos
        local dist: number = delta.Magnitude
        if dist < 0.25 or dist > 400 then
            hideTracerVisuals()
            return
        end
        local missing: boolean = not tracerPart or not tracerPart.Parent
            or not targetDotPart or not targetDotPart.Parent
        local geometryChanged: boolean = missing or not drawnOrigin or not drawnPoint
            or (originPos - (drawnOrigin :: Vector3)).Magnitude >= 0.002
            or (point - (drawnPoint :: Vector3)).Magnitude >= 0.002
        local opacityChanged: boolean = missing or not tracerShown
            or math.abs(tracerOpacity - drawnOpacity) >= 0.002
        if not geometryChanged and not opacityChanged then return end
        -- Named callback: unlike the old per-frame pcall(closure), this does
        -- not allocate a fresh closure every frame. No raycasts/tweens here.
        local ok: boolean = pcall(
            drawTracerParts, originPos, point, delta, dist,
            geometryChanged, tracerOpacity, opacityChanged
        )
        if ok then
            if geometryChanged then
                drawnOrigin = originPos
                drawnPoint = point
            end
            if opacityChanged then drawnOpacity = tracerOpacity end
        else
            pcall(hideTracerParts)
            tracerShown = false
            drawnOpacity = -1
            drawnOrigin = nil
            drawnPoint = nil
        end
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
        -- v159: no lane fallback at all. Without a visible target there is
        -- nothing to throw at: a blade is not a homing projectile, and a throw
        -- into an opening only spent the knife.
        if not target or not isValidTarget(target) then
            return false
        end
        local aimPos: Vector3? = resolveKnifeAim(target, originCF.Position, knife)
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
                            if originCF and target then
                                local aim: Vector3? = resolveKnifeAim(target, originCF.Position, knife)
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
                            if originCF and target then
                                local aim: Vector3? = resolveKnifeAim(target, originCF.Position, knife)
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
    -- 1/15 s when an automatic throw is due; a visual-only preview can use
    -- 1/10 s because the displayed point follows the observed root between
    -- solves. The actual throw always re-solves from the live handle.
    local AIM_CACHE_SECONDS: number = 1 / 15
    local TRACER_CACHE_SECONDS: number = 1 / 10
    local cachedTarget: Player? = nil
    local cachedAim: Vector3? = nil
    local cachedOrigin: CFrame? = nil
    local cachedVisualRoot: BasePart? = nil
    local cachedVisualPosition: Vector3? = nil
    local cachedAt: number = -math.huge

    local function solveAim(knife: Tool, throwDue: boolean): (Player?, Vector3?, CFrame?)
        local now: number = os.clock()
        local interval: number = throwDue and AIM_CACHE_SECONDS or TRACER_CACHE_SECONDS
        if now - cachedAt >= interval then
            cachedAt = now
            cachedTarget = findTarget()
            cachedAim = nil
            cachedVisualRoot = nil
            cachedVisualPosition = nil
            cachedOrigin = getThrowOriginCFrame(knife)
            if cachedOrigin and cachedTarget then
                cachedAim = resolveKnifeAim(cachedTarget, cachedOrigin.Position, knife)
                if cachedAim and settings.knifeTracer then
                    local character: Model? = cachedTarget.Character
                    local root: BasePart? = character
                        and character:FindFirstChild("HumanoidRootPart") :: BasePart?
                    if root then
                        cachedVisualRoot = root
                        cachedVisualPosition = root.Position
                    end
                end
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
        cachedVisualRoot = nil
        cachedVisualPosition = nil
    end

    -- getPlayerWeapon walks the character/backpack's children. A tracer-only
    -- heartbeat must not do that 60-240 times a second just to keep the line
    -- attached to an already equipped handle. Actual throws and native input
    -- still use a fresh getKnife(), and parent changes invalidate this cache.
    local loopKnife: Tool? = nil
    local loopKnifeParent: Instance? = nil
    local loopKnifeCharacter: Model? = nil
    local loopKnifeAt: number = -math.huge
    local function resetLoopKnife(): ()
        loopKnife = nil
        loopKnifeParent = nil
        loopKnifeCharacter = nil
        loopKnifeAt = -math.huge
        originHandleTool = nil
        originHandle = nil
    end
    local function getLoopKnife(now: number, throwDue: boolean): Tool?
        local character: Model? = LocalPlayer and LocalPlayer.Character
        if character ~= loopKnifeCharacter then resetLoopKnife() end
        loopKnifeCharacter = character
        if not throwDue then
            if loopKnife and loopKnife.Parent == character and character then
                return loopKnife
            end
            local age: number = now - loopKnifeAt
            if age >= 0 and age < TRACER_CACHE_SECONDS then
                if not loopKnife then return nil end
                if loopKnifeParent and loopKnife.Parent == loopKnifeParent then
                    return loopKnife
                end
            end
        end
        loopKnife = getKnife()
        loopKnifeParent = loopKnife and loopKnife.Parent or nil
        loopKnifeAt = now
        return loopKnife
    end

    local function tracerGoal(target: Player?, aimPos: Vector3?): Vector3?
        if not target or not aimPos then return nil end
        local root: BasePart? = cachedVisualRoot
        local captured: Vector3? = cachedVisualPosition
        if not root or not captured then return aimPos end
        if target ~= cachedTarget or root.Parent ~= target.Character then
            invalidateAim()
            return nil
        end
        -- Follow the already-observed root between the throttled solves. This is
        -- only a visual offset, not another prediction or a per-frame raycast.
        local moved: Vector3 = root.Position - captured
        if moved.Magnitude > 8 then
            invalidateAim()
            return nil
        end
        return aimPos + moved
    end

    -- Main loop for Knife Tracer and Auto Knife Throw
    local function knifeThrowLoop(deltaTime: number?): ()
        if not settings.enabled then
            setKnifeStatus(nil)
            hideTracerVisuals()
            destroyTracerVisuals()
            invalidateAim()
            return
        end

        local now: number = os.clock()
        local cooldown: number = math.clamp(tonumber(settings.delay) or 0, 0, 10)
        local wantThrow: boolean = settings.autoThrow
            and now - lastThrowAttempt >= cooldown

        -- Manual redirects solve on the native input path. Do not enumerate
        -- players, predict and raycast merely to update a status when both
        -- Auto Knife Throw and the tracer are off. Likewise, without a tracer
        -- no preview is needed during a successful throw's cooldown.
        if not settings.knifeTracer and not wantThrow then
            hideTracerVisuals()
            destroyTracerVisuals()
            if not settings.autoThrow then
                setKnifeStatus(nil)
                invalidateAim()
            end
            return
        end

        local knife: Tool? = getLoopKnife(now, wantThrow)
        if not knife then
            setKnifeStatus("Waiting for knife")
            hideTracerVisuals()
            invalidateAim()
            return
        end

        -- The cached pick only decides WHO gets the blade. throwKnife
        -- re-solves the aim from the live handle when it actually fires.
        local target, aimPos, originCF = solveAim(knife, wantThrow)
        if not aimPos then
            setKnifeStatus(target and "Target blocked · WallCheck" or "No visible target")
            hideTracerVisuals()
            return
        end
        setKnifeStatus("Predicted target")

        if settings.knifeTracer and originCF then
            updateTracerVisual(originCF.Position, tracerGoal(target, aimPos), target, deltaTime)
        else
            hideTracerVisuals()
            destroyTracerVisuals()
        end

        if wantThrow then
            if throwKnife(target, knife) then
                setKnifeStatus("Throw sent · hit unconfirmed")
                lastThrowAttempt = now
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
            hideTracerVisuals()
            destroyTracerVisuals()
            invalidateAim()
            resetLoopKnife()
            return
        end

        installWeaponServiceRedirect()
        featureConnections.MM2KnifeThrow =
            TaskManager:Connect(knifeThrowLoop, nil, "MM2 Knife Throw")
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
        "Checks the blade's path from the hand to the target, including a thin corridor and invisible solid barriers. With nobody visible, nothing is thrown."
    )

    addToggleOption(
        KnifeThrowFeature,
        "Auto Knife Throw",
        false,
        function(value: boolean): ()
            settings.autoThrow = value == true
        end,
        "Throws at the predicted intercept of a visible target. With nobody visible, or with the path blocked, no knife is spent. A sent throw is not a confirmed hit."
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
                hideTracerVisuals()
                destroyTracerVisuals()
            end
        end,
        "Smooth 3D preview from your hand to the predicted point. The actual throw is re-solved separately; the preview hides when no target passes WallCheck."
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
