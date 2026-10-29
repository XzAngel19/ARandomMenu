# X2 Duels: captura de código y remotes

## Opción integrada: Gun Probe (v153)

**Advertencia:** el usuario reportó BAC-1583 con Probe v148 y que la v149
impedía disparar. No está probada la causa ni su corrección. Oth no garantiza
que el juego no vuelva a expulsar.

### Buscar la fuente de Gun sin activar Probe

Con la pistola en la mochila o equipada, abre la tarjeta **Gun Probe** y pulsa
**Save gun sources** sin encenderla. Esta acción no instala hooks ni activa el
Probe. Usa las funciones `decompile` y `writefile` del executor, que pueden no
estar disponibles, fallar o ser detectadas. Al completarse, Status indica cuántos
scripts guardó y si hubo fallos. Busca en la raíz del workspace del executor:

- `X2Duels-gun-sources.json`: manifiesto de la última captura (se sobrescribe).
- `X2Duels-gun-source-<timestamp>-<generación>-<n>.luau`: scripts capturados;
  cada intento usa nombres distintos, no borrar ni confundir archivos anteriores.

Revisa los archivos antes de compartirlos: pueden incluir datos privados o
código sensible. No hay garantía de que capturen el script principal, y no son
el código de validación del servidor. Si dice `decompile unavailable` o `0/n`,
informa el Status en lugar de activar Gun Probe.

### Comprobar la carpeta

**Test workspace** también funciona con el módulo apagado y sin instalar hooks.
Escribe `X2Duels-workspace-test.txt` en la raíz del workspace, sin tocar el JSON
anterior. Status distingue lectura verificada, solo existencia y sin verificar.
Cada executor determina la ubicación física y su acceso externo.

Desde v153 Probe se detiene al iniciar combate y no se inicia mientras Silent,
Auto Shoot, Auto Win, Knife Throw o Kill Aura estén activos. No lo actives para
probar esas funciones: el usuario reportó BAC-1583 e interferencia con la Gun.

Cuando se activa Probe, `X2Duels-calibration.json` usa esa misma raíz y se
sobrescribe al empezar, cada ~3 s si hay cambios y al parar. La captura Oth
puede interferir con el arma: **no la actives para recolectar las fuentes**.
El JSON guarda como máximo los 400 eventos más recientes y puede contener
vectores y nombres; revisa privacidad antes de compartirlo.

## Recolector independiente anterior

**Advertencia:** el recolector siguiente usa `hookmetamethod`, no Oth. El usuario
reportó expulsiones con hooks tradicionales en este juego; no se recomienda
usarlo en esa situación. Es distinto de Gun Probe integrado.

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
