local Module = {
    Name = "MM2 Hide Names",
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
    assert(type(core) == "table", "MM2 Hide Names requires the MM2 core module")
    Module.Runtime = runtime

    local hiddenNameLabels = setmetatable({}, {__mode = "k"})
    local function toggleHideNames(enabled)
        disconnectFeatureConnection("MM2HideNames")
        if not enabled then
            for label, originalText in pairs(hiddenNameLabels) do
                if label and label.Parent and label.Text == "Anon" then
                    label.Text = originalText
                end
            end
            hiddenNameLabels = setmetatable({}, {__mode = "k"})
            return
        end

        local elapsed = 1
        featureConnections.MM2HideNames = TaskManager:Connect(function(deltaTime)
            elapsed = elapsed + deltaTime
            if elapsed < 0.25 then
                return
            end
            elapsed = 0

            local names = {}
            for _, player in ipairs(Players:GetPlayers()) do
                names[player.Name] = true
                names[player.DisplayName] = true
                names["@" .. player.Name] = true
                names[player.DisplayName .. " (@" .. player.Name .. ")"] = true
            end
            local roots = {}
            local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if playerGui then
                table.insert(roots, playerGui)
            end
            pcall(function()
                local robloxGui = game:GetService("CoreGui"):FindFirstChild("RobloxGui")
                local playerList = robloxGui
                    and robloxGui:FindFirstChild("PlayerList", true)
                if playerList then
                    table.insert(roots, playerList)
                end
            end)

            for _, root in ipairs(roots) do
                for _, object in ipairs(root:GetDescendants()) do
                    if (object:IsA("TextLabel") or object:IsA("TextButton"))
                        and names[object.Text] then
                        if hiddenNameLabels[object] == nil then
                            hiddenNameLabels[object] = object.Text
                        end
                        object.Text = "Anon"
                    end
                end
            end
        end)
    end

    createUniversalFeature(
        "Hide Names",
        "Replace player names in local UI and leaderboards with Anon",
        18,
        toggleHideNames,
        {
            noOptions = true,
            categoryName = "Render",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )

    activeCleanup = function(): ()
        toggleHideNames(false)
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
