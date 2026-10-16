# rootDirectory: vista raíz del módulo directory

Navegación de carpetas sobre el reactor y contenido de la carpeta elegida. Código:
[rootDirectory.py](../../core/matrix/motherboard/modules/directory/rootDirectory.py)
(modelo de carpetas y `FolderDial`),
[contentPanel.py](../../core/matrix/motherboard/modules/directory/components/contentPanel.py)
(migas, título y disposición) y
[contentCard.py](../../core/matrix/motherboard/modules/directory/components/contentCard.py)
(diseño de la tarjeta). Decisión: [ADR 0003](../adr/0003-dial-de-carpetas-en-el-directorio.md).
Colores y tipografía vienen de [globalKyoraUI.md](globalKyoraUI.md).

## Flujo
| Acción | Resultado |
|---|---|
| Elegir Directorio en el reactor | `MotherboardRoot.show_root_directory` muestra la vista y desliza el reactor con su centro al borde derecho (`REACTOR_SLIDE_MS` = 450 ms); al llegar lo fija (`set_pinned`) y aparece el dial encima |
| `Esc` | Sube un nivel; en las carpetas principales vuelve el reactor al centro con el menú de módulos |
| Pulsar un archivo | Emite `file_opened(ruta)`; por ahora `MotherboardRoot` no lo conecta |

`RootDirectory` ocupa toda la ventana; a la izquierda del reactor (`set_reactor_rect`) va
el `ContentPanel` y sobre el reactor el `FolderDial`, un widget transparente de su mismo
tamaño.

## Dial de carpetas
Escribe los nombres de las carpetas del nivel actual dentro del círculo, en su mitad
izquierda (el centro es el borde de la ventana), y aparece tras el crecimiento del reactor
(`MENU_MS`, `GROW_END`). La primera opción es siempre `‹ ATRÁS`.

| Propiedad | Valor |
|---|---|
| Carpeta elegida | En `LIST_ANGLE` = 180°, desplazada `LIST_CHOSEN_SHIFT` = 22 % hacia fuera, en negrita a `LIST_CHOSEN_SIZE` = 7.4 % del radio y con una barra a su izquierda |
| Hueco en el reactor | Los anillos que cruza se interrumpen `LIST_GAP_PAD` = 3 % alrededor del nombre; el hueco crece y se encoge con él al girar (`gaps_changed` → `Reactor.set_gaps`) |
| Demás carpetas | Cada `LIST_STEP` = 16° hacia arriba y abajo, hasta ±`LIST_SPAN` = 64°, de `LIST_OTHER_SIZE` = 4.2 % y más tenues cuanto más lejos; sobre `LIST_LABEL_RADIUS` = 64 % |
| Nombres largos | Se recortan con «…» hasta el borde de la ventana |

| Acción | Efecto |
|---|---|
| Girar el dial (arrastrar alrededor del centro o rueda del ratón) | Cambia de carpeta y el contenido se actualiza **mientras se gira**; la rueda da un nombre por muesca y la lista no envuelve; `‹ ATRÁS` no cambia el contenido |
| Clic en el nombre elegido | Entra: el dial pasa a mostrar sus subcarpetas (nada si no tiene) |
| Clic en otro nombre | Lo elige |
| Pulsar `‹ ATRÁS` | Sube un nivel y deja elegida la carpeta de la que se venía; en las carpetas principales sale al menú de módulos |
| Teclado: arriba / abajo | Carpeta anterior / siguiente |
| Teclado: derecha o Enter | Entra en la carpeta elegida |
| Teclado: izquierda o Retroceso | Sube un nivel (en las principales no hace nada; `Esc` sale) |

Las subcarpetas ocultas (nombre que empieza por `.` o `$`) no se muestran en el dial; se
leen hasta `MAX_FOLDERS` = 300 por nivel. Al mostrarse la vista vuelve a las carpetas
principales (Escritorio, Descargas, Documentos, Imágenes, Música y Videos), con
`DEFAULT_FOLDER` elegida.

## Contenido
`ContentPanel` ocupa lo que queda a la izquierda del reactor y alinea todo en su esquina
superior izquierda, a `MARGIN_LEFT` = 40 px y `MARGIN_TOP` = 32 px del borde (medidas en
píxeles de referencia, a 800 de alto de ventana, escaladas con su alto):

- **Migas** (`DIRECTORIO › DOCUMENTOS`): cada nivel superior es clicable y sube hasta él.
- **Título** de 30 px con la carpeta elegida, recortado si no cabe.
- **Cuenta** de carpetas y archivos.
- **Tarjetas**, una por subcarpeta y por archivo (primero las carpetas, cada grupo por
  nombre, hasta `MAX_ENTRIES` = 1000), a `LIST_GAP` = 18 px bajo la cuenta. Se desplazan
  con la rueda del ratón sobre el panel.
- El panel entra con un fundido de `INTRO_MS` = 600 ms.

## Tarjeta
El diseño vive en `contentCard.py`; el panel solo la coloca. La fila mide como máximo
`CARD_WIDTH` = 430 px (número incluido), `CARD_HEIGHT` = 48 px y se separa `CARD_GAP` = 12 px
de la siguiente, de modo que ocupa poco ancho y deja ver el fondo y el reactor.

| Parte | Contenido |
|---|---|
| Número | Posición en la lista, a la izquierda, en `INDEX_WIDTH` = 30 px |
| Recuadro | Cuadrado con la esquina superior derecha cortada (`TILE_CUT` = 10 px); icono de [carpeta](../../core/resources/icons/files/folder.py) o de [archivo](../../core/resources/icons/files/file.py) |
| Nombre | En negrita, recortado por el centro; debajo `▸` y el detalle: la fecha en carpetas, tamaño y fecha en archivos |
| Tipo | Bloque de `TYPE_WIDTH` = 96 px a la derecha con `TIPO` y `CARPETA` o la extensión (`ARCHIVO` si no tiene) |

Las esquinas superior izquierda e inferior derecha de la tarjeta van cortadas
`CARD_CUT` = 9 px.

| Estado | Colores (de `kyora_theme.py`) |
|---|---|
| Reposo | Cuerpo `BG_CARD_HOVER` (gris claro) con contorno `BORDER`; bloque del tipo `BG_ITEM` con contorno `BORDER_INPUT`; recuadro `BG_CARD`; nombre `TEXT`, tipo `TEXT_BODY`, detalle y número `TEXT_SUB`; icono `TEXT_BODY` (carpeta) o `TEXT_MUTED` (archivo) |
| Bajo el cursor | Cuerpo `ACCENT_DEEP_BORDER` con grosor visible de `CARD_DEPTH` = 5 px en `ACCENT_DEEP`; bloque del tipo `ACCENT_DEEP`; recuadro `BG_DEEP` con el icono en `ACCENT`; textos `BG_DEEP`, `ACCENT_DEEP` y `ACCENT_TINT`; número `ACCENT_DEEP_BORDER` |

Clic en un archivo emite `file_opened`; clic en una carpeta entra en ella y la deja
elegida en el dial.
