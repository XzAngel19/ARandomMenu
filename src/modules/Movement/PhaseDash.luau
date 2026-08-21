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
    local framework: any = context.framework
    local getCharacterParts: any = host.getCharacterParts
    local state: any = host.state
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


    local phaseDash: any
    phaseDash = framework.Categories.Movement:CreateModule({
        Name = "Phase Dash",
        Category = "Movement",
        Tooltip = "Directional dash: collision-aware blink or a velocity slide. "
            .. "The card's key slot is the dash key.",
        Function = function(enabled: boolean): ()
            phaseDashEnabled = enabled
            -- The dash key is the card's header key slot (bound below), so there
            -- is no private input handler and no "Dash key" row in the panel.
        end,
    })
    phaseDash:CreateDropdown({
        Name = "Mode",
        List = {"Blink", "Slide"},
        Index = 1,
        Function = function(value: string): ()
            phaseDashSettings.mode = value
        end,
    })
    phaseDash:CreateSlider({
        Name = "Dash distance",
        Show = {Option = "Mode", Values = {"Blink"}},
        Min = 4,
        Max = 80,
        Default = phaseDashSettings.distance,
        Function = function(value: number): ()
            phaseDashSettings.distance = value
        end,
        Tooltip = "How far a blink tries to move before the wall check "
            .. "shortens it.",
    })
    phaseDash:CreateSlider({
        Name = "Exit speed",
        Show = {Option = "Mode", Values = {"Blink"}},
        Min = 0,
        Max = 180,
        Default = phaseDashSettings.exitSpeed,
        Function = function(value: number): ()
            phaseDashSettings.exitSpeed = value
        end,
        Tooltip = "The velocity a blink leaves you with when Preserve "
            .. "velocity is off.",
    })
    phaseDash:CreateSlider({
        Name = "Slide speed",
        Show = {Option = "Mode", Values = {"Slide"}},
        Min = 20,
        Max = 250,
        Default = phaseDashSettings.slideSpeed,
        Function = function(value: number): ()
            phaseDashSettings.slideSpeed = value
        end,
    })
    phaseDash:CreateSlider({
        Name = "Collision padding",
        Show = {Option = "Mode", Values = {"Blink"}},
        Min = 0,
        Max = 8,
        Default = phaseDashSettings.collisionPadding,
        Function = function(value: number): ()
            phaseDashSettings.collisionPadding = value
        end,
        Tooltip = "Studs of clearance kept between you and whatever the blink "
            .. "stopped at.",
    })
    phaseDash:CreateSlider({
        Name = "Flash duration (s)",
        Min = 0.05,
        Max = 1.2,
        Default = phaseDashSettings.flashDuration,
        Function = function(value: number): ()
            phaseDashSettings.flashDuration = value
        end,
    })
    phaseDash:CreateToggle({
        Name = "Preserve velocity",
        Show = {Option = "Mode", Values = {"Blink"}},
        Default = phaseDashSettings.preserveVelocity,
        Function = function(value: boolean): ()
            phaseDashSettings.preserveVelocity = value
        end,
        Tooltip = "Keep the velocity you had before the blink instead of "
            .. "replacing it with Exit speed.",
    })
    -- Cooldown exists in both modes, so it is created last: an ungated final
    -- row is what keeps every rule above it honest, because the kernel only
    -- re-reads the rules when an option is created or a value changes.
    phaseDash:CreateSlider({
        Name = "Cooldown",
        Min = 0.1,
        Max = 5,
        Default = phaseDashSettings.cooldown,
        Function = function(value: number): ()
            phaseDashSettings.cooldown = value
        end,
    })

    -- The dash key is the card's own key slot, not an option row: one module,
    -- one keybind, in the place every other module keeps it. It starts blank
    -- like every other slot — the module used to arrive pre-bound to Q for no
    -- reason the player could see. On touch, tapping the slot places a DASH
    -- button.
    state.bindFeatureActivationKey(phaseDash.Feature, nil, performPhaseDash)

    activeCleanup = function(): ()
        phaseDashEnabled = false
    end
    Module.Initialized = true
    return phaseDash
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
