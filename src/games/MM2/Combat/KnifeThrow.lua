local Module = {
    Name = "MM2 Knife Throw",
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
    assert(type(core) == "table", "MM2 Knife Throw requires the MM2 core module")
    local prediction: any = state.mm2Prediction
    assert(type(prediction) == "table", "MM2 Knife Throw requires MM2 Prediction")
    Module.Runtime = runtime
    
    local findMurderer: any = core.findMurderer
    local getPlayerRole: any = core.getPlayerRole
    local getPlayerWeapon: any = core.getPlayerWeapon
    local isPlayerAlive: any = core.isPlayerAlive
    local isProtectedTarget: any = core.isProtectedTarget
    local isWeaponPathClear: any = core.isWeaponPathClear
    
    local settings = {
        wallCheck = true,
        delay = 0,
    }
    
    local knifeThrowActive = false
    local lastThrowAttempt = 0
    
    local function getKnife(): Tool?
        local character = LocalPlayer.Character
        if not character then return nil end
        return getPlayerWeapon(LocalPlayer, "Knife", true)
    end
    
    local function findTarget(): Player?
        local murderer = findMurderer()
        if murderer ~= LocalPlayer then return nil end
        
        local localRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not localRoot then return nil end
        
        local candidates = {}
        for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
            if player ~= LocalPlayer 
                and isPlayerAlive(player) 
                and not isProtectedTarget(player)
                and getPlayerRole(player) ~= "Murderer" then
                
                local targetRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                if targetRoot then
                    table.insert(candidates, {
                        player = player,
                        distance = (targetRoot.Position - localRoot.Position).Magnitude
                    })
                end
            end
        end
        
        table.sort(candidates, function(a, b) return a.distance < b.distance end)
        
        for _, candidate in ipairs(candidates) do
            if not settings.wallCheck or isWeaponPathClear(localRoot.Position, candidate.player.Character.HumanoidRootPart.Position, {}) then
                return candidate.player
            end
        end
        
        return nil
    end
    
    local function throwKnife(target: Player): boolean
        local knife = getKnife()
        if not knife then return false end
        
        local character = LocalPlayer.Character
        if not character then return false end
        
        local root = character:FindFirstChild("HumanoidRootPart")
        local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
        if not root or not targetRoot then return false end
        
        -- Get the throw remote
        local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
        if not remotes then return false end
        
        local event = remotes:FindFirstChild("Event")
        if not event then return false end
        
        -- Calculate aim with prediction
        local originCFrame = getGunOriginCFrame(knife)
        local aimPosition = targetRoot.Position
        
        -- Invoke the remote directly to trigger natural throw animation
        -- The game will handle the animation and throw naturally
        pcall(function()
            event:FireServer("Throw", {
                Origin = originCFrame,
                Direction = (aimPosition - originCFrame.Position).Unit,
                Target = target
            })
        end)
        
        return true
    end
    
    local function knifeThrowTick(): ()
        if not knifeThrowActive then return end
        
        local now = os.clock()
        local delay = settings.delay
        if now - lastThrowAttempt < delay then return end
        
        local target = findTarget()
        if not target then return end
        
        lastThrowAttempt = now
        throwKnife(target)
    end
    
    local function toggleKnifeThrow(enabled: boolean): ()
        knifeThrowActive = enabled
        
        if enabled then
            featureConnections.MM2KnifeThrow = TaskManager:Connect(knifeThrowTick)
            knifeThrowTick()
        else
            disconnectFeatureConnection("MM2KnifeThrow")
        end
    end
    
    local KnifeThrowFeature: any = createUniversalFeature(
        "Knife Throw",
        "Automatically throws knives at targets using the game's natural throw animation. Invokes the Remote directly for authentic behavior with prediction.",
        5,
        toggleKnifeThrow,
        {
            categoryName = "Combat",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    state.mm2KnifeThrowFeature = KnifeThrowFeature
    
    addToggleOption(KnifeThrowFeature, "WallCheck", true,
        function(value: boolean): ()
            settings.wallCheck = value
        end,
        "Only throw if there's a clear path to the target.")
    
    addNumberOption(KnifeThrowFeature, "Delay", 0, 0, 10,
        function(value: number): ()
            settings.delay = value
            if KnifeThrowFeature.enabled then
                KnifeThrowFeature:SetStatus(string.format("%.1fs", value))
            end
        end,
        "Delay in seconds between each throw attempt. 0 = throw as fast as possible.", 0.1)
    
    activeCleanup = function(): ()
        toggleKnifeThrow(false)
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
