# Biblo · diseño del panel

Sistema de diseño de Biblo, centrado en el panel de búsqueda que abre ⇧⌘Espacio. La ventana grande comparte su color,
su fondo y su botón de buscar, y ya está en español. Ajustes y la bienvenida llevan los mismos violetas, pero sus textos
siguen en inglés. El código de todo lo que se describe aquí está en `Sources/DigUpApp/SearchPanelView.swift` (armazón y
contrato), `PanelColumns.swift` (columnas, lupa y cinta) y `Components.swift` (`Brand`, `Backdrop`, `SearchBadge`,
`Motion`).

## Contrato

- **Tesis:** encontrar es reconocer. Biblo no da una lista. Abre cada formato por donde es más probable que esté lo
  que buscas.
- **Mundo propio:** Biblos, la ciudad fenicia que dio nombre al libro, y tu Mac como biblioteca. Los violetas de
  Microsoft Foundry: luces suaves de violeta, pervinca y orquídea detrás del contenido, y una cinta violeta, como la de
  un libro, que marca dónde estás. Nada de DigUp a la vista: ni su lema ni su lupa a la izquierda.
- **Historia:** escribes como lo recuerdas. Cada formato abre su estante y la cinta cae por cada columna, más ancha
  donde más acierta. Al bajar, cada hallazgo sale del estante y se abre grande.
- **Primera vista:** la barra; debajo, una columna por formato en orden fijo. La columna activa es ancha y muestra su
  mejor hallazgo abierto, con su % de acierto.
- **Forma:** columnas como estantes, una lupa vertical, una cinta que adelgaza con la probabilidad y, al final de la
  barra, un disco violeta para buscar. SF Pro con cifras tabulares.
- **Prohibido:** neón, texto en degradado, fondos que se mueven, fondos crema con serifa y rótulos monoespaciados en
  mayúsculas.

## El panel

```
╭──────────────────────────────────────────────────────────────────────────────────────╮
│ ▌  flores                                                                        (⌕) │  cinta, barra y botón de buscar (68 pt)
├──────────────────────────────────────────────────────────────────────────────────────┤
│ ╭──╮ ╭──╮ ╭ Imágenes 7 ──────────────────────────────╮ ╭ Vídeo 1 ──────────╮ ╭──╮    │
│ │S │ │S │ │┃ ▫ Flowers-Yellow Daisy.jpg        41 % │ │┃ ┌──────────────┐ │ │S │    │
│ │i │ │i │ │┃ ▫ Flowers-Poppy.jpg               37 % │ │┃ │  fotograma   │ │ │i │    │
│ │n │ │n │ │┃ ▢ Flowers-Flower.jpg              37 % │ │┃ └──────────────┘ │ │n │    │
│ │  │ │  │ │█ ┌──────────────┐ Flowers-Lotus  35 %  │ │╹ flores de prim…  │ │  │    │
│ │d │ │c │ │█ │   imagen     │ Por lo que se ve    │ │  82 %             │ │a │    │
│ │o │ │a │ │█ └──────────────┘ ~/…/img · 768 × 768  │ │                   │ │u │    │
│ │c │ │p │ │┃ ▢ Flowers-Dahlia.jpg              34 % │ │                   │ │d │    │
│ ╰──╯ ╰──╯ ╰─────────────────────────────────────────╯ ╰───────────────────╯ ╰──╯    │
├──────────────────────────────────────────────────────────────────────────────────────┤
│ 1 hallazgo en 1 formato · 7 con menos acierto          ↑↓ recorrer  ⇥ otro formato … │
╰──────────────────────────────────────────────────────────────────────────────────────╯
```

- **Tamaño:** 1160 × 620 pt; solo la barra, 68 pt. Esquinas de 24 pt. Cristal del sistema bajo
  `windowBackgroundColor` al 75 %, porque el cristal solo se transparenta demasiado sobre fondos cargados, y encima el
  fondo de Biblo (`Backdrop`, en «Color»).
- **Barra:** la cinta a la izquierda, el texto en SF Pro de 24 pt y, a la derecha, el botón de buscar (`SearchBadge`):
  un disco violeta de 34 pt con la lupa en blanco, que cambia a `</>` mientras se busca código. Pulsarlo pone el cursor
  en el campo. El texto de ejemplo pide una descripción, no un nombre de archivo:
  `Descríbelo como lo recuerdes: «receta de paella», «pingüino en un vídeo»…`.
- **Ventana grande:** la misma búsqueda en una cápsula de 38 pt con el disco de 28 pt al final y un anillo violeta
  mientras tiene el cursor.
- **Columnas:** Documentos · Capturas · Imágenes · Vídeo · Audio, siempre en ese orden para que la vista aprenda dónde
  está cada cosa. Una búsqueda `code:` muestra una sola columna, Código. Margen de 14 pt y separación de 10 pt.
- **Anchos:**
  - Un formato sin nada es un lomo de 44 pt con su nombre en vertical, de abajo arriba como en los libros españoles.
  - La columna activa ocupa cerca del 48 % del espacio, con un mínimo de 380 pt.
  - Las demás tienen 300 pt como máximo; lo que sobra va a la activa.
  - Al abrir, la activa es la del mejor hallazgo.
- **Pie:** el recuento («N hallazgos en M formatos · K con menos acierto»; M cuenta solo los formatos con hallazgos
  claros) y las teclas.

## La lupa

Al bajar por una columna, el resultado seleccionado se abre y sus vecinos crecen hacia él.

| Estado | Cuándo | Qué muestra |
|---|---|---|
| Tarjeta | El seleccionado de la columna activa | Vista grande de lo que coincidió (la imagen, la página, el fotograma o el tramo de sonido): 58 % del ancho × 240 pt, o encima del texto si la columna mide menos de 560 pt. Detrás, la misma imagen desenfocada rellena el hueco con sus colores. Al lado van el nombre, el acierto en grande, el porqué, el extracto con tus palabras marcadas, la carpeta y los datos. |
| Vecina | Justo encima o debajo | Miniatura de 38 pt, nombre, página o momento, carpeta y % |
| Compacta | El resto | Miniatura de 26 pt, nombre y % (si la columna mide 200 pt o más) |
| Asomada | El seleccionado de las otras columnas | Su imagen (fotograma, página o forma de onda para el audio), nombre y % |

- **Resultados débiles:** los que quedan por debajo de la mitad del mejor se dibujan al 55 %, salvo la tarjeta.
- **Desplazamiento:** el seleccionado se queda al 22 % de la altura para que se vea lo que viene después.
- **Movimiento:** muelle de respuesta 0,32 y amortiguación 0,84, sin rebote. Con «Reducir movimiento», un fundido de
  0,12 s.
- **Entrada:** la primera vez, los estantes entran uno tras otro con 40 ms de diferencia.

## La cinta

La cinta violeta solo marca dos cosas: qué ha encontrado Biblo y con cuánta seguridad.

- **Marca:** una cinta violeta de 14 pt que cuelga del borde superior, a la izquierda de la barra.
  - Sin nada que buscar es corta (30 pt).
  - Se balancea mientras se prepara la búsqueda por significado.
  - Sobre resultados cuelga larga (46 pt) y apunta hacia ellos.
- **Cinta de cada columna:** recorre el margen izquierdo de 16 pt.
  - **Ancho:** 2 + 8 × acierto, de 2 pt (poco probable) a 10 pt (seguro). Se estrecha hasta desaparecer tras el
    último resultado.
  - **Brillo:** en la columna activa es pleno junto al seleccionado y va del 35 al 100 % según el acierto en el resto.
    En las otras columnas va del 25 al 60 %.
- **Violeta de texto:** el acierto y el porqué usan `ink`. La selección y los controles también son violetas, no del
  acento del sistema: anillos y marcas en `ink`, chips y controles en `accent`, para que Biblo se vea igual en cualquier
  Mac.

## Icono

«La lupa y la cinta»: la cinta violeta cuelga del borde superior junto a una columna de resultados, con filas que
crecen hacia la ficha abierta del centro, sobre índigo profundo con una luz violeta arriba a la izquierda y algo de
orquídea abajo a la derecha: el fondo de la app, en pequeño. La barra de menús usa la misma cinta dentro de una
caja (`StatusIcon`). Fuentes, colores y cómo regenerarlo: `Resources/AppIcon/README.md`.

## Color

| Token | Valor | Uso |
|---|---|---|
| `violet` | #7B5CFF | Luz principal del fondo; arriba de la cinta y del disco de buscar |
| `indigo` | #4A2FD8 | Abajo de la cinta y del disco de buscar |
| `iris` (`accent`) | #6A4BF2 | Controles, botón por defecto y chip seleccionado (blanco encima: 5,4:1) |
| `periwinkle` | #8E8FF4 | Luz del fondo, arriba a la derecha |
| `orchid` | #C86BFA | Luz del fondo, abajo a la derecha |
| `ink` | #5536D6 en claro, #B7A8FF en oscuro | % de acierto, porqué, iconos activos, anillos de selección y del campo (≥ 4,5:1 sobre el panel y las ventanas) |

- **Degradados:** la cinta va de `violet` a `indigo` en claro y de #C2B5FF a `violet` en oscuro. El disco de buscar y
  los iconos de la bienvenida (`button`, `tile`) van de `violet` a `indigo` en diagonal, para que el blanco encima se
  lea entero.
- **Fondo (`Backdrop`):** detrás del panel, la ventana grande y la bienvenida, sobre el fondo propio de cada ventana.
  - Una luz violeta desde la esquina superior izquierda, pervinca arriba a la derecha y orquídea abajo a la derecha.
  - En claro, además, un velo blanco, un degradado muy tenue de violeta a orquídea de esquina a esquina y algo de iris
    abajo a la izquierda, para que ninguna zona quede gris y plana.
  - Quieto y sin desenfoques propios: el texto siempre cae sobre un tono casi liso.
- **Ajustes y la hoja de carpetas:** el acento violeta sobre el fondo del sistema.

El texto y los neutros son los del sistema, en modo claro y oscuro.

## Texto

- Español, con mayúscula solo al principio de la frase.
- Las invitaciones a buscar hablan de recordar: «¿Qué quieres encontrar?» en la ventana grande, «Descríbelo como lo
  recuerdes…» en la barra y, en la bienvenida (aún en inglés), «Search everything the way you remember it.».
- El porqué de cada resultado dice qué coincidió: «Por lo que se ve», «Por el fotograma de 0:12», «Por lo que se oye
  en 1:30», «Por la página 4», «Tiene tus palabras», «Por su nombre».
- Los vacíos dicen qué probar: «Nada parecido en tus carpetas · Prueba con lo que se veía o se oía, o con palabras que
  recuerdes».

## Teclado

↓↑ recorren la columna. ←→, ⇥ y ⇧⇥ cambian de formato, y ⌘1…⌘5 van a un formato por su sitio. ↩ abre en el punto
(la página, el segundo). Espacio abre la vista rápida, ⌘↩ lo muestra en Finder, ⌘C copia el archivo, ⌘O lleva la
búsqueda a la ventana grande y Esc cierra.

## Accesibilidad

- **Resultados:** cada uno es un solo elemento («Imágenes, Flowers-Lotus.jpg, Por lo que se ve, acierto 35 %») y la
  tarjeta lleva el rasgo de seleccionado.
- **Columnas:** son contenedores con el nombre del formato. Los lomos dicen «Sin audio», «Sin documentos».
- **Botón de buscar:** se anuncia como «Buscar», o «Buscando en tu código». El fondo no se anuncia.
- **Contraste y movimiento:** se respeta «Reducir movimiento». `ink` cumple 4,5:1 en claro y oscuro, y el blanco sobre
  el violeta de acento, 5,4:1.

## Profundidad del panel

Las columnas necesitan algo más que la lista corta de DigUp.

- **Problema:** el umbral de significado (z ≥ 2) dejaba «flores» con 2 resultados aunque hay 9 flores en la carpeta
  de prueba.
- **Solución:** el panel busca con `depth 0.5`. Si algo supera el umbral, este baja hasta el mayor de dos valores:
  1,5, o el mejor z menos 1. Si nada lo supera, sigue sin mostrar nada.
- **Efecto en la carpeta sintética:**
  - «flores» pasa de 2 a 8 resultados y «deportes» de 1 a 6.
  - «xkqz wbrt» sigue vacía.
- **Eval sintético:** idéntico con 0 y con 0,5 (R@1 0,78 · R@5 0,84 · R@10 0,84 · MRR 0,81).
- **Ventana grande y CLI:** siguen con 0. Para probar otros valores: `digup search "…" --depth 0.5`.

## Cómo comprobarlo

La app pinta el panel en un PNG sin tocar la pantalla. Ejemplo:

```sh
ROOTS=~/BibloTestbed/synthetic scripts/dev-run.sh -debugWaitForIndex YES -debugOffscreen YES \
  -debugQuery "flores" -debugSelect "Lotus" -debugSnapshot /tmp/biblo.png -debugQuit YES
```

Fuera de pantalla el panel no recibe teclas. Por eso `-debugSelect` coloca la lupa en el resultado cuyo nombre contiene
el texto dado. `-forceAppearance light` o `dark` fija el modo, para ver los dos fondos. Dos cosas que solo pasan en la
captura: el botón por defecto sale gris, porque una ventana fuera de pantalla nunca está activa, y la cápsula de la
ventana grande puede llevar una raya vertical en cada extremo. Los flags están documentados al principio de
`DebugHooks.swift`.
