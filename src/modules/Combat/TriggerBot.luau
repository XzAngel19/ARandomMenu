--!strict
--
-- TriggerBot.
--
-- Fires whatever the character is holding the moment a valid target crosses
-- the crosshair. The interesting part of a trigger bot is not the firing, it is
-- everything that decides *not* to fire: teammates, corpses, players behind a
-- wall, targets outside the weapon's useful range, and the human-looking pause
-- between seeing a target and pulling the trigger.
--
-- Firing paths, in order of preference:
--   1. `Tool:Activate()` — what a click does through the engine.
--   2. `mouse1click()` — executor level, for tools that only listen to the
--      real mouse button.
-- Both are attempted, so a game that ignores one still gets the other.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "TriggerBot",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

local function findTool(character: Model?): Tool?
    if not character then
        return nil
    end
    return character:FindFirstChildOfClass("Tool")
end

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local localPlayer: Player = host.LocalPlayer
    local userInput: UserInputService = host.UserInputService

    -- Per-target arming: the delay restarts whenever the crosshair moves onto
    -- a different player, which is what stops a sweep across a crowd from
    -- emptying a magazine.
    local armedTarget: Player? = nil
    local armedAt: number = 0
    local nextShotAt: number = 0

    local trigger: any
    trigger = framework.Categories.Combat:CreateModule({
        Name = "TriggerBot",
        Category = "Combat",
        Order = 1,
        Tooltip = "Fires the equipped tool when a valid target is under the "
            .. "crosshair.",
        Function = function(enabled: boolean): ()
            armedTarget = nil
            armedAt = 0
            nextShotAt = 0
            if not enabled then
                return
            end

            trigger:Loop(function(): ()
                local options: any = trigger.Options
                if options["Activation"].Value == "Hold key"
                    and not userInput:IsKeyDown(options["Hold key"].Value) then
                    armedTarget = nil
                    return
                end

                local character: Model? = localPlayer.Character
                local humanoid: Humanoid? = character
                    and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
                if not character or not humanoid or humanoid.Health <= 0 then
                    armedTarget = nil
                    return
                end

                local tool: Tool? = findTool(character)
                if options["Require tool"].Value and not tool then
                    armedTarget = nil
                    return
                end

                local target: Player?, distance: number =
                    Module.resolveTarget(context, trigger)
                if not target then
                    armedTarget = nil
                    return
                end
                if distance > options["Max distance"].Value then
                    armedTarget = nil
                    return
                end

                local now: number = os.clock()
                if armedTarget ~= target then
                    armedTarget = target
                    -- Reaction time plus a per-target jitter, so consecutive
                    -- shots never share the same interval.
                    armedAt = now
                        + options["Delay"].Value
                        + math.random() * options["Delay jitter"].Value
                    return
                end
                if now < armedAt or now < nextShotAt then
                    return
                end

                Module.fire(tool)
                if options["Fire mode"].Value == "Single" then
                    -- One shot per acquisition: the target has to leave the
                    -- crosshair and come back.
                    armedTarget = nil
                    nextShotAt = now + math.max(options["Fire rate"].Value, 0.05)
                else
                    nextShotAt = now + math.max(options["Fire rate"].Value, 0.05)
                end
            end)
        end,
    })

    trigger:CreateSection("Trigger")
    trigger:CreateDropdown({
        Name = "Activation",
        List = {"Always", "Hold key"},
        Index = 1,
        Tooltip = "Always runs while the module is on; Hold key only while "
            .. "the bind is down.",
    })
    trigger:CreateBind({
        Name = "Hold key",
        Default = Enum.KeyCode.Unknown,
        Tooltip = "Used when Activation is Hold key.",
    })
    trigger:CreateDropdown({
        Name = "Fire mode",
        List = {"Single", "Automatic"},
        Index = 1,
        Tooltip = "Single fires once per acquisition, Automatic keeps firing.",
    })
    trigger:CreateSlider({
        Name = "Delay",
        Min = 0,
        Max = 1,
        Default = 0.08,
        Tooltip = "Seconds between acquiring a target and firing.",
    })
    trigger:CreateSlider({
        Name = "Delay jitter",
        Min = 0,
        Max = 0.5,
        Default = 0.04,
        Tooltip = "Random amount added to the delay on every acquisition.",
    })
    trigger:CreateSlider({
        Name = "Fire rate",
        Min = 0.05,
        Max = 2,
        Default = 0.15,
        Tooltip = "Minimum seconds between two shots.",
    })

    trigger:CreateSection("Targeting")
    trigger:CreateDropdown({
        Name = "Target part",
        List = {"Any", "Head", "Torso"},
        Index = 1,
        Tooltip = "Which part has to be under the crosshair.",
    })
    trigger:CreateSlider({
        Name = "Aim radius",
        Min = 0,
        Max = 120,
        Default = 0,
        Tooltip = "Pixels of tolerance around the crosshair. 0 requires an "
            .. "exact hit on the target.",
    })
    trigger:CreateSlider({
        Name = "Max distance",
        Min = 10,
        Max = 2000,
        Default = 600,
    })
    trigger:CreateToggle({
        Name = "Team check",
        Default = true,
        Tooltip = "Never fire at players on your own team.",
    })
    trigger:CreateToggle({
        Name = "Wall check",
        Default = true,
        Tooltip = "Never fire at a target with geometry in the way.",
    })
    trigger:CreateToggle({
        Name = "Require tool",
        Default = true,
        Tooltip = "Only run while something is equipped.",
    })

    activeCleanup = function(): ()
        armedTarget = nil
    end
    Module.Initialized = true
    return trigger
end

-- Two ways of deciding what is under the crosshair, because they fail on
-- different games: a raycast is exact but misses tools with custom hitboxes,
-- and a screen-space radius catches those but needs a tolerance.
function Module.resolveTarget(context: Runtime, trigger: any): (Player?, number)
    local host: any = context.host
    local entityLibrary: any = context.entity
    local players: Players = host.Players
    local localPlayer: Player = host.LocalPlayer
    local currentWorkspace: Workspace = host.workspace or workspace
    local options: any = trigger.Options

    local ray: Ray? = host.state.getAimRay()
    if not ray then
        return nil, 0
    end
    local resolvedRay: Ray = ray :: Ray

    local partFilter: string = options["Target part"].Value
    local radius: number = options["Aim radius"].Value

    if radius <= 0 then
        local parameters: RaycastParams = RaycastParams.new()
        parameters.FilterType = Enum.RaycastFilterType.Exclude
        parameters.IgnoreWater = true
        parameters.FilterDescendantsInstances = {
            localPlayer.Character :: any,
            currentWorkspace.CurrentCamera :: any,
        }
        local result: RaycastResult? = currentWorkspace:Raycast(
            resolvedRay.Origin,
            resolvedRay.Direction.Unit * options["Max distance"].Value,
            parameters
        )
        if not result then
            return nil, 0
        end
        local hit: BasePart = result.Instance
        local character: Model? = hit:FindFirstAncestorOfClass("Model")
        if not character then
            return nil, 0
        end
        local player: Player? = players:GetPlayerFromCharacter(character)
        if not player then
            return nil, 0
        end
        local entity: any = entityLibrary:Get(player)
        if not entity then
            return nil, 0
        end
        if options["Team check"].Value and entity.IsFriendly then
            return nil, 0
        end
        if partFilter == "Head" and hit.Name ~= "Head" then
            return nil, 0
        end
        if partFilter == "Torso"
            and hit.Name ~= "UpperTorso"
            and hit.Name ~= "LowerTorso"
            and hit.Name ~= "Torso"
            and hit.Name ~= "HumanoidRootPart" then
            return nil, 0
        end
        return player, entity.Distance
    end

    entityLibrary:Refresh()
    local entity: any = entityLibrary:ClosestToRay(
        resolvedRay.Origin,
        resolvedRay.Direction,
        {
            -- The radius is given in pixels; converting it to studs at the
            -- target's own distance keeps the tolerance constant on screen
            -- instead of growing with range.
            Radius = radius * 0.05,
            MaxDistance = options["Max distance"].Value,
            IgnoreTeam = not options["Team check"].Value,
            IgnoreWalls = not options["Wall check"].Value,
            Part = partFilter == "Head" and "Head" or nil,
        }
    )
    if not entity then
        return nil, 0
    end
    return entity.Player, entity.Distance
end

function Module.fire(tool: Tool?): ()
    if tool then
        pcall(function(): ()
            tool:Activate()
        end)
    end
    local environment: any = getfenv()
    local click: any = environment.mouse1click
    if type(click) == "function" then
        pcall(click)
    end
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
