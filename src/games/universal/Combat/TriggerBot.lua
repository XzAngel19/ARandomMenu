export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "TriggerBot",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCard: any = nil
local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local localPlayer: Player = host.LocalPlayer
    local playersService: Players = host.Players
    local currentWorkspace: Workspace = host.workspace or workspace
    local protectedTargets: any = context.services.protectedTargets
    local teamCheck: any = host.state and host.state.teamCheck

    local nextShotAt: number = 0

    local function pressMouseButton(): ()
        local environment: any = getfenv()
        local press: any = environment.mouse1press
        local release: any = environment.mouse1release
        if type(press) == "function" and type(release) == "function" then
            pcall(press)
            pcall(release)
            return
        end
        local ok: boolean, virtualInput: any = pcall(function(): any
            return game:GetService("VirtualInputManager")
        end)
        if not ok or type(virtualInput) ~= "table" then
            return
        end
        local camera: Camera? = currentWorkspace.CurrentCamera
        local viewport: Vector2 = camera
            and camera.ViewportSize
            or Vector2.new(0, 0)
        local x: number = viewport.X / 2
        local y: number = viewport.Y / 2
        pcall(function(): ()
            (virtualInput :: any):SendMouseButtonEvent(x, y, 0, true, game, 0)
        end)
        pcall(function(): ()
            (virtualInput :: any):SendMouseButtonEvent(x, y, 0, false, game, 0)
        end)
    end

    local function characterOf(part: BasePart): Model?
        local current: Instance? = part
        while current and current ~= currentWorkspace do
            if current:IsA("Model") then
                local humanoid: Humanoid? =
                    (current :: Model):FindFirstChildOfClass("Humanoid")
                    :: Humanoid?
                if humanoid then
                    return current :: Model
                end
            end
            current = current.Parent
        end
        return nil
    end

    local trigger: any = nil

    trigger = framework.Categories.Combat:CreateModule({
        Name = "TriggerBot",
        Category = "Combat",
        ConfigKey = "Universal.TriggerBot",
        Order = 2,
        Tooltip = "Fires your weapon the instant the crosshair rests on a "
            .. "valid enemy. Uses the always-on team check.",
        Function = function(enabled: boolean): ()
            if not enabled then
                trigger:SetStatus(nil)
                return
            end
            nextShotAt = 0
            trigger:SetStatus("armed")

            trigger:Render(function(): ()
                local camera: Camera? = currentWorkspace.CurrentCamera
                if not camera then
                    return
                end
                local now: number = os.clock()
                if now < nextShotAt then
                    return
                end

                local options: any = trigger.Options
                local range: number = options["Range"].Value
                local viewport: Vector2 = camera.ViewportSize
                local ray: Ray = camera:ViewportPointToRay(
                    viewport.X / 2,
                    viewport.Y / 2
                )
                local parameters: RaycastParams = RaycastParams.new()
                parameters.FilterType = Enum.RaycastFilterType.Exclude
                parameters.IgnoreWater = true
                local exclude: {Instance} = {}
                if localPlayer.Character then
                    table.insert(exclude, localPlayer.Character :: Instance)
                end
                parameters.FilterDescendantsInstances = exclude

                local hit: RaycastResult? = currentWorkspace:Raycast(
                    ray.Origin,
                    ray.Direction * range,
                    parameters
                )
                if not hit then
                    trigger:SetStatus("armed")
                    return
                end
                local character: Model? = characterOf((hit :: RaycastResult).Instance :: BasePart)
                if not character then
                    trigger:SetStatus("armed")
                    return
                end
                local player: Player? =
                    playersService:GetPlayerFromCharacter(character :: Model)
                if not player or player == localPlayer then
                    trigger:SetStatus("armed")
                    return
                end
                local humanoid: Humanoid? =
                    (character :: Model):FindFirstChildOfClass("Humanoid")
                    :: Humanoid?
                if not humanoid or (humanoid :: Humanoid).Health <= 0 then
                    return
                end
                if protectedTargets and protectedTargets.isProtected(player) then
                    return
                end

                -- X2 owns one shared native path per weapon instead of
                -- registering a second TriggerBot card/loop.
                local x2Core: any = host.state and host.state.x2duelsCore
                if x2Core and type(x2Core.isEnemy) == "function"
                    and type(x2Core.fireGun) == "function"
                    and type(x2Core.fireKnife) == "function" then
                    if not x2Core.isEnemy(player, options["Teammates"].Value) then
                        trigger:SetStatus("not opponent")
                        return
                    end
                    local tool: Tool? = x2Core.equippedTool()
                    local kind: string? = x2Core.toolKind(tool)
                    if kind ~= "Gun" and kind ~= "Knife" then
                        trigger:SetStatus("equip gun/knife")
                        return
                    end
                    local target: any = x2Core.targetFor(player)
                    if not target then
                        trigger:SetStatus("no target")
                        return
                    end
                    nextShotAt = now + options["Delay"].Value
                    local fired: boolean = false
                    if kind == "Gun" then
                        fired = x2Core.fireGun(target)
                    else
                        fired = x2Core.fireKnife(target)
                    end
                    trigger:SetStatus(
                        fired and (kind == "Knife" and "throw queued" or "fired gun")
                            or "cooldown"
                    )
                    return
                end

                -- Advanced team check (always on): never fire at a teammate.
                if not options["Teammates"].Value then
                    local friendly: boolean = false
                    if teamCheck and type(teamCheck.isSameTeam) == "function" then
                        friendly = teamCheck.isSameTeam(player)
                    end
                    if friendly then
                        trigger:SetStatus("teammate")
                        return
                    end
                end

                nextShotAt = now + options["Delay"].Value
                pressMouseButton()
                trigger:SetStatus("fired")
            end)
        end,
    })

    trigger:CreateSlider({
        Name = "Range",
        Min = 25,
        Max = 2000,
        Step = 25,
        Default = 500,
        Tooltip = "How far the crosshair ray searches for a target.",
    })
    trigger:CreateSlider({
        Name = "Delay",
        Min = 0.05,
        Max = 1,
        Step = 0.05,
        Default = 0.15,
        Tooltip = "Seconds between automatic shots.",
    })
    trigger:CreateToggle({
        Name = "Teammates",
        Default = false,
        Tooltip = "Also fire at teammates. The advanced team check protects "
            .. "them while this is off.",
    })
    trigger:CreateNote(
        "Fires when the crosshair is over an enemy; it never aims for you. "
            .. "X2 Duels uses native Gun/Knife Tool activation. Other games "
            .. "use mouse1press or VirtualInputManager as before."
    )

    activeCard = trigger
    activeCleanup = function(): () end
    Module.Initialized = true
    return trigger
end

function Module.destroy(): ()
    if activeCard and activeCard.Enabled then
        pcall(function(): ()
            activeCard:Toggle(false)
        end)
    end
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    activeCard = nil
    Module.Initialized = false
end

return Module
