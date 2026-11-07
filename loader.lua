-- Wurst loader · v195
--
-- Dos líneas y listo:
--
--   loadstring(game:HttpGet("https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/arena/7446e4e3-arandommenu/loader.lua"))()
--
-- Este fichero es pequeño a propósito (~4 KB): si el ejecutor puede compilar
-- esto, puede llegar al menú. Todo lo que puede salir mal al bajar el menú
-- (255 KB) se resuelve aquí dentro, con reintentos, espejos y un mensaje que
-- dice la causa, en lugar de `attempt to call a nil value`.
--
-- Qué cubre, y por qué:
--   * `game:HttpGet` puede no existir en un ejecutor → se prueban `request`,
--     `http_request`, `syn.request` e `http.get`.
--   * `loadstring` puede no estar expuesto y sí `load` → se usan los dos.
--   * la descarga puede venir cortada, puede ser una página de error, o el CDN
--     puede devolver una copia vieja → tamaño mínimo + cabecera + `?t=`/`&a=`
--     (rompe la cache del CDN y la del ejecutor) + un segundo espejo (jsDelivr).
--   * un error DENTRO del menú salía como `Script ''` → el chunk se compila con
--     nombre `@Wurst`, así que se ve `Wurst:3412`.

local BRANCH: string = "arena/7446e4e3-arandommenu"
local MARK: string = "local RUNTIME_COMPATIBILITY_MARKER"
local MIN_BYTES: number = 100000
local ATTEMPTS: number = 4

local SOURCES: {string} = {
    "https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/"
        .. BRANCH
        .. "/src/Wurst.lua",
    "https://cdn.jsdelivr.net/gh/XzAngel19/ARandomMenu@"
        .. BRANCH
        .. "/src/Wurst.lua",
}

-- El entorno del ejecutor: `getfenv()` en Roblox Luau, `_G` si no existe.
local function environment(): any
    if type(getfenv) == "function" then
        local ok: boolean, value: any = pcall(getfenv)
        if ok and type(value) == "table" then
            return value
        end
    end
    return _G
end

local function compiler(): any
    local env: any = environment()
    if type(env.loadstring) == "function" then
        return env.loadstring
    end
    if type(loadstring) == "function" then
        return loadstring
    end
    if type(load) == "function" then
        return load
    end
    return nil
end

local function httpGet(url: string): (string?, string?)
    local ok: boolean, body: any = pcall(function(): any
        if type((game :: any).HttpGet) == "function" then
            return (game :: any):HttpGet(url)
        end
        error("no game:HttpGet")
    end)
    if ok and type(body) == "string" and body ~= "" then
        return body, nil
    end

    -- Executors that only expose a request wrapper.
    local env: any = environment()
    local wrappers: {any} = {}
    if type(env.request) == "function" then
        table.insert(wrappers, env.request)
    end
    if type(env.http_request) == "function" then
        table.insert(wrappers, env.http_request)
    end
    if type(env.http) == "table" and type(env.http.get) == "function" then
        table.insert(wrappers, env.http.get)
    end
    if type(env.syn) == "table" and type(env.syn.request) == "function" then
        table.insert(wrappers, env.syn.request)
    end
    for _, wrapper: any in ipairs(wrappers) do
        local sent: boolean, answer: any = pcall(wrapper, {
            Url = url,
            Method = "GET",
        })
        if sent and type(answer) == "table" and type(answer.Body) == "string" then
            return answer.Body, nil
        end
    end
    return nil, "no working HTTP function (game:HttpGet, request, http_request, http.get, syn.request)"
end

-- One download, validated before it is ever compiled: a short body or a body
-- that does not start with the menu's first line is a failure with a reason,
-- not a mysterious nil.
local function download(url: string): (string?, string?)
    local body: string?, errorText: string? = httpGet(url)
    if not body then
        return nil, tostring(errorText)
    end
    if #body < MIN_BYTES then
        return nil, "incomplete download (" .. #body .. " bytes)"
    end
    if string.sub(body, 1, #MARK) ~= MARK then
        return nil, "the answer is not the menu (" .. #body .. " bytes, starts with "
            .. string.sub(body, 1, 40):gsub("%s+", " ") .. ")"
    end
    return body, nil
end

local compile: any = compiler()
if type(compile) ~= "function" then
    warn("[Wurst] loader: this executor exposes neither loadstring nor load")
    return
end

local function globalEnv(): any
    if type(getgenv) == "function" then
        local ok: boolean, value: any = pcall(getgenv)
        if ok and type(value) == "table" then
            return value
        end
    end
    return environment()
end
globalEnv().WURST_BRANCH = BRANCH

local chunk: any = nil
local reason: string = "unknown"
for attempt: number = 1, ATTEMPTS do
    for index: number = 1, #SOURCES do
        local url: string = SOURCES[index]
            .. "?t=" .. tostring(os.time())
            .. "&a=" .. tostring(attempt)
            .. "&m=" .. tostring(index)
        local body: string?, errorText: string? = download(url)
        if body then
            local built: any, compileError: any = compile(body, "@Wurst")
            if built then
                chunk = built
                break
            end
            reason = "compile error: " .. tostring(compileError)
        else
            reason = tostring(errorText)
        end
    end
    if chunk then
        break
    end
    if attempt < ATTEMPTS then
        task.wait(1)
    end
end

if not chunk then
    warn("[Wurst] loader: " .. reason)
    return
end

chunk()
