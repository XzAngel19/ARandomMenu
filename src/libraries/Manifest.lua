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
        "src/libraries/GameRoles.lua",
        "src/libraries/CameraAccess.lua",

        "src/guis/Wurst/Code/Cards.lua",

        "src/guis/Wurst/Code/WindowManager.lua",

        "src/guis/Wurst/Code/ClickGui.lua",

        "src/guis/Wurst/Code/FloatingWindows.lua",

        "src/guis/Wurst/Code/SettingsPage.lua",

        "src/guis/Wurst/Code/MobileActions.lua",

        "src/guis/Wurst/Code/Furniture.lua",
    },
    modules = {
        {path = "src/games/universal/Render/FreeCam.lua", name = "FreeCam", category = "World"},

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
        {path = "src/games/universal/Render/Nametags.lua", name = "Nametags", category = "Render"},
        {path = "src/games/universal/Render/HP.lua", name = "HP", category = "Render"},
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
            path = "src/games/universal/Render/FieldOfView.lua",
            name = "FOV",
            category = "Render",
        },
        {
            path = "src/games/universal/Render/Fullbright.lua",
            name = "Fullbright",
            category = "Render",
        },
        {
            path = "src/games/universal/Render/TimeChanger.lua",
            name = "Time Changer",
            category = "Render",
        },
        {
            path = "src/games/universal/Render/XRay.lua",
            name = "X-Ray",
            category = "Render",
        },
        {
            path = "src/games/universal/Render/ZoomUnlocker.lua",
            name = "Zoom",
            category = "Render",
        },

        {
            path = "src/games/universal/Combat/KillAura.lua",
            name = "KillAura",
            category = "Combat",
        },
        {
            path = "src/games/universal/Combat/AimAssist.lua",
            name = "Aim Assist",
            category = "Combat",
        },
        {
            path = "src/games/universal/Combat/TriggerBot.lua",
            name = "TriggerBot",
            category = "Combat",
        },

        {
            path = "src/games/universal/Blatant/Invisible.lua",
            name = "Ghost",
            category = "Utilities",
        },

        {
            path = "src/games/universal/Movement/Speed.lua",
            name = "Speed",
            category = "Exploits",
        },
        {
            path = "src/games/universal/Movement/Jump.lua",
            name = "Jump",
            category = "Exploits",
        },
        {
            path = "src/games/universal/Movement/ClickTeleport.lua",
            name = "Teleport",
            category = "Utilities",
        },
        {
            path = "src/games/universal/Blatant/Spider.lua",
            name = "Spider",
            category = "Exploits",
        },
        {
            path = "src/games/universal/Blatant/Fly.lua",
            name = "Fly",
            category = "Exploits",
        },
        {
            path = "src/games/universal/Blatant/Noclip.lua",
            name = "Noclip",
            category = "Exploits",
        },
        {
            path = "src/games/universal/Movement/AntiVoid.lua",
            name = "Anti Void",
            category = "Utilities",
        },
        {
            path = "src/games/universal/Movement/AntiFling.lua",
            name = "Anti Fling",
            category = "Utilities",
        },
        {
            path = "src/games/universal/Movement/FreezeMovements.lua",
            name = "Freeze Movements",
            category = "Utilities",
        },
        {
            path = "src/games/universal/Movement/Gravity.lua",
            name = "Gravity",
            category = "World",
        },
        {
            path = "src/games/universal/Movement/SafeWalk.lua",
            name = "Safe Walk",
            category = "World",
        },


        {
            path = "src/games/universal/Other/Disguise.lua",
            name = "Disguise",
            category = "Utilities",
        },
        {
            path = "src/games/universal/Other/AntiAfk.lua",
            name = "Anti AFK",
            category = "World",
        },
        {
            path = "src/games/universal/Other/InteractExtender.lua",
            name = "Interact Extender",
            category = "Exploits",
        },
        {
            path = "src/games/universal/Other/ImproveFps.lua",
            name = "Improve FPS",
            category = "World",
        },
        {
            path = "src/games/universal/Blatant/Fling.lua",
            name = "Fling",
            category = "Exploits",
        },
    },
}

return Manifest
