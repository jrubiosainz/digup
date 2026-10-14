# Icono de Biblo: «La lupa y la cinta»

La cinta violeta de un marcapáginas cuelga del borde superior, junto a una columna de resultados. Las filas crecen
hacia la ficha abierta del centro, como cuando bajas por una columna del panel y la lupa abre en grande el resultado en
el que estás. Fondo índigo profundo con una luz violeta arriba a la izquierda y un poco de orquídea abajo a la derecha
(el fondo de la app, en pequeño); el único color propio es el violeta, en la cinta y en el porqué de la ficha.

- `appicon.svg`: el icono de la app (1024 × 1024, retícula de iconos de macOS). `../AppIcon.icns` lo guarda de 64 px en
  adelante.
- `appicon-small.svg`: lo mismo sin lo que a 16 y 32 px se vuelve ruido (las filas finas, el paisaje de la foto, los
  metadatos) y con la cinta más ancha. `../AppIcon.icns` lo guarda a 16 y 32 px.
- `AppIcon.icon`: el mismo diseño por capas para macOS 26 y posteriores (documento de Icon Composer: degradado índigo
  de fondo, sin las luces radiales, la columna y la cinta). `build.sh` lo compila en `Assets.car` con `actool` y `CFBundleIconName`, en
  `Info.plist`, apunta a él. Sin él, macOS 26 dibuja el `.icns` encogido dentro de un cuadrado gris. Los macOS
  anteriores usan el `.icns` (`CFBundleIconFile`; sin probar).
- `menubar.svg`: la marca de la barra de menús, la cinta colgando del borde de una caja. La app la dibuja en código con
  la misma geometría (`StatusIcon` en `Sources/DigUpApp/StatusMenu.swift`), con el anillo de indexado en lugar de la
  caja.

## Regenerar `AppIcon.icns`

Tras editar `appicon.svg` o `appicon-small.svg`, renderiza ambos a un iconset con un renderizador que dibuje los
filtros de desenfoque de SVG (un navegador; el de macOS se salta las sombras suaves). Por ejemplo, con Edge o Chrome
sin interfaz:

```sh
"/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" --headless=new --hide-scrollbars \
  --user-data-dir="$(mktemp -d)" --default-background-color=00000000 --window-size=1024,1024 \
  --screenshot="$PWD/appicon-1024.png" "file://$PWD/appicon.svg"
```

Después, con `sips -z <px> <px>`: `icon_16x16.png`, `icon_16x16@2x.png` e `icon_32x32.png` salen de
`appicon-small.svg` (16, 32 y 32 px); los otros siete archivos, de 64 a 1024 px, de `appicon.svg`. Por último,
`iconutil -c icns AppIcon.iconset -o ../AppIcon.icns`.

Las capas de `AppIcon.icon/Assets` no llevan filtros ni `clipPath`: Icon Composer pone sus propias sombras y brillos.
Usan `scale(1.242718) translate(-100 -100)` para llevar las coordenadas del cuerpo del icono (100–924) al lienzo
completo de 1024.

## Colores

- Fondo: #3A24A0 → #140C3E. Encima, en los SVG: luz radial #8B6CFF al 50 % arriba a la izquierda y #C86BFA al 28 %
  abajo a la derecha.
- Cinta: #8E74FF → #DCD3FF (en el centro) → #6040E8. En `appicon-small.svg`, #9A82FF → #DCD3FF → #6A4BF2.
- Ficha: #F5F3FD. Foto #6C6FC4 → #33306E (#4B4A8E lisa en el pequeño), sol #F6F1FF, montañas #8F8FD8 y #B9B6EC.
- Texto de la ficha: título #231D45, porqué #6A4BF2, metadatos #CEC8E6.
- Filas: blanco al 5–8 %, con miniatura y texto al 26–42 %.
