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
        local mode: string = card.Options["Mode"].Value
        local cameraModeRaw: string = "Auto"
        if card.Options["Camera"] then
            cameraModeRaw = tostring(card.Options["Camera"].Value)
        end
        local cameraMode: string = cameraModeRaw
        if cameraModeRaw == "CFrame" then
            cameraMode = "Camera"
        end
        local current: CFrame = cameraObject.CFrame
        local offset: Vector3 = target.position - current.Position
        if offset.Magnitude <= 0.001 then
            return false
        end

        local alpha: number = 1
        if mode ~= "Aimbot" then
            local dt = math.max(deltaTime, 0)
            local speed = math.max(0, card.Options.Speed.Value)
            local strength = math.max(0, card.Options.Strength.Value) / 100
            if speed == 0 or strength == 0 or dt == 0 then return false end
            local angle = math.acos(math.clamp(current.LookVector:Dot(offset.Unit), -1, 1))
            if angle < math.rad(0.5) then return false end
            alpha = math.min(1 - math.exp(-strength * 10 * dt),
                angle > 1e-6 and math.rad(speed) * dt / angle or 1)
        end

        local function isMouseLocked(): boolean
            local okBeh: boolean, beh: any = pcall(function(): any
                return (userInput :: any).MouseBehavior
            end)
            if okBeh and beh then
                local okEnum: boolean, lockCenter: any = pcall(function(): any
                    return (Enum :: any).MouseBehavior.LockCenter
                end)
                local okCurr: boolean, lockCurr: any = pcall(function(): any
                    return (Enum :: any).MouseBehavior.LockCurrentPosition
                end)
                if (okEnum and beh == lockCenter) or (okCurr and beh == lockCurr) then
                    return true
                end
            end
            local lp: Player? = host.LocalPlayer
            local char: Model? = lp and lp.Character
            local head: BasePart? = char and char:FindFirstChild("Head") :: BasePart?
            if head then
                local dist: number = (cameraObject.CFrame.Position - head.Position).Magnitude
                if dist < 2.5 then
                    return true
                end
            end
            return false
        end

        local function tryMouse(): boolean
            if cameraMode == "Camera" then return false end
            local env: any = getfenv()
            local moverel: any = env.mousemoverel or env.mousemove or (host and (host.mousemoverel or host.mousemove))
            if type(moverel) ~= "function" then return false end
            -- Use ViewportPoint for consistency with ViewportSize and GetMouseLocation
            local ok: boolean, screenPos: any, onScreen: any = pcall(function(): any
                return cameraObject:WorldToViewportPoint(target.position)
            end)
            if not ok or type(screenPos) ~= "Vector3" then
                -- fallback to ScreenPoint
                ok, screenPos, onScreen = pcall(function(): any
                    return cameraObject:WorldToScreenPoint(target.position)
                end)
                if not ok or type(screenPos) ~= "Vector3" then return false end
            end
            if onScreen == false and mode ~= "Aimbot" then return false end
            -- Always prefer GetMouseLocation when available, even when locked
            local mouse: Vector2? = nil
            local mouseOk: boolean, mousePos: any = pcall(function(): any return userInput:GetMouseLocation() end)
            if mouseOk and typeof(mousePos) == "Vector2" then
                mouse = mousePos
            else
                local vp: Vector2 = cameraObject.ViewportSize
                mouse = Vector2.new(vp.X / 2, vp.Y / 2)
            end
            -- For locked first-person, ViewportPoint vs GetMouseLocation may have 36px inset mismatch.
            -- If locked, ensure mouse is centered in viewport coordinates.
            if isMouseLocked() then
                local vp: Vector2 = cameraObject.ViewportSize
                -- GetMouseLocation in locked mode should already be center, but if it's not, force center
                if mouse then
                    local center: Vector2 = Vector2.new(vp.X / 2, vp.Y / 2)
                    -- If mouse is far from center (>100px) while locked, it's likely using ScreenPoint vs Viewport mismatch, use center
                    if (mouse :: Vector2).X < 5 or (mouse :: Vector2).Y < 5 then
                        mouse = center
                    end
                else
                    mouse = Vector2.new(vp.X / 2, vp.Y / 2)
                end
            end
            local m: Vector2 = mouse :: Vector2
            local delta: Vector2 = Vector2.new(screenPos.X - m.X, screenPos.Y - m.Y)
            if mode ~= "Aimbot" then
                delta = delta * alpha
            end
            if delta.Magnitude < 0.3 then return false end
            local maxDelta: number = 500
            if math.abs(delta.X) > maxDelta or math.abs(delta.Y) > maxDelta then
                delta = delta.Unit * maxDelta
            end
            local moved: boolean = false
            local okMove: boolean = pcall(function(): ()
                moverel(delta.X, delta.Y)
                moved = true
            end)
            return okMove and moved
        end

        local function tryCamera(): boolean
            if cameraMode == "Mouse" then return false end
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
            local newCFrame: CFrame = CFrame.lookAt(current.Position, current.Position + blended.Unit)
            local ok: boolean = pcall(function(): ()
                cameraObject.CFrame = newCFrame
            end)
            return ok
        end

        -- Auto: 1st person shift-lock -> Mouse (Rivals partida uses mouse delta), 3rd person -> Mouse as well, but Camera as fallback.
        -- User reported Camera works for 1st person, Mouse for 3rd, so we try both.
        -- For natural feel, try the primary driver first, then fallback.
        if cameraMode == "Auto" then
            -- Try mouse first (most natural for both, goes through game's recoil/sway), then camera
            if tryMouse() then return true end
            if tryCamera() then return true end
            return false
        elseif cameraMode == "Camera" then
            return tryCamera()
        elseif cameraMode == "Mouse" then
            return tryMouse()
        end
        return tryCamera()
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

    -- Compat migrate CFrame->Camera
    pcall(function(): ()
        local cfg: any = host.configData
        if cfg and type(cfg.values) == "table" then
            local key: string = "Universal.AimAssist.Camera"
            if cfg.values[key] == "CFrame" then
                cfg.values[key] = "Camera"
            end
        end
    end)

    card = framework.Categories.Exploits:CreateModule({
        Name = "Aimbot",
        Category = "Exploits",
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
        Tooltip = "Aim Assist = ayuda suave dentro de FOV usando Speed/Strength (natural). Aimbot = snap directo con Sticky opcional.",
    })
    card:CreateDropdown({
        Name = "Camera",
        List = {"Auto", "Camera", "Mouse"},
        Index = 1,
        Tooltip = "Auto: Mouse primero (natural, respeta recoil) luego Camera. Camera: CFrame directo (útil en 1st person shift-lock si Mouse no va). Mouse: solo mousemoverel.",
    })
    card:CreateSlider({
        Name = "FOV",
        Show = {Option = "Mode", Values = {"Aim Assist"}},
        Min = 15,
        Max = 500,
        Step = 5,
        Default = 180,
        Tooltip = "FOV en píxeles: radio alrededor del cursor. 15 pequeño — 500 pantalla completa. Default 180.",
    })
    card:CreateSlider({Name="Speed",Min=0,Max=360,Default=180,Step=5,
        Show={Option="Mode",Values={"Aim Assist"}},
        Tooltip="Speed °/s: rotación máxima. 0 sin ayuda, 180 default, 360 instantáneo."})
    card:CreateSlider({Name="Strength",Min=0,Max=100,Default=75,Step=5,
        Show={Option="Mode",Values={"Aim Assist"}},
        Tooltip="Strength %: fuerza de arrastre. 0 nada, 50 suave, 75 default, 100 máxima."})
    card:CreateNote("FOV: 15-500 px — 180 default • Speed: 0-360 °/s — 180 default • Strength: 0-100% — 75 default.")
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
        Tooltip = "Prediction s: anticipa movimiento. 0 sin predicción, 0.06 default (60 ms).",
    })
    card:CreateSlider({
        Name = "Max distance",
        Min = 25,
        Max = 2000,
        Step = 5,
        Default = 600,
        Tooltip = "Max distance studs: ignora targets más lejos. 600 default.",
    })
    card:CreateNote("Prediction: 0-0.5 s — 0.06 s default. Max distance 600 studs default.")
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
        Tooltip = "Hold the current Aimbot target. Turn off to release it every frame.",
    })
    card:CreateNote(
        "Natural: Auto prueba Mouse (mousemoverel ViewportPoint) luego Camera (CFrame.lookAt). Camera directo funciona en 1st person shift-lock donde el juego sobrescribe mouse."
    )

    pcall(function()
        local feature: any = (card :: any).Feature or (card :: any)._feature or card
        local optionsFrame: any = (feature :: any).options or (card :: any).options
        if not optionsFrame or type(optionsFrame.FindFirstChild) ~= "function" then return end
        local function patchOption(optionName: string, minText: string, maxText: string, suffix: string)
            local row: any = optionsFrame:FindFirstChild("Option_" .. optionName:gsub("%W", ""))
            if not row then return end
            local label: any = row:FindFirstChild("OptionLabel")
            if label and suffix then pcall(function() label.Text = label.Text .. " " .. suffix end) end
            local slider: any = row:FindFirstChild("Slider")
            if slider then
                local minL: any = slider:FindFirstChild("MinLabel")
                local maxL: any = slider:FindFirstChild("MaxLabel")
                if minL then pcall(function() minL.Text = minText end) end
                if maxL then pcall(function() maxL.Text = maxText end) end
            end
        end
        patchOption("FOV", "15 px", "500 px", "(píxeles)")
        patchOption("Speed", "0°/s", "360°/s", "(°/s)")
        patchOption("Strength", "0%", "100%", "(%)")
        patchOption("Prediction", "0 s", "0.5 s", "(s)")
        patchOption("Maxdistance", "25 studs", "2000 studs", "(studs)")
    end)

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
