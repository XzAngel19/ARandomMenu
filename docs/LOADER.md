# Loader — cómo inyectar Wurst y qué hacer si falla

## El error que motiva este documento

```
17:36:01   :2: attempt to call a nil value
Script '', Line 2
```

Ese `Script '', Line 2` es el cargador de **dos líneas**:

```lua
getgenv().WURST_BRANCH = "arena/7446e4e3-arandommenu"
loadstring(game:HttpGet("<url de src/Wurst.lua>"))()
```

`loadstring` devuelve `nil` cuando el texto recibido **no compila**, y llamar a
`nil` produce exactamente ese mensaje. El cargador de una línea **tira el motivo
a la basura**, así que no se puede saber cuál de estas tres cosas pasó:

1. **Descarga cortada.** `game:HttpGet` devolvió menos bytes de los que tiene el
   fichero (254 KB en v193). `loadstring` corta el texto en la mitad de una
   función y devuelve `nil`.
2. **Cache del ejecutor o del CDN.** Muchos ejecutores cachean `HttpGet` por URL
   dentro de la sesión. Si la primera descarga falló, todas las siguientes
   devuelven el mismo texto roto, aunque la URL esté bien: el síntoma se repite
   para siempre.
3. **Error de compilación real** (una versión de Luau más vieja que el fichero).

## El cargador bueno

Está en el `README.md`. Sus tres diferencias con el de una línea:

- `?t=<os.time()>&a=<intento>` en la URL: rompe la cache del ejecutor y la del
  CDN, así que cada intento pide el fichero de verdad;
- comprueba **tamaño** (`> 100000` bytes) y **cabecera**
  (`local RUNTIME_COMPATIBILITY_MARKER`) antes de compilar: una descarga cortada
  o un HTML de error se detectan sin gastar el `loadstring`;
- imprime el motivo con `warn("[Wurst] loader: …")` y reintenta hasta 4 veces,
  un segundo entre intentos.

Además pasa `"@Wurst"` como nombre de chunk, así que un error **dentro** del menú
sale como `Wurst:3412: …` en lugar de `Script '':3412`, que es lo que hacía
imposible distinguir un fallo del cargador de un fallo del menú.

## Qué hacer si vuelve a fallar

1. Copia la línea `[Wurst] loader: …` de la consola.
   - `descarga incompleta (N bytes)` → red/CDN. Reintenta; el propio cargador ya
     lo hace 4 veces.
   - `la respuesta no es el menu (HTTP N bytes)` → la URL devolvió un 404 o una
     página de error.
   - `error de compilacion: …` → el ejecutor no acepta alguna sintaxis; ese texto
     dice la línea y el token.
   - `HttpGet fallo: …` → el ejecutor bloquea HTTP.
2. Con la consola limpia (`[Wurst] 0.194 Release`), el menú está dentro.

## Verificación del lado del repositorio

`tools/test_v194_loader.py` comprueba, sin arrancar el juego:

- que el cargador documentado lleva el cache-buster, la comprobación de tamaño y
  cabecera, el `warn` con motivo y el `"@Wurst"`;
- que `src/Wurst.lua` es UTF-8 válido, sin BOM ni bytes NUL, que termina en
  salto de línea y que su cabecera es la esperada — es decir, que **lo que se
  publica se puede cargar con `loadstring` tal cual**.

Lo que no puede comprobar: la red del jugador ni la versión de Luau de su
ejecutor. Si el problema es cualquiera de esos dos, el `warn` lo dirá.
