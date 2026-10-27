# v148 — el Fling elige de una lista, y el Touch ya no te gira ni te lanza

Build: `v148-20261026-fling-picks-a-player-and-keeps-your-control`
Base: `v147-20261027-fling-holds-you-and-script-cost`

## 1. «Fling no detecta a nadie, ni sabe quién es sheriff o murder ni los inocentes»

La tarjeta pedía escribir un nombre a mano. Un nombre mal escrito, un
`DisplayName`, alguien que entró hace dos segundos o una ronda que todavía no
publicó los roles se veían exactamente igual: un fling que «no detecta a nadie».

Ahora la tarjeta tiene una **lista viva** de jugadores con su rol:

```
Fling target   →   Target [Sheriff]
                   Otra [Murderer]
                   Tercero [Innocent]
```

- Se construye con `addListOption`, la misma lista nativa que ya usa Espectar,
  así que se abre, se filtra y se guarda como el resto del menú.
- El rol sale primero de los datos de ronda (`getPlayerRole`), después de
  `services.gameBridge.playerRole` y, si MM2 todavía no replicó nada, **de la
  herramienta que el jugador lleva de verdad**: cuchillo → Murderer, arma →
  Sheriff. Ese es el caso que fallaba: sin datos de ronda la tarjeta no sabía
  nada de nadie.
- Los muertos no salen; si alguien muere o cambia de rol, la etiqueta se
  refresca sola (una firma de texto por segundo, sin trabajo si no cambió nada).
- El botón `Fling` y `Auto Fling Selected Target` usan **esa** selección. No hay
  forma de que el Fling actúe sobre un nombre que ya no existe: si la etiqueta
  guardada no está en la lista de vivos, no hay objetivo.
- Si MM2 no publicó los roles todavía, el aviso lo dice:
  `MM2 has not published the roles yet. Wait for the round to start.` Antes
  decía «no hay ningún murder», que es una mentira distinta.

## 2. «Quita esa opción de Touch Fling»

El toggle `Touch Fling` vivía **dos veces**: dentro de la tarjeta MM2 Fling y en
la tarjeta universal de Exploits. Eran dos dueños del mismo motor físico.

- Se borró el de la tarjeta MM2 Fling. La tarjeta universal no se tocó.
- `TOUCH FLING` sigue existiendo en Exploits y sigue apagándose al reiniciar.
- Un `true` viejo en la config ya no puede resucitar nada: la clave retirada
  `MM2.Fling.TouchFling` se **borra** al cargar la config
  (`RETIRED_OPTION_KEYS` en `Wurst.lua`), no se restaura ni se deja en `false`.

## 3. «¿Por qué tiene que rotar? Se bugea y parece que circula al objetivo»

Era literal: en el toque se hacía `PivotTo` al punto de contacto y **además** se
copiaba la orientación del objetivo. El personaje giraba hacia la víctima y el
cuerpo, al girar, parecía orbitarla.

Ahora el Touch **no coloca** al personaje, no copia orientaciones y no escribe
posiciones:

```lua
-- contacto: sólo el giro, nunca PivotTo
if (targetRoot.Position - root.Position).Magnitude > CONTACT_RANGE then return end
touchCooldownUntil = now + TOUCH_COOLDOWN
engageSpin(character, root, TOUCH_BURST, TOUCH_BURST)
```

- `TOUCH_BURST = 0.15 s` y `TOUCH_COOLDOWN = 0.4 s`: un pulso corto por contacto.
  Entre contactos no hay nada conectado, nada fijado y nada escrito, así que
  caminas, giras y saltas normal. El giro continuo de antes era el que te hacía
  circular y el que te lanzaba.
- La orientación del fling dirigido se conserva (`frame - frame.Position`): te
  mueves al punto de contacto sin mirar al objetivo.
- `orientationOf` es sólo rotación; no existe ningún `lookAt` ni cara al
  objetivo en todo el módulo.

## 4. «Me sigue botando el Touch Fling, ¿por qué me bota a mí?»

Tres capas, todas en el módulo compartido, así que valen para la tarjeta
universal y para el fling dirigido:

1. Mientras se entrega el impulso, un `AlignPosition` rígido (`OneAttachment`,
   `Position` = punto de contacto, `RigidityEnabled = true`) sujeta tu root: la
   reacción del contacto se absorbe ahí en vez de mandarte a volar.
2. Al terminar el pulso se pone `AssemblyLinearVelocity = 0` y
   `AssemblyAngularVelocity = 0`.
3. Si la física te movió más de `MAX_DRIFT = 6` studs durante el pulso, se te
   devuelve al punto de partida **manteniendo la orientación**. Caminar nunca
   entra en ese guard: sólo cuentan los pulsos de toque (`driftGuard`).

## 5. Lo que sigue pendiente (no se puede probar offline)

1. **Cuánto vuela el tocado en la partida real.** El mecanismo es el de IY
   (densidad infinita, `Massless`, `CanCollide = false`, `99999 rad/s`), pero un
   pulso de 0.15 s es más corto que el ciclo continuo de IY. Si en vivo no
   alcanza, el número a subir es `TOUCH_BURST` — no la lógica.
2. Que con el pulso corto no se pierda el knockback en ping alto.
3. Nada de esto lo puede demostrar un mock: los 66 suites prueban estructura,
   selección, roles y limpieza, no física del servidor de Roblox.

## 6. Verificación offline

```text
PASS 86 Lua sources compile
PASS 66 Python/Luau suites
[Wurst:Bootstrap] Load complete · failures=0
PASS bundle boot, silent startup, native controls and cleanup assertions
PASS every core.* and prediction.* call resolves to an export
PASS menu audit: 50 cards, every row dumped from the booted bundle
PASS release menu: 49 cards, no Calibration card
```

Suites nuevas/actualizadas:

- `tools/test_fling_physics.py`:
  - la lista existe, es de un solo objetivo y sus etiquetas llevan el rol;
  - elegir una fila resuelve a ese jugador y limpiar la lista limpia el objetivo;
  - `Fling` actúa sobre la selección y **no adivina** sin ella;
  - el rol se deduce del arma cuando no hay datos de ronda (cañón/arma y
    cuchillo, con dos instancias del módulo y el core sin rol);
  - con roles sin publicar, la lista sigue mostrando jugadores y el aviso
    explica que faltan roles;
  - el toque no rota, no coloca, no deja velocidad y deshace la deriva; el pulso
    se limpia solo y respeta el cooldown;
  - el `Touch Fling` de la tarjeta MM2 ya no existe.
- `tools/gen_full_boot_harness.py`: la tarjeta encendida desde el bundle real
  tiene `Fling target`, control de lista registrado, hook de roster y **ninguna**
  fila `Target player` ni `Touch Fling`.
- `tools/test_startup_restore.py`: una config vieja con
  `MM2.Fling.TouchFling = true` termina con la clave borrada (`nil`).
