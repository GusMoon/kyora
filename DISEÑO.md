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
| Lo que suena (panel de abajo) | Un reproductor de bolsillo (referencia de Gustavo): cuerpo oscuro en relieve (`paint_glass`, esquinas de 30), una **pantalla hundida** (`paint_well`) con la carátula vuelta pixeles, rayas de monitor y motas, teñida con los colores del fondo de pantalla (nombre arriba, tiempo y ondas con la línea de reproducción en el acento abajo) y **tres teclas iguales en relieve** (`paint_glass`) con el icono a línea: pausa o seguir, anterior y siguiente. Al pasar el cursor por la tarjeta sale una **✕** arriba a la derecha que detiene y cierra | `MusicPill` en `kyora/ui/musicpill.py` |
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
