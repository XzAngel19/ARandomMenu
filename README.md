# Wurst

Loader único (siempre esta rama):

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/arena/2ec6eed9-arandommenu/src/Wurst.lua"))()
```

- No uses copias viejas del loader: un loader de otra rama ejecuta otro árbol y
  muestra otra versión. El runtime rechaza un "Reinject" cuyo loader declare una
  rama distinta; usa **Wurst Options → Reinject latest** y no una copia guardada.
- El menú muestra la versión derivada del build real (`UI Settings · v150`). Si
  ves otra cosa, estás ejecutando otro archivo.
- **v150** reconstruye por completo Fling, Anti fling, Anti Void, Touch Fling y
  Auto Farm de MM2 usando el `place` de `TestingStuff`. Auto Farm ya no finge
  cobros: camina hasta las partes `Coin_Server` y solo cuenta monedas cuando el
  servidor emite `CoinCollected`. Evidencia y límites en `docs/FIXES-v150.md`.
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
