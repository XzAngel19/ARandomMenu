export type Candidate = {
    id: string,
    label: string,
    kind: string,
    melee: boolean,
    instance: Instance,
}

export type GameSource = {

    scan: () -> {{string}},

    press: (label: string, target: any?) -> boolean,
}

export type WeaponLibrary = {
    Scan: (self: WeaponLibrary, query: any?) -> {Candidate},
    Labels: (self: WeaponLibrary, query: any?) -> {string},
    Find: (self: WeaponLibrary, label: string) -> Candidate?,
    IsMelee: (self: WeaponLibrary, name: string) -> boolean,
    Activate: (self: WeaponLibrary, candidate: Candidate, target: any?) -> boolean,
    Best: (self: WeaponLibrary, query: any?) -> Candidate?,
    Invalidate: (self: WeaponLibrary) -> (),
    SetAllowEquip: (self: WeaponLibrary, allowed: boolean) -> (),
    Swing: (self: WeaponLibrary) -> boolean,
    RegisterGameSource: (self: WeaponLibrary, source: GameSource?) -> (),
    PressButton: (self: WeaponLibrary, button: GuiButton) -> boolean,
    Destroy: (self: WeaponLibrary) -> (),
}

local Module = {
    Name = "Weapons",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local WEAPON_WORDS: {string} = {
    "sword",
    "katana",
    "dagger",
    "blade",
    "knife",
    "axe",
    "mace",
    "spear",
    "scythe",
    "sabre",
    "saber",
    "machete",
    "hammer",
    "club",
    "bat",
    "staff",
    "pickaxe",
    "fist",
    "punch",
    "attack",
    "swing",
    "hit",
    "melee",
    "weapon",
    "combat",
}

local MELEE_WORDS: {string} = {
    "sword",
    "katana",
    "dagger",
    "blade",
    "knife",
    "axe",
    "mace",
    "spear",
    "scythe",
    "sickle",
    "sabre",
    "saber",
    "rapier",
    "cutlass",
    "machete",
    "glaive",
    "halberd",
    "hammer",
    "club",
    "baton",
    "bat",
    "pickaxe",
    "fist",
    "knuckle",
}

local RANGED_WORDS: {string} = {
    "bow",
    "crossbow",
    "arrow",
    "gun",
    "rifle",
    "pistol",
    "revolver",
    "shotgun",
    "sniper",
    "launcher",
    "rocket",
    "grenade",
    "snowball",
    "projectile",
    "throw",
    "wand",
    "staff",
    "gauntlet",
    "fireball",
}

local RIG_WORDS: {string} = {
    "hand",
    "arm",
    "leg",
    "foot",
    "torso",
    "head",
    "upper",
    "lower",
    "root",
    "limb",
    "joint",
    "motor",
    "weld",
    "attachment",
    "rig",
    "bone",
    "hitbox",
    "collider",
    "humanoid",
    "camera",
    "viewmodel",
    "idle",
    "walk",
    "run",
    "sprint",
    "sneak",
    "crouch",
    "jump",
    "fall",
    "land",
    "swim",
    "pose",
    "track",
    "sequence",
}

local NOT_WEAPON_WORDS: {string} = {
    "emote",
    "animation",
    "anim",
    "dance",
    "cosmetic",
    "cape",
    "skin",
    "kit",
    "shop",
    "setting",
    "gift",
    "trade",
    "coin",
    "gem",
    "wool",
    "block",
    "plank",
    "brick",
    "glass",
    "ladder",
    "wood ",
    "sand",
    "dirt",
    "obsidian",
    "potion",
    "food",
    "apple",
    "bed",
    "chest",
    "music",
    "sound",
    "menu",
    "close",
    "back",
    "shopkeeper",
}

local INVENTORY_WORDS: {string} = {
    "hotbar",
    "backpack",
    "inventory",
    "toolbar",
    "slots",
    "items",
}

local TOUCH_WORDS: {string} = {
    "mobile",
    "touch",
    "buttons",
    "controls",
}

local activeLibrary: WeaponLibrary? = nil

local function containsWord(text: string, words: {string}): boolean
    local lowered: string = string.lower(text)
    for _, word: string in ipairs(words) do
        if string.find(lowered, word, 1, true) then
            return true
        end
    end
    return false
end

local function isMeleeName(name: string): boolean
    if containsWord(name, NOT_WEAPON_WORDS)
        or containsWord(name, RANGED_WORDS)
        or containsWord(name, RIG_WORDS) then
        return false
    end
    return containsWord(name, MELEE_WORDS)
end

local function ancestryMatches(instance: Instance, words: {string}, depth: number): boolean
    local current: Instance? = instance
    local steps: number = 0
    while current and steps < depth do
        if containsWord(current.Name, words) then
            return true
        end
        current = current.Parent
        steps += 1
    end
    return false
end

function Module.init(context: any): WeaponLibrary
    local host: any = context
    local localPlayer: Player = host.LocalPlayer
    local currentWorkspace: Workspace = host.workspace or workspace
    local menuGui: Instance? = host.ScreenGui

    local library: any = {

        cache = {},
        cachedAt = -1,
        cachedAll = false,
        cachedMelee = false,

        allowEquip = false,
    }

    function library:PressButton(button: GuiButton): boolean
        local environment: any = getfenv()
        local connectionsOf: any = environment.getconnections
        local fireSignal: any = environment.firesignal
        local pressed: boolean = false

        if type(connectionsOf) == "function" then
            for _, signal: any in
                ipairs({
                    button.MouseButton1Down,
                    button.MouseButton1Click,
                    (button :: any).Activated,
                    button.MouseButton1Up,
                })
            do
                local ok: boolean, connections: any = pcall(connectionsOf, signal)
                if not ok or type(connections) ~= "table" then
                    continue
                end
                for _, connection: any in ipairs(connections) do
                    local fired: boolean = pcall(function(): ()
                        connection:Fire()
                    end)
                    pressed = pressed or fired
                end
            end
        end
        if not pressed and type(fireSignal) == "function" then
            pressed = pcall(fireSignal, (button :: any).Activated) == true
        end
        return pressed
    end

    local function isMenuOwned(instance: Instance): boolean
        return menuGui ~= nil and instance:IsDescendantOf(menuGui :: Instance)
    end

    function library:Invalidate(): ()
        library.cachedAt = -1
    end

    function library:RegisterGameSource(source: any): ()
        library.gameSource = source
        library.cachedAt = -1
    end

    function library:SetAllowEquip(allowed: boolean): ()
        library.allowEquip = allowed == true
    end

    function library:Scan(query: any?): {Candidate}
        local options: any = query or {}
        local everything: boolean = options.All == true
        local now: number = os.clock()
        if now - library.cachedAt < 1
            and library.cachedAll == everything
            and library.cachedMelee == (options.Melee == true) then
            return library.cache
        end
        local found: {Candidate} = {}
        local seen: {[string]: boolean} = {}

        local meleeOnly: boolean = options.Melee == true
        local function add(kind: string, label: string, instance: Instance): ()
            local id: string = kind .. ":" .. label
            if seen[id] then
                return
            end
            local melee: boolean = isMeleeName(label)
            if meleeOnly and not melee then
                return
            end
            seen[id] = true
            table.insert(found, {
                id = id,
                label = label,
                kind = kind,
                melee = melee,
                instance = instance,
            })
        end

        if library.gameSource and type(library.gameSource.scan) == "function" then
            local ok: boolean, listed: any = pcall(library.gameSource.scan)
            if ok and type(listed) == "table" then
                for _, entry: any in ipairs(listed) do
                    if type(entry) == "table" and entry[1] and entry[2] then
                        add("Game", tostring(entry[1]), entry[2])
                    end
                end
            end
        end

        local character: Model? = localPlayer.Character
        if character then
            for _, child: Instance in ipairs(character:GetChildren()) do
                if child:IsA("Tool") then
                    add("Tool", child.Name, child)
                end
            end
        end
        local backpack: Instance? = localPlayer:FindFirstChild("Backpack")
        if backpack then
            for _, child: Instance in ipairs(backpack:GetChildren()) do
                if child:IsA("Tool") then
                    add("Tool", child.Name, child)
                end
            end
        end

        local viewRoots: {Instance} = {}
        local camera: Camera? = currentWorkspace.CurrentCamera
        if camera then
            table.insert(viewRoots, camera)
        end
        if character then
            table.insert(viewRoots, character)
        end
        for _, root: Instance in ipairs(viewRoots) do
            for _, child: Instance in ipairs(root:GetChildren()) do
                if not child:IsA("Model") then
                    continue
                end
                if containsWord(child.Name, WEAPON_WORDS)
                    and not containsWord(child.Name, NOT_WEAPON_WORDS) then
                    add("ViewModel", child.Name, child)
                end
                if string.find(string.lower(child.Name), "viewmodel", 1, true) then

                    for _, held: Instance in ipairs(child:GetChildren()) do
                        if not held:IsA("Model") and not held:IsA("BasePart") then
                            continue
                        end
                        if not isMeleeName(held.Name) then
                            continue
                        end
                        add("ViewModel", held.Name, held)
                    end
                end
            end
        end

        local playerGui: Instance? = localPlayer:FindFirstChild("PlayerGui")
        if playerGui then
            for _, descendant: Instance in ipairs(playerGui:GetDescendants()) do
                if not descendant:IsA("GuiButton") then
                    continue
                end
                if isMenuOwned(descendant) then

                    continue
                end
                if containsWord(descendant.Name, NOT_WEAPON_WORDS) then
                    continue
                end
                local named: boolean = containsWord(descendant.Name, WEAPON_WORDS)
                if not named then

                    if not everything then
                        continue
                    end
                    if not ancestryMatches(descendant, TOUCH_WORDS, 4) then
                        continue
                    end
                    add("Button", descendant.Name, descendant)
                    continue
                end
                local inInventory: boolean =
                    ancestryMatches(descendant, INVENTORY_WORDS, 4)
                add(inInventory and "Slot" or "Button", descendant.Name, descendant)
            end
        end

        library.cache = found
        library.cachedAt = now
        library.cachedAll = everything
        library.cachedMelee = meleeOnly
        return found
    end

    function library:Labels(query: any?): {string}
        local labels: {string} = {}
        for _, candidate: Candidate in ipairs(library:Scan(query)) do
            table.insert(labels, candidate.label .. "  ·  " .. candidate.kind)
        end
        table.sort(labels)
        return labels
    end

    function library:IsMelee(name: string): boolean
        return isMeleeName(name)
    end

    function library:Find(label: string): Candidate?
        local wanted: string = string.lower(label)
        for _, candidate: Candidate in ipairs(library:Scan({All = true})) do
            if string.lower(candidate.label) == wanted then
                return candidate
            end
            if string.lower(candidate.label .. "  ·  " .. candidate.kind) == wanted then
                return candidate
            end
        end
        return nil
    end

    function library:Best(query: any?): Candidate?
        local found: {Candidate} = library:Scan(query or {All = false})

        local order: {string} = {"Game", "Tool", "Button", "Slot", "ViewModel"}
        local character: Model? = localPlayer.Character
        for _, kind: string in ipairs(order) do
            for _, candidate: Candidate in ipairs(found) do
                if candidate.kind ~= kind then
                    continue
                end
                if kind == "Tool"
                    and character
                    and candidate.instance.Parent ~= character
                    and not library.allowEquip then

                    continue
                end
                return candidate
            end
        end
        return found[1]
    end

    function library:Swing(): boolean

        local candidate: Candidate? = library:Best({Melee = true})
            or library:Best()
        if not candidate then
            return false
        end
        return library:Activate(candidate :: Candidate)
    end

    function library:Activate(candidate: Candidate, target: any?): boolean
        local instance: Instance = candidate.instance
        if candidate.kind == "Game" then

            if not library.gameSource or type(library.gameSource.press) ~= "function" then
                return false
            end
            local ok: boolean, pressed: any =
                pcall(library.gameSource.press, candidate.label, target)
            return ok and pressed == true
        end
        if not instance.Parent then
            return false
        end
        if candidate.kind == "Tool" then
            local tool: Tool = instance :: Tool

            if library.allowEquip and tool.Parent ~= localPlayer.Character then
                local humanoid: Humanoid? = localPlayer.Character
                    and localPlayer.Character:FindFirstChildOfClass("Humanoid") :: Humanoid?
                if humanoid then
                    pcall(function(): ()
                        (humanoid :: Humanoid):EquipTool(tool)
                    end)
                end
            end
            return pcall(function(): ()
                tool:Activate()
            end)
        end
        if candidate.kind == "Button" or candidate.kind == "Slot" then
            return library:PressButton(instance :: GuiButton)
        end
        if candidate.kind == "ViewModel" then

            for _, other: Candidate in ipairs(library:Scan({All = true})) do
                if other.kind == "Button" then
                    return library:PressButton(other.instance :: GuiButton)
                end
            end
            return false
        end
        return false
    end

    function library:Destroy(): ()
        if activeLibrary == library then
            activeLibrary = nil
        end
    end

    activeLibrary = (library :: any) :: WeaponLibrary
    Module.Initialized = true
    return (library :: any) :: WeaponLibrary
end

function Module.destroy(): ()
    local library: WeaponLibrary? = activeLibrary
    if library then
        library:Destroy()
    end
    activeLibrary = nil
    Module.Initialized = false
end

return Module
