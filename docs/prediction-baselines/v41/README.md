# Referencia reversible A — v41 / 627c556

Copias completas obtenidas de Git antes de modificar los predictores:
`Shoot.lua.txt`, `KnifeThrow.lua.txt`, `base.lua.txt`. El commit completo y los
SHA-256 están en `metadata.json`. No se incluyen como módulos en el bundle.
La referencia v35 anterior no fue modificada.

En v42, **Calibration → Prediction model → Reference v41** restaura las
matemáticas A de Gun y Knife conservando correcciones posteriores de menú,
activación/WallCheck y seguridad de atribución de ecos. No revierte toda la UI.
El test `test_prediction_v42.py` compara el solver Gun actual en Reference con
el archivo inmutable sobre 108 combinaciones de estado/velocidad/aceleración/
horizonte, además de verificar los hashes de los tres archivos.

Para una restauración histórica de todos los detalles del runtime, recuperar
las dependencias completas de este commit; no mezclar archivos antiguos con
una base futura sin comprobar su contrato.
