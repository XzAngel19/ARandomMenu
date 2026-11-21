--!nocheck
--[[
    Speed Hub X — Main tab hooks (Skill / Aim / Body)
    ================================================
    One stub per control shown on the Main page of the reference
    screenshot.  All bodies are intentionally empty — no automation,
    aimbot, combat, farming, movement or safe logic is implemented.
    The UI layer only ever stores flags / selections and forwards them
    to these hooks.
]]

local Main = {}

---------------------------------------------------------------------------
-- Skill
---------------------------------------------------------------------------
-- Auto Ultimate — "This is Meaning Auto Use Ultimate"
function Main.onAutoUltimateToggle(enabled)
    -- intentionally empty: enable/disable Auto Ultimate here
end

-- Auto Dash — "This is Meaning Auto Use Dash"
function Main.onAutoDashToggle(enabled)
    -- intentionally empty: enable/disable Auto Dash here
end

---------------------------------------------------------------------------
-- Aim
---------------------------------------------------------------------------
-- "Choose Aim Part" dropdown — `aimPart` is one of:
-- "Head" | "Torso" | "HumanoidRootPart" | "Left Leg" | "Right Leg" | "Random"
function Main.onAimPartChanged(aimPart)
    -- intentionally empty: store / apply the selected aim part here
end

-- Aimlock — "Aimlock = Lock Camera Player"
function Main.onAimlockToggle(enabled)
    -- intentionally empty: engage/release the camera lock here
end

---------------------------------------------------------------------------
-- Body
---------------------------------------------------------------------------
-- Anti-Knockback (BETA)
function Main.onAntiKnockbackToggle(enabled)
    -- intentionally empty: hook your anti-knockback here
end

-- Anti-Stun (BETA)
function Main.onAntiStunToggle(enabled)
    -- intentionally empty: hook your anti-stun here
end

-- Anti-Busy (BETA)
function Main.onAntiBusyToggle(enabled)
    -- intentionally empty: hook your anti-busy here
end

return Main
