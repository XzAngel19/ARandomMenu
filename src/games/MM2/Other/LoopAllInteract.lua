local Module = {
    Name = "MM2 Loop All Interact",
    PlaceId = 142823291,
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}

local activeCleanup: () -> () = function(): () end

function Module.init(runtime: any): any
    if Module.Initialized then
        return Module
    end
    local core: any = state.mm2Core
    assert(type(core) == "table", "MM2 Loop All Interact requires the MM2 core module")
    Module.Runtime = runtime
    local findMM2Map: any = core.findMM2Map

    local function toggleLoopAllInteract(enabled)
        disconnectFeatureConnection("MM2LoopInteract")
        if not enabled then
            return
        end

        local activeMap = nil
        local interactables = {}
        local elapsed = 0
        featureConnections.MM2LoopInteract = TaskManager:Connect(function(deltaTime)
            elapsed = elapsed + deltaTime
            if elapsed < 0.5 then
                return
            end
            elapsed = 0

            local map = findMM2Map()
            if map ~= activeMap then
                activeMap = map
                interactables = {}
                if map then
                    for _, object in ipairs(map:GetDescendants()) do
                        if object:IsA("ProximityPrompt")
                            or object:IsA("ClickDetector") then
                            table.insert(interactables, object)
                        end
                    end
                end
            end

            for _, object in ipairs(interactables) do
                if object:IsDescendantOf(activeMap) then
                    if object:IsA("ProximityPrompt")
                        and object.Enabled
                        and type(fireproximityprompt) == "function" then
                        pcall(fireproximityprompt, object)
                    elseif object:IsA("ClickDetector")
                        and type(fireclickdetector) == "function" then
                        pcall(fireclickdetector, object)
                    end
                end
            end
        end)
    end

    createUniversalFeature(
        "Loop All Interact",
        "Continuously activate prompts and click detectors",
        7,
        toggleLoopAllInteract,
        {
            noOptions = true,
            categoryName = "Other",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )

    activeCleanup = function(): ()
        toggleLoopAllInteract(false)
    end
    Module.Events = featureConnections
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    if not Module.Initialized then
        return
    end
    Module.Initialized = false
    pcall(activeCleanup)
    activeCleanup = function(): () end
    Module.Events = {}
    Module.Runtime = nil
end

return Module
