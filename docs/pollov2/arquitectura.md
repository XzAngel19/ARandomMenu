# PolloV2 — arquitectura

Paso 2. Se deriva de `PolloV2-idea.md`. Si algo de acá choca con la intención,
gana la intención y se rediseña esto.

---

## La decisión que ordena todo lo demás

> **Ningún módulo crea instancias. Un módulo devuelve una especificación; el
> renderer la interpreta.**

De esa única decisión salen las tres cosas que el concepto pide:

- si la UI es un **árbol declarado**, cada nodo puede tener una identidad;
- si tiene identidad, se puede **seleccionar** en el inspector;
- si se puede seleccionar, se puede **sobreescribir, serializar y exportar**.

Y sale gratis el no-negociable de la GUI reemplazable: los módulos no saben qué
es un pixel, así que el renderer se puede tirar y reescribir entero sin tocar un
solo módulo.

---

## 1. El árbol declarado (`Spec`)

Un módulo no construye UI, la describe:

```lua
return {
    id = "killaura",
    category = "combat",
    title = "Killaura",
    spec = {
        {id = "reach",   kind = "slider", label = "Reach",   min = 5,  max = 30, default = 12},
        {id = "hitmin",  kind = "slider", label = "Hitreg min", min = 1, max = 40, default = 35},
        {id = "hitmax",  kind = "slider", label = "Hitreg max", min = 1, max = 40, default = 36},
        {id = "targets", kind = "slider", label = "Max targets", min = 1, max = 5, default = 1},
        {id = "team",    kind = "toggle", label = "Team check", default = true},
    },
    onEnable = ..., onDisable = ..., onTick = ...,
}
```

Reglas duras, y las dos son testeables:

1. **Todo nodo lleva un `id` explícito.** El renderer rechaza el que no lo
   tenga. Nada de derivar la identidad del índice en el array ni del texto de la
   etiqueta — los dos cambian y el override del usuario se perdería en silencio.
2. **El `id` no se cambia nunca.** Es la clave del override guardado. Cambiarlo
   es borrar la customización de todo el que ya la hizo.

### Kinds de nodo

`group`, `module`, `row`, `toggle`, `slider`, `range`, `dropdown`, `color`,
`bind`, `text`, `button`, `separator`, `note`.

Cada kind sabe qué sub-partes tiene, y cada sub-parte es seleccionable:

```
toggle  →  track, knob, label
slider  →  track, fill, knob, label, value
module  →  background, title, indicator, dots
```

Eso es lo que hace que se pueda editar "los tres puntos": no son un adorno
dentro de un frame, son un nodo con identidad propia.

---

## 2. Identidad (`Identity`)

La identidad de un nodo es su **ruta**, construida al recorrer el árbol:

```
panel/combat/killaura/reach/knob
panel/combat/killaura/title
dock/logo
```

Estable, legible, y única. El inspector muestra esta ruta cuando seleccionás algo,
que es lo que le da la sensación de Studio.

```lua
export type Path = string          -- "panel/combat/killaura/reach/knob"

Identity.build(parent: Path?, id: string): Path
Identity.parent(path: Path): Path?
Identity.matches(path: Path, prefix: Path): boolean   -- para sobreescribir un subárbol entero
```

`matches` importa: un override en `panel/combat/killaura` aplica a todo el módulo,
y uno en `panel/combat/killaura/title` pisa a ese. Especificidad por profundidad,
igual que CSS.

---

## 3. Roles y la cadena de resolución

### Roles, no rutas, en el tema

Un tema **no** define colores por ruta — sería enorme y no se podría compartir.
Define colores por **rol**: el papel que cumple una pieza.

```lua
export type Role =
    | "panel.background" | "panel.border"
    | "row.background"   | "row.background.hover" | "row.background.active"
    | "row.label"        | "row.value"
    | "control.track"    | "control.fill" | "control.knob"
    | "accent"           | "accent.dim"
    | "text"             | "text.dim"
    | "semantic.danger"  | "semantic.success"
    | "dock.background"  | "dock.border"
    -- ~30 roles en total
```

Cada nodo del árbol declara su rol. El renderer pregunta por rol, nunca por ruta.

### La cadena

```lua
resolve(path: Path, prop: Prop): Value
-- 1. overrides[path][prop]          ← lo que tocaste en el inspector
-- 2. overrides[ancestro][prop]      ← herencia por subárbol
-- 3. theme[rol(path)][prop]         ← el tema activo
-- 4. defaults[rol(path)][prop]      ← el neutro de fábrica
```

Y por eso "restaurar" no borra: **destapa** la capa de abajo.

`prop` cubre las dos familias, porque el usuario edita las dos:

- **color**: `background`, `text`, `border`, `glow`
- **métrica**: `width`, `height`, `padding`, `radius`, `borderWidth`, `textSize`

Resolución con caché, invalidada por path cuando toca el inspector y en bloque
cuando cambia el tema. Sin caché, resolver sesenta piezas por frame no es una
opción.

---

## 4. Color (`Theme` + `Contrast`)

### Paleta curada como dato

Los anclajes del concepto viven en una tabla, no dispersos:

```lua
export type Anchor = {name: string, hex: string, character: string}
Palette.neutral : {Anchor}   -- void, panel, raised, line, bone, ash
Palette.accent  : {Anchor}   -- esmeralda, jade, turquesa, cobalto, ...
```

Prohibido por test: `#FFFFFF`, `#000000` y cualquier color con dos canales en 0
y uno en 255 (la firma de un primario crudo). Si alguien agrega un color así, el
gate falla. Es la forma de que "no uses colores simplones" sobreviva a seis
meses de cambios.

### La rueda interpola entre anclajes

```lua
Harmony.at(t: number): Anchor          -- t en [0,1], recorre los anclajes curados
Harmony.category(name: string, base: Anchor): Color3
```

Rotar HSV crudo queda prohibido explícitamente: es lo que genera `#FF00FF`.

### El contraste se resuelve, no se avisa

```lua
Contrast.ratio(fg: Color3, bg: Color3): number     -- WCAG real
Contrast.fix(fg: Color3, bg: Color3, target: number): Color3
```

`resolve` llama a `fix` sobre todo par texto/fondo antes de devolverlo. El matiz
del texto se conserva; se ajusta **solo la luminosidad**. Umbrales: 4.5:1 texto,
3:1 interfaz.

Consecuencia arquitectónica importante: **el texto nunca se resuelve solo.** Si
un nodo tiene `text`, su `background` resuelto es parte de la entrada. Eso hay
que resolverlo en el orden correcto y cachearlo junto.

---

## 5. El inspector

Un modo, no una ventana aparte:

```
estado: off | hover | selected(path)
```

- **hover**: el renderer dibuja un outline sobre la pieza bajo el cursor y
  muestra su ruta. Es una capa propia, no toca la pieza.
- **selected**: aparece el panel de propiedades, que es un spec como cualquier
  otro (el inspector se construye con el mismo renderer que el menú — no hay dos
  sistemas de UI).
- Cada propiedad escribe en `overrides[path][prop]` e invalida el caché de ese
  path. El cambio se ve en el mismo frame.
- `restaurar pieza` borra `overrides[path]`; `restaurar todo` borra la tabla.

Lo que hace que sea barato: el modo edición **solo existe mientras está activo**.
Fuera de él no hay listener de mouse extra, ni outline, ni nada.

---

## 6. Serialización

```
PLV2-1-<base64(json)>-<checksum4>
```

- `PLV2` magia, `1` versión del formato, checksum corto para detectar un paste
  truncado.
- El payload lleva: nombre del tema, los roles que difieren del default, y los
  overrides por path. **Solo lo que difiere** — un tema sin tocar pesa unos
  cientos de bytes.
- Al importar se valida contra el esquema y **se pasa por `Contrast.fix`**. Nadie
  te puede mandar un tema ilegible.
- Un tema **nunca** lleva configuración de módulos ni keybinds.

---

## 7. Efectos, con el techo en el tipo

```lua
export type Effect = {
    id: string,
    cost: number,
    apply: (target: Instance) -> () -> (),   -- devuelve su propio cleanup
}

Budget.total  : number
Budget.used   : number
Budget.request(effect: Effect): boolean       -- false si no entra
```

El techo es duro porque está en el tipo: `request` devuelve `false` y el efecto
no se aplica. No hay API para saltearlo.

Regla estructural: **todo efecto devuelve su cleanup**, y el cleanup corre
cuando el menú se cierra. Así "si el menú está cerrado no existe" no es una
promesa, es que no queda nada corriendo.

---

## 8. Contrato de módulo

Un módulo puede:

- devolver un spec;
- declarar `onEnable`, `onDisable`, `onTick`, `onChange(id, value)`;
- leer el estado del juego a través del bridge;
- registrar una fuente de juego (`{scan, press}`).

Un módulo **no puede**:

- crear instancias de UI, ni tocar `ScreenGui`;
- escribir un color, un tamaño o un `TweenService`;
- leer el tema;
- usar hooks globales (`hookmetamethod`, `hookfunction`, `hookproperty`,
  `replaceclosure`, `setrawmetatable`).

Las cuatro prohibiciones son testeables con un gate estático sobre
`src/modules/**`, igual que en ARandomMenu. No son una convención.

### Game support

Un juego describe lo que tiene y cómo se usa; las cards universales lo consumen:

```lua
GameSource = {
    scan: () -> {{string}},          -- {label, instance}
    press: (label: string, target: any?) -> boolean,
}
```

`press` recibe el target cuando el que llama lo tiene. Sin eso no se puede
unificar un KillAura, y en ARandomMenu ese detalle costó tres intentos.

---

## 9. Carpetas

```
src/
  core/
    Spec.luau          tipos del árbol + validación
    Identity.luau      rutas
    Theme.luau         roles, defaults, paleta curada
    Harmony.luau       interpolación entre anclajes
    Contrast.luau      WCAG + corrección
    Resolve.luau       la cadena + caché
    Serialize.luau     tema ↔ string
  ui/
    Renderer.luau      spec → instancias
    Inspector.luau     modo edición
    Effects.luau       capa con presupuesto
    Panel.luau  Dock.luau  ThemePicker.luau
  modules/
    combat/  visual/  movement/  player/  misc/
  game/
    Bridge.luau        fuentes de juego
  platform/
    Input.luau  Config.luau  Loader.luau
tools/
  validate.sh
  check_module_contract.py    las cuatro prohibiciones
  check_palette.py            sin blancos puros ni primarios
  check_identity.py           todo nodo con id explícito y único
test/
  suites/...
```

Los tres gates de `tools/` son lo que mantiene las reglas vivas. Una regla que no
está en un gate deja de existir en seis meses.

---

## 10. Orden de construcción

Cada paso termina con algo que funciona y se puede probar. No hay un paso que
dependa de tres futuros.

1. **Spec + Identity + Renderer** con estilos hardcoded. Un menú que anda, sin
   temas. Acá se valida que el árbol declarado no sea un infierno de escribir.
2. **Theme + Resolve.** Todo el menú se recolorea desde los roles. Todavía sin
   inspector.
3. **Contrast.** La garantía. A partir de acá no existe combinación ilegible.
4. **Inspector.** Click, seleccionar, sobreescribir en vivo, restaurar.
5. **Serialize + exportar/importar.** El menú se vuelve compartible.
6. **Effects + Budget.** La capa con techo duro.
7. **Las seis funciones estéticas**, en este orden: armonía → ripple → acento
   reactivo → transición en onda → acento con audio → miniaturas reales. Las
   últimas dos son las caras y van cuando todo lo demás ya está firme.
8. **Game bridge + módulos.** Lo último, porque es lo que menos riesgo tiene: el
   contrato ya existe probado en ARandomMenu.

Los pasos 1–3 son el proyecto. Si el árbol declarado resulta incómodo de
escribir, se cambia en el paso 1 y no en el 7.

---

## Riesgos, dichos de frente

1. **El árbol declarado puede quedar verboso.** Si escribir un módulo cuesta el
   doble que hoy, nadie va a escribir módulos. Mitigación: helpers por kind, y
   el paso 1 existe justamente para enterarse antes.
2. **Resolver sesenta piezas por frame.** Mitigación: caché por path, invalidación
   fina. Si el caché no aguanta, la UI se resuelve una vez y se ensucia solo.
3. **Los overrides por pieza hacen que un tema sea grande.** Mitigación: solo se
   serializa lo que difiere. Si aun así pesa, se comprime — pero no se recorta la
   capacidad.
4. **Las miniaturas reales renderizan el menú dos veces.** Mitigación: solo en el
   selector de temas, nunca durante el juego, y con un `ViewportFrame` propio.
