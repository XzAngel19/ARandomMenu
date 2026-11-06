# v187 — El hook __namecall rompía las llamadas nativas que no redirigía

Fecha: 2026-11-06. Stamp: `v187-20261106-namecall-hook`.
Rama: `arena/a4930bca-arandommenu`.

## Síntoma (reportado con captura de consola, sesión real)

Con Gun Aimbot activo en PC, ni la gun ni el knife accionaban nada. La
consola del juego mostraba en bucle:

- `argument #1 expects a string, but Instance was passed` —
  `src/games/MM2/Blatant/Shoot.lua`, línea 863, función `redirectNamecall`,
  llamada desde `Workspace.<jugador>.Knife.KnifeClient`, línea 262.
- `The current thread cannot call 'GetValue' (lacking capability Plugin)` —
  `Workspace.<jugador>.Gun.GunClient`, línea 70.

## Causa raíz (confirmada por la captura)

La línea 863 era `return predecessor(remote, ...)`: el trampolín original
al que el hook delega todo lo que no redirige. Antes de llegar ahí, el hook
ejecutaba sus propias llamadas a métodos (`getPlayerWeapon` →
`FindFirstChild`, `CollectionService:HasTag`, raycasts del solver…). Cada
una sobrescribe el **método namecall pendiente** del hilo, así que el
trampolín despachaba el último método ejecutado (que espera un string)
en vez de `FireServer`, y la llamada nativa moría dentro de nuestro hook.

Por eso fallaban a la vez la gun y el knife con Gun Aimbot encendido:
el hook es global, no solo intercepta `Gun.Shoot`. Antes de v183 no había
hook (el menú enviaba sus propios paquetes), por eso «antes funcionaba».

## Corrección (`src/games/MM2/Blatant/Shoot.lua`)

Dos reglas nuevas en `redirectNamecall`:

1. **Antes del trampolín solo corren llamadas planas/C**: `getnamecallmethod`,
   `checkcaller`, `table.pack`/`typeof` y una comparación de identidad
   contra el remoto `Gun.Shoot` **cacheado fuera del hook**
   (`refreshShootRemoteCache`, refrescado en toggles/infraestructura y,
   diferido y acotado, cuando llega un remoto que no coincide). Cualquier
   otro remoto — KnifeClient incluido — se delega intacto al instante.
2. **Tras ejecutar el solver** el registro de método ya está sobrescrito
   sin remedio, así que los frames (redirigidos u originales, si el solver
   rechaza) se reenvían por el motor: un `RemoteEvent:FireServer` nuevo
   reentra en el hook, ve la bandera `resendingNativeShot` y trampolina
   con el registro aún en `FireServer`. Se preservan los argumentos extra
   del paquete original a partir del tercero.

El hook ya no llama a `getPlayerWeapon` antes de delegar: si el arma no se
puede resolver (streaming), lo detecta el solver y el clic original se
reenvía intacto.

## Pruebas

- `tools/test_gun_native_pc.py` actualizado: el mock modela la entrada del
  motor para un `FireServer` nuevo (reentra como executor), el remoto mock
  expone `IsA`, y hay regresión nueva: un remoto ajeno (knife) trampolina
  sin una sola llamada a métodos previa aunque el lookup de arma lance error.
- `bash tools/validate.sh`: ver resultado en RESUME (126+ suites, boot
  `failures=0`). Siguen siendo mocks: no prueban daño del servidor.

## Pendiente en vivo

Confirmar en Delta que con Gun Aimbot activo: (a) la gun dispara en Bullet
y en Silent (CFrame), (b) el knife acciona normal (stab/throw nativos) sin
los warnings de la captura, (c) no reaparece `GetValue (lacking capability
Plugin)`. Si el knife sigue sin lanzar en Auto, reportar el texto del
status de la tarjeta (v186 lo publica).
