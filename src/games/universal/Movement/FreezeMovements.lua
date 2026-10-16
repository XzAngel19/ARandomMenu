export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "FreezeMovements",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local TaskManager: any = host.TaskManager
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local getCharacterParts: any = host.getCharacterParts
    local createUniversalFeature: any = host.createUniversalFeature
    local addCycleOption: any = host.addCycleOption
    local addInformationOption: any = host.addInformationOption
    local freezeSettings = {mode = "Anchor"}
    local FreezeFeature: any = nil
    local originalFreezeState = setmetatable({}, {__mode = "k"})
    -- Animation modes (Freeze Emotes / Glitch Animations) never touch
    -- WalkSpeed or the root; they only drive the local Animator, which
    -- replicates to everyone else automatically because we own the rig.
    local stickyEmoteTracks: {any} = {}
    local emoteLastSeen: {[any]: number} = setmetatable({}, {__mode = "k"})

    local function getAnimator(humanoid: any): any
        local animator: any = humanoid and humanoid:FindFirstChildOfClass("Animator")
        if not animator and humanoid and humanoid.Parent then
            local character: any = humanoid.Parent
            animator = character and character:FindFirstChildOfClass("Animator", true)
        end
        return animator
    end

    local emoteConnection: any = nil
    local catalogEmoteConnection: any = nil
    local emoteGeneration: number = 0
    local watchedHumanoid: any = nil
    local emoteNames: {[string]: boolean} = {}
    local emoteIds: {[string]: boolean} = {}
    local managedEmotes: {[any]: any} = {}
    local ownedEmotes: {[any]: boolean} = setmetatable({}, {__mode = "k"})
    local isEmoteTrack: (any) -> boolean
    local lastGlitch: number = -math.huge

    local function clearStickyEmoteTracks(): ()
        emoteGeneration += 1
        if emoteConnection then emoteConnection:Disconnect() end
        if catalogEmoteConnection then catalogEmoteConnection:Disconnect() end
        emoteConnection = nil
        catalogEmoteConnection = nil
        local previousHumanoid: any = watchedHumanoid
        watchedHumanoid = nil
        local stopped: {[any]: boolean} = {}
        local function stopOnce(track: any): ()
            if track and not stopped[track] then
                stopped[track] = true
                pcall(function(): () track:Stop(0.1) end)
            end
        end
        -- The original Animate track can still be playing even if we never
        -- had to hand it off. OFF must release that source as well as ours.
        for _, source: any in ipairs(stickyEmoteTracks) do stopOnce(source) end
        local animator: any = getAnimator(previousHumanoid)
        if animator then
            pcall(function(): ()
                for _, track: any in ipairs(animator:GetPlayingAnimationTracks()) do
                    if track.IsPlaying and not ownedEmotes[track] and isEmoteTrack(track) then stopOnce(track) end
                end
            end)
        end
        for _, track: any in pairs(managedEmotes) do
            stopOnce(track)
            pcall(function(): () track:Destroy() end)
        end
        managedEmotes = {}
        ownedEmotes = setmetatable({}, {__mode = "k"})
        emoteNames = {}
        emoteIds = {}
        stickyEmoteTracks = {}
        emoteLastSeen = setmetatable({}, {__mode = "k"})
    end

    local CLASSIC_EMOTES = {
        dance = true, dance1 = true, dance2 = true, dance3 = true,
        wave = true, point = true, cheer = true, laugh = true,
    }

    isEmoteTrack = function(track: any): boolean
        -- Action priority is also used by weapon attacks; it is NOT an
        -- emote identifier. Avoid substring matches such as SpinAttack.
        local function knownName(name: string): boolean
            local lower: string = string.lower(name)
            if emoteNames[lower] then return true end
            lower = lower:gsub("anim$", "")
            return CLASSIC_EMOTES[lower] == true
        end
        if knownName(tostring(track.Name or "")) then return true end
        local animation: any = track.Animation
        if typeof(animation) == "Instance" then
            if knownName(animation.Name) then return true end
            local node: any = animation.Parent
            for _depth: number = 1, 6 do
                if not node then break end
                if knownName(node.Name) then return true end
                node = node.Parent
            end
            local id: string? = string.match(animation.AnimationId, "%d+")
            if id and emoteIds[id] then return true end
        end
        return false
    end

    local function rememberEmote(track: any): ()
        -- A newly selected emote replaces the previous held emote. Never
        -- layer a whole history of dances on the same joints.
        for source: any, managed: any in pairs(managedEmotes) do
            pcall(function(): () managed:Stop(0.1) end)
            pcall(function(): () managed:Destroy() end)
            ownedEmotes[managed] = nil
            managedEmotes[source] = nil
        end
        stickyEmoteTracks = {track}
        emoteLastSeen = setmetatable({}, {__mode = "k"})
        emoteLastSeen[track] = os.clock()
    end

    local function freezeEmotesTick(humanoid: any, root: any): ()
        -- Hold the selected emote while walking with a track Animate does
        -- not own. Keep it through jumps; release on death, replacement,
        -- mode change or disable.
        local okState: boolean, state: any = pcall(function(): any return humanoid:GetState() end)
        if okState and state == Enum.HumanoidStateType.Dead then
            clearStickyEmoteTracks()
            return
        end
        local animator: any = getAnimator(humanoid)
        if not animator then
            return
        end
        if watchedHumanoid ~= humanoid then
            clearStickyEmoteTracks()
            watchedHumanoid = humanoid
            -- Catalog asset IDs are NOT necessarily the AnimationId played
            -- by Animate. Prefer the actual track reported by the engine.
            -- This event requires executor permissions on some client builds;
            -- a denied connection must not prevent the metadata fallback.
            pcall(function(): ()
                catalogEmoteConnection = humanoid.EmoteTriggered:Connect(function(success: boolean, track: any): ()
                    if success and track and watchedHumanoid == humanoid and not ownedEmotes[track] then
                        local animation: any = track.Animation
                        if animation then
                            local id: string? = string.match(animation.AnimationId, "%d+")
                            if id then emoteIds[id] = true end
                        end
                        rememberEmote(track)
                    end
                end)
            end)
            local catalogAssets: {number} = {}
            pcall(function(): ()
                local description: any = humanoid:GetAppliedDescription()
                local ok: boolean, emotes: any = pcall(description.GetEmotes, description)
                description:Destroy()
                if not ok then return end
                local seen: {[number]: boolean} = {}
                for name: string, ids: any in pairs(emotes) do
                    emoteNames[string.lower(name)] = true
                    for _, id: any in ipairs(ids) do
                        emoteIds[tostring(id)] = true
                        local numberId: number? = tonumber(id)
                        if numberId and not seen[numberId] and #catalogAssets < 48 then
                            seen[numberId] = true
                            table.insert(catalogAssets, numberId)
                        end
                    end
                end
            end)
            -- Resolve catalog containers without playing an emote to discover
            -- its ID. Never run downloaded scripts; only inspect Animation data.
            local generation: number = emoteGeneration
            if #catalogAssets > 0 and task and game then
                task.spawn(function(): ()
                    for _, assetId: number in ipairs(catalogAssets) do
                        if generation ~= emoteGeneration then return end
                        local ok: boolean, objects: any = pcall(function(): any
                            return game:GetObjects("rbxassetid://" .. tostring(assetId))
                        end)
                        if ok and type(objects) == "table" then
                            for _, object: any in ipairs(objects) do
                                pcall(function(): ()
                                    local nodes: {any} = object:GetDescendants()
                                    table.insert(nodes, object)
                                    for _, node: any in ipairs(nodes) do
                                        if generation == emoteGeneration and node:IsA("Animation") then
                                            local id: string? = string.match(node.AnimationId, "%d+")
                                            if id then emoteIds[id] = true end
                                        end
                                    end
                                end)
                                pcall(function(): () object:Destroy() end)
                            end
                        end
                    end
                end)
            end
            -- R6 /e dance2 commonly plays Animation1/2/3, not a track
            -- named dance2. Read IDs under Animate's named emote folders.
            pcall(function(): ()
                local animate: any = humanoid.Parent:FindFirstChild("Animate")
                if animate then
                    for _, animation: any in ipairs(animate:GetDescendants()) do
                        if animation:IsA("Animation") then
                            local node: any = animation
                            while node and node ~= animate do
                                local name: string = string.lower(node.Name):gsub("anim$", "")
                                if CLASSIC_EMOTES[name] or emoteNames[name] then
                                    local id: string? = string.match(animation.AnimationId, "%d+")
                                    if id then emoteIds[id] = true end
                                    break
                                end
                                node = node.Parent
                            end
                        end
                    end
                end
            end)
            -- Catch tracks at start, before Animate can cancel them on movement.
            emoteConnection = animator.AnimationPlayed:Connect(function(track: any): ()
                if not ownedEmotes[track] and isEmoteTrack(track) and not emoteLastSeen[track] then
                    rememberEmote(track)
                end
            end)
        end
        local okTracks: boolean, tracks: any = pcall(function(): any
            return animator:GetPlayingAnimationTracks()
        end)
        if not okTracks or type(tracks) ~= "table" then
            return
        end
        local playing: {[any]: boolean} = {}
        for _, track: any in ipairs(tracks) do
            if track and track.IsPlaying then
                playing[track] = true
                if not ownedEmotes[track] and not emoteLastSeen[track] and isEmoteTrack(track) then
                    rememberEmote(track)
                end
                if emoteLastSeen[track] then
                    emoteLastSeen[track] = os.clock()
                end
            end
        end
        local moving: boolean = root ~= nil
            and root.AssemblyLinearVelocity.Magnitude > 1
        local now: number = os.clock()
        for index: number = #stickyEmoteTracks, 1, -1 do
            local track: any = stickyEmoteTracks[index]
            if not track then
                table.remove(stickyEmoteTracks, index)
            elseif playing[track] or (managedEmotes[track] and managedEmotes[track].IsPlaying) then
                emoteLastSeen[track] = now
            else
                local lastSeen: number = emoteLastSeen[track]
                if lastSeen == nil then
                    lastSeen = now
                    emoteLastSeen[track] = now
                end
                -- Only hand off after a recent, recognized source was
                -- cancelled while moving; do not guess from Action priority.
                if moving and now - lastSeen < 1.5 then
                    pcall(function(): ()
                        -- A separate track is essential: Animate owns the
                        -- original and will keep cancelling it when walking.
                        local managed: any = managedEmotes[track]
                        if not managed then
                            managed = animator:LoadAnimation(track.Animation)
                            ownedEmotes[managed] = true
                            managedEmotes[track] = managed
                            managed.Looped = true
                            managed.Priority = Enum.AnimationPriority.Action
                        end
                        if not managed.IsPlaying then managed:Play(0.1) end
                    end)
                elseif now - lastSeen > 0.5 then
                    local managed: any = managedEmotes[track]
                    if managed then
                        pcall(function(): () managed:Stop(0.1) end)
                        pcall(function(): () managed:Destroy() end)
                        managedEmotes[track] = nil
                        ownedEmotes[managed] = nil
                    end
                    table.remove(stickyEmoteTracks, index)
                    emoteLastSeen[track] = nil
                end
            end
        end
    end

    local function glitchAnimationsTick(humanoid: any): ()
        -- Seek locomotion at a fixed cadence instead of calling Play every
        -- frame (which continually resets fades and also interrupts tools).
        local now: number = os.clock()
        if now - lastGlitch < 0.12 then return end
        lastGlitch = now
        local animator: any = getAnimator(humanoid)
        if not animator then
            return
        end
        local okTracks: boolean, tracks: any = pcall(function(): any
            return animator:GetPlayingAnimationTracks()
        end)
        if not okTracks or type(tracks) ~= "table" then
            return
        end
        for _, track: any in ipairs(tracks) do
            if track and track.IsPlaying
                and (track.Priority == Enum.AnimationPriority.Movement
                    or track.Priority == Enum.AnimationPriority.Core) then
                pcall(function(): ()
                    track.TimePosition = 0
                end)
            end
        end
    end

    local function restoreFreezeMovements()
        for humanoid, original in pairs(originalFreezeState) do
            if humanoid and humanoid.Parent then
                humanoid.WalkSpeed = original.walkSpeed
                humanoid.JumpPower = original.jumpPower
                humanoid.JumpHeight = original.jumpHeight
                humanoid.AutoRotate = original.autoRotate
                if original.root and original.root.Parent then
                    original.root.Anchored = original.rootAnchored
                end
            end
        end
        originalFreezeState = setmetatable({}, {__mode = "k"})
    end

    local function toggleFreezeMovements(enabled)
        disconnectFeatureConnection("FreezeMovements")
        restoreFreezeMovements()
        clearStickyEmoteTracks()
        lastGlitch = -math.huge

        if not enabled then
            if FreezeFeature then
                FreezeFeature:SetStatus(nil)
            end
            return
        end

        clearStickyEmoteTracks()
        FreezeFeature:SetStatus(freezeSettings.mode)
        featureConnections.FreezeMovements = TaskManager:Connect(function()
            local _, humanoid, root = getCharacterParts()
            if not humanoid then
                return
            end

            if freezeSettings.mode == "Freeze Emotes" then
                freezeEmotesTick(humanoid, root)
                return
            elseif freezeSettings.mode == "Glitch Animations" then
                glitchAnimationsTick(humanoid)
                return
            end

            if not root then
                return
            end

            if not originalFreezeState[humanoid] then
                originalFreezeState[humanoid] = {
                    walkSpeed = humanoid.WalkSpeed,
                    jumpPower = humanoid.JumpPower,
                    jumpHeight = humanoid.JumpHeight,
                    autoRotate = humanoid.AutoRotate,
                    root = root,
                    rootAnchored = root.Anchored,
                }
            end

            local original = originalFreezeState[humanoid]
            humanoid.WalkSpeed = 0
            humanoid.JumpPower = 0
            humanoid.JumpHeight = 0
            humanoid.AutoRotate = false
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            root.Anchored = freezeSettings.mode == "Anchor"
                and true
                or original.rootAnchored
        end)
    end

    FreezeFeature = createUniversalFeature(
        "Freeze Movements",
        "Prevent the local character from moving",
        1,
        toggleFreezeMovements,
        {
            categoryName = "Movement",
            configKey = "Movement.FreezeMovements",
        }
    )
    addCycleOption(
        FreezeFeature,
        "Freeze mode",
        {"Anchor", "Humanoid", "Freeze Emotes", "Glitch Animations"},
        1,
        function(value)
            freezeSettings.mode = value
            if FreezeFeature and FreezeFeature.enabled then
                -- Switching modes re-applies the feature: the previous
                -- mode is fully undone first (Anchor had left the root
                -- anchored with WalkSpeed 0 - "no puedo caminar") and the
                -- new mode starts clean.
                toggleFreezeMovements(false)
                toggleFreezeMovements(true)
            end
        end
    )
    addInformationOption(
        FreezeFeature,
        "Anchor stops all physics; Humanoid only blocks character controls."
    )
    addInformationOption(
        FreezeFeature,
        "Freeze Emotes keeps emotes playing while you walk; Glitch Animations makes your character stutter."
    )

    activeCleanup = function(): ()
        disconnectFeatureConnection("FreezeMovements")
        restoreFreezeMovements()
        clearStickyEmoteTracks()
    end
    Module.Initialized = true
    return FreezeFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
