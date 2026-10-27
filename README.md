# Wurst

Loader único (siempre esta rama):

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/arena/2ec6eed9-arandommenu/src/Wurst.lua"))()
```

- No uses copias viejas del loader: un loader de otra rama ejecuta otro árbol y
  muestra otra versión. El runtime rechaza un "Reinject" cuyo loader declare una
  rama distinta; usa **Wurst Options → Reinject latest** y no una copia guardada.
- El menú muestra la versión derivada del build real (`UI Settings · v151`). Si
  ves otra cosa, estás ejecutando otro archivo.
- **v151** corrige el reporte en vivo de que Fling, Touch Fling y Auto Farm no
  funcionaban. Fling y Touch Fling vuelven al `walkfling` real de Infinite Yield
  (`vel * 10000 + 10000Y` en Heartbeat, restaurado en RenderStepped, deriva
  ±0.1 en Stepped y noclip local temporal). Auto Farm elimina Pathfinding y el
  `BindToRenderStep` que bloqueaba el movimiento manual; el modo por defecto
  ahora se llama **Below Map**: aparca bajo cada `Coin_Server` real y sube el
  modelo hasta su volumen físico. Solo `CoinCollected` cuenta monedas. WASD o
  salto pausan el farm 1.2 s para conservar tu control.
- Evidencia, contratos y comprobaciones pendientes en vivo:
  `docs/FIXES-v151.md`. La evidencia del place sigue en `docs/FIXES-v150.md`.
- Cada inyección limpia en disco cualquier caché de un build anterior
  (`Wurst/src`, `Wurst/Assets`, marcadores). Tus perfiles en `Wurst/Profiles`
  no se tocan. **Wurst Options → Clear cache** fuerza esa limpieza y elimina
  también la caché del build actual.
- ¿Quieres probar otra rama sin editar nada? Define la variable antes de cargar:

```lua
getgenv().WURST_BRANCH = "arena/mi-rama"
loadstring(game:HttpGet("https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/arena/2ec6eed9-arandommenu/src/Wurst.lua"))()
```

El nombre pasa por una validación (sin espacios, sin `..`, longitud acotada); si
no es válido se ignora y se usa la rama canónica. Al cambiar de rama la caché se
invalida sola, así que no se mezclan árboles.
