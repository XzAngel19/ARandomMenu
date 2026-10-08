local Module = {
    Name = "MM2 Hide Names",
    PlaceId = 142823291,
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}

local activeCleanup: () -> () = function(): () end

-- The alias every label showing the local player's name is rewritten to.
local ALIAS = "John Doe"

function Module.init(runtime: any): any
    if Module.Initialized then
        return Module
    end
    local core: any = state.mm2Core
    assert(type(core) == "table", "MM2 Hide Names requires the MM2 core module")
    Module.Runtime = runtime

    -- label -> the text it had before we rewrote it, so disabling restores it.
    local hiddenNameLabels = setmetatable({}, {__mode = "k"})

    local function toggleHideNames(enabled)
        disconnectFeatureConnection("MM2HideNames")
        if not enabled then
            for label, originalText in pairs(hiddenNameLabels) do
                if label and label.Parent and label.Text == ALIAS then
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

            -- Only the local player's own identity is masked. Every string form
            -- the UIs use for a player is covered: bare name, display name, the
            -- @handle, and the "Display (@user)" form the player list and chat
            -- headers render.
            local names = {}
            names[LocalPlayer.Name] = true
            names[LocalPlayer.DisplayName] = true
            names["@" .. LocalPlayer.Name] = true
            names[LocalPlayer.DisplayName .. " (@" .. LocalPlayer.Name .. ")"] = true

            -- Where the name can appear:
            --   * PlayerGui  -> the MM2 scoreboard and any in-game panel
            --   * RobloxGui.PlayerList -> the default player list
            --   * ExperienceChat -> the chat window (sender labels)
            local roots = {}
            local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if playerGui then
                table.insert(roots, playerGui)
            end
            pcall(function()
                local coreGui = game:GetService("CoreGui")
                local robloxGui = coreGui:FindFirstChild("RobloxGui")
                local playerList = robloxGui
                    and robloxGui:FindFirstChild("PlayerList", true)
                if playerList then
                    table.insert(roots, playerList)
                end
                local chat = coreGui:FindFirstChild("ExperienceChat")
                if chat then
                    table.insert(roots, chat)
                end
            end)

            for _, root in ipairs(roots) do
                for _, object in ipairs(root:GetDescendants()) do
                    if (object:IsA("TextLabel") or object:IsA("TextButton"))
                        and names[object.Text] then
                        if hiddenNameLabels[object] == nil then
                            hiddenNameLabels[object] = object.Text
                        end
                        object.Text = ALIAS
                    end
                end
            end
        end)
    end

    createUniversalFeature(
        "Hide Names",
        "Replace your own name with " .. ALIAS
            .. " in the MM2 scoreboard, chat and player list",
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
