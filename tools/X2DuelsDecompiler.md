# X2 Duels: captura de código y remotes

`X2DuelsDecompiler.luau` es una herramienta independiente del menú. Se ejecuta dentro de X2 Duels para reunir la evidencia que el RBXL y el log anteriores no contienen.

## Uso

1. Entra a X2 Duels con un executor que permita `writefile` y `makefolder`.
2. Ejecuta `tools/X2DuelsDecompiler.luau`.
3. Juega una ronda completa: dispara la pistola, lanza el cuchillo, recoge una calabaza y pulsa **Play Again**.
4. Espera el mensaje `source dump complete` y detén la captura:

```luau
getgenv().X2DuelsDecompiler.stop()
```

Para actualizar el inventario sin detenerla:

```luau
getgenv().X2DuelsDecompiler.snapshot()
```

La carpeta se crea como `X2DuelsDecompiler/<placeId>-<timestamp>/`.

## Archivos

- `inventory.json`: remotes con ruta y parent, scripts, Tools, `PumpkinCurrency_*`, botones y jugadores.
- `remote-calls.jsonl`: una línea por llamada entrante/saliente, con método, caller y argumentos serializados.
- `sources.json` y `sources/`: resultado de `decompile`, bytecode de `getscriptbytecode` y errores de escritura.
- `capabilities.json`: APIs disponibles durante el volcado.
- `status.json`: estado final y restauración de la captura.

`usableSource=false` significa que el texto es un placeholder o una decompilación fallida; no debe tratarse como código recuperado. El `.luauc` se conserva como evidencia alternativa. Sin `appendfile`/`readfile`, el log usa un respaldo en memoria para no sobrescribir llamadas anteriores.

La herramienta no ejecuta el código volcado, no reescribe argumentos y no fabrica llamadas. Al detenerla restaura `__namecall` y desconecta sus listeners.

## Límite de la evidencia

El harness `tools/test_x2duels_decompiler.py` valida el comportamiento del recolector con un DataModel simulado. No demuestra los esquemas reales de X2. Hace falta una captura en vivo para confirmar combate, recolección de monedas y argumentos de resultados. `RematchTeleport:FireServer("back_to_lobby")` sigue siendo solo una transición al lobby, no un sustituto de Play Again.
