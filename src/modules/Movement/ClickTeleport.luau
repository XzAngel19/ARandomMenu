--!strict
--
-- Click Teleport.
--
-- A button, not a switch: pick a destination in the panel, then press the card
-- (or its key, or its placed mobile button) and you are there. The previous
-- version was a toggle that only ever did one thing — teleport to whatever the
-- camera was pointing at — and it did that wrong, because it raycast with
-- `Camera:ViewportPointToRay(input.Position)`. Input positions include the
-- 36-pixel top bar and viewport points do not, so every teleport landed above
-- the finger; on touch it usually hit nothing at all and the module looked
-- dead. `ScreenPointToRay` is the one that takes input coordinates.
--
-- Destinations:
--   Tap point       arms the module; the next tap on the world is where you go.
--   Nearest player  closest living player, friends excluded.
--   Named player    partial name or display name match.
--   Item            nearest part or model in the workspace whose name matches.
--   Waypoint        wherever you last pressed "Save waypoint".
--   Last position   undo: back to where the previous teleport started.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
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
    local state: any = host.state

    local runtime: any = {
        armedUntil = 0,
        waypoint = nil :: Vector3?,
        lastOrigin = nil :: Vector3?,
    }

    local teleport: any
    teleport = framework.Categories.Movement:CreateModule({
        Name = "Click Teleport",
        Category = "Movement",
        Order = 1,
        -- An action card: pressing it does the thing, once. There is no state
        -- to leave switched on by accident.
        Kind = "action",
        Silent = true,
        Tooltip = "Press to travel to the destination selected below.",
        Function = function(): ()
            Module.run(context, teleport, runtime)
        end,
    })

    teleport:CreateSection("Destination")
    teleport:CreateDropdown({
        Name = "Destination",
        List = {
            "Tap point",
            "Nearest player",
            "Named player",
            "Item",
            "Waypoint",
            "Last position",
        },
        Index = 1,
        Tooltip = "What the button travels to.",
    })
    teleport:CreateTextBox({
        Name = "Player",
        Default = "",
        Tooltip = "Part of a name or display name, for Named player.",
    })
    teleport:CreateTextBox({
        Name = "Item",
        Default = "",
        Tooltip = "Part or model name to look for, for Item. Partial names "
            .. "match, so \"chest\" finds \"GoldChest\".",
    })
    teleport:CreateButton({
        Name = "Save waypoint",
        Tooltip = "Stores where you are standing right now.",
        Function = function(): ()
            local root: BasePart? = characterRoot(localPlayer)
            if not root then
                return
            end
            runtime.waypoint = (root :: BasePart).Position
            teleport:Notify("waypoint saved")
        end,
    })
    teleport:CreateButton({
        Name = "Go back",
        Tooltip = "Returns to where the last teleport started.",
        Function = function(): ()
            if not runtime.lastOrigin then
                teleport:Notify("nowhere to go back to")
                return
            end
            Module.travel(context, teleport, runtime, runtime.lastOrigin, false)
        end,
    })

    local advanced: {any} = {}
    table.insert(advanced, teleport:CreateSection("Travel"))
    table.insert(advanced, teleport:CreateDropdown({
        Name = "Movement",
        List = {"Instant", "Glide"},
        Index = 1,
        Tooltip = "Glide steps the character across, which some games accept "
            .. "when a single jump is rejected.",
    }))
    table.insert(advanced, teleport:CreateSlider({
        Name = "Glide step",
        Min = 4,
        Max = 60,
        Default = 18,
    }))
    table.insert(advanced, teleport:CreateSlider({
        Name = "Height offset",
        Min = 0,
        Max = 12,
        Default = 3,
        Tooltip = "Studs above whatever you land on.",
    }))
    table.insert(advanced, teleport:CreateSlider({
        Name = "Player offset",
        Min = 0,
        Max = 20,
        Default = 4,
        Tooltip = "Studs to stop short of a player, so you do not land inside "
            .. "them.",
    }))
    table.insert(advanced, teleport:CreateSlider({
        Name = "Search range",
        Min = 50,
        Max = 5000,
        Default = 1500,
        Tooltip = "How far to look for items and players.",
    }))
    table.insert(advanced, teleport:CreateSlider({
        Name = "Arm window",
        Min = 1,
        Max = 15,
        Default = 6,
        Tooltip = "Seconds Tap point stays armed after the button is pressed.",
    }))
    table.insert(advanced, teleport:CreateToggle({
        Name = "Keep momentum",
        Default = false,
        Tooltip = "Leave your velocity alone on arrival instead of zeroing it.",
    }))
    table.insert(advanced, teleport:CreateToggle({
        Name = "Skip friends",
        Default = false,
        Tooltip = "Nearest player ignores anyone on the Friend List.",
    }))
    teleport:CreateToggle({
        Name = "Show travel options",
        Default = false,
        Function = function(value: boolean): ()
            for _, option: any in ipairs(advanced) do
                option:SetVisible(value)
            end
        end,
    })

    -- The tap listener lives for as long as the module exists: an action card
    -- has no "on" state to hang a connection off, and the listener does
    -- nothing at all unless the button armed it.
    local tapConnection: RBXScriptConnection = userInput.InputBegan:Connect(
        function(input: InputObject, processed: boolean): ()
            if processed or os.clock() >= runtime.armedUntil then
                return
            end
            if state.keyCaptureCallback or state.waitingForKey then
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
    end
    Module.Initialized = true
    return teleport
end

-- Where a tap landed, in the world.
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

-- Nearest thing in the workspace whose name contains the query. Models are
-- accepted through their pivot, because a chest or a vehicle is a model and
-- teleporting to one of its planks is not the same place.
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
        if not runtime.waypoint then
            teleport:Notify("no waypoint saved")
            return
        end
        Module.travel(context, teleport, runtime, runtime.waypoint, false)
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

    -- The two player destinations share their arrival maths: stop short of the
    -- target along the line you approached from.
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

    -- Remembered before the move, so "Go back" always undoes exactly one hop.
    runtime.lastOrigin = resolvedRoot.Position

    local target: Vector3 = destination :: Vector3
    if liftToSurface then
        -- A raycast hit is a point on the floor: standing there means standing
        -- inside it.
        local hipHeight: number = humanoid and (humanoid :: Humanoid).HipHeight or 2
        target = target
            + Vector3.new(0, hipHeight + options["Height offset"].Value, 0)
    end

    local keepMomentum: boolean = options["Keep momentum"].Value
    if options["Movement"].Value == "Instant" then
        resolvedRoot.CFrame = CFrame.new(target)
        if not keepMomentum then
            resolvedRoot.AssemblyLinearVelocity = Vector3.zero
        end
        return
    end

    local step: number = options["Glide step"].Value
    task.spawn(function(): ()
        for _ = 1, 360 do
            if not resolvedRoot.Parent then
                return
            end
            local offset: Vector3 = target - resolvedRoot.Position
            if offset.Magnitude < 3 then
                resolvedRoot.CFrame = CFrame.new(target)
                if not keepMomentum then
                    resolvedRoot.AssemblyLinearVelocity = Vector3.zero
                end
                return
            end
            resolvedRoot.CFrame = resolvedRoot.CFrame
                + offset.Unit * math.min(offset.Magnitude, step)
            if not keepMomentum then
                resolvedRoot.AssemblyLinearVelocity = Vector3.zero
            end
            task.wait()
        end
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
