# v41 — ItemESP, Calibration, Teleport y trabajo visual del tema

Stamp: `v41-20261016-menu-theme`.

## ItemESP: Gun ESP y Trap ESP restaurados

Los controladores MM2 ya existían en RoundEsp, pero no se registraban en
`services.itemEsp`. ItemESP tenía soporte de providers y no recibía ninguno.
Ahora se registran ambos providers y sus opciones reales aparecen dentro de
ItemESP. Su master habilita/deshabilita los providers seleccionados.

Gun ESP actualiza el arma caída con su cadencia existente y limpia el marcador
al recogerla. Trap ESP cubre trampas existentes y nuevas, sin repetir un objeto
ya marcado. OFF/unload desconectan observadores, limpian efectos y desregistran
los providers. No se crea otra tarjeta ESP.

## Weapon Visuals eliminado; TrailESP dentro de Calibration

Se elimina el archivo/módulo WeaponVisuals, sus opciones Double Gun/Double Knife,
clones, reconstrucciones, espejado de brazos y callback PreSimulation. No queda
un master invisible ni cosméticos funcionando de fondo.

`CalibrationTrails.lua` conserva únicamente la visualización opcional de los
paquetes replicados GunFired: trayecto y círculo de llegada, con color elegible.
TrailESP y Trail color se encuentran en Calibration y migran sus valores previos.

No hay opción Tracer Data ni otra llamada a noteTracerData. Calibration ya
observa/guarda los datos; el observador de TrailESP es solo visual y solo está
conectado cuando su toggle está ON. No escribe remotes. Los efectos son
transitorios y acotados, y OFF/unload eliminan todos los creados por él.

Se elimina el selector Mode de Calibration: solo tenía una opción. Status,
Save, Clear history y TrailESP quedan directamente en la tarjeta.

## Teleport: una sola selección de destino

Destination incluye directamente MM2 Map, MM2 Lobby, MM2 Player y MM2 Gun junto
con los modos universales. No existe MM2 target ni un segundo selector.

Las configuraciones v40 con Destination=MM2 convierten su antiguo MM2 target al
destino plano equivalente. Los perfiles nuevos empiezan en MM2 Map. Se conservan
los bindings/valores migrados, Auto Get Gun y la demora. Los controles genéricos
no aparecen en destinos MM2 y el nombre solo aparece para MM2 Player.

También se quita el botón Go back: repetía la acción principal cuando se elige
Last position. Save waypoint se conserva porque guarda, no teletransporta.
Cambiar Destination sigue cancelando un Tap point armado.

## Rainbow y personalización: causas verificables de trabajo innecesario

No se atribuye lag a un RGB constante por sí mismo. Se revisaron las rutas que
se ejecutaban repetidamente al cambiar colores:

1. ThemeEngine recorría TODOS los bindings por cada cambio, aunque solo cambiase
   Accent/Enabled. Ahora usa buckets por token y escribe únicamente los tokens
   que realmente cambiaron. Cambiar un color al mismo valor es un no-op.
2. Bind deduplica una misma propiedad, elimina su asignación anterior al cambiar
   de token y libera referencias al destruir la instancia. Los bindings siguen
   siendo fuertes mientras están vivos: no se reintroduce el problema histórico
   de perder wrappers de Roblox por usar referencias débiles.
3. Los listeners y repainters pueden filtrar tokens. Las flechas no se repintan
   por cada tick de Enabled; los títulos de ventana no se recalculan si no cambia
   su color. Las tarjetas no vuelven a llamar al dibujado de título si su color
   y transparencia siguen iguales.
4. Los iconos pixelados reutilizan su topología cuando kind/token no cambian.
   Un refresco de paleta ya no destruye/recrea esos Frames. Cambiar up/down sí
   reconstruye la forma cuando corresponde.
5. Rainbow de ClickGUI conserva su límite de 20 Hz y no repinta el menú oculto.
   No reescribe los colores personalizados guardados; al apagarlo se restauran
   Accent y Enabled elegidos. Los arcoíris de HUD siguen siendo independientes.
6. El HUD tenía glifos reutilizables, pero volvía a pasar por medición/layout y
   posición del holder en cada tick de color/animación. Ahora usa recolor sin
   medir, seleccionar atlas o reiniciar posiciones/tweens de entrada. Funciona
   con atlas y fallback RichText, conserva el color separado del status y baja
   ese pulso a 20 Hz. No se afirma que el renderer antiguo recreara todos los
   glifos: ya tenía un cache; se elimina el trabajo de layout restante.
7. Los checkboxes apagados y el chrome de ventanas usan los tokens surface y
   outline en lugar de imponer negro. Se mantienen colores semánticos y el
   contraste de accesibilidad, que no son overrides accidentales de la paleta.

No se eliminan las opciones de personalización ni se sustituye la paleta del
usuario por una fija. El objetivo es reducir recorridos, escrituras y trabajo
repetido; no se promete una cantidad de FPS sin medirla en el juego real.

## Verificación

- 22 suites Python/Luau, incluyendo pruebas nuevas de providers MM2, TrailESP y
  motor de temas/recolor. Se retiran los asserts del cosmético eliminado y se
  mantienen los grupos históricos v16 de visibilidad/migración aún aplicables.
- 76 fuentes compiladas y bundle actual de 67 fuentes.
- Boot real del menú sobre servicios mock: Gun ESP/Trap ESP registrados, master
  ItemESP probado, Weapon Visuals/Tracer Data/Mode único ausentes, TrailESP en
  Calibration, destinos planos y controles condicionales de Teleport.
- El boot compara identidad de píxeles antes/después del refresco para comprobar
  que no basta con registrar un nombre: los iconos reales no son recreados.
- Tests del tema comprueban escrituras por token, no-op, rebind/destroy,
  listeners filtrados, recolor de atlas/fallback y ausencia de cambios de layout.
- Tests visuales comprueban paquetes inválidos, límite de instancias, OFF/unload
  y callbacks tardíos. Tests de providers cubren gun pickup y trampas nuevas.
- Fórmulas Gun/Knife y baseline archivado sin cambios. Esta run prepara la
  limpieza previa a trabajar en Shoot Prediction/Silent AIM, no cambia el solver.

Estas verificaciones son automatizadas con mocks, no mediciones de FPS ni una
prueba online de precisión dentro de Roblox.
