--!strict

-- Standalone Client-Sided Luau GUI Menu Loader
-- Designed to run directly inside a live Roblox client via a script executor.
-- Loads the StandaloneMenu.lua module and initializes the GUI.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Safely load the standalone menu module from the workspace repository structure
local function loadModule(path)
    local success, module = pcall(function()
        local fenv = getfenv()
        local loader = fenv.loadstring or load
        local source = ""
        
        -- Attempt to read the file from the executor environment or workspace
        local readfile = fenv.readfile
        if type(readfile) == "function" then
            local ok, content = pcall(readfile, path)
            if ok then source = content end
        else
            -- Fallback: attempt to load via HTTP if the executor supports it or local source
            -- For standalone execution in the sandbox, we assume the file is available via the repository path
            -- In a live executor, you would paste the module code or use a custom loader.
            -- Here we provide a stubbed loader that assumes the module is in the repository root
            warn("[StandaloneMenu] Loading module from local repository path: " .. path)
            -- Note: In Arena sandbox, we can read the file directly to simulate the executor loading
            local f = io.open(path, "r")
            if f then
                source = f:read("*all")
                f:close()
            end
        end
        
        if source ~= "" then
            return loader(source, "@" .. path)()
        end
        error("Could not load module: " .. path)
    end)
    
    if not success then
        warn("[StandaloneMenu] Loader error: " .. tostring(module))
        return nil
    end
    return module
end

-- Path to the generated StandaloneMenu module
local MODULE_PATH = "src/gui/StandaloneMenu.lua"

local menuController = loadModule(MODULE_PATH)

if menuController then
    warn("[StandaloneMenu] Menu initialized successfully.")
    
    -- Bind the menu toggle key (RightShift or Mobile Button)
    local menuKey = Enum.KeyCode.RightShift
    UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == menuKey then
            menuController:setVisible(not menuController.visible)
        end
    end)
    
    -- Mobile toggle button logic stub
    if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
        local mobileButton = Instance.new("ImageButton")
        mobileButton.Name = "StandaloneMenuMobileToggle"
        mobileButton.AnchorPoint = Vector2.new(1, 0)
        mobileButton.AutoButtonColor = false
        mobileButton.BackgroundColor3 = Color3.fromRGB(29, 29, 33)
        mobileButton.BorderSizePixel = 0
        mobileButton.Position = UDim2.fromOffset(-70, 18)
        mobileButton.Size = UDim2.fromOffset(52, 52)
        mobileButton.ClipsDescendants = true
        mobileButton.ZIndex = 1000
        mobileButton.Parent = playerGui
        
        mobileButton.Activated:Connect(function()
            menuController:setVisible(not menuController.visible)
        end)
    end
else
    warn("[StandaloneMenu] Failed to load StandaloneMenu.lua")
end
