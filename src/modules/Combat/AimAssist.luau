--!strict
--
-- Aim Assist.
--
-- A visible, camera-only assist for supported Roblox experiences. It asks the
-- shared Targeting library for a valid player or NPC, then eases the local
-- camera toward that point while the module is enabled. Assist uses a cursor
-- FOV; Aimbot removes that gate and keeps a smooth, stable lock. It does not
-- hook Raycast, spoof Mouse.Hit, rewrite remotes, simulate clicks or change
-- hitboxes.
--
-- That boundary is intentional. A module can own its camera effect without
-- affecting other modules; a global hook cannot. The target selector is kept
-- separate so a future, explicitly supported game adapter can consume the
-- same target record without changing this universal module.

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

        -- Aimbot is deliberately a snap lock: it has no smoothing control and
        -- does not keep pulling the camera after the user chooses the mode. The
        -- normal assist uses a frame-rate-independent time constant; zero is a
        -- useful snap value and larger values settle more gently.
        local mode: string = card.Options["Mode"].Value
        local alpha: number = 1
        if mode ~= "Aimbot" then
            local smoothing: number = card.Options["Smoothing"].Value
            if smoothing > 0 then
                local timeConstant: number = 0.02 + smoothing * 0.01
                alpha = 1 - math.exp(-math.max(deltaTime, 1 / 240) / timeConstant)
                alpha = math.clamp(alpha, 0, 1)
            end
        end
        local currentLook: Vector3 = current.LookVector
        local blended: Vector3 = currentLook:Lerp(offset.Unit, alpha)
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
            -- Assist respects the user's cursor FOV. Aimbot intentionally
            -- removes that gate, then keeps one valid target until it leaves
            -- the query so the camera does not jump between players every frame.
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
                -- Menu surfaces own input while open. Do not steer the camera
                -- under a settings window or while a key is being assigned.
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
        Tooltip = "Aim Assist respects FOV; Aimbot keeps a smooth lock on the "
            .. "best valid character on screen.",
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
    card:CreateSlider({
        Name = "Smoothing",
        Show = {Option = "Mode", Values = {"Aim Assist"}},
        Min = 0,
        Max = 100,
        Step = 5,
        Default = 35,
        Tooltip = "0 snaps to the target; higher values make the camera settle "
            .. "more slowly. Aimbot always uses zero smoothing.",
    })
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
