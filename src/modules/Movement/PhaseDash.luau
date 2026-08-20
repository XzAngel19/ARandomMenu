--!strict
--
-- Phase Dash.
--
-- One press, one dash: Blink teleports through what is in front of you when
-- there is room on the far side, Slide is a velocity burst that does not. The
-- collision check is what stops a blink from leaving you inside a wall.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "PhaseDash",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local getCharacterParts: any = host.getCharacterParts
    local state: any = host.state
    local createUniversalFeature: any = host.createUniversalFeature
    local addToggleOption: any = host.addToggleOption
    local addNumberOption: any = host.addNumberOption
    local addCycleOption: any = host.addCycleOption
    type PhaseDashSettings = {
        mode: string,
        distance: number,
        cooldown: number,
        exitSpeed: number,
        slideSpeed: number,
        collisionPadding: number,
        flashDuration: number,
        preserveVelocity: boolean,
    }
    local phaseDashSettings: PhaseDashSettings = {
        mode = "Blink",
        distance = 20,
        cooldown = 0.8,
        exitSpeed = 42,
        slideSpeed = 60,
        collisionPadding = 2.25,
        flashDuration = 0.28,
        preserveVelocity = true,
    }
    local lastPhaseDash: number = -math.huge
    local phaseDashEnabled: boolean = false

    local function createPhaseFlash(character: Model): ()
        local oldFlash: Instance? = character:FindFirstChild("RTM_PhaseDashFlash")
        if oldFlash then
            oldFlash:Destroy()
        end
        local flash: Highlight = Instance.new("Highlight")
        flash.Name = "RTM_PhaseDashFlash"
        flash.Adornee = character
        flash.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        flash.FillColor = Theme.AccentViolet
        flash.FillTransparency = 0.42
        flash.OutlineColor = Theme.AccentCyan
        flash.OutlineTransparency = 0.05
        flash.Parent = character
        local fade: Tween = TweenService:Create(
            flash,
            TweenInfo.new(
                math.clamp(phaseDashSettings.flashDuration, 0.05, 1.2),
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.Out
            ),
            {FillTransparency = 1, OutlineTransparency = 1}
        )
        fade:Play()
        fade.Completed:Once(function(): ()
            if flash.Parent then
                flash:Destroy()
            end
        end)
    end

    local function performPhaseDash(): ()
        if not phaseDashEnabled then
            return
        end
        local now: number = os.clock()
        if now - lastPhaseDash < phaseDashSettings.cooldown then
            return
        end
        local character: Model?, humanoid: Humanoid?, root: BasePart? = getCharacterParts()
        local camera: Camera? = workspace.CurrentCamera
        if not character or not humanoid or not root or not camera then
            return
        end
        local direction: Vector3 = humanoid.MoveDirection
        if direction.Magnitude < 0.05 then
            direction = Vector3.new(
                camera.CFrame.LookVector.X,
                0,
                camera.CFrame.LookVector.Z
            )
        end
        if direction.Magnitude < 0.05 then
            return
        end
        direction = direction.Unit
        lastPhaseDash = now
        local previousVelocity: Vector3 = root.AssemblyLinearVelocity
        local padding: number = math.clamp(
            phaseDashSettings.collisionPadding,
            0,
            8
        )
        if phaseDashSettings.mode == "Slide" then
            -- Slide: a velocity burst instead of a teleport. No raycast, no wall
            -- stop — the dash pushes the character and the game physics handles
            -- the rest, which keeps the dash usable on uneven terrain.
            root.AssemblyLinearVelocity = direction * phaseDashSettings.slideSpeed
                + Vector3.new(0, previousVelocity.Y, 0)
            createPhaseFlash(character)
            return
        end
        -- Blink: collision-aware teleport along the dash line.
        local params: RaycastParams = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {character}
        local collision: RaycastResult? = workspace:Raycast(
            root.Position,
            direction * phaseDashSettings.distance,
            params
        )
        local safeDistance: number = collision
                and math.max(0, collision.Distance - padding)
            or phaseDashSettings.distance
        if safeDistance <= 0.1 then
            return
        end
        root.CFrame = root.CFrame + direction * safeDistance
        if not phaseDashSettings.preserveVelocity then
            root.AssemblyLinearVelocity = direction * phaseDashSettings.exitSpeed
                + Vector3.new(0, previousVelocity.Y, 0)
        end
        createPhaseFlash(character)
    end

    local function togglePhaseDash(enabled: boolean): ()
        disconnectFeatureConnection("PhaseDash")
        phaseDashEnabled = enabled
        if not enabled then
            return
        end
        -- The dash key is the card's header key slot (see
        -- `state.bindFeatureActivationKey` where the module is declared), so there
        -- is no private input handler and no "Dash key" row in the panel.
    end


    local PhaseDashFeature = createUniversalFeature(
        "Phase Dash",
        "Directional dash: collision-aware blink or a velocity slide",
        25,
        togglePhaseDash
    )
    addCycleOption(
        PhaseDashFeature,
        "Mode",
        {"Blink", "Slide"},
        1,
        function(value: string): ()
            phaseDashSettings.mode = value
        end
    )
    addNumberOption(
        PhaseDashFeature,
        "Dash distance",
        phaseDashSettings.distance,
        4,
        80,
        function(value: number): ()
            phaseDashSettings.distance = value
        end
    )
    addNumberOption(
        PhaseDashFeature,
        "Cooldown",
        phaseDashSettings.cooldown,
        0.1,
        5,
        function(value: number): ()
            phaseDashSettings.cooldown = value
        end
    )
    addNumberOption(
        PhaseDashFeature,
        "Exit speed",
        phaseDashSettings.exitSpeed,
        0,
        180,
        function(value: number): ()
            phaseDashSettings.exitSpeed = value
        end
    )
    addNumberOption(
        PhaseDashFeature,
        "Slide speed",
        phaseDashSettings.slideSpeed,
        20,
        250,
        function(value: number): ()
            phaseDashSettings.slideSpeed = value
        end
    )
    addNumberOption(
        PhaseDashFeature,
        "Collision padding",
        phaseDashSettings.collisionPadding,
        0,
        8,
        function(value: number): ()
            phaseDashSettings.collisionPadding = value
        end
    )
    addNumberOption(
        PhaseDashFeature,
        "Flash duration (s)",
        phaseDashSettings.flashDuration,
        0.05,
        1.2,
        function(value: number): ()
            phaseDashSettings.flashDuration = value
        end
    )
    addToggleOption(
        PhaseDashFeature,
        "Preserve velocity",
        phaseDashSettings.preserveVelocity,
        function(value: boolean): ()
            phaseDashSettings.preserveVelocity = value
        end
    )
    -- The dash key is the card's own key slot, not an option row: one module, one
    -- keybind, in the place every other module keeps it. It starts blank like
    -- every other slot — the module used to arrive pre-bound to Q for no reason
    -- the player could see. On touch, tapping the slot places a DASH button.
    state.bindFeatureActivationKey(
        PhaseDashFeature,
        nil,
        performPhaseDash
    )

    activeCleanup = function(): ()
        disconnectFeatureConnection("PhaseDash")
    end
    Module.Initialized = true
    return PhaseDashFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
