# GameRoles — contrato de roles para juegos

Servicio disponible como `context.services.gameRoles` en módulos universales,
o `services.gameRoles` en el entorno de módulos de juego. Es un servicio, no
otra tarjeta del menú. El bridge existente `registerRoleProvider` sigue siendo
compatible con los juegos anteriores.

```lua
local removeRoles = services.gameRoles:Register({
    Name = "ExampleGame",
    Roles = {"Medic", "Guard", "Spectator"},
    Colors = {
        Medic = Color3.fromRGB(100, 220, 170),
        Guard = Color3.fromRGB(100, 170, 245),
        Spectator = Color3.fromRGB(160, 170, 185),
    },
    -- false/omitido: roles y equipos pueden coexistir.
    ReplacesTeams = false,
    -- Opcional: permite a Chams incluir cuerpos muertos todavía existentes.
    DeadRoles = {"Spectator"},
    Get = function(player)
        return player:GetAttribute("Role") -- string de Roles, o nil
    end,
    -- Opcional: GetColor(role) ofrece colores iniciales dinámicos.
    -- Opcional: GetPerk(player) conserva compatibilidad con el bridge.
})

-- Al descargar el juego: solo elimina ESTE proveedor si sigue siendo actual.
removeRoles()
```

Usar nombres de rol estables, únicos, preferentemente IDs ASCII, sin
colisiones al quitar espacios/puntuación (las opciones comparten el sistema de
IDs del menú). Get/GetColor son funciones simples, no métodos con self.
No requieren polling propio del renderer; actualizar los datos del proveedor y
llamar `state.invalidateGameRoles()` cuando cambie un rol invalida la caché del
bridge. MM2 ya lo hace con sus eventos existentes.

## Consumir roles en un nuevo módulo visual

```lua
local binding = context.services.gameRoles:Bind(card, {
    filters = true, -- opcional: crea "Medic ESP", etc.
    -- palette = false: solo metadatos, sin opciones de colores (caso HP).
})

-- En render:
if binding:Allows(player) then
    local colour, role = binding:Resolve(player, fallbackColour)
    -- dibujar con colour; role puede ser nil
end

-- Al descargar el módulo (NO en cada OFF):
binding:Destroy()
```

Bind agrega Role colours y un color por rol únicamente cuando hay proveedor.
Los colores y filtros usan la persistencia normal del card y son independientes
entre módulos. No llama SetColor del proveedor: no modifica la paleta de otro
ESP. Si un proveedor se retira/cambia, oculta las filas antiguas y agrega las
nuevas sin duplicar controles. Se admiten hasta 32 roles visibles por proveedor.
Las preferencias existentes se conservan al registrar nuevamente el mismo rol.

`ReplacesTeams` permite ocultar y dejar de aplicar opciones de equipos cuando
no tienen sentido (MM2). No debe activarse por defecto en juegos que mezclan
roles con equipos reales. El consumidor controla esta política mediante
`binding.provider.ReplacesTeams`; el helper no fuerza un filtro de equipos a
un renderer que no lo pidió.

Get puede devolver nil o lanzar un error temporal sin romper el renderer: se
usa el color base y no se inventa un rol. Un nombre no declarado no recibe un
color/filtro accidental de otro rol. DeadRoles no resucita personajes ni
reconstruye corpses: Chams solo puede adornar modelos actualmente disponibles.

## Ciclo de vida y pruebas

El servicio se carga desde Manifest y su fallback del loader antes de los
módulos visuales. Los listeners se desregistran al destruir el binding/servicio.
El registro/remoción invalida las cachés de rol/color del bridge. El cleanup de
un proveedor anterior es inocuo si otro juego/proveedor ya tomó su lugar.

```sh
LUAU=/ruta/a/luau python3 tools/test_render_roles.py
python3 tools/gen_full_boot_harness.py
/ruta/a/luau build/full_boot.luau
```

Las pruebas ejecutan las fuentes reales, incluyendo cambio MM2→Medic/Guard,
paletas independientes, cadáver actual, Unicode, caché de tamaños, vida propia,
respawn y limpieza de recursos. No son una medición de FPS ni un screenshot de
Roblox real.
