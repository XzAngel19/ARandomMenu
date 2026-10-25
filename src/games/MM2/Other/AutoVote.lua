local Module = {
    Name = "MM2 Auto Vote",
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
    assert(type(core) == "table", "MM2 Auto Vote requires the MM2 core module")
    Module.Runtime = runtime

    local TICK_INTERVAL: number = 0.10
    local MAP_REFRESH_INTERVAL: number = 0.50
    local VOTE_HOLD_BEFORE_RESET: number = 0.22
    local RESET_RETRY_INTERVAL: number = 0.25
    local MAX_LOBBY_PAD_DISTANCE: number = 250

    local DEFAULT_MAP_CHOICES: {string} = {
        "House 2",
        "Hospital 3",
        "Police Station",
    }
    local mapChoices: {string} = {
        DEFAULT_MAP_CHOICES[1],
        DEFAULT_MAP_CHOICES[2],
        DEFAULT_MAP_CHOICES[3],
    }
    local selectedSlot: number = 1
    local selectedMapName: string = mapChoices[1]
    local selectMapButton: TextButton? = nil
    local selectMapOptionKey: string = "MM2.AutoVote.SelectMap"
    local AutoVoteFeature: any = nil

    local cachedLobby: Instance? = nil
    local cachedPadModels: {[number]: Instance?} = {}
    local cachedVotePadsFolder: Instance? = nil
    local cachedVoteIconsFolder: Instance? = nil
    local lastLobbyCheckAt: number = -math.huge
    local lastMapRefreshAt: number = -math.huge
    local savedDetectorCFrames: {[BasePart]: CFrame} = {}
    local roundBlockingVote: boolean = false
    local lastBillboardVotingState: boolean = false

    local function trim(s: string): string
        return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
    end

    local function isPlaceholderMapLabel(title: string?): boolean
        if type(title) ~= "string" then
            return true
        end
        local clean: string = string.upper(trim(title))
        return clean == ""
            or clean == "MAP NAME"
            or clean == "LOADING"
            or clean == "NONE"
            or clean == "MAP 1"
            or clean == "MAP 2"
            or clean == "MAP 3"
    end

    local function isValidMapTitle(title: string?): boolean
        return not isPlaceholderMapLabel(title)
    end

    local function isLobbyContainer(candidate: Instance?): boolean
        if not candidate or not candidate.Parent then
            return false
        end
        return candidate:FindFirstChild("VotePad1") ~= nil
            or candidate:FindFirstChild("VotePads") ~= nil
            or candidate:FindFirstChild("VoteIcons") ~= nil
    end

    local function findLobbyModel(): Instance?
        local now: number = os.clock()
        if cachedLobby and cachedLobby:IsDescendantOf(workspace) and now - lastLobbyCheckAt < 1.0 then
            return cachedLobby
        end
        lastLobbyCheckAt = now

        -- 1. Fast check on direct workspace children
        for _, name: string in ipairs({"RegularLobby", "Lobby", "MainLobby", "HalloweenLobby"}) do
            local candidate: Instance? = workspace:FindFirstChild(name)
            if isLobbyContainer(candidate) then
                cachedLobby = candidate
                return candidate
            end
        end

        local okChildren: boolean, children: any = pcall(function(): any
            return workspace:GetChildren()
        end)
        if okChildren and type(children) == "table" then
            for _, child: Instance in ipairs(children) do
                if (child:IsA("Model") or child:IsA("Folder")) and isLobbyContainer(child) then
                    cachedLobby = child
                    return child
                end
            end
        end

        -- 2. Check CollectionService "VotePad" tag (used on VotePad1..3 in MM2)
        local okTagged: boolean, tagged: any = pcall(function(): any
            return game:GetService("CollectionService"):GetTagged("VotePad")
        end)
        if okTagged and type(tagged) == "table" then
            for _, inst: Instance in ipairs(tagged) do
                if inst and inst:IsDescendantOf(workspace) then
                    local slotNum: number? = tonumber(string.match(inst.Name, "^VotePad(%d)$"))
                    if slotNum then
                        cachedPadModels[slotNum] = inst
                    end
                    if inst.Parent and inst.Parent ~= workspace then
                        cachedLobby = inst.Parent
                    end
                end
            end
            if cachedLobby and cachedLobby:IsDescendantOf(workspace) then
                return cachedLobby
            end
        end

        -- 3. Recursive fallback for nested seasonal/event lobbies
        local okDeep: boolean, deepPad: any = pcall(function(): any
            return workspace:FindFirstChild("VotePads", true)
                or workspace:FindFirstChild("VotePad1", true)
                or workspace:FindFirstChild("VoteIcons", true)
        end)
        if okDeep and deepPad and (deepPad :: Instance):IsDescendantOf(workspace) then
            local parent: Instance? = (deepPad :: Instance).Parent
            if parent and parent.Name == "VoteIcons" and parent.Parent then
                parent = parent.Parent
            end
            cachedLobby = parent
            return cachedLobby
        end

        cachedLobby = nil
        return nil
    end

    local function getPadModel(lobby: Instance?, slot: number): Instance?
        local cached: Instance? = cachedPadModels[slot]
        if cached and cached:IsDescendantOf(workspace) and not (cached.Parent and cached.Parent.Name == "VoteIcons") then
            return cached
        end
        local padName: string = "VotePad" .. tostring(slot)
        if lobby then
            local direct: Instance? = lobby:FindFirstChild(padName)
            if direct and not (direct.Parent and direct.Parent.Name == "VoteIcons") then
                cachedPadModels[slot] = direct
                return direct
            end
            local okDeep: boolean, deep: any = pcall(function(): any
                return lobby:FindFirstChild(padName, true)
            end)
            if okDeep and deep and not ((deep :: Instance).Parent and (deep :: Instance).Parent.Name == "VoteIcons") then
                cachedPadModels[slot] = deep :: Instance
                return deep :: Instance
            end
        end
        return nil
    end

    local function getVoteIconsFolder(lobby: Instance?): Instance?
        if cachedVoteIconsFolder and cachedVoteIconsFolder:IsDescendantOf(workspace) then
            return cachedVoteIconsFolder
        end
        if lobby then
            local direct: Instance? = lobby:FindFirstChild("VoteIcons")
                or lobby:FindFirstChild("VoteIcons", true)
            if direct then
                cachedVoteIconsFolder = direct
                return direct
            end
        end
        return nil
    end

    local function getVotePadsFolder(lobby: Instance?): Instance?
        if cachedVotePadsFolder and cachedVotePadsFolder:IsDescendantOf(workspace) then
            return cachedVotePadsFolder
        end
        if lobby then
            local direct: Instance? = lobby:FindFirstChild("VotePads")
                or lobby:FindFirstChild("VotePads", true)
            if direct then
                cachedVotePadsFolder = direct
                return direct
            end
        end
        return nil
    end

    -- Read the map name displayed on billboard slot i (1..3) from the lobby.
    local function readSlotMapName(lobby: Instance?, slot: number): string?
        if not lobby then
            return nil
        end
        local padModel: Instance? = getPadModel(lobby, slot)
        if padModel then
            local voteInfoGui: Instance? = padModel:FindFirstChild("VoteInfoGui")
            local container: Instance? = voteInfoGui and voteInfoGui:FindFirstChild("Container")
            local mapLabel: Instance? = (container and container:FindFirstChild("MapName"))
                or padModel:FindFirstChild("MapName", true)
            if mapLabel and mapLabel:IsA("TextLabel") then
                local text: string = (mapLabel :: TextLabel).Text
                if isValidMapTitle(text) then
                    return trim(text)
                end
            end
        end

        local voteIcons: Instance? = getVoteIconsFolder(lobby)
        local iconPart: Instance? = voteIcons and voteIcons:FindFirstChild("VotePad" .. tostring(slot))
        if iconPart then
            local mapLabel: Instance? = iconPart:FindFirstChild("MapName", true)
            if mapLabel and mapLabel:IsA("TextLabel") then
                local text: string = (mapLabel :: TextLabel).Text
                if isValidMapTitle(text) then
                    return trim(text)
                end
            end
            local mapObj: Instance? = iconPart:FindFirstChild("Map")
            if mapObj and mapObj:IsA("ObjectValue") then
                local val: Instance? = (mapObj :: ObjectValue).Value
                if val and isValidMapTitle(val.Name) then
                    return trim(val.Name)
                end
            end
        end

        return nil
    end

    -- Read the current vote count on slot i (1..3).
    local function readSlotVoteCount(lobby: Instance?, slot: number): number?
        if not lobby then
            return nil
        end
        local voteIcons: Instance? = getVoteIconsFolder(lobby)
        local iconPart: Instance? = voteIcons and voteIcons:FindFirstChild("VotePad" .. tostring(slot))
        if iconPart then
            local votesVal: Instance? = iconPart:FindFirstChild("Votes")
            if votesVal and votesVal:IsA("IntValue") then
                return (votesVal :: IntValue).Value
            end
        end
        local padModel: Instance? = getPadModel(lobby, slot)
        if padModel then
            local voteInfoGui: Instance? = padModel:FindFirstChild("VoteInfoGui")
            local container: Instance? = voteInfoGui and voteInfoGui:FindFirstChild("Container")
            local votesLabel: Instance? = (container and container:FindFirstChild("Votes"))
                or padModel:FindFirstChild("Votes", true)
            if votesLabel and votesLabel:IsA("TextLabel") then
                local numStr: string? = string.match((votesLabel :: TextLabel).Text, "(%d+)")
                if numStr then
                    return tonumber(numStr)
                end
            end
        end
        return nil
    end

    local function syncSelectMapControl(): ()
        local control: any = state.valueControls
            and state.valueControls[selectMapOptionKey]
        if type(control) == "table" and type(control.setIndex) == "function" then
            pcall(control.setIndex, selectedSlot)
        elseif selectMapButton then
            pcall(function(): ()
                selectMapButton.Text = mapChoices[selectedSlot]
            end)
        end
    end

    -- Refresh the 3 map choices in-place from the lobby billboard so the
    -- "Select Map" dropdown always displays the 3 real maps on the board.
    local function refreshMapChoices(force: boolean?): ()
        local now: number = os.clock()
        if not force and now - lastMapRefreshAt < MAP_REFRESH_INTERVAL then
            return
        end
        lastMapRefreshAt = now

        local lobby: Instance? = findLobbyModel()
        local changed: boolean = false
        for slot: number = 1, 3 do
            local title: string? = readSlotMapName(lobby, slot)
            local current: string? = mapChoices[slot]
            local nextLabel: string = title
                or (isValidMapTitle(current) and (current :: string) or DEFAULT_MAP_CHOICES[slot])
            if mapChoices[slot] ~= nextLabel then
                mapChoices[slot] = nextLabel
                changed = true
            end
        end

        if isValidMapTitle(selectedMapName) then
            local matchedSlot: number? = nil
            local targetLower: string = string.lower(selectedMapName)
            for slot: number = 1, 3 do
                if string.lower(mapChoices[slot]) == targetLower then
                    matchedSlot = slot
                    break
                end
            end
            if matchedSlot and selectedSlot ~= matchedSlot then
                selectedSlot = matchedSlot
                changed = true
            end
        end

        selectedSlot = math.clamp(selectedSlot, 1, 3)
        selectedMapName = mapChoices[selectedSlot]

        if changed or force then
            syncSelectMapControl()
        end
    end

    -- Resolve the wooden pad detector parts for slot (1..3):
    -- VotePads.Detector{slot} and VotePad{slot}.Pad
    local function getSlotDetectorParts(lobby: Instance?, slot: number): {BasePart}
        local parts: {BasePart} = {}
        if not lobby then
            return parts
        end

        local padModel: Instance? = getPadModel(lobby, slot)
        if padModel then
            local padPart: Instance? = padModel:FindFirstChild("Pad")
                or padModel:FindFirstChild("Pad", true)
            if padPart and padPart:IsA("BasePart") then
                parts[#parts + 1] = padPart :: BasePart
            end
        end

        local votePads: Instance? = getVotePadsFolder(lobby)
        if votePads then
            local detector: Instance? = votePads:FindFirstChild("Detector" .. tostring(slot))
                or votePads:FindFirstChild("Detector" .. tostring(slot), true)
            if detector and detector:IsA("BasePart") then
                parts[#parts + 1] = detector :: BasePart
            end
        end

        return parts
    end

    local function rememberDetectorPart(part: BasePart): ()
        if savedDetectorCFrames[part] then
            return
        end
        local ok: boolean, cf: any = pcall(function(): any
            return part.CFrame
        end)
        if ok and cf then
            savedDetectorCFrames[part] = cf
        end
    end

    local function restoreAllDetectorParts(): ()
        for part, cf in pairs(savedDetectorCFrames) do
            if part and part.Parent then
                pcall(function(): ()
                    part.CFrame = cf
                end)
            end
        end
        table.clear(savedDetectorCFrames)
    end

    -- Check whether the lobby voting billboards are currently enabled.
    local function areVotingBillboardsActive(lobby: Instance?): boolean
        if not lobby then
            return false
        end

        for slot: number = 1, 3 do
            local padModel: Instance? = getPadModel(lobby, slot)
            if padModel then
                local voteGui: Instance? = padModel:FindFirstChild("VoteInfoGui")
                if voteGui and voteGui:IsA("SurfaceGui") and (voteGui :: SurfaceGui).Enabled == true then
                    return true
                end
                local mapGui: Instance? = padModel:FindFirstChild("MapInfoGui")
                if mapGui and mapGui:IsA("SurfaceGui") and (mapGui :: SurfaceGui).Enabled == true then
                    return true
                end
            end

            local voteIcons: Instance? = getVoteIconsFolder(lobby)
            local iconPart: Instance? = voteIcons and voteIcons:FindFirstChild("VotePad" .. tostring(slot))
            if iconPart then
                local votingFlag: Instance? = iconPart:FindFirstChild("Voting")
                if votingFlag and votingFlag:IsA("BoolValue") and (votingFlag :: BoolValue).Value == true then
                    return true
                end
                local surface: Instance? = iconPart:FindFirstChild("Surface")
                if surface and surface:IsA("SurfaceGui") and (surface :: SurfaceGui).Enabled == true then
                    return true
                end
                local mapInfo: Instance? = iconPart:FindFirstChild("MapInfo")
                local infoSurface: Instance? = mapInfo and mapInfo:FindFirstChild("Surface")
                if infoSurface and infoSurface:IsA("SurfaceGui") and (infoSurface :: SurfaceGui).Enabled == true then
                    return true
                end
            end
        end

        return false
    end

    -- Returns true ONLY while the lobby voting intermission is open and the
    -- player is in the lobby. Returns false the instant voting ends or a round starts.
    local function isVotingIntermissionActive(root: BasePart?, detector: BasePart?): boolean
        local lobby: Instance? = findLobbyModel()
        local billboardsOn: boolean = areVotingBillboardsActive(lobby)

        -- If the voting billboards just turned on for a new intermission, clear
        -- any previous round lock.
        if billboardsOn and not lastBillboardVotingState then
            roundBlockingVote = false
        end
        lastBillboardVotingState = billboardsOn

        if not billboardsOn then
            return false
        end
        if roundBlockingVote then
            return false
        end

        if type(core.isRoundLifecycleActive) == "function"
            and core.isRoundLifecycleActive() == true then
            return false
        end

        local timerPart: Instance? = workspace:FindFirstChild("RoundTimerPart")
        if timerPart then
            local okTime: boolean, roundTime: any = pcall(function(): any
                return timerPart:GetAttribute("Time")
            end)
            if okTime and type(roundTime) == "number" and roundTime > 0 then
                return false
            end
        end

        if root and detector then
            local okDist: boolean, dist: any = pcall(function(): any
                return (root.Position - detector.Position).Magnitude
            end)
            if okDist and type(dist) == "number" and dist > MAX_LOBBY_PAD_DISTANCE then
                return false
            end
        end

        return true
    end

    local function resolveTargetSlot(lobby: Instance?): number
        refreshMapChoices(false)
        if lobby and isValidMapTitle(selectedMapName) then
            local targetLower: string = string.lower(selectedMapName)
            for slot: number = 1, 3 do
                local nameOnBoard: string? = readSlotMapName(lobby, slot)
                if nameOnBoard and string.lower(nameOnBoard) == targetLower then
                    selectedSlot = slot
                    return slot
                end
            end
        end
        return math.clamp(selectedSlot, 1, 3)
    end

    -- Step onto the wooden vote pad and pulse touch on its detectors so the
    -- server registers the vote on VotePads.Detector{slot} and VotePad{slot}.Pad.
    local function pulseVotePad(root: BasePart, detectors: {BasePart}): ()
        local primaryPad: BasePart? = detectors[1]
        if primaryPad then
            local okPos: boolean, padPos: any = pcall(function(): any
                local saved: CFrame? = savedDetectorCFrames[primaryPad]
                return saved and saved.Position or primaryPad.Position
            end)
            if okPos and typeof(padPos) == "Vector3" then
                pcall(function(): ()
                    local currentCF: CFrame = root.CFrame
                    local rotOnly: CFrame = currentCF - currentCF.Position
                    root.CFrame = CFrame.new(padPos) * rotOnly
                    root.AssemblyLinearVelocity = Vector3.zero
                end)
            end
        end

        local fireTouch: any = state.fireTouchInterest
        local rootCF: CFrame? = root.CFrame
        for _, part: BasePart in ipairs(detectors) do
            rememberDetectorPart(part)
            pcall(function(): ()
                part.CanCollide = false
                if rootCF then
                    part.CFrame = rootCF
                end
            end)
            if type(fireTouch) == "function" then
                pcall(fireTouch, root, part, 0)
                pcall(fireTouch, root, part, 1)
            end
        end
    end

    local function resetLocalCharacter(character: Model, humanoid: Humanoid): ()
        pcall(function(): ()
            humanoid:ChangeState(Enum.HumanoidStateType.Dead)
        end)
        pcall(function(): ()
            humanoid.Health = 0
        end)
        pcall(function(): ()
            if humanoid.Health > 0 then
                character:BreakJoints()
            end
        end)
    end

    local lastStatus: string? = nil
    local function setStatus(text: string?): ()
        if text == lastStatus then
            return
        end
        lastStatus = text
        if AutoVoteFeature then
            AutoVoteFeature:SetStatus(text)
        end
    end

    local function connectGameplayRemotes(): ()
        local okRs: boolean, rs: any = pcall(function(): any
            return game:GetService("ReplicatedStorage")
        end)
        if not okRs or not rs then
            return
        end
        local remotes: Instance? = rs:FindFirstChild("Remotes")
        local gameplay: Instance? = remotes and remotes:FindFirstChild("Gameplay")
        if not gameplay then
            return
        end

        for _, stopName: string in ipairs({
            "LoadingMap",
            "Fade",
            "RoleSelect",
            "ShowRoleSelect",
            "ShowRoleSelectNew",
            "RoundStart",
            "CoinsStarted",
        }) do
            local rem: Instance? = gameplay:FindFirstChild(stopName)
            if rem and rem:IsA("RemoteEvent") then
                local key: string = "MM2AutoVoteStop_" .. stopName
                disconnectFeatureConnection(key)
                featureConnections[key] = (rem :: RemoteEvent).OnClientEvent:Connect(function(): ()
                    roundBlockingVote = true
                    restoreAllDetectorParts()
                end)
            end
        end

        for _, endName: string in ipairs({
            "RoundEndFade",
            "VictoryScreen",
            "GameOver",
        }) do
            local rem: Instance? = gameplay:FindFirstChild(endName)
            if rem and rem:IsA("RemoteEvent") then
                local key: string = "MM2AutoVoteEnd_" .. endName
                disconnectFeatureConnection(key)
                featureConnections[key] = (rem :: RemoteEvent).OnClientEvent:Connect(function(): ()
                    roundBlockingVote = false
                    refreshMapChoices(true)
                end)
            end
        end
    end

    local function disconnectAllAutoVoteConnections(): ()
        disconnectFeatureConnection("MM2AutoVote")
        for key in pairs(featureConnections) do
            if string.sub(key, 1, 11) == "MM2AutoVote" and key ~= "MM2AutoVoteMapSync" then
                disconnectFeatureConnection(key)
            end
        end
    end

    local function toggleAutoVote(enabled: boolean): ()
        disconnectAllAutoVoteConnections()
        restoreAllDetectorParts()

        if not enabled then
            setStatus(nil)
            return
        end

        refreshMapChoices(true)
        connectGameplayRemotes()

        local lastTickAt: number = -math.huge
        local currentChar: Model? = nil
        local firstTouchAt: number = 0
        local lastResetAttemptAt: number = 0
        local voteCountBeforeTouch: number? = nil

        local function autoVoteTick(): ()
            local now: number = os.clock()
            if now - lastTickAt < TICK_INTERVAL then
                return
            end
            lastTickAt = now

            refreshMapChoices(false)

            local lobby: Instance? = findLobbyModel()
            local slot: number = resolveTargetSlot(lobby)
            local targetMapLabel: string = mapChoices[slot] or DEFAULT_MAP_CHOICES[slot]
            local detectors: {BasePart} = getSlotDetectorParts(lobby, slot)
            local primaryDetector: BasePart? = detectors[1]

            local character: Model? = LocalPlayer and LocalPlayer.Character
            local root: BasePart? = character
                and (character:FindFirstChild("HumanoidRootPart") :: BasePart?)
            local humanoid: Humanoid? = character
                and (character:FindFirstChildOfClass("Humanoid") :: Humanoid?)

            -- Stop immediately if the voting intermission is not active or has ended!
            if not isVotingIntermissionActive(root, primaryDetector) then
                restoreAllDetectorParts()
                firstTouchAt = 0
                lastResetAttemptAt = 0
                setStatus("Waiting for vote · " .. tostring(targetMapLabel))
                return
            end

            if #detectors == 0 then
                setStatus("No vote pad")
                return
            end

            if not character or not root or not humanoid or humanoid.Health <= 0 then
                restoreAllDetectorParts()
                return
            end

            if character ~= currentChar then
                currentChar = character
                firstTouchAt = 0
                lastResetAttemptAt = 0
                voteCountBeforeTouch = readSlotVoteCount(lobby, slot)
            end

            -- Step onto the wooden vote pad and pulse touch on its detectors
            pulseVotePad(root, detectors)
            if firstTouchAt == 0 then
                firstTouchAt = now
            end

            local currentVotes: number? = readSlotVoteCount(lobby, slot)
            local voteIncremented: boolean = (
                currentVotes ~= nil
                and voteCountBeforeTouch ~= nil
                and currentVotes > voteCountBeforeTouch
            )

            setStatus(
                "Voting " .. targetMapLabel
                .. (currentVotes ~= nil and (" (" .. tostring(currentVotes) .. ")") or "")
            )

            -- Once this character life has cast its vote on the wooden pad,
            -- re-verify voting intermission is STILL active and reset the
            -- character to stack another vote.
            if (voteIncremented or (now - firstTouchAt >= VOTE_HOLD_BEFORE_RESET))
                and (now - lastResetAttemptAt >= RESET_RETRY_INTERVAL) then
                restoreAllDetectorParts()
                if isVotingIntermissionActive(root, primaryDetector) then
                    lastResetAttemptAt = now
                    resetLocalCharacter(character, humanoid)
                end
            end
        end

        featureConnections.MM2AutoVote = TaskManager:Connect(autoVoteTick)
        autoVoteTick()
    end

    -- Clear any legacy "Map 1..3" placeholder saved in config so real map names show.
    pcall(function(): ()
        if type(configData) == "table" and type(configData.values) == "table" then
            local saved: any = configData.values[selectMapOptionKey]
            if isPlaceholderMapLabel(saved) then
                configData.values[selectMapOptionKey] = nil
            end
        end
    end)

    -- Populate initial map names if already in the lobby
    pcall(refreshMapChoices, true)

    AutoVoteFeature = createUniversalFeature(
        "Auto Vote",
        "Detects the 3 maps on the lobby voting billboard, votes on the wooden floor pad for your selected map, and resets repeatedly to stack votes until voting intermission ends.",
        7,
        toggleAutoVote,
        {
            categoryName = "Utilities",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    state.mm2AutoVoteFeature = AutoVoteFeature

    selectMapButton = addCycleOption(
        AutoVoteFeature,
        "Select Map",
        mapChoices,
        1,
        function(value: string): ()
            refreshMapChoices(false)
            selectedMapName = tostring(value)
            for slot: number = 1, 3 do
                if mapChoices[slot] == selectedMapName then
                    selectedSlot = slot
                    break
                end
            end
            if AutoVoteFeature and AutoVoteFeature.enabled then
                setStatus("Voting " .. tostring(mapChoices[selectedSlot] or selectedMapName))
            end
        end,
        "Select which of the 3 lobby billboard maps to vote for."
    )

    -- Refresh the 3 billboard map names right BEFORE the dropdown opens
    -- and keep the label synced with the lobby boards even while Auto Vote is OFF.
    pcall(function(): ()
        local control: any = state.valueControls
            and state.valueControls[selectMapOptionKey]
        if type(control) == "table" then
            control.onBeforeOpen = function(): ()
                refreshMapChoices(true)
            end
        end
    end)

    local lastBgSyncAt: number = -math.huge
    disconnectFeatureConnection("MM2AutoVoteMapSync")
    featureConnections.MM2AutoVoteMapSync = TaskManager:Connect(function(): ()
        local now: number = os.clock()
        if now - lastBgSyncAt < 1.0 then
            return
        end
        lastBgSyncAt = now
        refreshMapChoices(false)
    end)

    activeCleanup = function(): ()
        disconnectFeatureConnection("MM2AutoVoteMapSync")
        toggleAutoVote(false)
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
