export type ModuleEntry = {
    path: string,
    name: string,
    category: string,
}

export type Manifest = {
    version: number,
    widgets: string,
    core: {string},
    libraries: {string},
    modules: {ModuleEntry},
}

local Manifest: Manifest = {
    version = 1,

    widgets = "src/guis/Wurst/Code/Widgets.lua",
    core = {
        "src/libraries/Framework.lua",
    },
    libraries = {
        "src/libraries/Entity.lua",
        "src/libraries/Targeting.lua",
        "src/libraries/Weapons.lua",
        "src/libraries/Render.lua",

        "src/guis/Wurst/Code/Cards.lua",

        "src/guis/Wurst/Code/WindowManager.lua",

        "src/guis/Wurst/Code/ClickGui.lua",

        "src/guis/Wurst/Code/FloatingWindows.lua",

        "src/guis/Wurst/Code/SettingsPage.lua",

        "src/guis/Wurst/Code/MobileActions.lua",

        "src/guis/Wurst/Code/Furniture.lua",
    },
    modules = {

                {
            path = "src/games/universal/Render/ItemRender.lua",
            name = "ItemESP",
            category = "Render",
        },
        {
            path = "src/games/universal/Render/PlayerESP.lua",
            name = "PlayerESP",
            category = "Render",
        },
        {
            path = "src/games/universal/Render/Chams.lua",
            name = "Chams",
            category = "Render",
        },
        {
            path = "src/games/universal/Render/Arrows.lua",
            name = "Arrows",
            category = "Render",
        },
        {
            path = "src/games/universal/Render/NPCESP.lua",
            name = "NPCESP",
            category = "Render",
        },
        {
            path = "src/games/universal/Combat/KillAura.lua",
            name = "Killaura",
            category = "Combat",
        },
        {
            path = "src/games/universal/Utility/RemoteLogger.lua",
            name = "Remote Logger",
            category = "Other",
        },
        {
            path = "src/games/universal/Utility/Learning.lua",
            name = "Learning",
            category = "Other",
        },
        {
            path = "src/games/universal/Movement/ClickTeleport.lua",
            name = "Click Teleport",
            category = "Movement",
        },
        {
            path = "src/games/universal/Combat/AutoClicker.lua",
            name = "Auto Clicker",
            category = "Combat",
        },
        {
            path = "src/games/universal/Combat/TriggerBot.lua",
            name = "TriggerBot",
            category = "Combat",
        },
        {
            path = "src/games/universal/Combat/AimAssist.lua",
            name = "Aim Assist",
            category = "Combat",
        },

        {
            path = "src/games/universal/Render/XRay.lua",
            name = "X-Ray",
            category = "Render",
        },
        {
            path = "src/games/universal/Blatant/HighJump.lua",
            name = "HighJump",
            category = "Movement",
        },
        {
            path = "src/games/universal/Blatant/Spider.lua",
            name = "Spider",
            category = "Movement",
        },
        {
            path = "src/games/universal/Blatant/WallHop.lua",
            name = "WallHop",
            category = "Movement",
        },
        {
            path = "src/games/universal/Blatant/Invisible.lua",
            name = "Invisible",
            category = "Blatant",
        },
        {
            path = "src/games/universal/World/SafeWalk.lua",
            name = "SafeWalk",
            category = "Movement",
        },
        {
            path = "src/games/universal/World/RejoinServer.lua",
            name = "Rejoin Server",
            category = "Other",
        },
        {
            path = "src/games/universal/Render/ZoomUnlocker.lua",
            name = "Zoom",
            category = "Render",
        },
        {
            path = "src/games/universal/World/InteractExtender.lua",
            name = "Interact Extender",
            category = "Other",
        },
                        {
            path = "src/games/universal/Blatant/Fly.lua",
            name = "Flight",
            category = "Movement",
        },
        {
            path = "src/games/universal/Blatant/VehicleSpeed.lua",
            name = "Vehicle Speed",
            category = "Movement",
        },
        {
            path = "src/games/universal/Movement/AntiVoid.lua",
            name = "Anti-Void",
            category = "Movement",
        },
        {
            path = "src/games/universal/World/Gravity.lua",
            name = "Gravity",
            category = "Movement",
        },
        {
            path = "src/games/universal/Blatant/JumpPower.lua",
            name = "Jump Power",
            category = "Movement",
        },
        {
            path = "src/games/universal/Blatant/InfiniteJump.lua",
            name = "Infinite Jump",
            category = "Movement",
        },
        {
            path = "src/games/universal/Render/FieldOfView.lua",
            name = "FOV",
            category = "Render",
        },
        {
            path = "src/games/universal/Blatant/Noclip.lua",
            name = "Noclip",
            category = "Movement",
        },
        {
            path = "src/games/universal/World/AntiAfk.lua",
            name = "AntiAFK",
            category = "Other",
        },
        {
            path = "src/games/universal/Movement/AntiFling.lua",
            name = "Anti-Fling",
            category = "Movement",
        },
        {
            path = "src/games/universal/Utility/LagSwitch.lua",
            name = "Lag Switch",
            category = "Other",
        },
        {
            path = "src/games/universal/Blatant/Fling.lua",
            name = "Fling",
            category = "Other",
        },
        {
            path = "src/games/universal/Utility/ImproveFps.lua",
            name = "Improve FPS",
            category = "Other",
        },
        {
            path = "src/games/universal/Render/Fullbright.lua",
            name = "Fullbright",
            category = "Render",
        },
        {
            path = "src/games/universal/Movement/FreezeMovements.lua",
            name = "Freeze Movements",
            category = "Movement",
        },
        {
            path = "src/games/universal/Blatant/Speed.lua",
            name = "SpeedHack",
            category = "Movement",
        },
        {
            path = "src/games/universal/Blatant/Hitboxes.lua",
            name = "Hitboxes",
            category = "Blatant",
        },
        {
            path = "src/games/universal/Render/ProjectileCalibration.lua",
            name = "Projectile Calibration",
            category = "Other",
        },
        {
            path = "src/games/universal/Utility/GameLearning.lua",
            name = "Game Learning",
            category = "Other",
        },
        {
            path = "src/games/universal/Utility/SpinBot.lua",
            name = "SpinBot",
            category = "Fun",
        },
                            },
}

return Manifest
