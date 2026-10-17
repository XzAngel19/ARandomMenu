export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "ClickTeleport",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

local function characterRoot(localPlayer: Player): (BasePart?, Humanoid?)
    local character: Model? = localPlayer.Character
    if not character then
        return nil, nil
    end
    return character:FindFirstChild("HumanoidRootPart") :: BasePart?,
        character:FindFirstChildOfClass("Humanoid") :: Humanoid?
end

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local localPlayer: Player = host.LocalPlayer
    local userInput: UserInputService = host.UserInputService
    local menu: any = context.services.menu

    local runtime: any = {
        armedUntil = 0,
        point = nil :: string?,
        lastOrigin = nil :: Vector3?,
    }

    local teleport: any
    teleport = framework.Categories.Utilities:CreateModule({
        Name = "Teleport",
        ConfigKey = "Universal.ClickTeleport",
        Category = "Utilities",
        Order = 1,

        Kind = "action",
        Silent = true,
        Tooltip = "Press to travel to the destination selected below.",
        Function = function(): ()
            Module.run(context, teleport, runtime)
        end,
    })

    local destinations = {"Tap point", "Nearest player", "Named player", "Item", "Waypoint", "Last position"}
    if host.GAME_CHECK and host.GAME_CHECK.MM2Active then
        table.insert(destinations, 1, "MM2")
        local config = host.configData
        if config then
            local key = "Universal.ClickTeleport.Destination"
            if config.values[key] == nil or string.sub(tostring(config.values[key]), 1, 4) == "MM2 " then
                config.values[key] = "MM2"
            end
        end
    end
    teleport:CreateDropdown({Name = "Destination", List = destinations, Index = 1,
        Tooltip = "MM2 shows all game teleport buttons together. Other destinations use the main action.",
        Function = function(value)
            runtime.armedUntil = 0
            if runtime.cancelTravel then runtime.cancelTravel() end
            local mm2Controls = { ["Teleport to Map"] = true, ["Teleport to Lobby"] = true,
                ["Teleport to Player"] = true, ["Get Gun"] = true, ["Player name"] = true,
                ["Get Gun key"] = true, ["Auto Get Gun"] = true, ["Gun pickup delay"] = true }
            teleport.OptionFilter = function(name)
                if name == "Destination" then return true end
                return value == "MM2" and mm2Controls[name] == true or value ~= "MM2" and not mm2Controls[name]
            end
            teleport:RefreshVisibility()
        end})
    teleport:CreateTextBox({
        Name = "Player",
        Show = {Option = "Destination", Values = {"Named player"}},
        Default = "",
        Tooltip = "Part of a name or display name, for Named player.",
    })
    teleport:CreateTextBox({
        Name = "Item",
        Show = {Option = "Destination", Values = {"Item"}},
        Default = "",
        Tooltip = "Part or model name to look for, for Item. Partial names "
            .. "match, so \"chest\" finds \"GoldChest\".",
    })
    local pointList=teleport:CreateList({Name="Point",Single=true,
        Show={Option="Destination",Values={"Waypoint"}},
        EmptyText="No points. Save one in Markers.",Items=function()
            local points=context.services.points
            return points and points.Names() or {}
        end,Function=function(_,names) runtime.point=names[1] end,
        Tooltip="The same saved points as Markers. Choose one, then Teleport to point."})
    teleport:CreateButton({Name="Teleport to point",Show={Option="Destination",Values={"Waypoint"}},
        Function=function() Module.run(context,teleport,runtime) end})
    local unsubscribe
    if context.services.points then
        unsubscribe=context.services.points.Subscribe(function()
            if runtime.point and not context.services.points.Get(runtime.point) then
                if runtime.cancelTravel then runtime.cancelTravel() end
                pointList:Set(runtime.point,false)
            end
            pointList:Refresh()
        end)
    end
    teleport:CreateSlider({
        Name = "Arm window",
        Show = {Option = "Destination", Values = {"Tap point"}},
        Min = 1,
        Max = 15,
        Default = 6,
        Tooltip = "Seconds Tap point stays armed after the button is pressed.",
    })
    teleport:CreateSlider({
        Name = "Search range",
        Show = {Option = "Destination", Values = {"Nearest player", "Named player", "Item"}},
        Min = 50,
        Max = 5000,
        Default = 1500,
        Tooltip = "How far to look for items and players.",
    })
    teleport:CreateSlider({
        Name = "Player offset",
        Show = {Option = "Destination", Values = {"Nearest player", "Named player"}},
        Min = 0,
        Max = 20,
        Default = 4,
        Tooltip = "Studs to stop short of a player, so you do not land inside "
            .. "them.",
    })
    teleport:CreateToggle({
        Name = "Skip friends",
        Show = {Option = "Destination", Values = {"Nearest player"}},
        Default = false,
        Tooltip = "Nearest player ignores anyone on the Friend List.",
    })
    teleport:CreateDropdown({
        Name = "Movement",
        List = {"Instant", "Glide"},
        Index = 1,
        Tooltip = "Instant jumps to the destination. Glide moves continuously at Glide speed (studs/sec), regardless of frame rate. A new trip cancels the previous one.",
    })
    teleport:CreateSlider({
        Name = "Glide speed",
        Show = {Option = "Movement", Values = {"Glide"}},
        Min = 1,
        Max = 500,
        Default = 60,
        Tooltip = "Travel speed in studs per second, not distance per frame. Higher = faster.",
    })
    teleport:CreateSlider({
        Name = "Height offset",
        Min = 0,
        Max = 12,
        Default = 3,
        Tooltip = "Studs above whatever you land on.",
    })
    teleport:CreateToggle({
        Name = "Keep momentum",
        Default = false,
        Tooltip = "Leave your velocity alone on arrival instead of zeroing it.",
    })

    local tapConnection: RBXScriptConnection = userInput.InputBegan:Connect(
        function(input: InputObject, processed: boolean): ()
            if processed or os.clock() >= runtime.armedUntil then
                return
            end
            if menu.isCapturingInput() then
                return
            end
            local touched: boolean = input.UserInputType == Enum.UserInputType.Touch
            local clicked: boolean =
                input.UserInputType == Enum.UserInputType.MouseButton1
            if not touched and not clicked then
                return
            end
            runtime.armedUntil = 0
            Module.travel(
                context,
                teleport,
                runtime,
                Module.pointUnder(context, input.Position),
                true
            )
        end
    )

    activeCleanup = function(): ()
        pcall(function(): ()
            tapConnection:Disconnect()
        end)
        runtime.armedUntil = 0
        if runtime.cancelTravel then runtime.cancelTravel() end
        if unsubscribe then unsubscribe() end
    end
    Module.Initialized = true
    return teleport
end

function Module.pointUnder(context: Runtime, screenPosition: Vector3): Vector3?
    local host: any = context.host
    local currentWorkspace: Workspace = host.workspace or workspace
    local camera: Camera? = currentWorkspace.CurrentCamera
    if not camera then
        return nil
    end
    local resolvedCamera: Camera = camera :: Camera
    local ray: Ray = resolvedCamera:ScreenPointToRay(
        screenPosition.X,
        screenPosition.Y
    )
    local parameters: RaycastParams = RaycastParams.new()
    parameters.FilterType = Enum.RaycastFilterType.Exclude
    parameters.IgnoreWater = true
    parameters.FilterDescendantsInstances = {
        host.LocalPlayer.Character :: any,
        resolvedCamera,
    }
    local result: RaycastResult? = currentWorkspace:Raycast(
        ray.Origin,
        ray.Direction.Unit * 4096,
        parameters
    )
    return result and result.Position or nil
end

local function matchesName(candidate: string, query: string): boolean
    return string.find(string.lower(candidate), string.lower(query), 1, true) ~= nil
end

function Module.findItem(
    context: Runtime,
    query: string,
    origin: Vector3,
    range: number
): Vector3?
    local host: any = context.host
    local currentWorkspace: Workspace = host.workspace or workspace
    local best: Vector3? = nil
    local bestDistance: number = range
    local character: Model? = host.LocalPlayer.Character

    for _, descendant: Instance in ipairs(currentWorkspace:GetDescendants()) do
        if character and descendant:IsDescendantOf(character) then
            continue
        end
        if not matchesName(descendant.Name, query) then
            continue
        end
        local position: Vector3? = nil
        if descendant:IsA("BasePart") then
            position = (descendant :: BasePart).Position
        elseif descendant:IsA("Model") then
            local pivotOk: boolean, pivot: any = pcall(function(): CFrame
                return (descendant :: Model):GetPivot()
            end)
            if pivotOk then
                position = (pivot :: CFrame).Position
            end
        end
        if not position then
            continue
        end
        local distance: number = ((position :: Vector3) - origin).Magnitude
        if distance < bestDistance then
            best = position
            bestDistance = distance
        end
    end
    return best
end

function Module.run(context: Runtime, teleport: any, runtime: any): ()
    if runtime.cancelTravel then runtime.cancelTravel() end
    if teleport.Options.Destination.Value == "MM2" then
        teleport:Notify("Choose a MM2 teleport button below")
        return
    end
    local host: any = context.host
    local entityLibrary: any = context.entity
    local localPlayer: Player = host.LocalPlayer
    local options: any = teleport.Options
    local destination: string = options["Destination"].Value

    local root: BasePart? = characterRoot(localPlayer)
    if not root then
        teleport:Notify("no character")
        return
    end
    local origin: Vector3 = (root :: BasePart).Position
    local range: number = options["Search range"].Value

    if destination == "Tap point" then
        runtime.armedUntil = os.clock() + options["Arm window"].Value
        teleport:Notify("tap where you want to go")
        return
    end

    if destination == "Waypoint" then
        local points=context.services.points
        local position,surface
        if points and runtime.point then position,surface=points.Get(runtime.point) end
        if not position then teleport:Notify("Choose a saved point from Markers first.");return end
        Module.travel(context,teleport,runtime,position,surface==true)
        return
    end

    if destination == "Last position" then
        if not runtime.lastOrigin then
            teleport:Notify("nowhere to go back to")
            return
        end
        Module.travel(context, teleport, runtime, runtime.lastOrigin, false)
        return
    end

    if destination == "Item" then
        local query: string = tostring(options["Item"].Value or "")
        if query == "" then
            teleport:Notify("type an item name first")
            return
        end
        local found: Vector3? = Module.findItem(context, query, origin, range)
        if not found then
            teleport:Notify("no \"" .. query .. "\" within range")
            return
        end
        Module.travel(context, teleport, runtime, found, true)
        return
    end

    entityLibrary:Refresh()
    local target: any = nil
    if destination == "Nearest player" then
        local bestDistance: number = range
        for _, entity: any in ipairs(entityLibrary.List) do
            if options["Skip friends"].Value
                and entityLibrary:IsProtected(entity.Player) then
                continue
            end
            if entity.Distance < bestDistance then
                target = entity
                bestDistance = entity.Distance
            end
        end
    else
        local query: string = tostring(options["Player"].Value or "")
        if query == "" then
            teleport:Notify("type a player name first")
            return
        end
        for _, entity: any in ipairs(entityLibrary.List) do
            if matchesName(entity.Player.Name, query)
                or matchesName(entity.Player.DisplayName, query) then
                target = entity
                break
            end
        end
    end

    if not target then
        teleport:Notify("no matching player")
        return
    end

    local targetPosition: Vector3 = target.RootPart.Position
    local offset: number = options["Player offset"].Value
    local approach: Vector3 = targetPosition - origin
    if offset > 0 and approach.Magnitude > offset then
        targetPosition = targetPosition - approach.Unit * offset
    end
    Module.travel(context, teleport, runtime, targetPosition, false)
end

function Module.travel(
    context: Runtime,
    teleport: any,
    runtime: any,
    destination: Vector3?,
    liftToSurface: boolean
): ()
    local host: any = context.host
    local localPlayer: Player = host.LocalPlayer
    if runtime.cancelTravel then runtime.cancelTravel() end
    if not destination then
        teleport:Notify("nothing there")
        return
    end

    local root: BasePart?, humanoid: Humanoid? = characterRoot(localPlayer)
    if not root then
        return
    end
    local resolvedRoot: BasePart = root :: BasePart
    local options: any = teleport.Options

    runtime.lastOrigin = resolvedRoot.Position

    local target: Vector3 = destination :: Vector3
    if liftToSurface then

        local hipHeight: number = humanoid and (humanoid :: Humanoid).HipHeight or 2
        target = target
            + Vector3.new(0, hipHeight + options["Height offset"].Value, 0)
    end

    local keepMomentum: boolean = options["Keep momentum"].Value
    if options["Movement"].Value == "Instant" then
        resolvedRoot.CFrame = resolvedRoot.CFrame + (target - resolvedRoot.Position)
        if not keepMomentum then
            resolvedRoot.AssemblyLinearVelocity = Vector3.zero
            resolvedRoot.AssemblyAngularVelocity = Vector3.zero
        end
        return
    end

    local speed=math.max(0,options["Glide speed"].Value)
    if speed==0 then teleport:Notify("Glide speed must be greater than zero.");return end
    local character=localPlayer.Character
    local connection
    local function finish()
        if connection then connection:Disconnect();connection=nil end
        runtime.cancelTravel=nil
        if context.services.activity then context.services.activity.set("teleport",false) end
        teleport:SetStatus(nil)
    end
    if runtime.cancelTravel then runtime.cancelTravel() end
    runtime.cancelTravel=finish
    if context.services.activity then context.services.activity.set("teleport",true) end
    teleport:SetStatus("Gliding")
    connection=host.RunService.Heartbeat:Connect(function(dt)
        if localPlayer.Character~=character or not resolvedRoot.Parent
            or characterRoot(localPlayer)~=resolvedRoot or humanoid and humanoid.Health<=0 then finish();return end
        local offset=target-resolvedRoot.Position
        local distance=offset.Magnitude
        local amount=math.min(distance,speed*math.clamp(dt,0,0.1))
        if distance<=amount+0.001 then
            resolvedRoot.CFrame=resolvedRoot.CFrame+(target-resolvedRoot.Position)
            if not keepMomentum then resolvedRoot.AssemblyLinearVelocity=Vector3.zero;resolvedRoot.AssemblyAngularVelocity=Vector3.zero end
            finish();return
        end
        if distance>0 then resolvedRoot.CFrame+=offset.Unit*amount end
        if not keepMomentum then resolvedRoot.AssemblyLinearVelocity=Vector3.zero;resolvedRoot.AssemblyAngularVelocity=Vector3.zero end
    end)
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
