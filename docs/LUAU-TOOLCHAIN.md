# Luau toolchain (v199) — qué se instaló y por qué

Este documento cierra la petición «consigue las tools/skills necesarias para
compilar y programar correctamente». Todo está **dentro del repo**: un clon
nuevo, un sandbox con `node_modules` borrado o un CI sin red se reconstruyen con
un comando.

```bash
bash tools/luau/setup.sh --verify      # descompacta + prueba cada herramienta
```

## Lo que no se pudo traer, y por qué

El entorno solo permite salida a `github.com`, `api.github.com`,
`codeload.github.com`, `registry.npmjs.org`, `pypi.org` y
`files.pythonhosted.org`. Los binarios nativos de las releases de GitHub
(`darklua`, `stylua`, `luau-analyze`, `selene`) se descargan desde
`release-assets.githubusercontent.com`, que está **bloqueado**:

```
curl: (35) OpenSSL SSL_connect: SSL_ERROR_SYSCALL
     ... in connection to release-assets.githubusercontent.com:443
```

`api.github.com` sí responde, así que las versiones y los assets se pudieron
enumerar (DarkLua `v0.19.0`, StyLua `v2.6.0`, luau-lsp `1.70.1`). La solución no
fue un binario nativo sino la **build wasm de cada herramienta**, publicada en
npm y vendorizada como tarball:

| Necesidad | Antes | Ahora | Tarball |
| --- | --- | --- | --- |
| ejecutar Luau (harnesses) | `@luau-rs/luau` 0.739 | igual, ahora con script de verdad | `luau-rs-luau-0.739.0.tgz` (2.7 MB) |
| **DarkLua** | no existía | `tools/luau/minify.mjs` | `darklua-wasm-0.1.0.tgz` (1.2 MB) |
| **StyLua** | no existía | `tools/luau/format.mjs` | `johnnymorganz-stylua-2.6.0.tgz` (912 KB) |
| **luau-analyze** | no existía | `tools/luau/analyze.mjs` | ya venía en `@luau-rs/luau/analysis` |
| dependencia de `@luau-rs/luau` | se instalaba con `npm i` | vendorizada | `valibot-1.5.0.tgz` (188 KB) |

`tools/luau/setup.sh` desempaqueta los cuatro tarballs en `node_modules/` y crea
los binarios en `tools/luau/bin/`. Es idempotente y no toca la red.

## El detalle que costó el run: definiciones de tipos

`luau-analyze` sin definiciones reporta **9 129 diagnósticos**, casi todos
`Unknown global 'CFrame'` / `Unknown type 'Vector3'`. La fuente correcta es
`globalTypes.d.luau` de luau-lsp (880 KB, 2 306 declaraciones, generado del API
dump de Roblox). Se baja así, sin releases bloqueadas:

```bash
curl -sS "https://api.github.com/repos/JohnnyMorganz/luau-lsp/contents/scripts/globalTypes.d.luau?ref=main" \
  | python3 -c "import json,sys,base64;open('/tmp/globalTypes.d.luau','wb').write(base64.b64decode(json.load(sys.stdin)['content']))"
```

Cargarlo entero **no funciona**:

```
definition "globalTypes.d.luau": Internal error: Code is too complex to typecheck!
```

`tools/luau/definitions/build_definitions.py` construye un subconjunto y lo
**cierra sobre sí mismo**: lo renderiza, lo carga con el analizador real
(`tools/luau/probe.mjs`), lee los `Unknown type` que faltan, los añade, y repite
hasta que carga limpio. Reglas que descubrió ese bucle, en orden de aparición:

1. `Enum` y `EnumItem` primero, o los tipos miembro no pueden extenderlos.
2. Los tipos miembro (`EnumKeyCode`…) extienden `EnumItem`; su `_INTERNAL`
   extiende `Enum`.
3. Un tipo usado como superclase tiene que ser **clase** y estar **antes**:
   `Cannot use non-class type 'StyleBase' as a superclass of class 'StyleSheet'`.
4. Una clase mencionada por un miembro (p. ej. `Pages` en
   `MarketplaceService:GetDeveloperProductsAsync`) es un `Unknown type` si no se
   declara: se declara por nombre y superclase, sin miembros.
5. Un alias de cadena (`ContentId`, `ProtectedString`) también cuenta como
   `Unknown type`.
6. `Enum` global se declara `{ [string]: any }`: tiparlo como el `ENUM_LIST` de
   656 entradas devuelve el error de complejidad.

Resultado: `core.d.luau`, 3 685 líneas, carga en ~0.3 s. Y `runtime.d.luau` a
mano para el ejecutor (`getgenv`, `hookmetamethod`, `setclipboard`…) y el host
del menú (`create`, `Theme`, `state`, `notify`, `TaskManager`, `Players`…).

Efecto medido sobre el árbol: de **9 129 → 428** diagnósticos.

## Lo que el front end wasm no sabe hacer

Los 76 restantes están en `tools/luau/analyze-baseline.json`:

- `obj:IsA("MeshPart")` **no estrecha el tipo**. El analizador sigue viendo
  `Instance` y se queja de `MeshId`, `TextureID`… El código es correcto.
- `local k: Enum.KeyCode` no resuelve: `Enum` es la tabla global, no un espacio
  de nombres de tipos. `Enum.KeyCode.A` (expresión) sí funciona. Se probaron
  seis formas de declararlo, incluida la del dump original: ninguna resuelve en
  esta build.

`luau-analyze --baseline` falla **solo con errores nuevos** (`NEW`), así que la
puerta sirve de verdad: la suite demuestra que un global inventado la rompe.

## DarkLua en release

`tools/luau/minify.mjs` + `tools/luau/darklua.release.json` (13 reglas, las dos
listas tienen que coincidir):

```
remove_types → remove_debug_profiling → remove_compound_assignment →
convert_local_function_to_assign → group_local_assignment → remove_empty_do →
remove_unused_if_branch → remove_unused_while → remove_unused_variable →
remove_method_definition → rename_variables → remove_comments → remove_spaces
```

`src/Wurst.lua` 253 KB → **123 KB (−51.1 %)**, y el resultado compila con
`luau-compile`.

## Bug real encontrado por el toolchain

`src/games/MM2/Other/FlingEngine.lua` escribía `AssemblyLinearVelocity` y
`AssemblyAngularVelocity` en cada pose, exactamente lo que
`tools/test_fling_skid.py` prohíbe (es el bug que hacía «desaparecer» al
personaje local). El contrato del repo estaba escrito en la cabecera del propio
motor y la suite llevaba tiempo en rojo en un sandbox limpio. Corregido: la pose
vuelve a escribirse solo con `CFrame` + `Velocity`/`RotVelocity`; la suite pasa
14/14.

## Puertas nuevas en `tools/validate.sh`

```
luau-compile        todos los .lua compilan
luau-analyze        --baseline: 0 errores fuera de la deuda aceptada
luau-format         (opt-in) STYLUA_FILES="src/..." como puerta por cambio
build_definitions   --check: core.d.luau sale del dump fijado
test_luau_toolchain 12 suites del propio toolchain
```

Sobre el formato, una advertencia aprendida a golpes: **no se reformatea el
árbol entero**. StyLua cambia `{[string]: any}` por `{ [string]: any }`, y tres
suites de Python comparan ese texto literal. La puerta es por fichero tocado;
el reformateo global va en su propio commit si alguna vez se decide.
