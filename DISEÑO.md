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
| Lo que suena (panel de abajo) | Una tarjeta plana (esquinas de 14, degradado con los colores del fondo de pantalla) con una **pantalla hundida** (`paint_well`: ondas, línea de reproducción en el acento, tiempo grande, nombre y avatar redondo) y una fila de **botones redondos en relieve** (`paint_glass`): anterior, detener, pausa (grande, con su puntito) y siguiente | `MusicPill` en `kyora/ui/musicpill.py` |
| Marco y bordes de ventana | Borde en relieve del marco: línea oscura, filete de luz y sombra suave | `paint_raised_edge` en `kyora/ui/relief.py` |

### Excepción, por ahora: tareas, notas y chat, planas (tipo GNOME)

Gustavo pidió (ronda 10) quitarles el skeumorfismo a las tareas y las notas y dejarlas con un estilo moderno inspirado en Linux. Hasta que diga otra cosa, **solo** estas piezas van planas; el resto de Kyora sigue con el relieve de arriba.

| Pieza | Cómo es | En el código |
|---|---|---|
| Checklist de `>task`, tarea abierta, Kanban y notas | Superficies lisas y oscuras, esquinas redondeadas y un borde fino de 1 px. **Sin degradado, filete de luz ni sombra** | `paint_flat`, `paint_flat_well` en `kyora/ui/hub/cards.py`; `stylesheet(t, flat_style=True)` |
| Lo elegido | Algo más claro, sin relieve | `plate_pick` o un velo blanco suave |
| Las tareas, como pasos | Un círculo por tarea unido al siguiente por una línea fina; la elegida, con un fondo suave que abarca la fila entera; letra de 15 px (título en seminegrita) | `TaskChecklist` en `kyora/ui/task_cards.py` |
| El círculo de una tarea | Pendiente: un aro fino; terminada: un disco del acento con ✓ oscuro y el nombre en el acento | `paint_check` en `kyora/ui/task_cards.py` |
| El chat | Burbujas planas (`paint_flat`): las de este dispositivo a la derecha con un toque del acento, las de los otros a la izquierda; hora y estado (reloj = en espera, ✓ = enviado) dentro de cada una; fotos con esquinas redondeadas y archivos como tarjeta; el compositor es un hueco plano (`paint_flat_well`) | `ChatBoard` en `kyora/ui/chat.py` |
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
