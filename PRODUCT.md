# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Un único usuario: un profesional de Microsoft que trabaja en su Mac (Apple Silicon) y acumula en él documentos, imágenes, audio y vídeo. Su trabajo con esta app: recuperar un archivo cuando recuerda lo que contiene (lo que se veía, lo que se dijo, de qué trataba) pero no cómo se llama ni dónde lo guardó, y abrirlo justo donde está eso que recuerda. Lo hace desde cualquier app, sin dejar lo que estaba haciendo.

## Product Purpose

Buscador de escritorio para el contenido del Mac. Indexa las carpetas que elige el usuario con EmbeddingGemma 2, el modelo de embeddings multimodal de Google DeepMind (octubre de 2026), y con un atajo de teclado abre un buscador donde se describe con palabras propias lo que se busca, sea un documento, una imagen, un audio o un vídeo.

Éxito: el usuario escribe lo que recuerda, el archivo correcto aparece entre los primeros resultados mientras escribe y, al abrirlo, cae en la página, la imagen o el segundo que buscaba. Cuando no se usa, la app no se nota en el Mac.

## Positioning

No es Spotlight ni un lanzador de apps. Spotlight encuentra archivos por su nombre, su texto y sus metadatos; Biblo los encuentra por lo que muestran, dicen o suenan, porque EmbeddingGemma 2 pone texto, imágenes, audio y vídeo en un único espacio de significado: una descripción encuentra una foto, el minuto de una grabación o la página de un PDF, también entre idiomas. Lo combina con las palabras exactas (un número de factura, un nombre, un código de error) y abre el resultado en el punto donde está. Todo ocurre en el Mac.

## Operating Context

- App nativa de macOS en Swift: AppKit para el panel flotante y la barra de menús, SwiftUI para las vistas. Apple Silicon y macOS 14 o posterior; el Mac del usuario tiene macOS 26, un M5 y 32 GB. El valor `web` de Platform es solo el comodín del esquema de impeccable, que no tiene valor para macOS: la app no es web ni usa WebView ni Electron.
- Base técnica: el fork del usuario de DigUp (`jrubiosainz/DigUp`, licencia MIT, © 2026 Abdur Rahim), que ya resuelve el motor: lectores de Apple (ImageIO, PDFKit, AVFoundation y Vision para el texto de las capturas), EmbeddingGemma 2 sobre llama.cpp con Metal en un proceso auxiliar que se cierra al terminar, y un único archivo SQLite con un vector por imagen, página, pasaje, fotograma y 30 s de sonido, más un índice de palabras (FTS5).
- Rendimiento como requisito del usuario: la arquitectura no puede lastrar el Mac. Por eso Swift nativo y no Electron + React. Medido en su Mac con un panel mínimo: SwiftUI en un NSPanel, 17 MB en 1 proceso; Swift con WKWebView, 51 MB en 4; Electron, 102 MB en 4. La inferencia (llama.cpp con Metal) es la misma en cualquier opción; cambian el coste fijo del armazón y el acceso directo a Vision, PDFKit, AVFoundation y Quick Look.
- Modelo: la versión de 8 bits de ggml-org, descargada una vez (865 MB: parte de texto 310 MB, codificadores de imagen y audio 555 MB). Para buscar solo se carga la parte de texto (unos 250 MB), en un proceso que se cierra tras un rato sin uso.
- Uso: desde cualquier app, un atajo global abre el panel de búsqueda; se escribe y los resultados salen en una columna por formato, cada una ordenada por acierto, que se recorre con el teclado; luego se abre o se previsualiza el elegido. Una ventana más grande muestra la misma búsqueda con rejilla de imágenes y filtros. La barra de menús enseña el progreso del indexado, permite pausarlo y abre Ajustes. Biblo se instala en Aplicaciones y tiene icono fijo en el Dock, que abre la ventana grande.
- Primera ejecución: el modelo se descarga mientras el usuario elige carpetas (enteras o solo algunas subcarpetas), con una estimación de lo que tardará el primer pase en cada una.

## Capabilities and Constraints

- Solo indexa las carpetas que elige el usuario. Nunca lee claves, certificados, archivos de contraseñas, carpetas ocultas como `~/.ssh`, paquetes de apps ni cachés, y se salta las carpetas que parecen datasets.
- No provoca descargas: se salta los archivos que solo están en la nube (iCloud con «Optimizar almacenamiento» y proveedores de archivos como OneDrive), como ya hace el motor.
- Solo lectura: nunca cambia, mueve ni sube archivos. Nada de lo indexado sale del Mac; la app solo sale a internet para descargar el modelo y, si se mantienen, para buscar actualizaciones.
- Formatos que ya lee el motor:
  - imágenes y capturas (HEIC, JPEG, PNG, RAW, WebP y más), por lo que muestran; las capturas, también por su texto;
  - PDF página a página, escaneados incluidos, hasta 5.000 páginas por archivo;
  - documentos: txt, md, rtf, doc, docx, odt y html;
  - audio de cualquier duración, en ventanas de 30 s solapadas;
  - vídeo de cualquier duración: un fotograma cada pocos segundos, uno por plano, más la pista de sonido.
- Búsqueda híbrida: significado y palabras exactas a la vez; las coincidencias literales suben. Busca entre idiomas (el modelo conoce más de 100).
- Abrir en el punto: vídeo y audio en el segundo, PDF en la página con las palabras buscadas; Quick Look en la página o el momento; mostrar en Finder; copiar el archivo.
- Teclado: ⇧⌘Espacio abre el panel (configurable), ↓↑ recorren la columna de un formato, ←→, ⇥ y ⌘1…⌘5 cambian de formato, ↩ abre, Espacio hace Quick Look, ⌘↩ muestra en Finder, ⌘C copia y ⌘O pasa a la ventana grande.
- Indexado: el primer pase pesa una sola vez (minutos para cientos de archivos, hasta una hora para una carpeta de Descargas grande); después, un archivo nuevo se puede buscar en uno o dos segundos. Se pausa en modo de bajo consumo y puede esperar al cargador.
- Al abrir el panel en frío, el codificador de consultas tarda unos 0,35 s; hasta entonces la búsqueda va solo por palabras exactas.
- Búsqueda de código: el motor la incluye, desactivada por defecto y con índice propio (prefijo `code:`).
- Licencias: conservar el aviso MIT de DigUp (Abdur Rahim) y los créditos de EmbeddingGemma 2 (Apache 2.0) y de llama.cpp (MIT).
- Decisiones abiertas:
  - Atajo: ⇧⌘Espacio, el de DigUp, u otro.
  - Office: el motor no lee pptx ni xlsx (docx sí). Propuesta: añadirlos.
  - Palabras dentro de audio y vídeo: hoy se encuentran por significado, no por la palabra exacta. Propuesta: transcripción local opcional para buscar literalmente lo dicho.
  - Comando de terminal: el motor trae la CLI `digup` (indexar, buscar, evals); falta decidir si Biblo la ofrece como `biblo`.
  - Búsqueda de código: mantenerla, ocultarla o quitarla.
  - Actualizaciones: apagadas. `Resources/Info.plist` ya no lleva el `SUFeedURL` de DigUp y sin él Sparkle no arranca ni ofrece buscar actualizaciones. Antes de distribuir hay que darle un feed y una clave EdDSA propios (`SPARKLE_FEED` y `SPARKLE_KEY` al compilar, o en `Info.plist`). `scripts/release.sh` y `appcast.py` ya generan Biblo y apuntan a las releases de este fork.
  - Idioma de la interfaz: el panel y la ventana grande ya están en español. Ajustes y la bienvenida siguen en inglés.
  - Distribución: solo uso personal o también para compañeros.

## Brand Commitments

- Nombre: Biblo, elegido por el usuario en lugar del nombre de trabajo, Zahorí. Viene de Biblos, la ciudad fenicia que dio nombre al libro: tu Mac como biblioteca. Sustituye a DigUp en la app, el icono, la barra de menús y los textos.
- Mundo visual: los violetas de Microsoft Foundry, con luces suaves de violeta, pervinca y orquídea detrás del contenido, y una cinta violeta, como la de un libro, que marca qué ha encontrado y con cuánta seguridad. Para buscar, un disco violeta con la lupa a la derecha de la barra. El panel muestra una columna por formato ordenada por acierto, con una lupa que abre en grande el resultado en el que estás. El icono repite la idea: la cinta violeta junto a una columna con la ficha abierta, sobre índigo. Detalle en `DESIGN.md` y `Resources/AppIcon/README.md`.
- Identidad visual propia: de Aforo solo toma la forma de app de escritorio personal, no su aspecto. La interfaz actual de DigUp es la base funcional, no la estética: Biblo no debe parecer DigUp, ni por su lema («Describe it. Dig it up.») ni por su lupa a la izquierda del campo.

## Evidence on Hand

- Código del motor en el fork: `Sources/DigUpKit` (rastreo, lectores, índice y búsqueda), `Sources/LlamaRuntime` (EmbeddingGemma 2 sobre llama.cpp) y `Sources/DigUpApp` (panel, ventana grande, barra de menús y bienvenida), con pruebas en `Tests/DigUpKitTests` y `Tests/LlamaRuntimeTests`.
- `evals/` (`synthetic.json`, `multilingual.json`, `code.json`): las consultas con las que se mide el orden de los resultados, en inglés, bengalí y árabe; ninguna en español. `scripts/make-testbed.sh` genera una carpeta de archivos de prueba (necesita ffmpeg).
- `docs/demo.gif` y `docs/logo.png` son de DigUp, no de Biblo.
- Mediciones de memoria de un panel mínimo en el Mac del usuario: SwiftUI 17 MB, WKWebView 51 MB, Electron 102 MB; Raycast, en uso, 53 MB.
- No hay índice de los archivos reales del usuario. Las capturas del panel y las métricas de Biblo salen solo de la carpeta sintética `~/BibloTestbed` (81 vectores): eval sintético R@1 0,78 · R@5 0,84 · R@10 0,84 · MRR 0,81, y unos 0,33 s por consulta con el codificador ya cargado. Bocetos y demos usan contenido sintético rotulado como tal; no se inventan resultados, tiempos ni porcentajes de acierto.

## Product Principles

1. Se busca por lo que hay dentro: lo que se ve, se oye o se dice cuenta tanto como el nombre del archivo.
2. Encontrar es llegar: un resultado vale cuando abre la página, la imagen o el segundo exactos.
3. Lo elige el usuario y no sale del Mac: carpetas elegidas, índice local, solo lectura y ninguna descarga de la nube.
4. Al instante y sin peso: se abre con un atajo desde cualquier app, responde mientras se escribe y, cuando no se usa, no se nota en memoria ni en batería.
5. Significado y literalidad juntos: la descripción con palabras propias y el dato escrito tal cual (un número, un nombre) se buscan a la vez.
