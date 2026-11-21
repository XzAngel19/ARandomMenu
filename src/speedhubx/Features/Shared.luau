--!nocheck
--[[
    Speed Hub X — Shared state & hooks
    ==================================
    Data-only hub state plus the (intentionally empty) shared hooks used
    by more than one tab.  No gameplay, farming, combat, movement,
    safe-mode or automation logic is implemented anywhere in this
    project — wire these stubs up to your own logic if you want it.
]]

local Shared = {}

-- Non-gameplay hub state (pure UI model).
Shared.State = {
    Version = "3.7.0",
    CurrentTab = "Main",
    SupaTechV2Enabled = false,  -- mirrors the "Supa Tech V2: Off" pill
    WatermarkVisible = true,
    ConfigLoaded = false,
}

-- Fired when the floating "S" logo is clicked.
function Shared.onLogoClicked()
    -- intentionally empty: hook your own logic here
end

-- Fired when the "Supa Tech V2" status pill is clicked.
-- `enabled` is the requested state; respect Shared.State.SupaTechV2Enabled.
function Shared.onSupaTechV2Toggle(enabled)
    -- intentionally empty: hook your own logic here
end

-- Serialise/persist the current UI state.  Intentionally left empty.
function Shared.saveConfig()
    -- intentionally empty: serialize Shared.State (and any feature flags) here
end

-- Restore a previously saved configuration.  Intentionally left empty.
function Shared.loadConfig()
    -- intentionally empty: apply your saved flags to the toggles here
end

-- Unload the whole interface and release connections.  Wired to nothing by
-- default; the window's close button destroys the GUI directly (UI only).
function Shared.unload()
    -- intentionally empty: tear down your logic here
end

return Shared
