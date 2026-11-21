--!nocheck
--[[
    Speed Hub X — Home tab hooks
    =============================
    Stub callbacks for the Home page.  Everything here is intentionally
    empty — no gameplay, farming, combat, movement, safe-mode or
    automation logic is implemented.
]]

local Home = {}

-- "Save Configuration" button on the Home page.
function Home.onSaveConfig()
    -- intentionally empty: persist toggles / dropdown values here
end

-- "Reload Interface" button on the Home page (pure UI rebuild; the
-- wiring lives in App.luau — this hook exists for feature parity).
function Home.onReloadInterface()
    -- intentionally empty: optional extra teardown before the UI rebuilds
end

-- Version/status rows are display-only and need no callbacks.

return Home
