# Rúbrica de diseño de Kyora

Esta es la norma que sigue **toda** la interfaz de Kyora. Un cambio de diseño nuevo debe cumplirla; si algo no encaja, se cambia la rúbrica antes que saltársela.

## Estilo: skeumorfismo oscuro inspirado en Linux

Superficies que parecen objetos, con luz que viene de arriba, como los escritorios clásicos de Linux. **Nada de cristal translúcido** en las superficies de contenido. La excepción (ronda 13): el **marco** y lo que sale de él (barra, buscador, paneles, Win+E) llevan de fondo el fondo de pantalla **muy desenfocado y oscurecido** (`kyora/ui/backdrop.py`); el velo oscuro es lo bastante fuerte para que el texto claro se lea siempre.

| Pieza | Cómo es | En el código |
|---|---|---|
| Superficies (paneles, tarjetas) | Opacas y oscuras, con un degradado vertical suave (más clara arriba) | `paint_glass` en `kyora/ui/hub/cards.py` (tokens `plate_top`, `plate_bottom`) |
| Superficies elevadas (tarjetas, botones, píldoras) | Filete de luz de 1 px arriba, línea oscura de 1 px alrededor y una sombra corta debajo | `paint_glass`, `raised()` en `kyora/ui/explorer/style.py` |
| Campos de escritura y carriles | Hundidos: más oscuros, sombra interior arriba y un filete claro abajo | `paint_well`, `well()` |
| Lo elegido | Superficie más clara (`plate_pick`), con el borde o el punto en el acento | |
| Lo activo en la barra | La cápsula en relieve (`paint_raised` en `kyora/ui/bar.py`) | |
| La información (panel de abajo: hora, clima, RAM, batería) | El mismo cuerpo del reproductor: placa oscura en relieve (`paint_glass` con `plate_bottom`, esquinas de 30, sin sombra) | `QuickMain.paintEvent` en `kyora/ui/quickdock.py` |
| Lo que suena (panel de abajo) | Una tarjeta **baja y minimalista** (380 × 156; se encoge hasta 146 de alto si el panel no cabe en la pantalla): cuerpo oscuro en relieve (`paint_glass`, esquinas de 32) y una **pantalla sin marco aparte** con la carátula nítida y algo oscurecida (sin pixelar, rayas ni ruido) y una sombra interior en el borde; arriba, el nombre y el tiempo; abajo, las ondas con la línea de reproducción en el acento. **Solo al pasar el cursor por la pantalla** salen cinco botones sobre la imagen, todos círculos planos (fondo oscuro translúcido, filo fino, sin relieve ni sombra) con el icono a línea: anterior y siguiente a los lados; pausa o seguir, descargar y cerrar en el medio | `MusicPill` en `kyora/ui/musicpill.py` |
| Marco y bordes de ventana | Borde en relieve del marco: línea oscura, filete de luz y sombra suave | `paint_raised_edge` en `kyora/ui/relief.py` |

### Excepción, por ahora: tareas, notas y chat, planas (tipo GNOME)

Gustavo pidió (ronda 10) quitarles el skeumorfismo a las tareas y las notas y dejarlas con un estilo moderno inspirado en Linux. Hasta que diga otra cosa, **solo** estas piezas van planas; el resto de Kyora sigue con el relieve de arriba.

| Pieza | Cómo es | En el código |
|---|---|---|
| Checklist de `>task`, tarea abierta, Kanban y notas | Superficies lisas y oscuras, esquinas redondeadas y un borde fino de 1 px. **Sin degradado, filete de luz ni sombra** | `paint_flat`, `paint_flat_well` en `kyora/ui/hub/cards.py`; `stylesheet(t, flat_style=True)` |
| Lo elegido | Algo más claro, sin relieve | `plate_pick` o un velo blanco suave |
| Las tareas, como pasos | Un círculo por tarea unido al siguiente por una línea fina; la elegida, con un fondo suave que abarca la fila entera; letra de 15 px (título en seminegrita) | `TaskChecklist` en `kyora/ui/task_cards.py` |
| El círculo de una tarea | Pendiente: un aro fino; terminada: un disco del acento con ✓ oscuro y el nombre en el acento | `paint_check` en `kyora/ui/task_cards.py` |
| El chat (estilo de un chat con un agente, como Claude) | Lo mío, en una burbuja gris redondeada a la derecha (`plate_pick`, sin borde); lo de mis otros dispositivos, texto limpio a la izquierda **sin burbuja**, con una lechuza en el acento y el nombre del dispositivo encima (grandes: 22 px y 15 px). La **hora** (y el ✓ de enviado) solo se ve al pasar el cursor, en la línea de arriba: junto al nombre en lo ajeno, a la derecha sobre la burbuja en lo mío; el reloj de «En espera» y los errores se ven siempre. Mis mensajes de texto van en un cuadro de esquinas redondeadas con borde fino. Al pasar el cursor, debajo del mensaje salen sus acciones (copiar, descargar si lleva archivo, borrar con doble pulsación). Fotos con esquinas redondeadas; los documentos (PDF, Word, TXT, MD) como tarjeta con encabezado (hoja, nombre y descarga), título, un extracto del contenido y su tamaño. Cabecera mínima (título y punto de conexión, sin línea). El compositor es un campo grande y redondeado (`paint_flat_well`) con «+» a la izquierda (adjuntar) y un botón redondo con flecha en el acento a la derecha (enviar; atenuado si no hay nada que mandar). Cuerpo a 15 px; hora y avisos a 13 px | `ChatBoard` en `kyora/ui/chat.py`; en el móvil, `mobile/lib/ui/` |
| Las notas | Un editor: barra de formato en píldora arriba, "TÍTULO" en mayúsculas atenuadas, el título, una línea fina y el texto con aire entre párrafos; las citas, con una barrita del acento | `NotesBoard` en `kyora/ui/notes.py` |
| Cambiar de nota | El texto se desvanece con una tapa del color del fondo (pintura, no opacidad sobre widgets) | `_Cover` en `kyora/ui/notes.py` |

En el buscador, el contenido (resultados, tareas, Kanban, notas, árbol, fondos) va **directo sobre el fondo oscuro del panel**, sin recuadro gris detrás; solo lo elegido lleva un velo suave.

Además, tareas y notas **se manejan solo desde el buscador de abajo**: nada abre ventanas aparte ni diálogos. Borrar se confirma pulsando dos veces (la primera avisa ahí mismo). En el Kanban (`Ctrl+K` en `>task`) y en `>notes` el buscador se ensancha.

### Kyra, la app del móvil (2026-11-03, rondas 2 y 3 el 2026-11-04)

La app del móvil se llama **Kyra** (la del escritorio sigue siendo Kyora). Tiene su propio estilo, que no es el skeumorfismo del escritorio: **cristal redondeado sin color** sobre una foto de fondo.

| Pieza | Cómo es | En el código |
|---|---|---|
| Fondo | Sin fondo de pantalla, un gris **muy oscuro**. Con uno (se elige en Configuración), esa imagen **muy suavizada** (se decodifica a 96 px y se estira, sin filtros en vivo) y oscurecida con un velo del 50–65 %, para que el texto claro se lea sea cual sea la imagen | `AppBackdrop` en `mobile/lib/ui/widgets/app_backdrop.dart` |
| Fondo de las secciones | **En Inicio**, la foto se ve **nítida arriba** y el efecto (suavizado + velo) cubre el **70 % de abajo**: vale 0 en la línea del 30 % de la altura y va ganando hasta el 100 % en el borde de abajo. Un velo fino arriba (negro 40 % → 0) asegura que el texto se lea. **En las demás secciones y en las pantallas que se abren encima**, el efecto ocupa el **100 %**: todo borroso, sin la foto nítida, y un poco más oscuro (negro 65 % → 75 %). El paso entre uno y otro es un fundido que dura lo mismo que el cambio de sección; el fondo no se desplaza. Esa capa va debajo de las secciones, así que no le quita el desenfoque al cristal | `_Wallpaper`, `BackdropLayers(full:)` en `app_backdrop.dart`, `AppBackdrop.sharpUntil/sharpStops/sharpAlphas/fullVeil`; el fundido en `SectionHost` |
| Colores | Los **5 colores principales del fondo** (k-means sobre una miniatura; cada uno es la media del núcleo de su grupo, nunca un color que no esté en la imagen). Se enseñan en Configuración (con su código) y con un fondo puesto **mandan** sobre el color de la carátula que suena. Ya no salen en Inicio | `mobile/lib/util/palette.dart`, `WallpaperController`, `buildCoverTheme` |
| Tarjetas | **Esquinas redondeadas**, **sin color de relleno**: solo difuminan lo de detrás (`BackdropFilter`, sigma 18) y llevan un borde fino blanco. Lo único con relleno son los botones redondos pequeños (blanco con icono oscuro) | `GlassCard` en `mobile/lib/ui/widgets/glass_card.dart` |
| Tarjeta de tareas | Abajo del todo, grande, con una **muesca** en la esquina de arriba a la derecha (esquinas de la muesca cóncavas y redondeadas) donde va el clima en su propia tarjeta de cristal. Dentro: «Próxima» y la tarea, «Tareas» enorme con el botón que abre esa sección, lo pendiente en cifra grande y en curso / hechas pequeñas | `NotchedCard`/`NotchShape` en `mobile/lib/ui/widgets/notched_card.dart` |
| Inicio | Primera sección: la fecha («Noviembre 3, 2026»), el saludo según la hora («Buenos días / Buenas tardes / Buenas noches, Señor Marrufo») y los días `L M M J V S D` con el de hoy remarcado; arriba a la derecha el botón de configuración | `HomePage` en `mobile/lib/ui/home_page.dart` |
| Cambio de sección | **Una sola sección a la vez.** Al cambiar, **cada bloque** (título, tarjeta, mazo, lista, barra…) **sale por su borde más cercano** (lo de arriba por arriba, lo de abajo por abajo, lo del medio por los lados) y, con una espera mínima (70 ms), los de la nueva **entran por el suyo**: salida 200 ms, entrada 300 ms, 25 ms entre bloques. Las filas de una lista se mueven juntas. Al terminar, la sección anterior **se destruye**: nada queda en segundo plano (se pierde lo escrito a medias y el desplazamiento). Los bloques solo se desplazan, nunca usan opacidad; el fondo no se mueve (ver «Fondo de las secciones»). «Atrás» vuelve a Inicio | `SectionHost` en `mobile/lib/ui/section_host.dart`; `SectionMotion`, `FlyIn`, `FlyInBar` en `mobile/lib/ui/widgets/section_motion.dart` |
| Menú circular | Se navega **manteniendo el dedo** en cualquier punto (lo que dura una pulsación larga del sistema): todo lo de debajo queda **borroso y más oscuro** y se despliegan las opciones en un **círculo completo alrededor del dedo**, siempre en el **mismo orden** para poder memorizarlo: la primera arriba y las demás en el sentido del reloj (Inicio, Chat solo admin, Música, Tareas, Recordatorios y Configuración, que abre la hoja). Cerca de un borde, el círculo entero se corre lo justo para que todo se vea, sin girar. Se **desliza hacia una** (se elige por ángulo; su nombre sale en el centro) y se **suelta** para ir. Soltar en el centro cancela. La sección actual va marcada. Los círculos crecen (escala), no se funden. Una pulsación larga de dentro de una pantalla (un mensaje del chat) gana sobre el menú. Inicio lleva una pista «Mantén el dedo para navegar» hasta la primera vez | `RadialGeometry`, `RadialMenuView` en `mobile/lib/ui/widgets/radial_menu.dart`; `NavHintStore` |
| Música: ruleta | Sin título arriba. En reposo, **un solo álbum** en grande (tarjeta cuadrada de esquinas redondeadas con el nombre debajo); los demás esperan **escondidos detrás**. Al tirar a un lado o al otro el anillo se abre en perspectiva y gira **sin tope**; al soltar sigue por la inercia, se detiene en un álbum y los demás vuelven detrás suavemente (420 ms). Solo transformaciones y un velo oscuro en los de atrás, nunca opacidad. Tocar el de enfrente lo abre. Debajo, las favoritas | `AlbumDeck`, `DeckCard`, `DeckController` en `mobile/lib/ui/widgets/album_deck.dart` |
| Música: carátula | **Solo se define por álbum** (desde dentro del álbum, botón de la imagen); todas las canciones del álbum enseñan esa: la elegida o, si no hay, la incrustada de la primera que la traiga. Ya no hay imagen por canción | `LocalMusicController.albumArt/albumIdOf/artOf` |
| Música: vista del álbum | Fondo: la portada del álbum a pantalla completa y muy borrosa (decodificada a 48 px). **En el centro de la pantalla, un vinilo realista** con los colores de la portada: plástico jaspeado, surcos y bandas entre pistas, y etiqueta con la portada, que giran; encima, reflejos de luz que **no giran**. Debajo, sin ningún fondo, el nombre y el artista. Sin panel ni mini-barra: el disco es el reproductor. **Un toque** reproduce o pausa, sin esperar; suena a 33⅓ rpm con inercia al arrancar y frenar. **Girarlo con el dedo** adelanta o retrocede (1 vuelta = 30 s) y salta al soltar. **Línea blanca** por el contorno con el avance de la canción, desde arriba y en el sentido del reloj. **Círculo central** de línea blanca: los bajos lo hinchan y los golpes alteran la línea con la onda real; sin poder leer el sonido, late. Fuera del disco, deslizar pasa de álbum sin parar la música. Un álbum solo enseña sus canciones: las subcarpetas no se muestran | `AlbumView` en `mobile/lib/ui/album_view.dart`; `DiscPlayer`, `VinylDisc`, `SoundCircle` en `mobile/lib/ui/widgets/`; `marblePixels`, `SoundShape` en `mobile/lib/util/` |
| Música: lista de canciones | **Doble toque en cualquier parte menos en el disco** la abre; otro doble toque o «atrás» la cierran. El fondo se oscurece casi a negro, el disco encoge hasta la fila del centro y las demás llegan por la derecha. Discos pequeños con la portada a lo largo de una **curva** abombada a la izquierda, difuminados arriba y abajo, con imán a la fila del centro. La fila del centro lleva una **píldora** con nombre, artista, corazón y botón de reproducir o pausar (en enviadas, también «Recibido» y ⋯). Tocar otra fila la trae al centro; mantener pulsada empieza a marcar. Sin `BackdropFilter`, porque va bajo el difuminado | `SongArcList` en `mobile/lib/ui/widgets/song_arc_list.dart` |
| Configuración | Una **hoja que sube desde el borde de abajo hasta el 70 %** de la pantalla (se abre con el botón de Inicio), en gris oscuro semitransparente que difumina lo de detrás; arriba se sigue viendo la pantalla. Sin velo, con tirador; se cierra arrastrando, tocando fuera o con «atrás». Dentro, grupos (Apariencia, Clima, Música, Cuenta) con su título en el acento, una línea que explica y filas con filetes finos (sin tarjetas de cristal anidadas) | `showSettingsSheet`, `SettingsSheet` en `mobile/lib/ui/settings_sheet.dart` |
| Cristal que no se quita | Una tarjeta de cristal solo difumina lo pintado dentro de su capa: **nada con opacidad por encima** (`Opacity`, `FadeTransition`, `AnimatedOpacity`, `ShaderMask`) ni el efecto de estiramiento de los extremos. Las pantallas empujadas suben desde abajo con su propio fondo (`LayerPageTransitions`), las barras se deslizan sin fundirse y el desplazamiento no estira (`KyraScrollBehavior`). Un `BackdropGroup` por pantalla comparte la captura entre sus tarjetas. Lo vigila `test/blur_guard_test.dart` | `app_backdrop.dart`, `theme.dart` |

### La luz de la ventana activa

Se dibuja **una sola vez** al pasar a una ventana: nace como un trazo corto que gira y se alarga hasta rodearla entera (~0,9 s) y se queda quieta. Nada gira sin parar: una animación continua cuesta trabajo a Kyora todo el rato.

## Color

- **Siempre del fondo de pantalla, al 100 %** (`kyora/ui/accent.py`): el acento es el color que más ocupa la imagen; el segundo, el siguiente. Si el fondo es gris, el acento es gris claro. Nunca se inventa un color que no está.
- **El acento** solo para lo activo, lo elegido, lo que tiene el foco y lo que avisa. Todo el contenido de la barra va en el acento.
- **Rojo** (`warn`) solo para avisar: vencido, uso alto, batería baja.
- **Fondos siempre oscuros**; **texto claro**, con contraste de 7:1 como mínimo sobre el marco.

## Texto

- Letra mínima de **15 px** (miopía de Gustavo). La barra es la excepción: **13 px**, y el buscador (lista, tareas, árbol y campo), a petición suya: **14 px**.
- Títulos en negrita y grandes; lo secundario, atenuado (`dim`), nunca más pequeño de lo permitido.

## Contenido

- **Práctico y sin saturar**: pocos botones a la vista (el principal, uno). Lo demás, con el teclado, y los atajos se enseñan en la propia pantalla o en `>commands`.
- **Sin cajas donde no hacen falta**: en un detalle, el texto es el contenido (como la tarea abierta en `>task`).
- **Sin ventanas de más ni diálogos de confirmación**: lo destructivo se confirma pulsando dos veces, con el aviso en la misma pieza.
- **Animaciones cortas y suaves** (120–260 ms, curvas OutCubic/OutQuint) y sobre imágenes, nunca efectos de opacidad sobre árboles de widgets.
- **Todo en español.**
