# v42 — evidencia, reproducción y alcance

## Fuentes realmente consultadas

Repositorio documental: `XzAngel19/TestingStuff` (no código descargado ejecutado).

| Documento | Git blob |
|---|---|
| 2026-10-16T22_14_51Z.log | `56ccae0d2ca6d9a44d6e02fc40e31b78a5f6ae6a` |
| 2026-10-16T22_18_17Z.log | `a7e658f2699e66ee276bbda23e33bb9e7928cee3` |
| 2026-10-16T22_19_27Z.log | `f37b77506dea04401e4bd353046cfb1e06c06ad5` |
| MM2_Trajectory_Calibration.json, build v35 | `80ed658e206c330ab28145ff05fafb146d507ed3` |
| Shoot..txt | `380b198c8b00f600cb78c082ba351ae55e56c40b` |
| 2026-10-16T00_49_35Z.log | `58bc36f7643d5bc678c6b4d9f0c2678b11eb6b23` |
| calibración pequeña, build v34 | `88b3ef2478a2b6176d0c94f6a1727c9ba322cdca` |
| calibración pequeña, build v31 | `0f97ae190c0ac597918b5c29218f54e73534e9ab` |
| otra sesión, build v30, reservada para contraste | `5af0bcff9b7cdfc63860159f0e2cfad1f608219c` |

Native XML ya recuperado: blob `755f47708dfbe83a5eaad25d5a60a5a36788dcf6`.
Su ThrowingKnifeVisuals integra dirección × velocidad × dt, default 96.
KnifeClient no estaba presente: no atribuimos una fórmula de autoría exacta
al juego. Shoot..txt contiene nuestro Shoot, no una fórmula nativa distinta.

Los logs se volvieron a descargar y auditar en esta run. Los dos pares propios
Shoot→GunFired tardan 119.671/132.397 ms según CreationTime y permanecen sobre
la dirección enviada (desviaciones 0.000203/0.000303 studs). No identifican
rewind. Los cinco KnifeThrown nativos documentan protocolo/cadencia del usuario,
no un cooldown obligatorio, AnimationIds ni keyframes. El JSON v35 contiene
122 eventos, 9 confirmaciones Gun, 7 asociaciones hitPart–objetivo y 4 trazas:
eso NO es un denominador válido para hit-rate.

`evidence.json` guarda hashes e identidades; `remote-audit.json` reproduce
el análisis de paquetes sin contarlos varias veces por listener.

## Qué se contrastó y qué se descartó

1. Un reemplazo completo por velocidad constante/frenada elevó el MAE cliente
   de 0.5062 a 0.5287: **descartado**.
2. Añadir curvas sin conservar los casos fiables de A tampoco bastó
   (0.5107): **descartado como reemplazo general**.
3. B final es híbrido: conserva A excepto reposo, desacuerdos de salto,
   frenadas/curvas sostenidas con corrección mayor que la incertidumbre corporal,
   y pisos reales. No introduce otro factor RTT "aprendido" de los ecos.
4. Se inspeccionaron variantes con la sesión v35 y las dos pequeñas. No son
   holdout limpio. La sesión v30 se descargó después de fijar el híbrido;
   posteriormente sirvió también de regresión al corregir el muestreo por FPS.
   Por tanto, ya es un conjunto conocido y no debe reutilizarse como si fuera
   una nueva validación ciega. No se ajustaron parámetros por disparo.

## Replay del solver Gun contra poses de cliente

Se ejecutan `getFilteredVelocity` y `computeGunAim` **reales**, con A y B sobre
la misma muestra. La verdad comparada es posición futura interpolada de las
trazas del cliente, no posición rewound del servidor. El horizonte es la
hipótesis RTT acotada existente, igual para ambos. Se usa gravedad 196.2 y no se
dispone de geometría del mapa para el clamp de piso. Las muestras de una misma
ventana están correlacionadas: no son cientos de partidas independientes.

| Dataset | Ventanas | Muestras | MAE A (studs) | MAE B (studs) |
|---|---:|---:|---:|---:|
| desarrollo v35 | 27 | 176 | 0.506216 | 0.459032 |
| otra sesión v30, imperfecta | 30 | 284 | 3.256006 | 3.211581 |
| pequeñas v34/v31 | 2 | 17 | 0.203354 | 0.203354 |

También se conserva el desglose por tipo del evento original. Ejemplo v35:
las 34 muestras procedentes de eventos Gun pasan de 1.075053 a 1.030103.
Las ventanas registradas alrededor de Knife se usan **solo como movimiento
adicional del objetivo para el solver Gun**. No evalúan el nuevo interceptador
Knife ni demuestran su precisión. Los JSON históricos tienen casos malos y
error alto; ni siquiera las confirmaciones permiten convertir estos MAE en
porcentajes de acierto.

Fixtures mínimas desidentificadas en `tools/fixtures/prediction-v42/`, sin
nombres/IDs de jugadores ni telemetría completa. Cada fixture conserva SHA-256
del JSON documental original. Los resultados incluyen SHA-256 de las fixtures.

```sh
export LUAU=/ruta/a/luau
python3 tools/replay_gun_prediction.py \
  tools/fixtures/prediction-v42/development.json
python3 tools/replay_gun_prediction.py \
  tools/fixtures/prediction-v42/holdout.json
python3 tools/test_prediction_replay.py
python3 tools/test_prediction_v42.py
```

El test nuevo cubre A inmutable en 108 combinaciones, stop sin retroceso,
reposo, curvas con signo, apex/suelo, historial acotado sin duplicados por FPS,
respawn, endpoint A de sombra, ausencia de gate por incertidumbre y atribución
geométrica de ecos. Knife se verifica con su función real y casos controlados
de intercepción/gravedad del objetivo/aterrizaje; esto **no es prueba online**.
La animación/protocolo de release siguen pasando las suites existentes R6/R15,
revalidación de objetivo y una sola llamada al remote.

## Lo que falta demostrar en Roblox

Aciertos/rechazos reales de servidor con denominador y asociación inequívoca,
ping/jitter distintos, pisos y coberturas reales, sesiones nuevas, móvil/PC.
No hubo acceso a un cliente Roblox vivo en este entorno. El rollback está
expuesto en Calibration y el punto A se registra sin enviar otro paquete.
