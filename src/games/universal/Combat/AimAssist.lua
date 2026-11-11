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
    local localPlayer: Player? = host.LocalPlayer
    local runtime: any = {
        target = nil,
        lockedTarget = nil,
        lastFire = -math.huge,
        fireMode = "Hold",
        clickPressed = false,
    }
    local card: any

    local function camera(): Camera?
        return currentWorkspace.CurrentCamera
    end

    local function getHeldTool(): Tool?
        local player: Player? = localPlayer or host.LocalPlayer
        if not player then return nil end
        local character: Model? = player.Character
        if not character then return nil end
        for _, child: Instance in ipairs(character:GetChildren()) do
            if child:IsA("Tool") then
                return child :: Tool
            end
        end
        return nil
    end

    -- Screen position of the real cursor (includes the top-bar inset), used
    -- both to aim the virtual mouse and to place virtual clicks.
    local function getMouseScreenPosition(cameraObject: Camera?): Vector2
        local mouseOk: boolean, mousePos: any = pcall(function(): any
            return userInput:GetMouseLocation()
        end)
        if mouseOk and typeof(mousePos) == "Vector2" then
            return mousePos
        end
        local vp: Vector2 = cameraObject and cameraObject.ViewportSize
            or Vector2.new(800, 600)
        local insetY: number = 36
        pcall(function(): ()
            local guiService: any = game:GetService("GuiService")
            local inset: Vector2 = guiService:GetGuiInset()
            if typeof(inset) == "Vector2" then insetY = inset.Y end
        end)
        return Vector2.new(vp.X / 2, vp.Y / 2 + insetY)
    end

    local function tryFireOnce(fireMode: string?, clickPressed: boolean?): boolean
        -- Only a tool that is ALREADY held gets Activate(). Equipping from the
        -- backpack mid-fight was removed on purpose: EquipTool can trigger the
        -- game's equip/ADS logic, which switches or locks the camera exactly at
        -- the point where the player clicked.
        local tool: Tool? = getHeldTool()
        if tool then
            if tool.Enabled == false then return false end
            -- Hold mode: the player's real click already activates the held tool
            -- (Roblox fires Tool.Activated on click); an extra Activate()
            -- double-fires semi-auto guns.
            if fireMode == "Hold" and clickPressed == true then return true end
            local ok: boolean = pcall(function(): () (tool :: Tool):Activate() end)
            if ok then return true end
        end
        -- Rivals / FPS without Tool (ViewModel + RemoteEvent): fallback to a
        -- virtual click. It MUST be sent at the real cursor position: sending
        -- (0, 0) shoots at the top-left screen corner and, with a free cursor,
        -- yanks the mouse (and any camera driven by absolute mouse position)
        -- to that corner.
        local mouse: Vector2 = getMouseScreenPosition(camera())
        local vimOk: boolean = pcall(function(): ()
            local vim: any = game:GetService("VirtualInputManager")
            if vim and type(vim.SendMouseButtonEvent) == "function" then
                -- Press and release quickly; the CPS loop controls rate
                vim:SendMouseButtonEvent(mouse.X, mouse.Y, 0, true, game, 0)
                vim:SendMouseButtonEvent(mouse.X, mouse.Y, 0, false, game, 0)
            else
                error("no vim")
            end
        end)
        if vimOk then return true end
        local env: any = getfenv()
        local click: any = env.mouse1click or env.mouse1press
        if type(click) == "function" then
            local ok2: boolean = pcall(function(): () click() end)
            if ok2 then return true end
            -- mouse1press needs release
            local rel: any = env.mouse1release
            if type(rel) == "function" then
                pcall(function(): () click(); task.wait(0.02); rel() end)
                return true
            end
        end
        return false
    end

    local function getCPS(): number
        local opt: any = nil
        if card and card.Options then
            opt = card.Options["Clicks Per Second"] or card.Options["Fire rate"] or card.Options["CPS"]
        end
        if opt and opt.Value ~= nil then
            return math.max(1, tonumber(opt.Value) or 12)
        end
        return 12
    end

    local function shouldAutoFire(): boolean
        if not card or not card.Options or not card.Options["Auto Fire"] then return false end
        if not card.Options["Auto Fire"].Value then return false end
        local rate: number = getCPS()
        local now: number = os.clock()
        if now - runtime.lastFire < 1 / rate then return false end
        local fireMode: string = "Hold"
        if card.Options["Auto Fire mode"] then
            fireMode = tostring(card.Options["Auto Fire mode"].Value)
        end
        local okHeld: boolean, isPressed: any = pcall(function(): any
            return userInput:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
        end)
        local clickPressed: boolean = okHeld and isPressed == true
        -- Remembered for tryFireOnce: in Hold mode a real click already fired
        -- the held tool, so the module must not Activate() it a second time.
        runtime.fireMode = fireMode
        runtime.clickPressed = clickPressed
        if fireMode == "Always" then
            runtime.lastFire = now
            return true
        end
        if clickPressed then
            runtime.lastFire = now
            return true
        end
        return false
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
            local lp: Player? = localPlayer or host.LocalPlayer
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
            -- Use ScreenPoint to match GetMouseLocation (both include top-bar inset 36px)
            local ok: boolean, screenPos: any, onScreen: any = pcall(function(): any
                return cameraObject:WorldToScreenPoint(target.position)
            end)
            if not ok or type(screenPos) ~= "Vector3" then return false end
            if onScreen == false and mode ~= "Aimbot" then return false end
            -- Always use GetMouseLocation (with inset) for delta; fallback to Viewport/2+inset
            local m: Vector2 = getMouseScreenPosition(cameraObject)
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
            -- Write directly from this frame callback. Card Render tasks run
            -- on RenderStepped, i.e. AFTER the game's own camera update
            -- (RenderPriority.Camera), so this write wins for the frame.
            -- Deliberately NO BindToRenderStep here: the old one-shot binding
            -- captured a stale newCFrame and tried to unbind itself from inside
            -- the render step; when that unbind failed (the pcall swallowed it),
            -- the binding re-wrote the same stale CFrame every frame and the
            -- camera froze on the last aim point — the spot where the player
            -- clicked. Writing only from the per-frame callback means that as
            -- soon as there is no target, nothing writes the camera anymore and
            -- the game owns the view again.
            local ok: boolean = pcall(function(): ()
                cameraObject.CFrame = newCFrame
            end)
            return ok
        end

        -- Hybrid fix for Rivals: with Tool/weapon, the gun's ray often uses mouse Hit, not just camera.
        -- Pure Camera leaves Mouse Hit at old side; pure Mouse has 1-frame camera lag.
        -- For natural + accurate, do BOTH when locked (FPS). For 3rd person, Mouse is enough.
        if cameraMode == "Auto" then
            local locked: boolean = isMouseLocked()
            if locked then
                -- FPS shift-lock / 1st person: try both to keep camera and Mouse Hit synced.
                -- Mouse first (game's native delta), then immediate Camera to remove 1-frame lag for hitscan.
                local didMouse: boolean = tryMouse()
                local didCamera: boolean = tryCamera()
                -- If we did Camera, we synced immediately; if only Mouse, camera will catch next frame via game's handler.
                return didMouse or didCamera
            else
                -- 3rd person: Mouse is natural and weapon (if any) follows camera via game's orbit, no need for double.
                if tryMouse() then return true end
                if tryCamera() then return true end
                return false
            end
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

    pcall(function(): ()
        local cfg: any = host.configData
        if cfg and type(cfg.values) == "table" then
            local key: string = "Universal.AimAssist.Camera"
            if cfg.values[key] == "CFrame" then
                cfg.values[key] = "Camera"
            end
            local oldKey: string = "Universal.AimAssist.Fire rate"
            local newKey: string = "Universal.AimAssist.Clicks Per Second"
            if cfg.values[oldKey] ~= nil and cfg.values[newKey] == nil then
                cfg.values[newKey] = cfg.values[oldKey]
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
            runtime.lastFire = -math.huge
            if not enabled then
                card:SetStatus(nil)
                local rs: any = (host :: any).RunService
                if rs and type(rs.UnbindFromRenderStep) == "function" then
                    pcall(function(): () rs:UnbindFromRenderStep("WurstAimAssistCam") end)
                end
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
                if shouldAutoFire() then
                    pcall(function(): () tryFireOnce(runtime.fireMode, runtime.clickPressed) end)
                end
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
                local rs: any = (host :: any).RunService
                if rs and type(rs.UnbindFromRenderStep) == "function" then
                    pcall(function(): () rs:UnbindFromRenderStep("WurstAimAssistCam") end)
                end
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
        Tooltip = "Auto: 3rd=Mouse (natural) 1st/FPS=Mouse+Camera híbrido para que el arma siga (Mouse Hit + CFrame instant). Camera: solo CFrame (1st person). Mouse: solo mousemoverel.",
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
    card:CreateToggle({
        Name = "Auto Fire",
        Default = false,
        Tooltip = "Autoclick genérico: si no hay Tool hace click virtual. No toca GUI.",
    })
    card:CreateDropdown({
        Name = "Auto Fire mode",
        List = {"Hold", "Always"},
        Index = 1,
        Show = {Option = "Auto Fire"},
        Tooltip = "Hold = solo mientras mantienes click izquierdo (para semi-auto). Always = dispara solo al tener target.",
    })
    card:CreateSlider({
        Name = "Clicks Per Second",
        Min = 1,
        Max = 20,
        Step = 1,
        Default = 12,
        Show = {Option = "Auto Fire"},
        Tooltip = "Clicks por segundo manteniendo. 12 default = pistola semi-auto. Sube para automático.",
    })
    card:CreateNote(
        "Natural: Auto 3rd=Mouse, 1st=Mouse+Camera híbrido (sincroniza Mouse Hit + CFrame) para que el arma no se quede atrás."
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
        patchOption("ClicksPerSecond", "1", "20", "(cps)")
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
