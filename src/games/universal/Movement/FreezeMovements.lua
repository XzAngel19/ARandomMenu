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
    local addToggleOption: any = host.addToggleOption
    local freezeSettings = {mode = "Anchor", emotes = true, animation = false}
    -- An old saved emote mode must not silently become Anchor on upgrade.
    local config: any = host.configData
    if config and config.values and config.states then
        local key: string = "Movement.FreezeMovements.Freezemode"
        local legacy: any = config.values[key]
        if legacy == "Freeze Emotes" or legacy == "Glitch Animations" then
            config.values[key] = "Motion"
            local prefix: string = "Movement.FreezeMovements."
            if config.states[prefix .. "FreezeEmotes"] == nil then
                config.states[prefix .. "FreezeEmotes"] = legacy == "Freeze Emotes"
            end
            if config.states[prefix .. "FreezeAnimation"] == nil then
                config.states[prefix .. "FreezeAnimation"] = legacy == "Glitch Animations"
            end
        end
    end
    local FreezeFeature: any = nil
    local originalFreezeState = setmetatable({}, {__mode = "k"})
    -- Motion never changes movement physics. Managed tracks are local;
    -- cross-client visibility depends on the game's animation replication.
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

    local motionSource: any = nil
    local motionTrack: any = nil
    local motionHumanoid: any = nil
    local function clearMotionTrack(): ()
        if motionTrack then
            pcall(function(): () motionTrack:Stop(0.1) end)
            pcall(function(): () motionTrack:Destroy() end)
        end
        motionSource, motionTrack, motionHumanoid = nil, nil, nil
    end

    local LOCOMOTION = {walk=true, run=true, idle=true, jump=true, fall=true,
        climb=true, swim=true, swimidle=true}
    local function isLocomotion(track: any): boolean
        if not track or ownedEmotes[track] or isEmoteTrack(track) then return false end
        if track.Priority == Enum.AnimationPriority.Movement then return true end
        if track.Priority ~= Enum.AnimationPriority.Core and track.Priority ~= Enum.AnimationPriority.Idle then return false end
        local function known(name: any): boolean
            local key: string = string.lower(tostring(name or "")):gsub("anim$", "")
            return LOCOMOTION[key] == true
        end
        if known(track.Name) then return true end
        local node: any = track.Animation
        for _index: number = 1, 5 do
            if not node then break end
            if known(node.Name) then return true end
            node = node.Parent
        end
        return false
    end

    local function freezeAnimationTick(humanoid: any): ()
        if motionHumanoid ~= humanoid then
            clearMotionTrack()
            motionHumanoid = humanoid
        end
        local animator: any = getAnimator(humanoid)
        if not animator then return end
        if not motionSource then
            local ok: boolean, tracks: any = pcall(function(): any return animator:GetPlayingAnimationTracks() end)
            if not ok or type(tracks) ~= "table" then return end
            local weight: number = -1
            for _, track: any in ipairs(tracks) do
                if track.IsPlaying and isLocomotion(track) then
                    local current: number = tonumber(track.WeightCurrent) or 1
                    if current > weight then motionSource, weight = track, current end
                end
            end
        end
        if not motionSource then return end
        -- Lock the selected clip, NOT its TimePosition. Walking continues
        -- looping even while the native controller switches to jump/fall.
        pcall(function(): ()
            if not motionTrack then
                motionTrack = animator:LoadAnimation(motionSource.Animation)
                motionTrack.Looped = true
                motionTrack.Priority = Enum.AnimationPriority.Action
                motionTrack:Play(0.1)
                motionTrack.TimePosition = motionSource.TimePosition
                motionTrack:AdjustSpeed(motionSource.Speed or 1)
            end
            -- Explicit emotes take precedence when both Motion boxes are on.
            local emotePlaying: boolean = false
            if freezeSettings.emotes then
                for _, source: any in ipairs(stickyEmoteTracks) do
                    if source.IsPlaying or (managedEmotes[source] and managedEmotes[source].IsPlaying) then
                        emotePlaying = true
                        break
                    end
                end
            end
            if emotePlaying then
                if motionTrack.IsPlaying then motionTrack:Stop(0.1) end
            elseif not motionTrack.IsPlaying then
                motionTrack:Play(0.1)
            end
        end)
    end

    local function restoreFreezeMovements(): ()
        for root: any, original: any in pairs(originalFreezeState) do
            pcall(function(): () root.Anchored = original.anchored end)
        end
        originalFreezeState = setmetatable({}, {__mode = "k"})
    end

    local function toggleFreezeMovements(enabled: boolean): ()
        disconnectFeatureConnection("FreezeMovements")
        restoreFreezeMovements()
        clearMotionTrack()
        clearStickyEmoteTracks()
        if not enabled then
            if FreezeFeature then FreezeFeature:SetStatus(nil) end
            return
        end
        FreezeFeature:SetStatus(freezeSettings.mode)
        local previousRoot: any = nil
        featureConnections.FreezeMovements = TaskManager:Connect(function(): ()
            local _, humanoid, root = getCharacterParts()
            if root ~= previousRoot then
                restoreFreezeMovements()
                clearMotionTrack()
                clearStickyEmoteTracks()
                previousRoot = root
            end
            if not humanoid then
                clearMotionTrack()
                clearStickyEmoteTracks()
                return
            end
            local ok: boolean, state: any = pcall(function(): any return humanoid:GetState() end)
            if ok and state == Enum.HumanoidStateType.Dead then
                restoreFreezeMovements()
                clearMotionTrack()
                clearStickyEmoteTracks()
                return
            end
            if freezeSettings.mode == "Motion" then
                if freezeSettings.emotes then freezeEmotesTick(humanoid, root) end
                if freezeSettings.animation then freezeAnimationTick(humanoid) end
            elseif root then
                if not originalFreezeState[root] then originalFreezeState[root] = {anchored = root.Anchored} end
                root.Anchored = true
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end
        end)
    end

    FreezeFeature = createUniversalFeature(
        "Freeze Movements", "Anchor physics or keep selected animations while moving", 4,
        toggleFreezeMovements,
        {categoryName = "Utilities", configKey = "Movement.FreezeMovements"}
    )
    local motionRows: {any} = {}
    local function refreshMotionOptions(): ()
        for _, row: any in ipairs(motionRows) do
            if host.setOptionVisible then
                host.setOptionVisible(FreezeFeature, row, freezeSettings.mode == "Motion")
            else row.Visible = freezeSettings.mode == "Motion" end
        end
    end
    addCycleOption(FreezeFeature, "Freeze mode", {"Anchor", "Motion"}, 1, function(value: string): ()
        freezeSettings.mode = value
        refreshMotionOptions()
        if FreezeFeature and FreezeFeature.enabled then toggleFreezeMovements(true) end
    end)
    local heading: any = host.addSectionOption and host.addSectionOption(FreezeFeature, "Motion settings")
    if heading then
        if host.makeTextLabel then
            heading.Size = UDim2.new(1, 0, 0, 20)
            local title: any = host.makeTextLabel(heading, "Motion settings", 10)
            title.Size = UDim2.fromScale(1, 1)
            title.TextXAlignment = Enum.TextXAlignment.Left
        end
        table.insert(motionRows, heading)
    end
    local emotes: any = addToggleOption(FreezeFeature, "Freeze Emotes", true, function(value: boolean): ()
        freezeSettings.emotes = value
        if not value then clearStickyEmoteTracks() end
    end, "Keep classic and UGC emotes playing while moving. Takes precedence over the locked locomotion clip.")
    if emotes then table.insert(motionRows, emotes.Parent) end
    local animation: any = addToggleOption(FreezeFeature, "Freeze Animation", false, function(value: boolean): ()
        freezeSettings.animation = value
        clearMotionTrack()
    end, "Keep the current locomotion clip looping through jumps and other movement. Does not freeze a single frame.")
    if animation then table.insert(motionRows, animation.Parent) end
    refreshMotionOptions()
    activeCleanup = function(): () toggleFreezeMovements(false) end
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
