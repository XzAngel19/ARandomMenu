--!strict
--
-- Module manifest.
--
-- The single ordered list of everything the runtime downloads on top of
-- `ARandomMenu.luau`: the kernel first, then shared libraries, then the module
-- files themselves. Adding a module means adding one line here and one file
-- under `src/modules/<Category>/`; nothing in the main file has to change.
--
-- The runtime keeps a copy of this list as a fallback for the case where the
-- manifest itself cannot be downloaded, and the repository's validation
-- workflow fails if the two ever drift apart.

export type ModuleEntry = {
    path: string,
    name: string,
    category: string,
}

export type Manifest = {
    version: number,
    core: {string},
    libraries: {string},
    modules: {ModuleEntry},
}

local Manifest: Manifest = {
    version = 1,
    core = {
        "src/core/Framework.luau",
    },
    libraries = {
        "src/library/Entity.luau",
        "src/library/Weapons.luau",
        "src/library/Render.luau",
    },
    modules = {
        -- Friend List comes first: every targeting module below asks it who
        -- must not be touched.
        {
            path = "src/modules/Utility/FriendList.luau",
            name = "Friend List",
            category = "Utility",
        },
        {
            path = "src/modules/Visuals/ItemRender.luau",
            name = "Item Render",
            category = "Visuals",
        },
        {
            path = "src/modules/Visuals/PlayerESP.luau",
            name = "Player ESP",
            category = "Visuals",
        },
        {
            path = "src/modules/Combat/KillAura.luau",
            name = "Kill Aura",
            category = "Combat",
        },
        {
            path = "src/modules/Utility/RemoteLogger.luau",
            name = "Remote Logger",
            category = "Utility",
        },
        {
            path = "src/modules/Movement/ClickTeleport.luau",
            name = "Click Teleport",
            category = "Movement",
        },
        {
            path = "src/modules/Combat/AutoClicker.luau",
            name = "Auto Clicker",
            category = "Combat",
        },
        {
            path = "src/modules/Combat/TriggerBot.luau",
            name = "TriggerBot",
            category = "Combat",
        },
        -- Spoof: cosmetic only, and each one lands on its own page.
        {
            path = "src/modules/Combat/Hitboxes.luau",
            name = "Hitboxes",
            category = "Combat",
        },
        {
            path = "src/modules/Combat/ProjectileCalibration.luau",
            name = "Projectile Calibration",
            category = "Combat",
        },
        {
            path = "src/modules/Spoof/Disguise.luau",
            name = "Disguise",
            category = "Spoof",
        },
        {
            path = "src/modules/Spoof/AnimationChanger.luau",
            name = "Animation Changer",
            category = "Spoof",
        },
        {
            path = "src/modules/Spoof/EmotePlayer.luau",
            name = "Emote Player",
            category = "Spoof",
        },
    },
}

return Manifest
