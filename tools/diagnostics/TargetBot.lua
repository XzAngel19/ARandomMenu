--[[
    WURST TARGET BOT v5  (diagnostic, standalone -- for YOUR OWN alt)

    Lo que demostraron las versiones anteriores:
      - Humanoid:Move es ignorado por este controlador.
      - Humanoid:MoveTo sí mueve al personaje.
      - Humanoid.Jump tampoco basta; ChangeState(Jumping) es la vía.
      - Ir en línea recta hacia un punto produce choques, atascos y
        movimientos robóticos.

    v5 cambia la arquitectura:

      * NAVEGACIÓN REAL: un planificador (10 Hz) puntúa 24 direcciones
        con rayos paralelos al cuerpo (izquierda/centro/derecha),
        altura baja y alta, y sonda de suelo en el punto destino. Elige
        waypoint practicable, no solo "la dirección que quiero".
      * MOVIMIENTO NATURAL: velocidad con aceleración y frenado,
        tiempo de reacción al cambiar de intención (120-320 ms),
        ruido suave continuo (suma de senos, no azar por tick),
        giros limitados y paradas con inercia. Nada de tele-giros.
      * WALLCHECKS COMPLETOS: pasillo de 3 rayos, rayo de rodillas
        para decidir saltos de obstáculo, suelo y caída en el destino,
        línea de visión rival->punto para buscar COBERTURA real, y
        recuperación por anillos cuando todo está bloqueado.
      * ANTI-ATASCO POR DESPLAZAMIENTO REAL: si el cuerpo no viaja,
        salta, escapa por el hueco mejor puntuado, cambia de patrón y,
        en Imposible, puede salir con un blink.
      * IMPOSIBLE: dash con LinearVelocity temporal, doble salto con
        control aéreo, blink a punto validado (pasillo + suelo) y
        vuelo con altura sobre el terreno, velocidad suavizada y
        evasión 3D. Es un test extremo: no representa a un jugador.

    Menú: Activo, Modo, Patrón, Saltos, Distancia, Velocidad,
    Extras (dash/vuelo/blink), Rival, Reanclar y Detener.
    Inyectar una vez para empezar; otra vez (o el botón rojo) para
    retirar bot, menú y todos los objetos físicos creados.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local genv = getgenv()
if genv.WURST_TARGET_BOT and genv.WURST_TARGET_BOT.active then
    local old = genv.WURST_TARGET_BOT
    if old.cleanup then
        pcall(old.cleanup)
    else
        old.active = false
        if old.gui then pcall(function() old.gui:Destroy() end) end
    end
    print("[TargetBot] removed")
    return
end

local SETTINGS = {
    running = true,
    difficulty = "Dificil",
    jumps = "Normal",
    distance = "Media",
    speed = "Normal",
    opponent = "Auto",
    extras = "Todo",
    pattern = "Auto",
}
-- turn: giro maximo (grados/s). reaction: retardo humano al cambiar
-- de intencion. accel: rampa de velocidad (fraccion/s). flip: ritmo
-- de cambio de lado. jump: intervalo entre saltos. dash: intervalo
-- entre acelerones (0 = nunca).
local PROFILES = {
    Realista = {turn = 215, reaction = 0.26, accel = 1.5,
        flipMin = 1.0, flipMax = 1.8, jumpMin = 2.8, jumpMax = 4.6,
        dashMin = 0, dashMax = 0, noise = 0.16},
    Dificil = {turn = 340, reaction = 0.18, accel = 2.4,
        flipMin = 0.6, flipMax = 1.1, jumpMin = 1.3, jumpMax = 2.6,
        dashMin = 4, dashMax = 7, noise = 0.24},
    Caotico = {turn = 540, reaction = 0.11, accel = 3.6,
        flipMin = 0.36, flipMax = 0.7, jumpMin = 0.6, jumpMax = 1.25,
        dashMin = 1.8, dashMax = 3.4, noise = 0.38},
    Imposible = {turn = 780, reaction = 0.05, accel = 5.5,
        flipMin = 0.2, flipMax = 0.48, jumpMin = 0.32, jumpMax = 0.75,
        dashMin = 0.8, dashMax = 1.9, noise = 0.55},
}
local JUMP_MULT = {Sin = 0, Normal = 1, Frecuentes = 0.55}
local DISTANCE = {Cerca = 14, Media = 24, Lejos = 36}
local SPEEDS = {Normal = 16, Rapida = 22, Extrema = 30}

local state = {
    active = true,
    heading = math.random() * math.pi * 2,
    desiredHeading = 0,
    moveHeading = 0,
    waypoint = nil,
    wallClearance = 99,
    speedScale = 0,
    desiredIntensity = 1,
    behavior = "strafe",
    behaviorLabel = "Strafe lateral",
    patternUntil = 0,
    pendingHeading = nil,
    reactionAt = 0,
    jumpQueued = false,
    obstacleJump = false,
    nextJumpAt = os.clock() + 2,
    jumpAttempts = 0,
    jumpsDone = 0,
    jumpCheckAt = nil,
    doubleJumpReady = false,
    nextDashAt = os.clock() + 4,
    dashUntil = 0,
    dashDirection = Vector3.zero,
    dashAttachment = nil,
    dashVelocity = nil,
    nextBlinkAt = os.clock() + 6,
    blinkCount = 0,
    flying = false,
    flightUntil = 0,
    flightBaseY = 0,
    flightAttachment = nil,
    flightVelocity = nil,
    flightVelocityValue = Vector3.zero,
    standUntil = 0,
    coverPoint = nil,
    coverUntil = 0,
    forceSwitch = false,
    recoveryUntil = 0,
    recoveryHeading = 0,
    lastReplan = 0,
    lastMoveTo = 0,
    noiseA = math.random() * 20,
    noiseB = math.random() * 20,
    noiseC = math.random() * 20,
    gui = nil,
    cleanup = nil,
}
state.desiredHeading = state.heading
state.moveHeading = state.heading
genv.WURST_TARGET_BOT = state

local function characterParts()
    local character = LocalPlayer.Character
    if not character then return nil, nil, nil end
    return character,
        character:FindFirstChildOfClass("Humanoid"),
        character:FindFirstChild("HumanoidRootPart")
end

local _, humanoid0, root0 = characterParts()
if not humanoid0 or not root0 then
    print("[TargetBot] character not ready -- inject again in game")
    state.active = false
    return
end
local originalWalkSpeed = humanoid0.WalkSpeed
local anchor = root0.Position

local function getOpponent()
    if SETTINGS.opponent ~= "Auto" then
        local named = Players:FindFirstChild(SETTINGS.opponent)
        if named and named ~= LocalPlayer and named.Character then
            local root = named.Character
                :FindFirstChild("HumanoidRootPart")
            if root then return named, root end
        end
    end
    local myRoot = select(3, characterParts())
    if not myRoot then return nil, nil end
    local best, bestRoot, bestDistance = nil, nil, math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local root = player.Character
                :FindFirstChild("HumanoidRootPart")
            if root then
                local distance =
                    (root.Position - myRoot.Position).Magnitude
                if distance < bestDistance then
                    best, bestRoot, bestDistance =
                        player, root, distance
                end
            end
        end
    end
    return best, bestRoot
end

local function wrapAngle(a)
    while a > math.pi do a -= math.pi * 2 end
    while a < -math.pi do a += math.pi * 2 end
    return a
end
local function vecFromAngle(a)
    return Vector3.new(math.sin(a), 0, math.cos(a))
end
local function angleOf(v)
    return math.atan2(v.X, v.Z)
end
local function flatUnit(v, fallback)
    local flat = Vector3.new(v.X, 0, v.Z)
    if flat.Magnitude < 0.001 then return fallback end
    return flat.Unit
end
local function randomBetween(a, b)
    return a + math.random() * (b - a)
end
local function smoothNoise(t)
    return math.sin(t * 0.7 + state.noiseA) * 0.55
        + math.sin(t * 1.7 + state.noiseB) * 0.3
        + math.sin(t * 3.1 + state.noiseC) * 0.15
end
local function extrasAllow(name)
    if SETTINGS.extras == "Todo" then return true end
    if SETTINGS.extras == "Sin extras" then return false end
    return SETTINGS.extras == name
end

--------------------------------------------------------------------------
-- Raycast helpers. El filtro excluye a TODOS los personajes: un rival
-- no es una pared, y nuestro propio cuerpo tampoco.
--------------------------------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function refreshFilter(characterNow)
    local filter = {}
    if characterNow then table.insert(filter, characterNow) end
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            table.insert(filter, player.Character)
        end
    end
    rayParams.FilterDescendantsInstances = filter
end

local function cast(origin, direction)
    local result = workspace:Raycast(origin, direction, rayParams)
    if not result then return nil, direction.Magnitude end
    -- Geometria sin colision (decoracion consultable) no es pared.
    if result.Instance and result.Instance:IsA("BasePart")
        and not result.Instance.CanCollide
        and result.Instance.ClassName ~= "Terrain" then
        return nil, direction.Magnitude
    end
    return result, result.Distance
end

local function wallDistance(rootPos, dirVec, length, yOffset)
    local _, dist = cast(
        rootPos + Vector3.new(0, yOffset, 0), dirVec * length)
    return dist
end

-- Distancia libre del pasillo: tres rayos paralelos (ancho del cuerpo).
local function corridorClearance(rootPos, dirVec, length)
    local perp = Vector3.new(dirVec.Z, 0, -dirVec.X)
    local minDist = length
    for _, side in ipairs({-1.4, 0, 1.4}) do
        local origin = rootPos + perp * side
            + Vector3.new(0, 2, 0)
        local _, dist = cast(origin, dirVec * length)
        if dist < minDist then minDist = dist end
    end
    return minDist
end

local function floorAt(rootPos, point)
    local hit, _ = cast(
        point + Vector3.new(0, 4, 0), Vector3.new(0, -11, 0))
    if not hit then return nil end
    return hit.Position.Y
end

--------------------------------------------------------------------------
-- Planificador: puntua direcciones alrededor de la deseada.
-- Devuelve waypoint y deja en state la holgura de pared observada.
--------------------------------------------------------------------------
local function scoreDirection(rootPos, angle, desiredAngle, probeLen)
    local dir = vecFromAngle(angle)
    local clearance = corridorClearance(rootPos, dir, probeLen)
    local reach = math.clamp(clearance - 1.4, 2.2, probeLen)
    local point = rootPos + dir * reach
    local floorY = state.flying and rootPos.Y or floorAt(rootPos, point)
    local align = math.cos(wrapAngle(angle - desiredAngle))
    local turnCost = math.abs(wrapAngle(angle - state.moveHeading))
    local score = align * 46 + clearance * 3.2 - turnCost * 9
    if clearance <= 1.7 then score -= 30 end
    if not state.flying then
        if floorY == nil then
            score -= 26
        elseif rootPos.Y - floorY > 7 then
            score -= 18 -- caida grande: solo si no queda otra
        end
    end
    -- Rayo de rodillas: obstaculo bajo con paso libre arriba y suelo
    -- al otro lado = salto natural, no rodeo. Solo cuenta si esta
    -- acaba siendo la direccion elegida.
    local knee = wallDistance(rootPos, dir, 4, 0.6)
    local head = wallDistance(rootPos, dir, 4, 3.4)
    local jumpable = knee < 3 and head > 4 and floorY ~= nil
        and math.abs(wrapAngle(angle - desiredAngle)) < 0.5
    if jumpable then
        score += 14
    end
    return score, point, clearance, jumpable
end

local function planPath(rootNow, characterNow)
    refreshFilter(characterNow)
    local desired = state.desiredHeading
    if os.clock() < state.recoveryUntil then
        desired = state.recoveryHeading
    end
    local probeLen = 12
    local bestScore, bestPoint, bestAngle, bestClear =
        -math.huge, nil, desired, probeLen
    local bestJumpable = false
    for step = 0, 23 do
        local offset = (step - 11.5) / 11.5 * math.pi
        local angle = desired + offset
        local score, point, clearance, jumpable =
            scoreDirection(rootNow.Position, angle, desired, probeLen)
        -- Histéresis: cambiar de hueco cada tick es lo que parece
        -- robot; el camino anterior recibe una pequena ventaja.
        if math.abs(wrapAngle(angle - state.moveHeading)) < 0.2 then
            score += 4
        end
        if score > bestScore then
            bestScore, bestPoint, bestAngle, bestClear, bestJumpable =
                score, point, angle, clearance, jumpable
        end
    end
    state.moveHeading = bestAngle
    state.waypoint = bestPoint
    state.wallClearance = bestClear
    state.obstacleJump = bestJumpable
    return bestPoint
end

-- Punto con linea de vision bloqueada desde el rival: cobertura real.
local function findCoverPoint(rootNow, oppRoot)
    refreshFilter(select(1, characterParts()))
    local bestPoint, bestScore = nil, -math.huge
    for step = 0, 15 do
        local angle = step / 16 * math.pi * 2
        for _, dist in ipairs({7, 11, 15, 20}) do
            local point = rootNow.Position + vecFromAngle(angle) * dist
            local floorY = floorAt(rootNow.Position, point)
            if floorY ~= nil then
                local eye = oppRoot.Position + Vector3.new(0, 2, 0)
                local targetPos = point + Vector3.new(0, 2, 0)
                local los, losDist = cast(eye, targetPos - eye)
                local blocked = los ~= nil
                    and losDist < (targetPos - eye).Magnitude - 2.5
                if blocked then
                    local score = 30 - dist * 0.7
                        - (point - rootNow.Position).Magnitude * 0.4
                    if score > bestScore then
                        bestScore, bestPoint = score, point
                    end
                end
            end
        end
    end
    return bestPoint
end

--------------------------------------------------------------------------
-- Objetos fisicos temporales (dash / vuelo), siempre con nombre y
-- siempre destruidos al desactivarse.
--------------------------------------------------------------------------
local function destroyPhysics(name1, name2)
    if state[name1] then
        pcall(function() state[name1]:Destroy() end)
        state[name1] = nil
    end
    if state[name2] then
        pcall(function() state[name2]:Destroy() end)
        state[name2] = nil
    end
end

local function setFlight(enabled, humNow, rootNow)
    if enabled then
        if not rootNow or not humNow then return end
        if not state.flightAttachment
            or not state.flightAttachment.Parent then
            state.flightAttachment = Instance.new("Attachment")
            state.flightAttachment.Name = "TargetBotFlightAttachment"
            state.flightAttachment.Parent = rootNow
        end
        if not state.flightVelocity
            or not state.flightVelocity.Parent then
            state.flightVelocity = Instance.new("LinearVelocity")
            state.flightVelocity.Name = "TargetBotFlightVelocity"
            state.flightVelocity.Attachment0 = state.flightAttachment
            state.flightVelocity.RelativeTo =
                Enum.ActuatorRelativeTo.World
            state.flightVelocity.VelocityConstraintMode =
                Enum.VelocityConstraintMode.Vector
            state.flightVelocity.MaxForce = 100000
            state.flightVelocity.Parent = rootNow
        end
        humNow.PlatformStand = true
        state.flying = true
    else
        destroyPhysics("flightVelocity", "flightAttachment")
        if humNow then
            pcall(function() humNow.PlatformStand = false end)
        end
        state.flying = false
    end
end

local function setDash(enabled, rootNow, direction)
    if enabled then
        if not rootNow then return end
        if not state.dashAttachment
            or not state.dashAttachment.Parent then
            state.dashAttachment = Instance.new("Attachment")
            state.dashAttachment.Name = "TargetBotDashAttachment"
            state.dashAttachment.Parent = rootNow
        end
        if not state.dashVelocity or not state.dashVelocity.Parent then
            state.dashVelocity = Instance.new("LinearVelocity")
            state.dashVelocity.Name = "TargetBotDashVelocity"
            state.dashVelocity.Attachment0 = state.dashAttachment
            state.dashVelocity.RelativeTo =
                Enum.ActuatorRelativeTo.World
            state.dashVelocity.VelocityConstraintMode =
                Enum.VelocityConstraintMode.Vector
            state.dashVelocity.MaxForce = 90000
            state.dashVelocity.Parent = rootNow
        end
        local speed = (SPEEDS[SETTINGS.speed] or 16) * 2.6
        state.dashVelocity.VectorVelocity = Vector3.new(
            direction.X * speed,
            math.max(rootNow.AssemblyLinearVelocity.Y, 2),
            direction.Z * speed)
    else
        destroyPhysics("dashVelocity", "dashAttachment")
    end
end

local function tryBlink(rootNow, characterNow)
    -- Destino validado: pasillo libre, suelo y espacio al llegar.
    refreshFilter(characterNow)
    local sides = {math.pi / 2, -math.pi / 2, math.pi,
        math.pi / 4, -math.pi / 4}
    for _, offset in ipairs(sides) do
        local angle = state.moveHeading + offset
            + math.rad(math.random(-20, 20))
        local dir = vecFromAngle(angle)
        local length = randomBetween(8, 14)
        local clearance = corridorClearance(
            rootNow.Position, dir, length + 2)
        if clearance > length then
            local dest = rootNow.Position + dir * length
            local floorY = floorAt(rootNow.Position, dest)
            if floorY ~= nil
                and corridorClearance(dest, dir, 3) > 2.4 then
                local look = dest + vecFromAngle(state.moveHeading)
                rootNow.CFrame = CFrame.lookAt(
                    Vector3.new(dest.X, floorY + 3.2, dest.Z), look)
                state.blinkCount += 1
                return true
            end
        end
    end
    return false
end

--------------------------------------------------------------------------
-- Cerebro: intencion (direccion deseada) segun patron y rival.
--------------------------------------------------------------------------
local BEHAVIOR_LABELS = {
    strafe = "Strafe lateral", orbit = "Orbitando",
    zigzagIn = "Zigzag hacia ti", zigzagOut = "Zigzag alejandose",
    rush = "Rusheando", wander = "Deambulando",
    stopGo = "Paradas y arranques", cover = "Buscando cobertura",
    fake = "Amago y cambio", fly = "VOLANDO",
    airChaos = "Caos aereo", blinkMad = "Blink y dash",
}
local PATTERN_POOL = {
    "strafe", "orbit", "zigzagIn", "cover", "fake",
    "zigzagOut", "rush", "wander", "stopGo", "strafe",
}
local PATTERN_POOL_IMPOSIBLE = {
    "strafe", "fly", "zigzagIn", "airChaos", "cover",
    "blinkMad", "orbit", "fake", "strafe", "fly",
}

local brainThread = task.spawn(function()
    local behaviorUntil = 0
    local flipAt = 0
    local side = 1
    local poolIndex = 0
    local stopStanding, stopSwitchAt = false, 0
    local fakeFlipped = false
    while state.active do
        task.wait(0.08)
        local _, humNow, rootNow = characterParts()
        local now = os.clock()
        local profile = PROFILES[SETTINGS.difficulty]
        if not SETTINGS.running or not humNow
            or humNow.Health <= 0 or not rootNow then
            state.desiredHeading = state.heading
            state.desiredIntensity = 0
            state.flying = false
        else
            state.desiredIntensity = 1
            local forced = SETTINGS.pattern ~= "Auto"
            local wanted = forced and SETTINGS.pattern or nil
            if forced and state.behavior ~= wanted then
                state.behavior = wanted
                behaviorUntil = now + 3600
                flipAt = now
                fakeFlipped = false
                if wanted == "fly" then
                    state.flightBaseY = rootNow.Position.Y + 9
                    state.flightUntil = now + 3600
                end
                if wanted == "cover" then
                    state.coverPoint = nil
                    state.coverUntil = 0
                end
            elseif not forced
                and (now >= behaviorUntil or state.forceSwitch) then
                state.forceSwitch = false
                local pool = SETTINGS.difficulty == "Imposible"
                    and PATTERN_POOL_IMPOSIBLE or PATTERN_POOL
                poolIndex = poolIndex % #pool + 1
                state.behavior = pool[poolIndex]
                local duration = SETTINGS.difficulty == "Realista"
                    and randomBetween(5, 10)
                    or SETTINGS.difficulty == "Dificil"
                        and randomBetween(4, 8)
                        or randomBetween(2.5, 5.5)
                behaviorUntil = now + duration
                flipAt = now
                fakeFlipped = false
                if state.behavior == "fly" then
                    state.flightBaseY = rootNow.Position.Y + 9
                    state.flightUntil = behaviorUntil
                end
                if state.behavior == "cover" then
                    state.coverPoint = nil
                    state.coverUntil = 0
                end
                if state.behavior == "stopGo" then
                    stopStanding, stopSwitchAt = false, now
                end
                -- Reaccion humana: la nueva intencion no entra de
                -- golpe; se anuncia y el pump la aplica tras el retardo.
                state.reactionAt = now + profile.reaction
                print("[TargetBot] behavior: " .. state.behavior)
            end
            state.behaviorLabel =
                BEHAVIOR_LABELS[state.behavior] or state.behavior
            state.flying = state.behavior == "fly"
                and now < state.flightUntil
                and SETTINGS.difficulty == "Imposible"
                and extrasAllow("SoloVuelo")

            local oppPlayer, oppRoot = getOpponent()
            local behavior = state.behavior

            -- Paradas: ciclos de quieto/moverse con tiempos humanos.
            if behavior == "stopGo" then
                if now >= stopSwitchAt then
                    stopStanding = not stopStanding
                    stopSwitchAt = now + (stopStanding
                        and randomBetween(0.35, 0.9)
                        or randomBetween(0.8, 1.8))
                    state.standUntil = stopStanding
                        and stopSwitchAt or 0
                end
                if stopStanding then
                    state.desiredIntensity = 0
                end
            end

            if behavior == "cover" and oppRoot then
                if not state.coverPoint or now >= state.coverUntil then
                    state.coverPoint =
                        findCoverPoint(rootNow, oppRoot)
                    state.coverUntil = now + 6
                end
                if state.coverPoint then
                    local toCover = state.coverPoint
                        - rootNow.Position
                    if Vector3.new(toCover.X, 0, toCover.Z).Magnitude
                        < 2.2 then
                        state.standUntil = now + 0.8
                        state.desiredIntensity = 0
                        state.coverPoint = nil
                        state.coverUntil = now + 1
                        state.forceSwitch = true
                    else
                        state.desiredHeading = angleOf(toCover)
                    end
                else
                    behavior = "strafe"
                end
            end

            if behavior ~= "cover" and oppRoot
                and not (behavior == "stopGo" and stopStanding) then
                -- El rival tambien se mueve: se apunta a donde va a
                -- estar dentro de ~0.25 s, como hace un jugador.
                local oppVel = oppRoot.AssemblyLinearVelocity
                local oppPredicted = oppRoot.Position + Vector3.new(
                    oppVel.X, 0, oppVel.Z) * 0.25
                local away = rootNow.Position - oppPredicted
                local flat = Vector3.new(away.X, 0, away.Z)
                local dist = flat.Magnitude
                local awayUnit = dist > 0.01 and flat.Unit
                    or vecFromAngle(state.heading)
                local towardUnit = -awayUnit
                local tangent = Vector3.new(
                    awayUnit.Z, 0, -awayUnit.X)
                local desired = DISTANCE[SETTINGS.distance]
                -- Banda muerta: dentro de +-3 studs no hay correccion
                -- radial; fuera, rampa hasta 1.
                local radial = 0
                if dist > desired + 3 then
                    radial = math.clamp((dist - desired) / 10, 0, 1)
                elseif dist < desired - 3 then
                    radial = -math.clamp((desired - dist) / 10, 0, 1)
                end

                local tangentWeight, radialWeight = 1, 0.8
                if behavior == "zigzagIn" then
                    radial = math.max(radial, 0.85)
                    tangentWeight = 0.95
                elseif behavior == "zigzagOut" then
                    radial = math.min(radial, -0.85)
                    tangentWeight = 0.95
                elseif behavior == "rush" then
                    radial = 1
                    tangentWeight = 0.3
                elseif behavior == "orbit" then
                    radialWeight = 1.35
                elseif behavior == "wander" then
                    tangentWeight = 0.4
                    radialWeight = 0.3
                elseif behavior == "fake" then
                    tangentWeight = 1
                    radialWeight = 0.5
                end
                if behavior == "strafe" or behavior == "zigzagIn"
                    or behavior == "zigzagOut"
                    or behavior == "orbit"
                    or behavior == "blinkMad" then
                    if now >= flipAt then
                        side = -side
                        flipAt = now + randomBetween(
                            profile.flipMin, profile.flipMax)
                        if behavior == "orbit"
                            and math.random() > 0.35 then
                            side = -side
                        end
                    end
                elseif behavior == "fake" then
                    local phaseLen = behaviorUntil - now
                    if not fakeFlipped and phaseLen < 2.2 then
                        side = -side
                        fakeFlipped = true
                    end
                end
                local move = tangent * (side * tangentWeight)
                    + towardUnit * (radial * radialWeight)
                if dist < 6 then
                    -- Pegado al rival: retroceso franco.
                    move = awayUnit * 1.2 + tangent * (side * 0.6)
                end
                if move.Magnitude > 0.05 then
                    local noiseAngle = smoothNoise(now)
                        * profile.noise
                    local angle = angleOf(move) + noiseAngle
                    if now >= (state.reactionAt or 0) then
                        state.desiredHeading = angle
                    else
                        state.pendingHeading = angle
                    end
                end
            elseif behavior ~= "cover" then
                if now >= flipAt then
                    flipAt = now + randomBetween(0.5, 1.0)
                    state.desiredHeading = state.heading
                        + math.rad(math.random(-80, 80))
                end
            end
            if state.pendingHeading
                and now >= (state.reactionAt or 0) then
                state.desiredHeading = state.pendingHeading
                state.pendingHeading = nil
            end

            -- Sujecion al ancla (no durante el vuelo).
            if not state.flying then
                local flat = Vector3.new(
                    rootNow.Position.X - anchor.X, 0,
                    rootNow.Position.Z - anchor.Z)
                if flat.Magnitude > 55 then
                    state.desiredHeading =
                        math.atan2(-flat.X, -flat.Z)
                    state.behaviorLabel = "Volviendo al ancla"
                end
            end

            -- Saltos programados, independientes del strafe.
            local jumpMult = JUMP_MULT[SETTINGS.jumps]
            if jumpMult > 0 and not state.flying
                and now >= state.nextJumpAt then
                state.jumpQueued = true
                state.nextJumpAt = now + randomBetween(
                    profile.jumpMin, profile.jumpMax) * jumpMult
            end
        end
    end
end)

--------------------------------------------------------------------------
-- Bomba: direccion suave, velocidad con inercia, saltos, dash,
-- blink, vuelo y anti-atasco por desplazamiento real.
--------------------------------------------------------------------------
local pumpConnection
local anchorConnection
local progressPos, progressAt, stuckCount = root0.Position, os.clock(), 0

pumpConnection = RunService.Heartbeat:Connect(function(dt)
    if not state.active then return end
    local characterNow, humNow, rootNow = characterParts()
    if not humNow or not rootNow then return end
    local now = os.clock()
    if humNow.Health <= 0 then
        setFlight(false, humNow, rootNow)
        setDash(false, rootNow)
        return
    end
    if not SETTINGS.running then
        setFlight(false, humNow, rootNow)
        setDash(false, rootNow)
        humNow:MoveTo(rootNow.Position)
        return
    end
    dt = math.clamp(dt, 1 / 240, 1 / 20)
    local profile = PROFILES[SETTINGS.difficulty]

    -- Inercia de velocidad: la escala sube/baja con aceleracion
    -- limitada; el WalkSpeed efectivo la sigue.
    local accelStep = profile.accel * dt
    state.speedScale = state.speedScale + math.clamp(
        state.desiredIntensity - state.speedScale,
        -accelStep, accelStep)
    if not state.flying then
        local wanted = (SPEEDS[SETTINGS.speed] or 16)
            * math.clamp(state.speedScale, 0.2, 1.12)
        if math.abs(humNow.WalkSpeed - wanted) > 0.6 then
            humNow.WalkSpeed = wanted
        end
    end

    -- Giro suave hacia la direccion deseada.
    local delta = wrapAngle(state.desiredHeading - state.heading)
    local maxTurn = math.rad(profile.turn) * dt
    state.heading = wrapAngle(
        state.heading + math.clamp(delta, -maxTurn, maxTurn))

    state.flying = state.flying
        and SETTINGS.difficulty == "Imposible"
        and extrasAllow("SoloVuelo")

    if state.flying then
        if not state.flightVelocity
            or not state.flightVelocity.Parent then
            setFlight(true, humNow, rootNow)
            state.flightBaseY = rootNow.Position.Y + 9
            state.flightVelocityValue = Vector3.zero
        end
        refreshFilter(characterNow)
        local floorY = floorAt(rootNow.Position, rootNow.Position)
        local hoverBase = floorY and (floorY + 9)
            or state.flightBaseY
        local dir = vecFromAngle(state.heading)
        -- Evasion 3D: pared delante a altura de vuelo = subir o girar.
        local ahead = wallDistance(
            rootNow.Position, dir, 8, 4)
        if ahead < 5 then
            hoverBase += 5
            state.desiredHeading = state.heading
                + math.rad(55)
        end
        local cruise = (SPEEDS[SETTINGS.speed] or 16) * 1.7
        local targetY = hoverBase + math.sin(now * 1.7) * 1.6
        local vy = math.clamp(
            (targetY - rootNow.Position.Y) * 3.5, -20, 22)
        local wantedVel = Vector3.new(
            dir.X * cruise, vy, dir.Z * cruise)
        local blend = 1 - math.exp(-dt * 4)
        state.flightVelocityValue =
            state.flightVelocityValue:Lerp(wantedVel, blend)
        state.flightVelocity.VectorVelocity =
            state.flightVelocityValue
        humNow:MoveTo(rootNow.Position)
    else
        if state.flightVelocity or state.flightAttachment then
            setFlight(false, humNow, rootNow)
        end
        -- Dash activo: ventana corta con su propio objeto.
        if os.clock() < state.dashUntil then
            if not state.dashVelocity
                or not state.dashVelocity.Parent then
                setDash(true, rootNow,
                    vecFromAngle(state.dashHeading or state.heading))
            end
        elseif state.dashVelocity or state.dashAttachment then
            setDash(false, rootNow)
        end

        local standing = now < state.standUntil
            or state.desiredIntensity <= 0.05
        if standing then
            humNow:MoveTo(rootNow.Position)
        else
            if now - state.lastReplan > 0.1 then
                state.lastReplan = now
                planPath(rootNow, characterNow)
            end
            if state.waypoint and now - state.lastMoveTo > 0.14 then
                state.lastMoveTo = now
                humNow:MoveTo(state.waypoint)
            end
            -- Salto de obstaculo detectado por el planificador.
            if state.obstacleJump then
                state.obstacleJump = false
                state.jumpQueued = true
            end
            -- Dash programado.
            if profile.dashMax > 0
                and extrasAllow("SoloDash")
                and now >= state.nextDashAt then
                state.nextDashAt = now + randomBetween(
                    profile.dashMin, profile.dashMax)
                state.dashHeading = state.moveHeading
                    + (math.random() < 0.5
                        and -math.pi / 2 or math.pi / 2)
                state.dashUntil = now + 0.18
                setDash(true, rootNow,
                    vecFromAngle(state.dashHeading))
                state.jumpQueued = true
            end
            -- Blink (solo Imposible): salida o cambio de lado.
            if SETTINGS.difficulty == "Imposible"
                and extrasAllow("SoloBlink")
                and now >= state.nextBlinkAt then
                state.nextBlinkAt = now + randomBetween(2.5, 5)
                tryBlink(rootNow, characterNow)
            end
        end

        -- Salto: ChangeState (lo que este controlador obedece).
        local grounded = humNow.FloorMaterial ~= Enum.Material.Air
        if state.jumpQueued and not standing then
            state.jumpQueued = false
            if grounded then
                state.jumpAttempts += 1
                state.jumpCheckAt = now + 0.3
                state.doubleJumpReady =
                    SETTINGS.difficulty == "Imposible"
                pcall(function()
                    humNow:ChangeState(
                        Enum.HumanoidStateType.Jumping)
                end)
                pcall(function() humNow.Jump = true end)
            end
        end
        if state.jumpCheckAt and now >= state.jumpCheckAt then
            state.jumpCheckAt = nil
            local vy = rootNow.AssemblyLinearVelocity.Y
            local name = ""
            pcall(function() name = humNow:GetState().Name end)
            if vy > 8 or name == "Jumping" or name == "Freefall" then
                state.jumpsDone += 1
            end
        end
        -- Doble salto / control aereo (Imposible).
        if not grounded
            and SETTINGS.difficulty == "Imposible" then
            local v = rootNow.AssemblyLinearVelocity
            if state.doubleJumpReady and v.Y < 6
                and extrasAllow("SoloDash") then
                state.doubleJumpReady = false
                local dir = vecFromAngle(state.moveHeading)
                rootNow.AssemblyLinearVelocity = Vector3.new(
                    dir.X * 24, 34, dir.Z * 24)
                state.jumpsDone += 1
            else
                -- Deriva aerea suave hacia el waypoint.
                local dir = vecFromAngle(state.moveHeading)
                local steered = Vector3.new(
                    v.X + dir.X * dt * 16, v.Y,
                    v.Z + dir.Z * dt * 16)
                local flat = Vector3.new(steered.X, 0, steered.Z)
                if flat.Magnitude > 36 then
                    flat = flat.Unit * 36
                    steered = Vector3.new(flat.X, v.Y, flat.Z)
                end
                rootNow.AssemblyLinearVelocity = steered
            end
        end

        -- Anti-atasco por desplazamiento real.
        if not standing and now - progressAt >= 0.7 then
            local traveled =
                (rootNow.Position - progressPos).Magnitude
            progressPos = rootNow.Position
            progressAt = now
            if traveled < 0.45 then
                stuckCount += 1
                state.jumpQueued = true
                -- Escaneo global: el hueco mas claro manda.
                refreshFilter(characterNow)
                local bestAngle, bestClear =
                    state.heading + math.pi, -1
                for step = 0, 15 do
                    local angle = step / 16 * math.pi * 2
                    local clear = corridorClearance(
                        rootNow.Position, vecFromAngle(angle), 10)
                    if clear > bestClear then
                        bestClear, bestAngle = clear, angle
                    end
                end
                state.recoveryHeading = bestAngle
                state.recoveryUntil = now + 0.85
                if stuckCount >= 2 then
                    stuckCount = 0
                    state.forceSwitch = true
                    if SETTINGS.difficulty == "Imposible"
                        and extrasAllow("SoloBlink") then
                        tryBlink(rootNow, characterNow)
                    end
                    print("[TargetBot] stuck -- escape + new behavior")
                end
            else
                stuckCount = 0
            end
        end
    end
end)

anchorConnection = LocalPlayer.CharacterAdded:Connect(
    function(character)
        task.wait(1)
        local rootNow =
            character:FindFirstChild("HumanoidRootPart")
        if rootNow then
            anchor = rootNow.Position
            progressPos = rootNow.Position
            progressAt = os.clock()
            print("[TargetBot] re-anchored at respawn")
        end
    end)

local function cleanup()
    state.active = false
    SETTINGS.running = false
    pcall(function() task.cancel(brainThread) end)
    local _, humNow, rootNow = characterParts()
    setFlight(false, humNow, rootNow)
    setDash(false, rootNow)
    if pumpConnection then pumpConnection:Disconnect() end
    if anchorConnection then anchorConnection:Disconnect() end
    if humNow then
        pcall(function() humNow.WalkSpeed = originalWalkSpeed end)
        pcall(function() humNow.PlatformStand = false end)
        if rootNow then
            pcall(function() humNow:MoveTo(rootNow.Position) end)
        end
    end
    if state.gui then
        pcall(function() state.gui:Destroy() end)
    end
end
state.cleanup = cleanup

--------------------------------------------------------------------------
-- Mini menu
--------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "WurstTargetBot"
gui.ResetOnSpawn = false
state.gui = gui
local parentOk = pcall(function() gui.Parent = gethui() end)
if not parentOk or not gui.Parent then
    pcall(function()
        gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end)
end

local frame = Instance.new("Frame")
frame.Name = "Panel"
frame.Size = UDim2.fromOffset(200, 404)
frame.Position = UDim2.new(0, 12, 0.5, -202)
frame.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
frame.BackgroundTransparency = 0.12
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = gui

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 24)
title.BackgroundColor3 = Color3.fromRGB(14, 14, 17)
title.Text = "  TargetBot v5"
title.TextColor3 = Color3.fromRGB(240, 240, 240)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.SourceSansBold
title.TextSize = 15
title.Parent = frame

local dragging, dragStart, frameStart = false, nil, nil
title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        frameStart = frame.Position
    end
end)
title.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)
local dragConnection = RunService.RenderStepped:Connect(function()
    if dragging and dragStart then
        local mouse = LocalPlayer:GetMouse()
        frame.Position = UDim2.new(
            frameStart.X.Scale,
            frameStart.X.Offset + (mouse.X - dragStart.X),
            frameStart.Y.Scale,
            frameStart.Y.Offset + (mouse.Y - dragStart.Y))
    end
end)
table.insert(state, dragConnection)

local function makeLabel(y, height, color, size)
    local label = Instance.new("TextLabel")
    label.Position = UDim2.fromOffset(8, y)
    label.Size = UDim2.new(1, -16, 0, height)
    label.BackgroundTransparency = 1
    label.TextColor3 = color
    label.Font = Enum.Font.SourceSans
    label.TextSize = size
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Text = "..."
    label.Parent = frame
    return label
end
local status1 = makeLabel(28, 16, Color3.fromRGB(170, 220, 170), 13)
local status2 = makeLabel(44, 16, Color3.fromRGB(190, 190, 200), 12)

local function makeButton(y, text)
    local button = Instance.new("TextButton")
    button.Position = UDim2.fromOffset(8, y)
    button.Size = UDim2.new(1, -16, 0, 25)
    button.BackgroundColor3 = Color3.fromRGB(45, 45, 54)
    button.BorderSizePixel = 0
    button.TextColor3 = Color3.fromRGB(235, 235, 235)
    button.Font = Enum.Font.SourceSansBold
    button.TextSize = 13
    button.Text = text
    button.Parent = frame
    return button
end

local function cycleIn(list, value)
    for index, item in ipairs(list) do
        if item == value then return list[index % #list + 1] end
    end
    return list[1]
end

local runButton = makeButton(66, "Activo: SI")
runButton.MouseButton1Click:Connect(function()
    SETTINGS.running = not SETTINGS.running
    runButton.Text = SETTINGS.running and "Activo: SI" or "Activo: NO"
end)
local diffButton = makeButton(97, "Modo: Dificil")
diffButton.MouseButton1Click:Connect(function()
    SETTINGS.difficulty = cycleIn(
        {"Realista", "Dificil", "Caotico", "Imposible"},
        SETTINGS.difficulty)
    diffButton.Text = "Modo: " .. SETTINGS.difficulty
    if SETTINGS.difficulty ~= "Imposible" then
        state.flying = false
        state.flightUntil = 0
    end
end)
local PATTERN_LIST = {
    {id = "Auto", label = "Auto"},
    {id = "strafe", label = "Strafe"},
    {id = "orbit", label = "Orbita"},
    {id = "zigzagIn", label = "Zigzag In"},
    {id = "zigzagOut", label = "Zigzag Out"},
    {id = "rush", label = "Rush"},
    {id = "cover", label = "Cobertura"},
    {id = "fake", label = "Amago"},
    {id = "stopGo", label = "Stop-Go"},
    {id = "wander", label = "Deambular"},
    {id = "fly", label = "Vuelo"},
}
local patternButton = makeButton(128, "Patron: Auto")
patternButton.MouseButton1Click:Connect(function()
    local current = 1
    for index, entry in ipairs(PATTERN_LIST) do
        if entry.id == SETTINGS.pattern then current = index end
    end
    local nextEntry = PATTERN_LIST[current % #PATTERN_LIST + 1]
    SETTINGS.pattern = nextEntry.id
    patternButton.Text = "Patron: " .. nextEntry.label
    if nextEntry.id == "Auto" then
        state.forceSwitch = true
    end
end)
local jumpButton = makeButton(159, "Saltos: Normal")
jumpButton.MouseButton1Click:Connect(function()
    SETTINGS.jumps = cycleIn(
        {"Sin", "Normal", "Frecuentes"}, SETTINGS.jumps)
    jumpButton.Text = "Saltos: " .. SETTINGS.jumps
end)
local distButton = makeButton(190, "Distancia: Media")
distButton.MouseButton1Click:Connect(function()
    SETTINGS.distance = cycleIn(
        {"Cerca", "Media", "Lejos"}, SETTINGS.distance)
    distButton.Text = "Distancia: " .. SETTINGS.distance
end)
local speedButton = makeButton(221, "Velocidad: Normal")
speedButton.MouseButton1Click:Connect(function()
    SETTINGS.speed = cycleIn(
        {"Normal", "Rapida", "Extrema"}, SETTINGS.speed)
    speedButton.Text = "Velocidad: " .. SETTINGS.speed
end)
local extrasButton = makeButton(252, "Extras: Todo")
extrasButton.MouseButton1Click:Connect(function()
    SETTINGS.extras = cycleIn(
        {"Todo", "SoloDash", "SoloVuelo", "SoloBlink", "Sin extras"},
        SETTINGS.extras)
    extrasButton.Text = "Extras: " .. SETTINGS.extras
end)
local oppButton = makeButton(283, "Rival: Auto")
oppButton.MouseButton1Click:Connect(function()
    local choices = {"Auto"}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            table.insert(choices, player.Name)
        end
    end
    SETTINGS.opponent = cycleIn(choices, SETTINGS.opponent)
    local label = SETTINGS.opponent
    if #label > 14 then label = string.sub(label, 1, 14) end
    oppButton.Text = "Rival: " .. label
end)
local anchorButton = makeButton(314, "Reanclar aqui")
anchorButton.MouseButton1Click:Connect(function()
    local rootNow = select(3, characterParts())
    if rootNow then
        anchor = rootNow.Position
        print("[TargetBot] anchor moved here")
    end
end)
local stopButton = makeButton(345, "DETENER Y QUITAR")
stopButton.BackgroundColor3 = Color3.fromRGB(120, 45, 45)
stopButton.MouseButton1Click:Connect(function()
    cleanup()
    print("[TargetBot] removed from the menu button")
end)
makeLabel(374, 16, Color3.fromRGB(140, 140, 150), 11).Text =
    "Imposible: vuelo, dash, blink, doble salto"

task.spawn(function()
    while state.active do
        local _, _, rootNow = characterParts()
        local oppPlayer, oppRoot = getOpponent()
        local distText = "-"
        if rootNow and oppRoot then
            distText = string.format("%.0f",
                (oppRoot.Position - rootNow.Position).Magnitude)
        end
        status1.Text = (SETTINGS.running and "" or "PAUSA · ")
            .. state.behaviorLabel
            .. (os.clock() < state.recoveryUntil
                and " [desatasco]" or "")
        status2.Text = string.format(
            "Rival %s a %s · Muro %.0f · S %d/%d B %d",
            oppPlayer and oppPlayer.Name or "?",
            distText, state.wallClearance,
            state.jumpsDone, state.jumpAttempts,
            state.blinkCount)
        task.wait(0.25)
    end
end)

print("[TargetBot v5] started. Planner + steering + wallchecks. "
    .. "Inject again to remove everything.")
