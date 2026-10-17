export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    libraries: {[string]: any},
    services: any,
}

local Module = {
    Name = "AimAssist",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCard: any = nil

function Module.init(context: Runtime): any
    local framework: any = context.framework
    local host: any = context.host
    local services: any = context.services
    local targeting: any = context.libraries and context.libraries.targeting
    local entity: any = context.entity
    local userInput: UserInputService = host.UserInputService
    local currentWorkspace: Workspace = host.workspace or workspace
    local runtime: any = {
        target = nil,
        lockedTarget = nil,
    }
    local card: any

    local function camera(): Camera?
        return currentWorkspace.CurrentCamera
    end

    local function moveCamera(target: any, deltaTime: number): boolean
        local cameraObject: Camera? = camera()
        if not cameraObject or not target then
            return false
        end
        local current: CFrame = cameraObject.CFrame
        local offset: Vector3 = target.position - current.Position
        if offset.Magnitude <= 0.001 then
            return false
        end

        local mode: string = card.Options["Mode"].Value
        local alpha: number = 1
        if mode ~= "Aimbot" then
            -- Speed caps turn rate; Strength controls the pull near the target.
            -- Both are time-based, rather than a frame-count smoothing factor.
            local dt = math.max(deltaTime, 0)
            local speed = math.max(0, card.Options.Speed.Value)
            local strength = math.max(0, card.Options.Strength.Value) / 100
            if speed == 0 or strength == 0 or dt == 0 then return false end
            local angle = math.acos(math.clamp(current.LookVector:Dot(offset.Unit), -1, 1))
            alpha = math.min(1 - math.exp(-strength * 10 * dt),
                angle > 1e-6 and math.rad(speed) * dt / angle or 1)
        end
        local currentLook: Vector3 = current.LookVector
        local blended: Vector3 = offset.Unit
        if alpha < 1 then
            local dot = math.clamp(currentLook:Dot(offset.Unit), -1, 1)
            local tangent = offset.Unit - currentLook * dot
            if tangent.Magnitude < 1e-6 then tangent = current.RightVector end
            local turn = math.acos(dot) * alpha
            blended = currentLook * math.cos(turn) + tangent.Unit * math.sin(turn)
        end
        if blended.Magnitude <= 0.001 then
            return false
        end
        cameraObject.CFrame = CFrame.lookAt(
            current.Position,
            current.Position + blended.Unit
        )
        return true
    end

    local function anotherAimAdapterIsActive(): boolean
        local activity: any = services and services.activity
        local free = services and services.freeCam
        local spectate = services and services.spectate
        if free and free.IsActive() or spectate and spectate.IsActive() then return true end
        return activity ~= nil
            and type(activity.isActive) == "function"
            and activity.isActive("mvsdSilentAim") == true
    end

    local function selectTarget(): any
        if anotherAimAdapterIsActive()
            or not targeting
            or type(targeting.List) ~= "function" then
            return nil
        end
        local options: any = card.Options
        local mode: string = options["Mode"].Value
        local candidates: {any} = targeting:List(entity, {

            FOV = mode == "Aim Assist" and options["FOV"].Value or nil,
            MaxDistance = options["Max distance"].Value,
            TargetPart = options["Target part"].Value,
            Prediction = options["Prediction"].Value,
            TeamCheck = options["Team check"].Value,
            VisibilityCheck = options["Visibility check"].Value,
            Priority = options["Priority"].Value,
            IncludeNPCs = options["Target NPCs"].Value,
            AllowOffscreen = mode == "Aimbot",
        })
        if mode ~= "Aimbot" then
            runtime.lockedTarget = nil
            return candidates[1]
        end
        if options["Sticky target"].Value and runtime.lockedTarget then
            for _, candidate: any in ipairs(candidates) do
                if candidate.entity == runtime.lockedTarget.entity then
                    runtime.lockedTarget = candidate
                    return candidate
                end
            end
        end
        runtime.lockedTarget = candidates[1]
        return runtime.lockedTarget
    end

    card = framework.Categories.Combat:CreateModule({
        Name = "Aim Assist",
        Category = "Combat",
        ConfigKey = "Universal.AimAssist",
        Order = 4,
        Tooltip = "Eases the local camera toward a valid target; no raycast or "
            .. "remote hooks.",
        Function = function(enabled: boolean): ()
            runtime.target = nil
            runtime.lockedTarget = nil
            if not enabled then
                card:SetStatus(nil)
                return
            end
            card:SetStatus("searching")
            card:Render(function(deltaTime: number): ()

                if anotherAimAdapterIsActive()
                    or services.menu.isVisible()
                    or services.menu.isCapturingInput() then
                    runtime.target = nil
                    runtime.lockedTarget = nil
                    card:SetStatus("paused")
                    return
                end
                if userInput:GetFocusedTextBox() then
                    runtime.target = nil
                    runtime.lockedTarget = nil
                    card:SetStatus("paused")
                    return
                end

                local selected: any = selectTarget()
                runtime.target = selected
                if not selected then
                    card:SetStatus("searching")
                    return
                end
                local moved: boolean = moveCamera(selected, deltaTime)
                local targetPlayer: Player? = selected.player
                local displayName: string = targetPlayer
                    and tostring(targetPlayer.DisplayName or targetPlayer.Name)
                    or tostring(selected.entity.Name or selected.character.Name)
                local distance: number = math.round(selected.distance)
                card:SetStatus(
                    displayName .. " · " .. tostring(distance) .. " studs"
                        .. (moved and " · locked" or " · ready")
                )
            end)
            card:Clean(function(): ()
                runtime.target = nil
                card:SetStatus(nil)
            end)
        end,
    })

    card:CreateDropdown({
        Name = "Mode",
        List = {"Aim Assist", "Aimbot"},
        Index = 1,
        Function = function(): ()
            runtime.lockedTarget = nil
        end,
        Tooltip = "Aim Assist uses Speed and Strength inside FOV. Aimbot snaps "
            .. "to a valid target and can keep a sticky lock.",
    })
    card:CreateSlider({
        Name = "FOV",
        Show = {Option = "Mode", Values = {"Aim Assist"}},
        Min = 15,
        Max = 500,
        Step = 5,
        Default = 180,
        Tooltip = "Pixels around the cursor in which a target may be selected.",
    })
    card:CreateSlider({Name="Speed",Min=0,Max=360,Default=180,Step=5,
        Show={Option="Mode",Values={"Aim Assist"}},
        Tooltip="Maximum camera turn in degrees per second. Higher = faster. 0 = no assist."})
    card:CreateSlider({Name="Strength",Min=0,Max=100,Default=75,Step=5,
        Show={Option="Mode",Values={"Aim Assist"}},
        Tooltip="Pull toward the target, in percent. Higher = firmer tracking; 0 = no assist. Aimbot snaps instead."})
    card:CreateDropdown({
        Name = "Target part",
        List = {"Closest", "Head", "Torso"},
        Index = 1,
        Tooltip = "Body part used as the camera target.",
    })
    card:CreateDropdown({
        Name = "Priority",
        List = {"Cursor", "Distance"},
        Index = 1,
        Tooltip = "Choose the target nearest the cursor or nearest in the world.",
    })
    card:CreateSlider({
        Name = "Prediction",
        Min = 0,
        Max = 0.5,
        Step = 0.01,
        Default = 0.06,
        Tooltip = "Seconds of target velocity to lead. Set to 0 for no lead.",
    })
    card:CreateSlider({
        Name = "Max distance",
        Min = 25,
        Max = 2000,
        Step = 5,
        Default = 600,
        Tooltip = "Ignore targets farther than this many studs.",
    })
    card:CreateToggle({
        Name = "Visibility check",
        Default = true,
        Tooltip = "Skip targets hidden by map geometry.",
    })
    card:CreateToggle({
        Name = "Team check",
        Default = true,
        Tooltip = "Skip teammates and Friend List entries.",
    })
    card:CreateToggle({
        Name = "Target NPCs",
        Default = false,
        Tooltip = "Include non-player humanoid models in both modes.",
    })
    card:CreateToggle({
        Name = "Sticky target",
        Show = {Option = "Mode", Values = {"Aimbot"}},
        Default = true,
        Function = function(value: boolean): ()
            if not value then
                runtime.lockedTarget = nil
            end
        end,
        Tooltip = "Hold the current Aimbot target. Turn off to release it and "
            .. "select a new target every frame.",
    })
    card:CreateNote(
        "Camera-only assist. It never edits remotes, raycasts or hitboxes."
    )

    activeCard = card
    Module.Initialized = true
    return card
end

function Module.destroy(): ()
    if activeCard and activeCard.Enabled then
        activeCard:Toggle(false)
    end
    activeCard = nil
    Module.Initialized = false
end

return Module
