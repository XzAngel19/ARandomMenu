# PolloV2 — la idea

Paso 1. Esto es la **intención**: qué es, en qué se diferencia y por qué. La
arquitectura viene después y se deriva de esto.

---

## Qué es

Un menú de Roblox **neutral, rápido y completamente editable**.

La referencia de usabilidad es VapeV4: estructura fija, panel único, práctico.
Pollo toma eso y le agrega lo que a Vape le falta — que el menú entero sea
editable elemento por elemento, desde adentro, en vivo.

> Cambiás cualquier cosa del menú tocándola. Y se ve caro sin costar frames.

---

## La paleta es curada, no generada

Prohibido el blanco puro, el negro puro y los primarios. `#FFFFFF` sobre
`#000000` no es elegante, es agresivo — el blanco puro sobre negro puro produce
halo y cansa la vista en cinco minutos. Y `#FF0000` / `#00FF00` / `#0000FF` son
colores de placeholder, no de producto.

Cada color del sistema es un tono elegido a mano, con nombre:

### Neutros
| Token | Valor | Nota |
|---|---|---|
| `void` | `#0B0B0C` | Fondo. Negro con un pelo de azul, no negro muerto |
| `panel` | `#141416` | Superficie del panel |
| `raised` | `#1C1C1F` | Hover y selección |
| `line` | `#2A2A2E` | Bordes y separadores |
| `bone` | `#EDEDEF` | Texto. Hueso, no blanco |
| `ash` | `#8A8A93` | Etiquetas y unidades |

### Acentos (todos tonos, ninguno primario)
| Nombre | Valor | Carácter |
|---|---|---|
| **Esmeralda** | `#10B981` | El de fábrica. Verde joya, no verde terminal |
| Jade | `#059669` | Esmeralda profunda |
| Turquesa | `#14B8A6` | Frío, limpio |
| Cobalto | `#2563EB` | Azul serio, no azul Excel |
| Zafiro | `#3B82F6` | Azul luminoso |
| Orquídea | `#A855F7` | Violeta suave, no morado neón |
| Coral | `#FB7185` | Cálido sin gritar |
| Rubí | `#E11D48` | Rojo joya, no rojo error |
| Ámbar | `#F59E0B` | Dorado, no amarillo |
| Cobre | `#EA7C47` | Naranja tostado |

Regla: **un solo acento en todo el menú.** Si algo necesita un segundo color,
está mal diseñado. Las excepciones son semánticas y nada más — peligro, éxito —
y salen de la misma paleta curada, nunca de un primario.

### La rueda de armonía no rota en HSV crudo

Rotar el matiz en HSV es lo que produce `#FF00FF` y `#00FF00`: colores
saturados que se ven de juguete. La rueda de Pollo **interpola entre los anclajes
curados de arriba**, así que cada parada del recorrido es un color diseñado. El
usuario gira y siempre cae en algo bonito, porque no hay forma de caer en otra
cosa.

Y las categorías derivan del mismo anclaje con un corrimiento chico de matiz y
de luminosidad: Combat, Visual, Move y el resto quedan en familia sin que nadie
tenga que elegir seis colores que combinen.

---

## La diferencia central: el tema es dato, no código

Verificado en el dump de VapeV4 (`reference/vape-v4-universal.lua.txt`): expone
`Background Color`, `Bar Color`, `Border Color`, `Circle Color`, `Color Begin` /
`Color End`, `Blur`, `Font` y `CornerRadius` — pero **por módulo y por widget**.
Cada uno decide su color. No hay un lugar donde cambiar todo, y no hay forma de
exportar un tema: busqué `themecode`, `exporttheme`, `importtheme` y no existe
ninguno.

| | VapeV4 | PolloV2 |
|---|---|---|
| Color | Por módulo y por widget | Por token, y **por elemento** si querés |
| Alcance | Un widget | El menú entero, o una sola pieza |
| Tamaño y forma | `CornerRadius` suelto | Todo, por pieza y en vivo |
| Compartir | No existe | Un string que se copia y se pega |
| Cómo se edita | Buscando la opción del módulo | **Tocando la pieza** |

La regla que hace esto posible:

> **Ningún componente sabe su propio color, su tamaño ni su forma.** Todo lo lee.
> Si un archivo tiene un `Color3` o un número de padding escrito a mano, está mal.

---

## El inspector: un Roblox Studio chiquito

Esta es la pieza central y lo que hace a Pollo distinto.

Un interruptor activa el **modo edición**. A partir de ahí:

1. **Pasás el cursor por el menú y cada pieza se resalta con su nombre y su
   ruta**: `panel › Combat › Killaura › fila › tres puntos`. Nada es "un frame":
   todo tiene identidad y dirección.
2. **Click = seleccionar.** Al lado aparece el panel de propiedades de esa pieza.
3. **Editás en vivo, todo.** Color de fondo, texto, stroke, glow, opacidad — y
   también tamaño: ancho, alto, padding, corner radius, grosor de stroke, tamaño
   de texto. Cualquier pieza, hasta los tres puntos. Lo que tocás se ve en el
   momento, sin aplicar ni guardar.

   La única red de seguridad es el contraste (abajo): se puede cambiar todo, pero
   el sistema no deja que el menú quede ilegible.

   Y como se puede romper, se puede deshacer: **restaurar pieza** y **restaurar
   todo**, siempre a la vista.
4. **Cada propiedad tiene su "restaurar"**, que la devuelve al valor del tema.
5. **Esc o click afuera** deselecciona. Salir del modo edición no guarda nada por
   sí solo: hay un guardar explícito.

Lo que se puede seleccionar llega hasta lo mínimo: el módulo entero, su fondo,
su título, su toggle, **sus tres puntos**, el stroke, el hover. Si se ve, se
puede tocar.

### La jerarquía de valores

Exactamente como las propiedades en Studio:

```
override del elemento   ← lo que tocaste en el inspector
        ↑ si no está
token del tema          ← el tema activo
        ↑ si no está
default del sistema     ← el neutro de fábrica
```

Por eso "restaurar" tiene sentido: no borra, **destapa** la capa de abajo.

### Lo que esto cuesta, dicho de frente

Para que cada pieza sea seleccionable, el menú no se puede construir creando
instancias al vuelo: se construye como un **árbol declarado donde cada nodo tiene
una identidad estable**. Ese es el trabajo real, y es innegociable — pero es el
mismo trabajo que necesita el sistema de temas, así que se paga una vez.

Y es lo que hace que todo lo demás sea trivial: si cada nodo tiene identidad,
tiene dirección; si tiene dirección, se puede sobreescribir; si se puede
sobreescribir, se puede exportar.

---

## Temas compartibles

Un tema es una tabla serializada: los tokens **más** los overrides del inspector.

- **Exportar** → un string con todo.
- **Importar** → pegás, ves un preview, y recién ahí aplicás.
- **Guardar** → queda en la lista con nombre y miniatura.

Esto convierte "customizable" en una comunidad: la gente se pasa temas, no
capturas. Vape no puede y por eso todos los Vapes se parecen.

Regla: un tema **solo lleva apariencia**. Nunca configuración de módulos ni
keybinds — mezclar las dos cosas es cómo un tema importado te desconfigura el
menú.

---

## Efectos y cosméticos, con techo duro

Dos cosas separadas, porque hoy en todos los menús están mezcladas:

**Cosméticos de UI** (el menú): glow en la fila activa, gradiente animado
recorriendo el stroke, scanlines, partículas de fondo, acento reactivo.

**Cosméticos del juego** (el personaje): auras, trails, efectos de hit y de
kill. Son módulos, no tema. Un tema cambia cómo se ve el menú; un aura cambia
cómo te ves vos.

### El techo no se puede pasar

Cada efecto declara su costo y el total tiene un **límite duro**. Cuando llegás
al techo, el siguiente efecto no se activa y te dice cuánto cuesta y cuánto te
falta. No hay modo de pasarse, ni un "avanzado" que lo saltee.

| Efecto | Costo |
|---|---|
| Gradiente animado en stroke | 1 |
| Glow en fila activa | 1 |
| Scanlines | 1 |
| Trail | 1 |
| Partículas de fondo | 2 |
| Aura de personaje | 2 |
| Blur de fondo | 3 |

Es la decisión correcta para un menú que se vende como *performance +
aesthetics*: la estética tiene que tener un presupuesto con número, o la palabra
performance es marketing.

Y tres reglas que sostienen el número:

> **Si el menú está cerrado, no existe.** Cero instancias visibles, cero tweens
> corriendo, cero `RenderStepped`. Lo único vivo es el logo.

> **La estética cara vive en los bordes, no en el relleno.** Un gradiente en el
> panel activo cuesta una instancia; ponerle blur y sombra a cada fila cuesta
> sesenta.

> **Nada corre en loop si no se está mirando.** El gradiente animado se pausa
> cuando el menú se cierra.

---

## Movimiento

- Nada pasa de **400 ms**.
- Nada se anima dos veces por el mismo motivo.
- **Los valores numéricos nunca se interpolan.** Un slider que muestra `13.7`
  camino a `14` es un slider en el que no podés confiar.
- El easing es una preferencia del tema: el que quiere rebote pone
  `Back`/`Elastic`, el que quiere seriedad pone `Cubic`.

---

## El contraste no se negocia

Se puede cambiar todo, y justamente por eso el sistema tiene que impedir que el
menú quede ilegible. El problema clásico: alguien pone un acento oscuro sobre un
fondo oscuro, o texto gris sobre gris, y el menú se ve "roto" aunque funcione.

Regla dura:

> **El usuario elige el matiz. El sistema es dueño de la luminosidad del texto.**

Cada par texto/fondo se mide con la relación de contraste real (WCAG): **4.5:1**
para texto y **3:1** para elementos de interfaz. Si el par no llega, el sistema
**corrige solo la luminosidad del texto** hasta que llega — nunca rechaza, nunca
avisa y sigue, simplemente lo arregla. El matiz que eligió el usuario se
respeta siempre.

Tres consecuencias:

- No existe la combinación que no se lee. No hay que tener cuidado.
- El editor muestra el número de contraste en vivo, para el que quiera saber.
- Un tema importado pasa por lo mismo al entrar, así que nadie te puede mandar
  un tema ilegible.

Esto es lo que separa un menú custom de un menú custom *roto*, y es la función
menos visible y más importante de todas.

---

## Las funciones difíciles

Lo que hace que la gente diga "este menú es otro nivel". Están ordenadas por
cuánto gustan contra cuánto cuestan, y las últimas dos las propongo para
**rechazarlas** — decir que no también es diseño.

### 1. Rueda de armonía
Un solo control de matiz recolorea el menú entero, y cada categoría recibe su
color **derivado** del mismo matiz por rotación en HSV. Combat cálido, Visual
frío, Move intermedio — siempre en familia, nunca tres colores que se pelean.
Costo: bajo. Es lo primero que hay que hacer, porque todo lo demás cuelga de
tener un sistema de color y no una lista de colores.

### 2. Transición de tema en onda
Cambiar de tema no hace un corte: el color viaja por el menú como una ola, fila
por fila, con un desfase de unos milisegundos entre cada una. Dura 400 ms y se
siente carísimo. Costo: medio — necesita que cada color sea interpolable y un
sistema de desfase, pero no toca el rendimiento cuando no estás cambiando de
tema.

### 3. Glow que sigue al cursor
Una luz suave que acompaña al mouse por el menú y se concentra en la pieza que
estás por tocar. En Roblox no hay iluminación real sobre la UI, así que se
falsea con una imagen radial que sigue la posición del puntero. Costo: medio, y
**solo corre con el menú abierto**, que es cuando importa.

### 4. Ripple al click
Click en una fila y el acento se expande desde el punto exacto del click, como
Material Design. Chiquito, rápido (180 ms), y es de esas cosas que no sabés que
extrañás hasta que las usás. Costo: bajo.

### 5. Acento reactivo al juego
El color respira según lo que pasa: más intenso con módulos activos, más tenso
cuando estás bajo de vida, más frío en el menú de un juego y más cálido en otro.
La UI deja de ser un panel pegado encima y pasa a sentirse parte de la partida.
Costo: bajo — es leer estado que ya se lee, y traducirlo a un matiz.

### 6. Acento que respira con el audio
El acento late con la música del juego. Roblox deja leer el volumen de
reproducción de un `Sound`, así que es posible de verdad. Costo: medio, y hay
que suavizarlo bien o queda epiléptico en vez de elegante.

### 7. Miniaturas reales en el selector de temas
El picker no muestra una muestra de color: muestra **el menú en miniatura
renderizado con ese tema**. Se hace con un `ViewportFrame`. Es lo que separa un
selector de temas de una lista de nombres, y es lo primero que la gente
screenshotear. Costo: alto — hay que renderizar el menú dos veces, una en
miniatura, y eso no puede pasar mientras se juega.

### 8. Guardapolvo de contraste
El editor de temas te avisa cuando el texto sobre un fondo no se lee — con la
relación de contraste real, no a ojo. No es llamativo y es exactamente lo que
hace que un menú custom no termine siendo ilegible. Costo: bajo. Es la función
que demuestra oficio.

### Decididas

Entran: **rueda de armonía**, **transición en onda**, **ripple**, **acento
reactivo al juego**, **acento que respira con el audio** y **miniaturas reales
en el selector de temas**. Más el sistema de contraste, que es el que hace que
todo lo anterior no se pueda romper.

Fuera: el glow que sigue al cursor — no entró en la lista y el ripple ya cubre
la respuesta al puntero con una fracción del costo.

### Rechazadas a propósito

**Vidrio esmerilado real.** Necesita blur sobre lo que hay detrás, y el blur es
lo más caro que existe en la UI de Roblox. Se puede falsear con una captura del
`ViewportFrame`, pero eso es renderizar el juego dos veces por frame. Va contra
el techo duro, y el techo duro es la promesa del menú.

**Sacar la paleta de una imagen.** Pegás una imagen y el menú extrae los colores.
Es la función que todos piden y en Roblox no se puede leer un framebuffer sin
capturar el viewport, que otra vez es caro. La salida honesta es que el tema se
genere afuera —una página que toma la imagen y escupe el string del tema— y el
menú solo lo importe. Mismo resultado, cero costo en juego.

---

## Lo práctico

Panel único fijo, dos columnas —lista a la izquierda, detalle a la derecha—, sin
sub-ventanas. Tres aceleradores:

1. **Búsqueda global** (`Ctrl+K`) que filtra módulos *y* opciones; Enter te lleva
   a la opción.
2. **Presets**: `legit`, `semi`, `rage` de fábrica y los tuyos. Es lo que hace
   que "muchas funciones" no signifique "muchas decisiones".
3. **Favoritos automáticos**: las filas que más tocás suben solas.

Los "tricks" son **presets con nombre**, no módulos nuevos.

---

## Mobile

Sin adaptación dedicada. Un **logo** para abrir y cerrar el menú, y el mismo
panel. Si entra, entra; si no, se scrolla. No se diseña un layout paralelo ni se
mantiene una variante — eso duplica el trabajo de cada cambio de UI para
siempre.

El inspector no existe en mobile: editar el menú es cosa de escritorio.

---

## No-negociables heredados

1. **Contrato de módulo explícito.** Cualquiera agrega un módulo sin leer el
   resto del proyecto.
2. **La GUI es reemplazable.** Con el inspector esto importa más: el árbol
   declarado *es* la interfaz entre los módulos y el renderer.
3. **Game support, no forks.** Un juego describe lo que tiene; las cards
   universales lo consumen. Nunca un segundo KillAura por juego.
4. **Cero hooks globales.** Lo que toca una superficie compartida del proceso no
   es aislable por más que viva en su propio archivo.

---

## Lo que NO está acá (a propósito)

Arquitectura de carpetas, el formato del árbol declarado, cómo se serializa un
tema, persistencia, loader, lista de módulos. Eso es el paso 2 y se deriva de
esto. Si algo de la arquitectura choca con la intención escrita acá, gana la
intención.
