# v186 — Gun: pulsación manual sin muestras; Knife: puertas con nombre y redirect reintentado

Fecha: 2026-11-06. Stamp: `v186-20261106-gun-knife-send`.
Rama de publicación: `arena/a4930bca-arandommenu` (nuevo `RUNTIME_BRANCH`
por defecto; `getgenv().WURST_BRANCH` sigue pudiendo sobrescribirlo).

## Síntoma reportado

En PC, con Gun Aimbot en Silent (CFrame), pulsar el disparo «no accionaba
nada», y el Auto Knife Throw de MM2 nunca lanzaba el cuchillo. Sin daño que
discutir: simplemente no salía paquete.

## Causas identificadas en el código

### Gun

1. **La pulsación manual ignoraba su propio contrato.** El keybind llama a
   `fireGunAtTarget(..., {whenReady = true})`, pero `whenReady` se aceptaba
   en `FireOptions` y no se usaba en ninguna parte. El clic nativo
   interceptado (PC) y Auto Shoot sí tenían fallback de primera muestra
   (raíz viva + lead corto) cuando el predictor aún no tenía historial;
   la pulsación manual, no: rechazaba con «no samples / stale sample» y no
   salía ningún paquete. Al inicio de ronda o tras un respawn del objetivo
   era, a efectos del usuario, un gatillo muerto.
2. El resto de puertas de la ruta (gate de confirmación de 1,5 s, Tool
   deshabilitada/recargando, `validateGunShot`/WallCheck) ya escriben su
   motivo en el status de la tarjeta; el fallback nuevo sigue pasando por
   la validación final completa, no es un bypass.

### Knife Throw

1. **`throwKnife` fallaba en silencio.** El loop anunciaba
   «Predicted target» (selección barata: solo cuerpo visible) y después la
   verificación completa podía devolver `false` sin escribir ningún motivo:
   equip pendiente, sin origen, objetivo inválido o corredor WallCheck
   bloqueado se veían igual que un lanzamiento aceptado. Ahora cada salida
   nombra su puerta y el loop la muestra en el status.
2. **El redirect de WeaponService solo se intentaba al activar la tarjeta.**
   Si `ReplicatedStorage.ClientServices.WeaponService` aún no existía
   (lobby, transición de ronda), la instalación no-opaba y no se reintentaba
   en toda la sesión: los lanzamientos manuales nunca se redirigían. Ahora
   el loop reintenta como mucho una vez por segundo mientras la tarjeta
   siga activa.
3. El contrato del paquete no cambió: coincide con el nativo observado
   (`Knife.Events.KnifeThrown:FireServer(handleCFrame, CFrame.new(aim))`).

## Cambios

- `src/games/MM2/Blatant/Shoot.lua`: el fallback de primera muestra incluye
  `opts.whenReady == true`, en paridad con el clic nativo de v185.
- `src/games/MM2/Combat/KnifeThrow.lua`: `throwKnife` devuelve
  `(boolean, string?)` con el motivo; el loop lo publica en el status;
  reintento acotado de `installWeaponServiceRedirect`.
- `tools/test_gun_safety.py`: las expectativas manuales «sin predicción no
  envía» pasan a «sin predicción cae al fallback validado» (la filosofía
  v185 del clic nativo), manteniendo que el fallback no salta la
  validación final.

## Verificación y límites

- `bash tools/validate.sh`: **verde** — 126 suites PASS, bundle de 79
  fuentes, boot `failures=0`, 46 tarjetas debug/release. Las suites son
  mocks: prueban puertas, conteo de paquetes y limpieza, no daño ni
  aceptación del servidor.
- **Pendiente en vivo (Roblox/Delta):** si el status de Knife Throw muestra
  una puerta concreta («Target blocked · WallCheck», «Equipping knife…»,
  «KnifeThrown remote unavailable») hay que reportar el texto exacto; si la
  gun sigue sin accionar ni con keybind ni con clic, hay que reportar si el
  aviso de hook («needs executor hookmetamethod…») aparece al activar
  Gun Aimbot, porque la redirección PC de v183 nunca se verificó en vivo.
