local Module = {Name = "CameraAccess", Initialized = false}
local active

function Module.init(host)
    local api = {playerModule = nil, source = nil, pending = false, checkedAt = -math.huge}
    local patch
    function api:Refresh()
        if self.destroyed then return end
        local scripts = host.LocalPlayer:FindFirstChild("PlayerScripts")
        local source = scripts and scripts:FindFirstChild("PlayerModule")
        if source ~= self.source then self.playerModule, self.poppercam = nil, nil end
        if self.pending or source == self.source and self.playerModule then return end
        if os.clock() - self.checkedAt < 0.5 then return end
        self.checkedAt = os.clock()
        if not source then return end
        self.source, self.pending = source, true
        -- require may yield on a newly installed PlayerModule, not in render.
        task.spawn(function()
            local ok, result = pcall(require, source)
            local cameraModule = source:FindFirstChild("CameraModule")
            local popper = cameraModule and cameraModule:FindFirstChild("Poppercam")
            local cameraOk, cameraClass
            if popper then cameraOk, cameraClass = pcall(require, popper) end
            if not self.destroyed and self.source == source then
                self.playerModule = ok and type(result) == "table" and result or nil
                -- Modern CameraModule returns {}, but its Poppercam class still
                -- supplies the Update method used by the native camera instance.
                self.poppercam = cameraOk and type(cameraClass) == "table" and cameraClass or nil
            end
            self.pending = false
        end)
    end
    local function get(method)
        api:Refresh()
        local playerModule = api.playerModule
        if playerModule and type(playerModule[method]) == "function" then
            local ok, result = pcall(playerModule[method], playerModule)
            if ok then return result end
        end
    end
    function api:GetControls() return get("GetControls") end
    function api:GetCameras()
        local result = get("GetCameras")
        return type(result) == "table" and result or nil
    end
    local function restore()
        if not patch then return end
        local old = patch
        patch = nil
        if old.module.Update == old.replacement then
            local ok = pcall(function() old.module.Update = old.update end)
            if ok and old.enabled then pcall(old.module.Enable, old.module, true) end
        end
    end
    function api:ThroughWalls(enabled)
        if not enabled or self.destroyed then restore(); return false end
        local cameras = self:GetCameras()
        local occlusion = cameras and cameras.activeOcclusionModule or self.poppercam
        if patch and patch.module ~= occlusion then restore() end
        if patch then return patch.module.Update == patch.replacement end
        if type(occlusion) ~= "table" or type(occlusion.Update) ~= "function" then return false end
        local wasEnabled = false
        if type(occlusion.GetEnabled) == "function" and type(occlusion.Enable) == "function" then
            local ok, value = pcall(occlusion.GetEnabled, occlusion)
            wasEnabled = ok and value == true
            if wasEnabled then pcall(occlusion.Enable, occlusion, false) end
        end
        local cleaned = setmetatable({}, {__mode="k"})
        local replacement = function(instance, _, cameraFrame, focus)
            if not cleaned[instance] then
                cleaned[instance] = true
                if type(instance.Cleanup) == "function" then pcall(instance.Cleanup,instance) end
            end
            local extrapolator = instance.focusExtrapolator
            if extrapolator and type(extrapolator.Reset) == "function" then extrapolator:Reset() end
            return cameraFrame, focus
        end
        local update = occlusion.Update
        local ok = pcall(function() occlusion.Update = replacement end)
        if not ok then
            if wasEnabled then pcall(occlusion.Enable, occlusion, true) end
            return false
        end
        patch = {module = occlusion, update = update, replacement = replacement, enabled = wasEnabled}
        return true
    end
    function api:Destroy()
        restore()
        self.destroyed = true
        self.playerModule, self.poppercam = nil, nil
    end
    host.services.cameraAccess = api
    active = api
    Module.Initialized = true
    return api
end
function Module.destroy()
    if active then active:Destroy(); active = nil end
    Module.Initialized = false
end
return Module
