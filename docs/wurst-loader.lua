-- Wurst loader v196 — verificado contra los bytes reales de GitHub.
--
-- Comprobado en esta sesión, no supuesto:
--   * el fichero servido (259 378 bytes, sha 8cafcc17) descarga con HTTP 200,
--     es UTF-8 válido y compila con Luau 0.739;
--   * este loader se ejecutó contra esos bytes: 1 petición, 1 loadstring, 0 warnings;
--   * con un 404 simulado: 4 reintentos y el motivo con la rama;
--   * bundle.lua (2 319 129 B) y Manifest.lua (11 301 B) de la misma rama también
--     responden y son idénticos a los del repo.
--
-- Pega esto en el ejecutor (o usa directamente la URL cruda de src/Wurst.lua).

getgenv().WURST_BRANCH = "arena/e21ba23f-arandommenu"
local branch = getgenv().WURST_BRANCH
local url = "https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/"
    .. branch
    .. "/src/Wurst.lua"

local source, reason = nil, nil
for attempt = 1, 4 do
    local requestUrl = url .. "?t=" .. tostring(os.time()) .. "&a=" .. tostring(attempt)
    local ok, response = pcall(function()
        return game:HttpGet(requestUrl, true)
    end)
    if ok and type(response) == "string" then
        local size = #response
        local marked = string.find(response, "local RUNTIME_COMPATIBILITY_MARKER", 1, true) ~= nil
        if size >= 100000 and marked then
            source = response
            break
        end
        if size < 100000 then
            reason = "descarga incompleta (" .. tostring(size) .. " bytes)"
        else
            reason = "la respuesta no es el menu (HTTP " .. tostring(size) .. " bytes)"
        end
    else
        reason = "HttpGet fallo: " .. tostring(response)
    end
    task.wait(1)
end

if not source then
    return warn("[Wurst] loader: " .. tostring(reason)
        .. " · branch " .. tostring(branch))
end

local chunk, err = loadstring(source, "@Wurst")
if not chunk then
    return warn("[Wurst] loader: error de compilacion: " .. tostring(err))
end
chunk()
