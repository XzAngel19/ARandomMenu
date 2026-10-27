export type ModuleEntry = {
    path: string,
    name: string,
    category: string,
}

export type GamePlaceEntry = {
    placeId: number,
    module: string,
    displayName: string,
}

export type Manifest = {
    version: number,
    widgets: string,
    core: {string},
    libraries: {string},
    modules: {ModuleEntry},
    gamePlaces: {GamePlaceEntry},
    gameModules: {[string]: {string}},
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
        {path = "src/games/universal/Render/Spectate.lua", name = "Spectate", category = "World"},
        {path = "src/games/universal/Render/Markers.lua", name = "Markers", category = "Render"},

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
            path = "src/games/universal/Combat/TargetStrafe.lua",
            name = "StrafeBot",
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
            path = "src/games/universal/Movement/InfiniteJump.lua",
            name = "Infinite Jump",
            category = "Exploits",
        },
        {
            path = "src/games/universal/Movement/AirWalk.lua",
            name = "AirWalk",
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
            path = "src/games/universal/Blatant/WalkFling.lua",
            name = "Walk Fling",
            category = "Exploits",
        },
        {
            path = "src/games/universal/Blatant/Swim.lua",
            name = "Swim",
            category = "Exploits",
        },
        {
            path = "src/games/universal/Blatant/Jesus.lua",
            name = "Jesus",
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
            category = "World",
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
            path = "src/games/universal/Other/RejoinServer.lua",
            name = "Rejoin Server",
            category = "Utilities",
        },
        {
            path = "src/games/universal/Other/ImproveFps.lua",
            name = "Improve FPS",
            category = "World",
        },
    },

    gamePlaces = {
        {placeId = 71480482338212, module = "BedFight", displayName = "Bed Fight"},
        {placeId = 142823291, module = "MM2", displayName = "Murder Mystery 2"},
        {placeId = 14315258385, module = "TRS", displayName = "The Regular Show"},
        {placeId = 93978595733734, module = "VD", displayName = "Virtual Dealer"},
        {placeId = 92876937625630, module = "X2Duels", displayName = "X2 Duels (Legacy)"},
        {placeId = 135856908115931, module = "X2Duels", displayName = "X2 Duels"},
    },

    gameModules = {
        MM2 = {
            "src/games/MM2/base.lua",
            "src/games/MM2/Prediction.lua",
            "src/games/MM2/Blatant/Shoot.lua",
            "src/games/MM2/Blatant/KnifeAura.lua",
            "src/games/MM2/Combat/AutoShoot.lua",
            "src/games/MM2/Combat/KnifeThrow.lua",
            "src/games/MM2/Render/RoundEsp.lua",
            "src/games/MM2/Render/CoinEsp.lua",
            "src/games/MM2/Movement/Sprint.lua",
            "src/games/MM2/Blatant/Fling.lua",
            "src/games/MM2/Movement/Teleport.lua",
            "src/games/MM2/Fun/BlurtRoles.lua",
            "src/games/MM2/Other/AutoUnbox.lua",
            "src/games/MM2/Other/AutoFarm.lua",
            "src/games/MM2/Other/AutoVote.lua",
            "src/games/MM2/Other/CoinsAura.lua",
            "src/games/MM2/Other/GunAura.lua",
            "src/games/MM2/Other/AutoWin.lua",
            "src/games/MM2/Other/GetAllEmotes.lua",
            "src/games/MM2/Other/TrajectoryCalibration.lua",
            "src/games/MM2/Other/CalibrationTrails.lua",
        },
        VD = {
            "src/games/VD/base.lua",
        },
        BedFight = {
            "src/games/BedFight/base.lua",
            "src/games/BedFight/Combat/AutoSwing.lua",
            "src/games/BedFight/Render/RoundInfo.lua",
        },
        X2Duels = {
            "src/games/X2Duels/Rules.lua",
            "src/games/X2Duels/base.lua",
            "src/games/X2Duels/Other/AutoFarm.lua",
        },
        TRS = {
            "src/games/TRS/base.lua",
        },
    },
}

return Manifest
