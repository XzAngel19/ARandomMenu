local Module = {Name = "FreeCam", Initialized = false}
local card

function Module.init(context)
    local host = context.host
    local input, run = host.UserInputService, host.RunService
    local actions = game:GetService("ContextActionService")
    local access = context.services.cameraAccess
    local world = host.workspace or workspace
    local create = host.create
    local id = "ARandomMenu.FreeCam." .. tostring({})
    local spectateTarget

    card = context.framework.Categories.Visuals:CreateModule({
        Name = "FreeCam", Category = "World", ConfigKey = "Universal.FreeCam", Order = 6,
        Tooltip = "Move the camera without moving your character. WASD, Q/E, right-drag; touch controls on mobile.",
        Function = function(enabled)
            if not enabled then card:SetStatus(nil); return end
            local keys, held, connections = {}, {}, {}
            local camera, saved, position, pitch, yaw
            local writtenFrame, writtenFocus
            local controls, controlsEnabled
            local touchGui, touchGuiEnabled
            local moveTouch, lookTouch, dragging
            local stick = Vector2.zero
            local mouseMode, mouseIcon
            local gui, pad, knob

            local function connect(signal, callback)
                table.insert(connections, signal:Connect(callback))
            end
            local function releaseMouse()
                if not dragging then return end
                dragging = false
                if input.MouseBehavior == Enum.MouseBehavior.LockCurrentPosition then input.MouseBehavior = mouseMode end
                if input.MouseIconEnabled == false then input.MouseIconEnabled = mouseIcon end
            end
            local function resetInput()
                table.clear(keys); table.clear(held)
                moveTouch, lookTouch = nil, nil
                stick = Vector2.zero
                if knob then knob.Position = UDim2.fromScale(0.5,0.5) end
                releaseMouse()
            end
            local function restoreCamera()
                if camera and saved then
                    pcall(function()
                        if camera.CameraType ~= Enum.CameraType.Scriptable then return end
                        camera.CameraType = saved.kind
                        if camera.CFrame == writtenFrame then camera.CFrame = saved.frame end
                        if camera.Focus == writtenFocus then camera.Focus = saved.focus end
                    end)
                end
                camera, saved, writtenFrame, writtenFocus = nil, nil, nil, nil
            end
            local function releaseControls()
                if controls and controlsEnabled then pcall(controls.Enable, controls) end
                controls, controlsEnabled = nil, nil
                if touchGui then pcall(function() touchGui.Enabled = touchGuiEnabled end) end
                touchGui = nil
            end
            card:Clean(function()
                run:UnbindFromRenderStep(id)
                table.clear(keys); table.clear(held)
                for _, name in ipairs({"Forward","Back","Left","Right","Up","Down"}) do actions:UnbindAction(id .. name) end
                for _, connection in ipairs(connections) do connection:Disconnect() end
                releaseMouse(); restoreCamera(); releaseControls()
                if gui then gui:Destroy() end
            end)
            local function hold(name, source, down)
                held[name] = held[name] or {}
                held[name][source] = down and true or nil
                keys[name] = next(held[name]) ~= nil
            end
            for _, definition in ipairs({
                {"Forward",Enum.KeyCode.W,Enum.KeyCode.Up}, {"Back",Enum.KeyCode.S,Enum.KeyCode.Down},
                {"Left",Enum.KeyCode.A,Enum.KeyCode.Left}, {"Right",Enum.KeyCode.D,Enum.KeyCode.Right},
                {"Up",Enum.KeyCode.E,Enum.KeyCode.Space}, {"Down",Enum.KeyCode.Q,Enum.KeyCode.LeftControl},
            }) do
                local name = definition[1]
                actions:BindActionAtPriority(id .. name, function(_, state, event)
                    if input:GetFocusedTextBox() then held[name] = nil; keys[name] = false; return Enum.ContextActionResult.Pass end
                    if state == Enum.UserInputState.Cancel then held[name] = nil; keys[name] = false
                    else hold(name,event.KeyCode,state == Enum.UserInputState.Begin or state == Enum.UserInputState.Change) end
                    return Enum.ContextActionResult.Sink
                end, false, Enum.ContextActionPriority.High.Value + 1, definition[2], definition[3])
            end
            local function pan(delta)
                local sensitivity = math.rad(card.Options.Sensitivity.Value)
                yaw -= delta.X * sensitivity
                pitch = math.clamp(pitch - delta.Y * sensitivity, -math.rad(89), math.rad(89))
            end
            connect(input.InputBegan, function(event, processed)
                if processed or input:GetFocusedTextBox() or not position then return end
                if event.UserInputType == Enum.UserInputType.MouseButton2 then
                    mouseMode, mouseIcon = input.MouseBehavior, input.MouseIconEnabled
                    dragging = true
                    input.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
                    input.MouseIconEnabled = false
                end
            end)
            connect(input.InputChanged, function(event)
                if dragging and event.UserInputType == Enum.UserInputType.MouseMovement and not input:GetFocusedTextBox() then pan(event.Delta) end
            end)
            connect(input.InputEnded, function(event)
                if event.UserInputType == Enum.UserInputType.MouseButton2 then releaseMouse() end
            end)
            connect(input.WindowFocusReleased, resetInput)
            connect(input.TextBoxFocused, resetInput)

            if input.TouchEnabled then
                gui = create("Frame", {Name="FreeCamControls", Parent=host.ScreenGui, Size=UDim2.fromScale(1,1), BackgroundTransparency=1, ZIndex=30})
                local function button(name, text, at, size)
                    local object = create("TextButton", {Name=name, Parent=gui, Position=at, Size=size, Text=text, Font=Enum.Font.Code,
                        TextSize=18, TextColor3=Color3.new(1,1,1), BackgroundColor3=Color3.fromRGB(25,25,25), BackgroundTransparency=0.3,
                        BorderSizePixel=1, BorderColor3=Color3.fromRGB(120,120,120), AutoButtonColor=true, ZIndex=31})
                    if host.ThemeEngine then
                        host.ThemeEngine.Bind(object,"BackgroundColor3","background")
                        host.ThemeEngine.Bind(object,"TextColor3","text")
                    end
                    return object
                end
                pad = button("Move", "", UDim2.new(0,22,1,-152), UDim2.fromOffset(104,104))
                knob = create("Frame", {Parent=pad, Name="Stick", AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale(0.5,0.5),
                    Size=UDim2.fromOffset(26,26), BackgroundColor3=Color3.fromRGB(220,220,220), BorderSizePixel=0, ZIndex=32})
                local function moveStick(event)
                    local centre = pad.AbsolutePosition + pad.AbsoluteSize * 0.5
                    local delta = (Vector2.new(event.Position.X,event.Position.Y) - centre) / 42
                    stick = delta.Magnitude > 1 and delta.Unit or delta
                    if stick.Magnitude < 0.12 then stick = Vector2.zero end
                    knob.Position = UDim2.new(0.5,stick.X*36,0.5,stick.Y*36)
                end
                connect(pad.InputBegan, function(event)
                    if event.UserInputType == Enum.UserInputType.Touch and not moveTouch then moveTouch = event; moveStick(event) end
                end)
                for _, name in ipairs({"Up","Down"}) do
                    local object = button(name, name == "Up" and "+" or "−", UDim2.new(1,-70,1,name == "Up" and -152 or -96), UDim2.fromOffset(48,48))
                    connect(object.InputBegan, function(event) if event.UserInputType == Enum.UserInputType.Touch then hold(name,event,true) end end)
                    connect(object.InputEnded, function(event) if event.UserInputType == Enum.UserInputType.Touch then hold(name,event,false) end end)
                end
                local exit = button("Exit", "Exit FreeCam", UDim2.new(0.5,-66,0,48), UDim2.fromOffset(132,30))
                connect(exit.Activated, function()
                    if card.Feature and card.Feature.enabled and card.Feature.activate then card.Feature.activate() else card:Toggle(false) end
                end)
                connect(input.TouchStarted, function(event, processed)
                    local current = world.CurrentCamera
                    if not processed and not lookTouch and event ~= moveTouch and current
                        and event.Position.X > current.ViewportSize.X * 0.45 and not input:GetFocusedTextBox() then lookTouch = event end
                end)
                connect(input.TouchMoved, function(event)
                    if event == moveTouch then
                        moveStick(event)
                    elseif event == lookTouch and position then pan(event.Delta) end
                end)
                connect(input.TouchEnded, function(event)
                    hold("Up",event,false); hold("Down",event,false)
                    if event == moveTouch then moveTouch = nil; stick = Vector2.zero; knob.Position = UDim2.fromScale(0.5,0.5) end
                    if event == lookTouch then lookTouch = nil end
                end)
            end
            card:SetStatus("WASD / touch")
            run:BindToRenderStep(id, Enum.RenderPriority.Camera.Value + 1, function(dt)
                local nextCamera = world.CurrentCamera
                if camera ~= nextCamera then
                    restoreCamera()
                    camera = nextCamera
                    if camera then
                        saved = {kind=camera.CameraType, frame=camera.CFrame, focus=camera.Focus}
                        if not position then
                            position = camera.CFrame.Position
                            local look = camera.CFrame.LookVector
                            pitch, yaw = math.asin(math.clamp(look.Y,-1,1)), math.atan2(-look.X,-look.Z)
                        end
                    end
                end
                if not camera then return end
                if writtenFrame and camera.CameraType ~= Enum.CameraType.Scriptable then
                    saved.kind, saved.frame, saved.focus = camera.CameraType, camera.CFrame, camera.Focus
                elseif writtenFrame and camera.CFrame ~= writtenFrame then
                    saved.frame, saved.focus = camera.CFrame, camera.Focus
                end
                local nextControls = access:GetControls()
                if type(nextControls) ~= "table" or type(nextControls.Disable) ~= "function" or type(nextControls.Enable) ~= "function" then nextControls = nil end
                if nextControls ~= controls then
                    releaseControls(); controls = nextControls
                    if controls then
                        controlsEnabled = controls.controlsEnabled ~= false
                        local ok = pcall(controls.Disable, controls)
                        if not ok then controls, controlsEnabled = nil, nil end
                    end
                end
                local playerGui = host.LocalPlayer:FindFirstChildOfClass("PlayerGui")
                local nativeTouch = playerGui and playerGui:FindFirstChild("TouchGui")
                if nativeTouch ~= touchGui then
                    if touchGui then pcall(function() touchGui.Enabled = touchGuiEnabled end) end
                    touchGui = nativeTouch
                    if touchGui then touchGuiEnabled = touchGui.Enabled end
                end
                if touchGui then touchGui.Enabled = false end
                if not controls then
                    local character = host.LocalPlayer.Character
                    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                    if humanoid then humanoid:Move(Vector3.zero, false) end
                end
                local spectating = false
                local selected = card.Options["Spectate Player"]
                if selected then
                    for _, player in ipairs(host.Players:GetPlayers()) do
                        if player ~= host.LocalPlayer and selected:IsSelected(player.Name) then
                            local character = player.Character
                            local root = character and character:FindFirstChild("HumanoidRootPart")
                            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                            if root and humanoid and humanoid.Health > 0 then
                                local orbit = CFrame.fromOrientation(pitch,yaw,0)
                                position = root.Position - orbit.LookVector * 12 + Vector3.new(0,3,0)
                                spectating = true
                                break
                            end
                        end
                    end
                end
                local rotation = CFrame.fromOrientation(pitch,yaw,0)
                if not spectating and not input:GetFocusedTextBox() then
                    local move = Vector3.new((keys.Right and 1 or 0)-(keys.Left and 1 or 0)+stick.X,
                        (keys.Up and 1 or 0)-(keys.Down and 1 or 0), (keys.Back and 1 or 0)-(keys.Forward and 1 or 0)+stick.Y)
                    local direction = rotation:VectorToWorldSpace(Vector3.new(move.X,0,move.Z)) + Vector3.yAxis * move.Y
                    if direction.Magnitude > 1 then direction = direction.Unit end
                    local speed = card.Options.Speed.Value * (input:IsKeyDown(Enum.KeyCode.LeftShift) and 3 or 1)
                    position += direction * speed * math.clamp(dt,0,0.1)
                end
                camera.CameraType = Enum.CameraType.Scriptable
                camera.CFrame = CFrame.new(position) * rotation
                camera.Focus = camera.CFrame * CFrame.new(0,0,-16)
                writtenFrame, writtenFocus = camera.CFrame, camera.Focus
            end)
        end,
    })
    card:CreateSlider({Name="Speed", Min=1, Max=150, Default=48})
    card:CreateSlider({Name="Sensitivity", Min=0.05, Max=0.6, Default=0.2})
    card:CreateList({Name="Spectate Player",Items=function()
        local names = {}
        for _, player in ipairs(host.Players:GetPlayers()) do
            if player ~= host.LocalPlayer then table.insert(names,player.Name) end
        end
        table.sort(names);return names
    end,Tooltip="Select one player to follow while FreeCam is ON. Right-drag/touch rotates the view; deselect to fly freely.",Function=function(selected,names)
        local option = card.Options["Spectate Player"]
        local chosen = names[1]
        if #names > 1 then
            for _, name in ipairs(names) do if name ~= spectateTarget then chosen = name; break end end
        end
        spectateTarget = chosen
        if option then
            for _, name in ipairs(names) do if name ~= chosen then option:Set(name,false) end end
        end
    end})
    Module.Initialized = true
    return card
end
function Module.destroy()
    if card and card.Enabled then card:Toggle(false) end
    card = nil
    Module.Initialized = false
end
return Module
