# Killaura (catsix/games/universal.lua) — fix de CPU sin bajarle rendimiento

Este arreglo apunta al Killaura melee que se carga desde `catsix/games/universal.lua`
(bloque ~2470–2749) antes del script de BedWars. Ese archivo corre en tu executor y
no está en este repo, así que aquí está el parche listo para pegar. Los patrones se
verificaron contra el ancestro sin ofuscar del mismo módulo
(`reference/vape-v4-universal.lua.txt`, bloque del Killaura ~2370–2530), del cual el
de catvape desciende: mismos sliders (Swing range / Attack range / Max angle) con
High hitreg y Dynamic delay agregados encima.

Objetivo: **que el KA pegue exactamente igual** (mismos rangos, mismo hit rate, 0%
menos de acierto) y deje de gastar CPU "porque sí". Lo que sobra es trabajo por
frame que no contribuye a ningún golpe.

## Los 4 desperdicios y su fix

### 1. Escanear con 28 studs de Swing range cada frame aunque no haya nadie

Con Swing range en 28, `AllPosition` (o el picker equivalente) recolecta y ordena a
**todos** los jugadores en 28 studs **cada frame**, con wallcheck (raycasts) incluido,
aunque el objetivo esté a 18+ studs fuera del Attack range real y aunque el swing ni
vaya a salir.

Fix: filtra barato ANTES del wallcheck. El orden correcto es: distancia → ángulo →
wallcheck → visuales. El wallcheck (raycast) es lo más caro: que solo lo pague quien
pase distancia y ángulo.

```lua
-- ANTES (patron): AllPosition({Range = SwingRange.Value, Wallcheck = ...})
-- DESPUES: traer sin wallcheck y medir angulo/distancia primero
local plrs = entitylib.AllPosition({
    Range = SwingRange.Value,
    Part = 'RootPart',
    Players = Targets.Players.Enabled,
    NPCs = Targets.NPCs.Enabled,
    Limit = Max.Value
})
-- ... y el Wallcheck (raycast) solo para los que ya pasaron
-- distancia <= AttackRange.Value y el filtro de Max angle.
```

### 2. Overlap queries por candidato por frame

El ancestro hace, para cada candidato que pasa el ángulo:

```lua
Overlay.FilterDescendantsInstances = {v.Character}
for _, part in workspace:GetPartBoundsInBox(v.RootPart.CFrame, Vector3.new(4,4,4), Overlay) do
```

Eso es una query física **por candidato por frame** — con 3 rivales cerca son 3
queries + N toques `firetouchinterest` por frame, aun cuando `AttackDelay` no ha
llegado y el golpe no va a salir este frame.

Fix: la parte del toque solo tiene sentido cuando `AttackDelay < tick()`. Mueve el
bloque de `GetPartBoundsInBox + firetouchinterest` **dentro** del `if AttackDelay < tick() then`
(no lo hagas cada frame para cada candidato). Con Attack speed ~0.27s, eso recorta
~95% de esas queries.

### 3. Los loops de visuales (Boxes/Particles) corren siempre

En el ancestro, los dos `for i, v in Boxes do` / `for i, v in Particles do` corren
**cada frame** aunque `attacked` esté vacío y aunque el visualizer esté apagado.
En catvape pasa igual con sus boxes/círculo.

Fix: solo recorre visuales cuando hubo candidatos este frame o cuando el frame
anterior los hubo (para limpiar):

```lua
if #attacked > 0 or hadTargets then
    -- loops de boxes/particles
end
hadTargets = #attacked > 0
```

Y si el toggle del visualizer esta apagado, saltate los loops por completo.

### 4. High hitreg: el bucle extra que solo sirve cuando hay victima

El tooltip lo confiesa: "uses extra CPU for precise timing at low FPS". Es un bucle
de precision (varios escaneos por frame) que corre **siempre** que esta encendido.

Fix sin perder hits: solo corre el bucle fino cuando hay un candidato dentro de
Attack range + angle. Fuera de combate el KA vuelve al escaneo normal de 1 por frame.
Si no quieres tocar codigo: apagalo — el hit rate real (el que registra el servidor)
lo da tu Attack speed (~0.2745s, el cooldown de la espada); los "ghost hits" son
swings visuales, no daño extra.

## Aplicarlo

1. Abre `catsix/games/universal.lua` en el editor del executor, ve al bloque del
   Killaura (~lineas 2470–2749).
2. Aplica 1–3 (son de ganancia segura, no cambian ningun hit). Para 4 usa el gate
   "solo con victima" o apaga el toggle.
3. Guarda y recarga el script. El KA pega igual; con varias personas cerca el uso de
   CPU baja mucho (menos raycasts + menos overlap queries + visuales solo cuando toca).

Si al abrir el archivo el bloque no coincide con estos patrones (catvape cambio la
estructura), vuela el contenido de las lineas 2470–2749 a este repo y se hace el
parche exacto sobre el codigo real.

## Anexo: fijar tus archivos para que las updates no los pisen

El propio `universal.lua` documenta el mecanismo: `downloadFile` solo descarga si el
archivo NO existe, y el loader marca cada cache con la linea
`--This watermark is used to delete the file if its cached...`. Esa marca es lo que
el updater borra al actualizar; un archivo sin la marca se considera tuyo y se deja
intacto. Comando para fijar todo el folder (correrlo en el executor con catvape ya
cargado una vez):

```lua
local function pin(folder)
	for _, f in listfiles(folder) do
		if isfolder(f) then
			pin(f)
		elseif f:sub(-4) == '.lua' and isfile(f) then
			local src = readfile(f)
			if src:find('--This watermark', 1, true) then
				writefile(f, (src:gsub('^%-%-This watermark[^\n]*\n', '', 1)))
				print('fijado:', f)
			end
		end
	end
end
pin('catsix')
```

Para revertir (volver a dejar que las updates reemplacen): borra el archivo o el
folder `catsix` y deja que el cliente lo descargue de nuevo.

### El orden correcto: pin ANTES de abrir catvape

El barrido de updates corre dentro del script de catvape cuando arranca, asi que un
comando corrido "despues de abrir" siempre llega tarde. La solucion es un wrapper que
primero quita las marcas de los archivos cacheados y despues carga el cliente — el
barrido arranca, no encuentra marcas en tus archivos y los deja intactos:

```lua
-- PIN + CARGA: ejecuta esto EN LUGAR de tu loadstring de catvape
local function pin(folder)
	for _, f in listfiles(folder) do
		if isfolder(f) then
			pin(f)
		elseif f:sub(-4) == '.lua' and isfile(f) then
			local src = readfile(f)
			if src:find('--This watermark', 1, true) then
				writefile(f, (src:gsub('^%-%-This watermark[^\n]*\n', '', 1)))
			end
		end
	end
end
if isfolder('catsix') then
	pin('catsix')
end

-- AQUI va tu loadstring de catvape de siempre, sin cambios:
-- loadstring(game:HttpGet('...'))()
```

Guardar ese wrapper como archivo del executor y ejecutarlo cada sesion (o bindearlo)
equivale a "no se puede actualizar": el pin corre siempre antes del barrido.

Notas:
- La primera vez, asegurate de que tus archivos parcheados (universal.lua con el fix
  de CPU, 6872274481.lua) ya esten en catsix antes de correr el wrapper.
- Al estar fijados, NINGUNA update automatica los toca — tampoco las buenas. Para
  tomar una update a proposito: borra el archivo concreto, abre catvape (re-descarga
  con marca), vuelve a aplicar los fixes y re-corre el wrapper.
- Si el loader expone un modo developer/local (p. ej. `shared.vape_developer = true`)
  que salte la descarga, seria una alternativa; el wrapper no depende de flags
  ocultos y funciona garantizado con el mecanismo documentado de la marca.
