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
    },
    modules = {
        {
            path = "src/modules/Visuals/PlayerESP.luau",
            name = "Player ESP",
            category = "Visuals",
        },
        {
            path = "src/modules/Combat/TriggerBot.luau",
            name = "TriggerBot",
            category = "Combat",
        },
    },
}

return Manifest
