--!strict
--
-- Targeting library.
--
-- Target selection is deliberately pure from a module's point of view: it
-- reads the entity index and camera, applies the same team/friend/visibility
-- policy to every caller, and returns a player or NPC record. It never moves
-- the camera, fires a tool, edits a remote or installs a hook. Aim Assist uses
-- the result;
-- a future supported-game adapter can use the same result without sharing any
-- of the side effects.

export type Query = {
    FOV: number?,
    MaxDistance: number?,
    TargetPart: string?,
    Prediction: number?,
    TeamCheck: boolean?,
    VisibilityCheck: boolean?,
    Priority: string?,
    IncludeNPCs: boolean?,
    AllowOffscreen: boolean?,
}

export type Target = {
    player: Player?,
    entity: any,
    character: Model,
    part: BasePart,
    position: Vector3,
    screenPosition: Vector2,
    distance: number,
    cursorDistance: number,
}

export type Library = {
    List: (self: Library, entities: any, query: Query?) -> {Target},
    Select: (self: Library, entities: any, query: Query?) -> Target?,
    Destroy: (self: Library) -> (),
}

local Module = {
    Name = "Targeting",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeLibrary: Library? = nil

local function asBasePart(instance: Instance?): BasePart?
    if instance and instance:IsA("BasePart") then
        return instance :: BasePart
    end
    return nil
end

function Module.init(context: any): Library
    local host: any = context.host or context
    local userInput: UserInputService? = host.UserInputService
    local currentWorkspace: Workspace = host.workspace or workspace
    local localPlayer: Player? = host.LocalPlayer
    local services: any = context.services or host.services

    local library: any = {}

    local function camera(): Camera?
        return currentWorkspace.CurrentCamera
    end

    local function cursor(cameraObject: Camera): Vector2
        if userInput and userInput.MouseEnabled then
            local ok: boolean, location: any = pcall(
                (userInput :: UserInputService).GetMouseLocation,
                userInput
            )
            if ok and typeof(location) == "Vector2" then
                return location :: Vector2
            end
        end
        local viewport: Vector2 = cameraObject.ViewportSize
        return Vector2.new(viewport.X / 2, viewport.Y / 2)
    end

    local function targetParts(entity: any, requested: string?): {BasePart}
        local character: Model = entity.Character
        local wanted: string = requested or "Closest"
        if wanted == "Head" then
            return {
                asBasePart(character:FindFirstChild("Head")) or entity.RootPart,
            }
        end
        if wanted == "Torso" then
            return {
                asBasePart(character:FindFirstChild("UpperTorso"))
                    or asBasePart(character:FindFirstChild("Torso"))
                    or entity.RootPart,
            }
        end
        if wanted ~= "Closest" then
            return {entity.RootPart}
        end
        local head: BasePart? = asBasePart(character:FindFirstChild("Head"))
        if head then
            return {head, entity.RootPart}
        end
        return {entity.RootPart}
    end

    local function protected(player: Player?): boolean
        if not player then
            return false
        end
        local policy: any = services and services.protectedTargets
        if policy and type(policy.isProtected) == "function" then
            return policy.isProtected(player) == true
        end
        return false
    end

    local function visibleFrom(
        cameraObject: Camera,
        entity: any,
        position: Vector3
    ): boolean
        local origin: Vector3 = cameraObject.CFrame.Position
        local parameters: RaycastParams = RaycastParams.new()
        parameters.FilterType = Enum.RaycastFilterType.Exclude
        local ignored: {Instance} = {entity.Character, cameraObject}
        if localPlayer and localPlayer.Character then
            table.insert(ignored, localPlayer.Character)
        end
        parameters.FilterDescendantsInstances = ignored
        parameters.IgnoreWater = true
        local ok: boolean, result: any = pcall(
            currentWorkspace.Raycast,
            currentWorkspace,
            origin,
            position - origin,
            parameters
        )
        return ok and result == nil
    end

    local function candidateForPart(
        cameraObject: Camera,
        pointer: Vector2,
        entity: any,
        part: BasePart,
        prediction: number,
        query: Query
    ): Target?
        local velocity: Vector3 = part.AssemblyLinearVelocity or Vector3.zero
        local predicted: Vector3 = part.Position + velocity * prediction
        local projected: Vector3, onScreen: boolean =
            cameraObject:WorldToViewportPoint(predicted)
        if (not onScreen or projected.Z <= 0) and not query.AllowOffscreen then
            return nil
        end
        local screenPosition: Vector2 = Vector2.new(projected.X, projected.Y)
        local cursorDistance: number = onScreen
                and (screenPosition - pointer).Magnitude
            or math.huge
        if query.FOV ~= nil and cursorDistance > (query.FOV :: number) then
            return nil
        end
        if query.VisibilityCheck == true
            and not visibleFrom(cameraObject, entity, predicted) then
            return nil
        end
        return {
            player = entity.Player,
            entity = entity,
            character = entity.Character,
            part = part,
            position = predicted,
            screenPosition = screenPosition,
            distance = entity.Distance,
            cursorDistance = cursorDistance,
        }
    end

    function library:List(entities: any, query: Query?): {Target}
        local options: Query = query or {}
        local cameraObject: Camera? = camera()
        if not cameraObject or not entities then
            return {}
        end
        if type(entities.Refresh) == "function" then
            entities:Refresh()
        end
        local pointer: Vector2 = cursor(cameraObject :: Camera)
        local found: {Target} = {}
        local maxDistance: number = options.MaxDistance or math.huge
        local prediction: number = math.max(options.Prediction or 0, 0)

        local function consider(entity: any): ()
            if entity.Distance > maxDistance then
                return
            end
            if options.TeamCheck ~= false and entity.IsFriendly then
                return
            end
            if protected(entity.Player) then
                return
            end

            local bestForEntity: Target? = nil
            for _, part: BasePart in ipairs(targetParts(entity, options.TargetPart)) do
                local candidate: Target? = candidateForPart(
                    cameraObject :: Camera,
                    pointer,
                    entity,
                    part,
                    prediction,
                    options
                )
                if candidate
                    and (not bestForEntity
                        or candidate.cursorDistance < (bestForEntity :: Target).cursorDistance) then
                    bestForEntity = candidate
                end
            end
            if bestForEntity then
                table.insert(found, bestForEntity :: Target)
            end
        end
        for _, entity: any in ipairs(entities.List or {}) do
            consider(entity)
        end
        if options.IncludeNPCs then
            for _, entity: any in ipairs(entities.NPCList or {}) do
                consider(entity)
            end
        end

        local priority: string = options.Priority or "Cursor"
        table.sort(found, function(first: Target, second: Target): boolean
            if priority == "Distance" then
                if first.distance == second.distance then
                    return first.cursorDistance < second.cursorDistance
                end
                return first.distance < second.distance
            end
            if first.cursorDistance == second.cursorDistance then
                return first.distance < second.distance
            end
            return first.cursorDistance < second.cursorDistance
        end)
        return found
    end

    function library:Select(entities: any, query: Query?): Target?
        return self:List(entities, query)[1]
    end

    function library:Destroy(): ()
        if activeLibrary == library then
            activeLibrary = nil
        end
    end

    activeLibrary = (library :: any) :: Library
    Module.Initialized = true
    return (library :: any) :: Library
end

function Module.destroy(): ()
    local library: Library? = activeLibrary
    if library then
        library:Destroy()
    end
    activeLibrary = nil
    Module.Initialized = false
end

return Module
