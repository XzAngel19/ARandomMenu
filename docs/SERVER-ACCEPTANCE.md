# Aceptación del servidor de MM2: qué se puede demostrar

Este documento responde a la afirmación «el servidor acepta como máximo 200 ms
(200,33 ms)». Se contrasta con el código de cliente incluido en la copia del
place y con los registros guardados en `TestingStuff`.

## Lo que sí está en el código del cliente

`ClientServices.WeaponService` (`research/rbxlx/092_WeaponService_ModuleScript.lua`):

- Filtro de rayos: excluye el personaje local y todo lo etiquetado
  `WeaponPassthrough`; si el impacto tiene `Transparency == 1`, lo añade a la
  exclusión y repite el raycast.
- `GetTargetPosition` / `GetMouseTargetCFrame`: raycast desde la cámara de
  **300 studs**; con `MouseLock` activo y sin gamepad, el rayo se centra en el
  viewport.
- `ThrowKnife` solo dispara un `BindableEvent` local.
- `GunFired` es un `RemoteEvent` que el servidor reenvía a los clientes;
  `GunBeams` lo dibuja. El `hitPart` que llega en ese evento lo calcula el
  servidor, así que el eco `FireServer → GunFired` sí es evidencia del lado
  servidor.

No hay ninguna comprobación temporal, de distancia ni de «ventana de
aceptación» en este módulo. Es lógica de cliente, no validación del servidor.

`ThrowingKnifeVisuals` (`research/rbxlx/223_...`):

- El cuchillo avanza en línea recta: `CFrame + Direction * ThrowSpeed * dt`,
  `ThrowSpeed` por defecto **96**, sin gravedad y sin tiempo de vida.
- Por eso el alcance del cuchillo no está limitado por el cliente.

El servidor de MM2 no está incluido en la copia del place (no hay scripts de
servidor ni manejadores `OnServerEvent` entre los 229 scripts extraídos). Por
tanto **no se puede leer el umbral exacto** desde este repositorio.

## Lo que dicen los registros

`TestingStuff/Place_142823291_Game_Learning.json` (93 tiros; 29 confirmaciones
`GunFired`, 7 con impacto en un jugador). Para los 18 tiros con eco medido y
resultado, ordenados por eco:

| Eco (ms) | ¿Impacto en el objetivo? |
|---|---|
| 128.3 | no |
| 163.8 | no |
| 164.1 | no |
| 166.7 | no |
| 183.5 | no |
| 185.3 | sí |
| 187.1 | sí |
| 197.6 | no |
| 204.4 | no |
| 204.8 | sí |
| 210.4 | no |
| 211.5 | sí |
| 228.6 | sí |
| 255.2 | sí |
| 259.2 | sí |
| 359.3 | no |
| 679.2 | no |
| 1007.7 | no |

## La «ventana dinámica» del 16 de octubre

`TestingStuff/MM2_Trajectory_Calibration.json` (stamp `v35-20261016-menu-motion`,
sesión con ping ~108 ms) guarda el estimador que usó el otro agente:

| Métrica | Valor |
|---|---|
| `confirmedShots` | 297 |
| `gunAcceptanceMs` mínimo | 3,73 ms |
| `gunAcceptanceMs` media | **123,51 ms** |
| `gunAcceptanceMs` máximo | **631,12 ms** |

Ese 123,5 ms es la **media** de una distribución con cola larga, no un umbral:
el propio registro contiene aceptaciones de 3,73 ms y de 631 ms. La media es
~15 ms mayor que el ping de esa sesión, así que la regla «ventana ≈ RTT + 10–20
ms» describe bien el centro de la distribución, pero **no es un corte**:
usar 123 ms como límite habría rechazado disparos que el servidor sí aceptó.

Es exactamente lo que ya hace el mod: la mediana de ecos medidos (con respaldo
del ping) es la «ventana» en vivo, sin constante mágica. La diferencia es que
nosotros usamos la mediana y no la media, y no descartamos por encima de un
número fijo.

Ojo con mezclar archivos: en `Place_142823291_Game_Learning.json` (14 oct) los
**297** son `hitboxAnomalies` y solo hay **29** `confirmations`; los 297
disparos confirmados y el 123,5 ms salen del archivo de calibración v35.

## Veredicto

La afirmación tal como suena —un corte duro de aceptación a 200 ms— **no queda
en pie como está formulada**, pero tampoco se puede declarar falsa sin matices:

1. **Si «200 ms» se refiere al eco `FireServer → GunFired`** (lo que cualquiera
   puede medir desde el cliente), está refutado: hay ecos de 679 y 1007 ms, y
   hubo impactos confirmados con 259,2 ms de eco. Ese número no es un umbral.
2. **Si «200 ms» se refiere a la edad del disparo al llegar al servidor**, los
   registros son compatibles con ello y no lo demuestran: con un ping de sesión
   de ~171 ms, un eco de 259 ms deja el disparo en el servidor a ~85 ms de
   haberse enviado. El eco no mide la edad de llegada.
3. **No hay fuente en el place** que fije 200,33 ms. Sin el código del servidor,
   no se puede confirmar ese número concreto; solo se puede desmentir que el eco
   tenga ese tope.

Consecuencia práctica: el mod **no construye nada sobre un umbral de 200 ms**.
El horizonte de predicción sale del eco medido y del ping real, con un tope de
1 s, y el WallCheck no cambia según la latencia. Si en el futuro apareciera un
límite real, el diseño ya apunta al lado conservador (se apunta al futuro, no
al pasado), pero no se afirma que exista.

## Lo que sí conviene explotar

1. **`WeaponPassthrough`.** Ciertas partes del mapa dejan pasar el disparo. El
   WallCheck las excluye igual que el juego, tanto para el arma como para el
   cuchillo, así que disparar o lanzar a través de ellas es legítimo.
2. **Rayo de puntería de 300 studs.** Es el límite del *aim* del cliente, no del
   daño; el WallCheck propio no impone distancia al disparo.
3. **Cuchillo sin caída y sin límite de vida.** El blade sigue recto hasta
   impactar; el límite útil lo pone la geometría, no la velocidad.
4. **Ping alto no impide acertar.** La sesión registrada tenía ping mediano
   ~171 ms y máximos de 507 ms, y aun así hubo impactos: por eso el lead
   automático usa el eco real en vez de un valor fijo.
