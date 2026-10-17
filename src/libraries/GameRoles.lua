-- Shared role presentation contract. Games register data; render modules own
-- their palettes/filters. A Chams colour must never overwrite PlayerESP's.
local Module = {Name = "GameRoles", Initialized = false}
local active: any = nil

function Module.init(host: any): any
    local bridge = host.services.gameBridge
    local service = {bindings = {}}

    function service:Register(provider: any): () -> ()
        assert(type(provider) == "table" and type(provider.Get) == "function", "GameRoles needs Get(player)")
        assert(type(provider.Roles) == "table", "GameRoles needs a Roles array")
        bridge.registerRoles(provider)
        return function() bridge.unregisterRoles(provider) end
    end

    function service:Bind(card: any, settings: any?): any
        settings = settings or {}
        local binding = {provider = nil, rows = {}, roles = {}, dead = false}
        local function visibility(option, visible)
            if visible then option.Show = nil else option.Show = {Option = "__GameRolesAbsent", Values = {true}} end
            if option.SetVisible then option:SetVisible(visible) end
        end
        local function update(provider)
            if binding.dead then return end
            binding.provider = type(provider) == "table" and provider or nil
            table.clear(binding.roles)
            if binding.provider then
                for _, role in ipairs(type(provider.Roles) == "table" and provider.Roles or {}) do
                    if type(role) == "string" and role ~= "" and #binding.roles < 32 and not table.find(binding.roles, role) then
                        table.insert(binding.roles, role)
                    end
                end
            end
            if settings.palette ~= false and #binding.roles > 0 and not card.Options["Role colours"] then
                binding.rows["Role colours"] = card:CreateToggle({Name = "Role colours", Default = true})
            end
            for _, role in ipairs(binding.roles) do
                local colourName = role .. " colour"
                if settings.palette ~= false and not binding.rows[colourName] then
                    local colour = provider.Colors and provider.Colors[role]
                    if type(provider.GetColor) == "function" then
                        local ok, value = pcall(provider.GetColor, role)
                        if ok and typeof(value) == "Color3" then colour = value end
                    end
                    binding.rows[colourName] = card:CreateColor({Name = colourName,
                        Default = typeof(colour) == "Color3" and colour or Color3.fromRGB(236,236,240),
                        Show = {Option = "Role colours"}})
                end
                if settings.filters and not binding.rows[role .. " ESP"] then
                    binding.rows[role .. " ESP"] = card:CreateToggle({Name = role .. " ESP", Default = true})
                end
            end
            for name, option in pairs(binding.rows) do
                local present = name == "Role colours" and #binding.roles > 0
                for _, role in ipairs(binding.roles) do
                    if name == role .. " colour" or name == role .. " ESP" then present = true; break end
                end
                visibility(option, present)
                if present and name ~= "Role colours" and string.sub(name, -7) == " colour" then
                    option.Show = {Option = "Role colours"}
                end
            end
            card:RefreshVisibility()
        end
        function binding:Role(player)
            if not self.provider then return nil end
            local getter = bridge.playerRole or self.provider.Get
            local ok, role = pcall(getter, player)
            return ok and type(role) == "string" and table.find(self.roles, role) and role or nil
        end
        function binding:Resolve(player, fallback)
            local role = self:Role(player)
            local option = role and card.Options[role .. " colour"]
            local enabled = card.Options["Role colours"]
            return option and enabled and enabled.Value and option.Value or fallback, role
        end
        function binding:Allows(player)
            local role = self:Role(player)
            local option = role and card.Options[role .. " ESP"]
            return not option or option.Value ~= false
        end
        local disconnect = bridge.onEvent(function(kind, provider)
            if kind == "roles" then update(provider) end
        end)
        function binding:Destroy()
            if self.dead then return end
            self.dead = true
            if disconnect then disconnect(); disconnect = nil end
            self.provider = nil
            local index = table.find(service.bindings, self)
            if index then table.remove(service.bindings, index) end
        end
        table.insert(service.bindings, binding)
        return binding
    end
    function service:Destroy()
        for _, binding in ipairs(table.clone(self.bindings)) do binding:Destroy() end
    end
    host.services.gameRoles = service
    active = service
    Module.Initialized = true
    return service
end
function Module.destroy()
    if active then active:Destroy(); active = nil end
    Module.Initialized = false
end
return Module
