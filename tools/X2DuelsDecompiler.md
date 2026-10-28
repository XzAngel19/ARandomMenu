# X2 Duels: captura de código y remotes

## Opción integrada: Gun Probe (v148)

En X2 Duels, abre **Combat → Gun Probe**, actívalo y usa **Equip gun**. Dispara
con el control normal y luego apaga el módulo o usa **Save report**. La captura
es pasiva y termina a los 60 segundos: `X2Duels-calibration.json` se guarda en
los archivos del executor y se sobrescribe en la siguiente sesión. El Status
indica si Oth Mouse, namecall y Raycast directo se instalaron y si falló guardar.
Primero prueba con Silent AIM apagado; si quieres comparar, conserva el archivo
antes de repetir con Silent activado. `Save gun sources` es opcional y guarda
hasta 20 archivos `X2Duels-gun-source-<n>.luau` si decompile/writefile funcionan.

Contiene nombres de scripts/remotos, tipos de argumentos y origen/dirección de
rayos: revisa información privada antes de compartir. Puede capturar eventos
ajenos o duplicados, omitir APIs, y no confirma impactos. Hooks Oth inactivos
quedan hasta salir; no garantiza que no haya detección. Si guardado o hook falla,
informa el Status y no asumas que el método no se usa.

## Recolector independiente anterior

**Advertencia:** el recolector siguiente usa `hookmetamethod`, no Oth. El usuario
reportó expulsiones con hooks tradicionales en este juego; no se recomienda
usarlo en esa situación. Es distinto de Gun Probe v148.

`X2DuelsDecompiler.luau` es una herramienta independiente del menú. Se ejecuta dentro de X2 Duels para reunir la evidencia que el RBXL y el log anteriores no contienen. **No envía disparos ni modifica sus argumentos.**

## Capturar la pistola en una partida

1. Entra a X2 Duels con un executor que permita `writefile` y `makefolder` y ejecuta `tools/X2DuelsDecompiler.luau`.
2. Cuando la Gun esté en el inventario o equipada **durante la partida**, ejecuta:

   ```luau
   getgenv().X2DuelsDecompiler.snapshotWeapons()
   ```

   Espera el mensaje `weapon snapshot ... complete`. Si el arma aparece después de la primera captura o vuelves a aparecer, repite el comando. La captura inicial de `sources.json` sólo incluye los scripts que existían cuando comenzó; por eso es importante esta captura específica.
3. Dispara una vez con el control normal del juego y una vez con el botón de Silent AIM. Si también se investiga Knife Throw, captura el cuchillo mientras esté en la mochila o equipado y haz un lanzamiento normal.
4. Espera el mensaje `source dump complete` y detén la captura:

   ```luau
   getgenv().X2DuelsDecompiler.stop()
   ```

Para actualizar el inventario sin detenerla, usa `getgenv().X2DuelsDecompiler.snapshot()`. Para comprobar si finalizaron las capturas de armas, usa `getgenv().X2DuelsDecompiler.areWeaponSnapshotsDone()`.

La carpeta se crea como `X2DuelsDecompiler/<placeId>-<timestamp>/`. Para investigar Silent AIM son especialmente útiles `weapon-sources-<n>.json`, sus archivos `sources/weapon_<n>_...`, `capabilities.json` y el tramo correspondiente de `remote-calls.jsonl`. También ayuda indicar el nombre del executor, si es celular o PC y el mensaje exacto de **Status**.

## Archivos y privacidad

- `inventory.json`: remotes con ruta y parent, scripts, Tools, `PumpkinCurrency_*`, botones y jugadores. Se actualiza con el Backpack y Character actuales después de un respawn.
- `weapon-sources-<n>.json`: Tools actuales y sus scripts decompilados o bytecode, incluso si aparecieron después de inyectar el recolector. Cada llamada usa un número nuevo.
- `remote-calls.jsonl`: una línea por llamada entrante/saliente, con método, caller y argumentos serializados.
- `sources.json` y `sources/`: resultado de `decompile`, bytecode de `getscriptbytecode` y errores de escritura.
- `capabilities.json`: executor identificado cuando es posible, controles disponibles y APIs detectadas, incluyendo `checkcaller`, `getrawmetatable`, `setreadonly` e `isreadonly` para diagnosticar el fallback Mouse. La presencia de una API no garantiza que funcione con este juego; `hookmetamethod` indica si pudo instalarse el hook de captura `__namecall`, no necesariamente el de `__index`.
- `status.json`: estado final y restauración de la captura.

Las capturas pueden contener nombres de usuario, identificadores de jugadores/servidor y argumentos de remotes. Revísalas antes de compartirlas y no compartas contraseñas, tokens ni credenciales. `usableSource=false` significa que el texto es un placeholder o una decompilación fallida; no debe tratarse como código recuperado. El `.luauc` se conserva como evidencia alternativa. Sin `appendfile`/`readfile`, el log usa un respaldo en memoria para no sobrescribir llamadas anteriores.

La herramienta no ejecuta el código volcado, no reescribe argumentos y no fabrica llamadas. Al detenerla restaura `__namecall` y desconecta sus listeners.

## Límite de la evidencia

El harness `tools/test_x2duels_decompiler.py` valida el comportamiento del recolector con un DataModel simulado. No demuestra los esquemas reales de X2. Hace falta una captura en vivo para confirmar combate, recolección de monedas y argumentos de resultados. `RematchTeleport:FireServer("back_to_lobby")` sigue siendo solo una transición al lobby, no un sustituto de Play Again.
