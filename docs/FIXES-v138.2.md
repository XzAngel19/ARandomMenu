# v138.2 — Walk Fling como tarjeta, Fling con SkidFling, Anti Void con plataforma y Anti Fling aparte

Build: `v138.2-20261027-walkfling-platform-antifling`
Base: `v138.1-20261027-no-autofling-touchfling-only`

Pedido del usuario, textual: *«Haz que Touch Fling sea un módulo llamado
WalkFling, y Fling no hace nada, intenta hacer algo pero no manda a volar a
nadie, ni con touch fling activado. Además Anti Fling y Anti Void no funciona.
Que Anti Void sea un módulo independiente en donde cree una plataforma
invisible que solo la puedes ver tú que siempre está a unos studs debajo de tu
personaje, básicamente como lo hace VapeV4. Cópiate de un Fling aleatorio el
cual sí funcione y ya quedaría.»*

---

## 1. Walk Fling es una tarjeta propia

`src/games/universal/Blatant/WalkFling.lua` (nuevo, Exploits, orden 8).

- Sale del Fling de MM2: el pulso de Infinite Yield ya no vive allí.
- El pulso es el mismo que se aprobó (`savedVel * Power + (0, Power, 0)` con
  `Power = 10000`, devuelto en RenderStepped, micro-oscilación en Stepped y
  noclip del personaje local).
- `Power` es configurable (1000–1000000, paso 1000).
- Nunca arranca al inyectar: `configData.states["Universal.WalkFling"] = false`
  en `init`.
- Restaura el `CanCollide` original de cada parte al apagar, al destruir y al
  terminar el bucle. Si el toggle se apaga en medio de una iteración, esa
  iteración ya no vuelve a aplicar el pico (bug que tenía la versión anterior).

## 2. Fling: SkidFling, el fling que sí lanza

El fling de v138 fijaba el CFrame del personaje local sobre la víctima con una
`BodyAngularVelocity` y pulsos de velocidad, y en la práctica no movía a nadie:
el contacto nunca llegaba a transferir impulso.

Se reemplazó por **SkidFling** (la implementación pública de `zqyDSUWX` que
circula en múltiples repos de GitHub y que es la base de casi todos los menús que
funcionan):

<https://github.com/FaithfulAC/Scripts-for-custom-games/blob/main/skidfling.lua>

```lua
local FPos = function(BasePart, Pos, Ang)
    RootPart.CFrame = CFrame.new(BasePart.Position) * Pos * Ang
    RootPart.Velocity = Vector3.new(9e7, 9e7 * 10, 9e7)
    RootPart.RotVelocity = Vector3.new(9e8, 9e8, 9e8)
end
workspace.FallenPartsDestroyHeight = 0/0
local BV = Instance.new("BodyVelocity")
BV.Parent = RootPart
BV.Velocity = Vector3.new(0, 0, 0)
BV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
```

Eso es lo que quedó en `src/games/MM2/Blatant/Fling.lua`:

| Pieza | Función |
| --- | --- |
| `flingPose` | Pone el root local sobre la víctima (±1.5 studs, girando 100° por pose) y escribe `9e7 / 9e8`. |
| `BodyVelocity` (0, MaxForce 9e9) | Evita que el que flingea salga volando mientras entrega el impulso. |
| `FallenPartsDestroyHeight = 0/0` | Evita que el mapa destruya al personaje durante el vuelo. Se restaura siempre. |
| Vuelta a casa | Hasta 25 intentos para volver al CFrame guardado (o `returnCFrame`), con velocidades a cero. |
| Salida | Se destruye la `BodyVelocity`, se re-habilita `Seated`, se devuelve la cámara y la altura de destrucción. |

API preservada para Auto Farm / Auto Win: `state.mm2PerformFling`
(`silent`, `duration`, `shouldStop`, `blocking`, `returnCFrame`) y
`state.mm2FlingStep(character, humanoid, root, targetPlayer, ...)`.

La tarjeta ya no tiene `Touch Fling` (vive en Walk Fling) ni `Auto Fling`.

## 3. Anti Void: plataforma invisible independiente

`src/games/universal/Movement/AntiVoid.lua` reescrito. Ya no comparte nada con
Anti Fling.

- Crea **una** `Part` local llamada `Wurst_AntiVoidPlatform`:
  `Anchored = true`, `CanCollide = true`, `CanQuery = false`, `CanTouch = false`,
  `CastShadow = false`, `Transparency = 1`, `Size = 14×1×14`.
- Como la instancia la crea el cliente, **el servidor no la conoce**: solo existe
  en tu sesión.
- Se coloca `Distance` studs debajo del personaje (1–40, por defecto 4) y lo
  sigue en X/Z. Mientras caes, **deja de bajar** para que la caída aterrice en
  ella en vez de caer con vosotros.
- Nunca baja del `FallenPartsDestroyHeight + 8` (una parte anclada por debajo de
  esa altura la destruye el juego).
- Opción `Show platform` (transparencia 0.4 solo para ti) para comprobar dónde
  está; el resto del tiempo es invisible.
- Al apagar o destruir, la parte se destruye.

## 4. Anti Fling: tarjeta propia que sí cancela el impulso

`src/games/universal/Movement/AntiFling.lua` (nuevo, Utilities, orden 5).

El código anterior metía Anti Fling dentro de Anti Void, recorría
`GetDescendants()` de todos los jugadores y solo reaccionaba a firmas concretas.
Ahora, cada frame, sobre el personaje local:

| Señal | Límite | Acción |
| --- | --- | --- |
| Velocidad planar | `max(80, WalkSpeed × Sensitivity)` | se queda la dirección de input, se quita el impulso |
| Subida | `max(150, JumpPower × 3)` | se recorta |
| Caída | 500 studs/s | se recorta |
| Giro | 20 rad/s | se pone a cero |

- `Sensitivity` (1.5–10, por defecto 2.5) escala el límite planar.
- Se salta asientos, roots anclados y los flings propios
  (`activity.isActive("fling")` / `"walkfling"`), para no cancelar Fling ni
  Walk Fling.
- No teletransporta ni toca la posición: solo la velocidad.

## 5. Verificación

- `tools/test_walkfling.py` (nuevo): inerte al inyectar, el pico solo con la
  tarjeta ON, `Power` escala, OFF/destroy restauran colisiones y dejan el cuerpo
  parado.
- `tools/test_fling_skid.py` (nuevo): ejecuta el módulo real y comprueba que se
  escriben `9e7`/`9e8`, que hay `BodyVelocity` con MaxForce `9e9`, que
  `FallenPartsDestroyHeight` se restaura, que el personaje vuelve y que un
  objetivo sin personaje falla cerrado.
- `tools/test_antivoid50.py` reescrito: plataforma invisible bajo el personaje,
  no baja al caer, sube al saltar, se limita sobre el destroy layer, y el clamp
  de Anti Fling (input conservado, salto normal intacto, sensibilidad).
- `tools/test_menu47.py` y `tools/gen_full_boot_harness.py` ajustados al nuevo
  reparto (Anti Fling ya no es sub-opción; Walk Fling y Anti Fling son tarjetas).
- `bash tools/validate.sh` en verde: 93 fuentes, 64 suites, boot `failures=0`,
  menú 52/51 tarjetas.

## 6. Lo que no se tocó

- La tarjeta **Fling** sigue siendo de MM2 y sigue exponiendo Fling Murderer /
  Sheriff / All Innocents / Select Target / Target player / Fling.
- **Noclip** universal intacto.
- El fling no se probó en vivo desde aquí: la mecánica es la copia literal de
  SkidFling, pero el knockback real solo se confirma en Roblox.
