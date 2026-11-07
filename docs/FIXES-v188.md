# v188 — Ghost reparado y clic nativo de la pistola verificado

Fecha: 2026-11-07. Stamp: `v188-20261107-ghost-and-native-click`.
Rama: `arena/05c45e27-arandommenu` (base v187 `70bbfc4`).

## 1. Pistola: el hook nativo respeta el WallCheck (revisión del pendiente v187)

Pregunta del jugador: *«¿el hook que debería ser nativo funciona? El CFrame de
la pistola respeta el WallCheck; si el enemigo no está en la mira por el
WallCheck, aún puedes disparar, solo que no usa Silent/Cframe porque el enemigo
no se detecta.»*

Sí, y es el comportamiento correcto. Trazado en `src/games/MM2/Blatant/Shoot.lua`:

1. El hook de `__namecall` solo intercepta `FireServer`, llamadas **del motor**
   (`checkcaller() == false`) y el remoto cacheado `Gun.Shoot`. Todo lo demás
   trampolina intacto.
2. Con el objetivo resoluble, `fireGunAtTarget` construye el par de CFrame y
   **pasa antes por `safeToSend`**: `validateGunShot` con la línea del arma y la
   del origen, más `isWeaponPathClear` en modo raw. Si hay muro, el solver
   rechaza y `redirectNamecall` reenvía **el clic original** por el motor.
3. Si no hay objetivo (muerto, no visible, filtrado, protegido o rol
   desconocido), `getSelectedShootTarget()` devuelve `nil`, el solver rechaza
   con «No selected shoot target was found.» y el clic original se reenvía con
   sus argumentos extra. La pistola del juego dispara exactamente donde apuntaba
   el jugador; el menú no inventa un segundo paquete ni un CFrame sin objetivo.

Regresión nueva en `tools/test_gun_native_pc.py`: con `getSelectedShootTarget`
devolviendo `nil`, se verifica un único transporte, frames originales intactos,
argumentos extra preservados y cero llamadas al solver.

Límite que se mantiene: el daño y la aceptación del servidor solo se prueban en
Roblox/Delta. Estas suites son mocks.

## 2. Ghost — reescritura del contrato

`src/games/universal/Blatant/Invisible.lua`. Lo que estaba mal y lo que cambió:

| Antes (v187) | Ahora (v188) |
| --- | --- |
| `Void depth` default **120**, mínimo 50 | Default = **mínimo (1)**, rango 1–350; el cuerpo real va justo debajo del puppet |
| Sin migración: un perfil viejo seguía con 120 | Migración única: solo reescribe si el valor estaba ausente o era exactamente 120 |
| `Highlight` azul siempre, `AlwaysOnTop` implícito | **Sin Highlight** por defecto; `Outline` es una opción OFF (y `Occluded`, nunca a través de paredes) |
| El clon heredaba Scripts/GUIs del avatar | Se destruyen también `Highlight`, `BillboardGui`, `SurfaceGui` y `SelectionBox` del clon |
| El clon podía aparecer como bot en NPC ESP / Entity | Se marca `WurstDisguise = true` (ambos índices ya lo rechazan) |
| WalkSpeed fijo 16, sprint fijo 32 | **Ghost WalkSpeed** real (1–200) + **Sprint multiplier** (1–5, 1 = sin sprint) |
| Fly leía teclas WASD crudas: móvil y binds no funcionaban | Fly lee `services.movementInput` (stick móvil y binds incluidos) y usa `AssemblyLinearVelocity`, sin teletransportar el clon |
| Sin input en Fly, la velocidad quedaba congelada o derivaba | Sin input ⇒ velocidad cero; la velocidad se recompone por `dt` |
| Caminar sin suelo: el clon caía para siempre y arrastraba el cuerpo real al vacío | **Void guard** acotado (solo caminando): reasienta sobre el mayor de «260 studs bajo el último suelo sólido» o «24 studos sobre el piso del mapa» |

`Void guard` es un tope local: no es física del servidor, no promete que el
servidor te vea en el suelo.

### Por qué 50 de profundidad «no servía»

Con 120 (o 50) studs de separación, el puppet queda tan abajo que deja de ser
útil: no pasa por huecos, no entra a habitaciones y cualquier `WallCheck` del
juego te sigue viendo el cuerpo real. A profundidad mínima el cuerpo va pegado
bajo el puppet, que es lo que el jugador pidió.

### Lo que Ghost no hace

- No cambia el estado del servidor: el cuerpo real sigue donde el servidor
  cree que está.
- No oculta el nombre del jugador de otros clientes más allá del clone local.
- No promete inmunidad al vacío: el guard es local y acotado.

## 3. Pruebas

- `tools/test_ghost50.py` reescrita: WalkSpeed/multiplicador, guard acotado y
  su OFF, Outline ON/OFF, transparencia en vivo, atributo de disfraz, Fly por
  servicio de movimiento + velocidad, migración de 120 → 1 y preservación de un
  valor elegido (200), spawn fallido, pérdida del clon y unload.
- `tools/test_gun_native_pc.py`: caso «sin objetivo» añadido.
- `tools/gen_full_boot_harness.py`: asserts de los defaults nuevos en el boot
  real del bundle.
- `bash tools/validate.sh` completo en verde (ver RESUME).
