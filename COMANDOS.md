# Comandos de Kyora

Es la lista de todo lo que se puede hacer con el teclado y el ratón. Úsala como referencia para pedir cambios.

Los atajos se pueden cambiar en `%APPDATA%\Kyora\config.json` (sección `hotkeys`). Cada atajo apunta a una acción por su nombre (columna **Acción**).

## Atajos de teclado

| Atajo | Qué hace | Acción |
|---|---|---|
| `Alt+F` | Pasar el foco a la siguiente ventana visible (después de la última, vuelve a la primera) | `wm.focus_next` |
| `Alt+←/→/↑/↓` | Mover la ventana con foco al hueco de ese lado (se intercambia con la vecina) | `wm.move` |
| `Alt+Esc` | Cerrar la ventana con foco | `wm.close` |
| `Alt+D` | Nuevo escritorio (y se va a él) | `desktop.create` |
| `Alt+E` | Cambiar de app: panel de ventanas en espera (ver abajo) | `switcher.toggle` |
| `Alt+O` | Girar la ventana grande: arriba → derecha → abajo → izquierda → arriba | `wm.rotate` |
| `Alt+1` / `Alt+2` / `Alt+3` | Ver 1, 2 o 3 ventanas (aparca las que sobran o trae las que esperan) | `wm.show_count` |
| `Alt+Espacio` | Buscador de apps y ventanas (sale del borde inferior) | `search.toggle` |
| `Alt+M` | Activar o desactivar el foco con el ratón | `app.focus_follows_mouse` |
| `Win+↑` / `Win+↓` | Ir al escritorio de arriba / de abajo (en el primero o el último no hace nada) | `desktop.step` |
| `Win+Esc` (dos veces) | Cerrar todas las ventanas de todos los escritorios. La primera pulsación avisa; la segunda, en 3 s, cierra. Las apps pueden preguntar si guardar | `wm.close_all` |
| `Win+-` (o el `-` del teclado numérico) | Cerrar este escritorio: sus ventanas pasan al anterior | `desktop.close_current` |
| `Win+X` | Apagar, reiniciar o suspender el equipo (el mismo panel que el botón de apagar; ver abajo) | `power.menu` |
| `Win+I` / `Win+E` / `Win+T` / `Win+B` / `Win+K` | Panel de arriba en **Lobby** / **Archivos** / **Tareas** / **Segundo Cerebro** / **Kyora** (ver abajo). Otra vez lo cierra | `hub.toggle` |
| `Ctrl+Alt+Shift+Q` | Salida de emergencia: devuelve todo a Windows y cierra Kyora | `app.release` |

Mientras Kyora está abierta, estos atajos ya no llegan a las apps. Por ejemplo, `Alt+←/→` deja de ser atrás/adelante en el navegador y `Alt+D` deja de ir a su barra de direcciones.

**Dentro del panel de Alt+E** (se abre sobre la ventana con foco):

| Tecla | Qué hace |
|---|---|
| `↑` / `↓` (o `K` / `J`, o la rueda) | Elegir otra ventana en espera |
| `Enter` o clic | Traerla al hueco: la que estaba ahí pasa a espera |
| `Supr` | Cerrar la ventana elegida |
| `Esc` | Salir |

Si no hay ventanas en espera, el panel muestra "No hay aplicaciones en espera".

**Dentro del buscador:** escribe para buscar; `↑`/`↓` eligen, `Enter` abre y `Esc` cierra. Escribe `commands` para ver todos los atajos (con `↑`/`↓` o la rueda se recorre la lista); al borrarlo se vuelve a buscar apps y ventanas.

**Panel de energía (Win+X o botón de apagar):** `←`/`→` (o `1`, `2`, `3`) eligen y `Enter` ejecuta: Apagar, Reiniciar o Suspender. Apagar y reiniciar devuelven antes las ventanas a Windows, así que las apps que tengan algo sin guardar te lo preguntan. `Esc` sale.

**Tecla Windows:** pulsarla sola no abre el menú de inicio. Las combinaciones siguen funcionando (`Win+L`, `Win+D`, `Win+Shift+S`…), menos `Win+↑`, `Win+↓`, `Win+Esc`, `Win+-`, `Win+X`, `Win+I`, `Win+E`, `Win+T`, `Win+B` y `Win+K`, que ahora son de Kyora.

## Panel de arriba (Win+I · Win+E · Win+T · Win+B · Win+K)

Sale del borde de arriba. Arriba a la izquierda, las migas de pan; **en el centro, la mini barra de secciones**: la activa es una píldora clara con su nombre (Lobby, Archivos, Tareas, Cerebro, Kyora) y las demás solo su icono; un clic cambia de sección. Todo va en placas de cristal oscuro, sin rayas. Se cierra al hacer clic fuera, con `Esc` o con el mismo atajo otra vez.

| Atajo (con el panel abierto) | Qué hace |
|---|---|
| `Ctrl+1` … `Ctrl+5` | Ir a Lobby / Archivos / Tareas / Segundo Cerebro / Kyora |
| `Ctrl+Tab` / `Ctrl+Shift+Tab` | Sección siguiente / anterior |
| `Ctrl+Shift+H` / `E` / `O` / `D` / `I` | En Archivos: carpeta personal, Escritorio, Documentos, Descargas, Imágenes |

- **Lobby:** a la izquierda la hora en grande con la fecha; el clima de ahora y de las 6 horas siguientes (la ciudad va en `config.json`: `"weather": {"city": "Tu ciudad"}`); **RAM** y **CPU** con su número y sus barras de los últimos minutos; volumen y brillo con su deslizador (clic en el altavoz: silenciar), disco C: (al pasar el ratón, los GB) y batería; y tu usuario de Windows. A la derecha, la semana con hoy en claro y, debajo, el sitio de las tareas (vacío por ahora).
- **Archivos:** el explorador, con los iconos propios de Kyora (carpeta de cristal y hoja blanca). La ruta está en las migas de pan; a la izquierda **Lugares** (las carpetas de siempre, las ancladas —clic derecho para desanclar— y debajo el árbol de carpetas); en el centro la carpeta con sus botones; a la derecha la vista previa.
- **Tareas** y **Segundo Cerebro:** ver abajo.
- **Kyora:** lo que antes estaba en la lechuza, en tarjetas con su explicación; un clic lo ejecuta (desconectar o reiniciar Kyora, actualizar, consola, rescate, arranque con Windows).

| Tecla o ratón | Qué hace |
|---|---|
| Doble clic o `Enter` | Abrir (las carpetas se abren dentro del explorador; los archivos, con su programa) |
| `Retroceso` | Subir a la carpeta de arriba |
| Botones `←` `→` `↑` | Atrás, adelante y carpeta de arriba |
| Clic en un tramo de la ruta | Ir a esa carpeta |
| `Ctrl+L` o clic en el hueco de la ruta | Escribir la ruta (con autocompletado) |
| `Ctrl+F` o lupa | Buscar por nombre en esta carpeta y sus subcarpetas |
| Clic / `Ctrl`+clic / `Shift`+clic | Elegir uno, varios sueltos o un tramo seguido |
| `Ctrl`+clic en otra carpeta | Sumar elementos de varias carpetas a la vez (abajo aparece "N seleccionados en M carpetas"; un clic ahí los muestra o vacía la selección) |
| `Ctrl+C` / `Ctrl+X` / `Ctrl+V` | Copiar / cortar / pegar (también con el Explorador de Windows y otras apps) |
| `Ctrl+D` | Duplicar en la misma carpeta ("nombre (2)") |
| `F2` | Renombrar |
| `Supr` | Mandar a la Papelera de Windows (pregunta antes) |
| `Ctrl+Shift+N` | Nueva carpeta |
| `Ctrl+Z` | Deshacer lo último (crear, renombrar, copiar, mover). Lo borrado se recupera desde la Papelera de Windows |
| `Ctrl+H` | Mostrar u ocultar los archivos ocultos |
| `Espacio` | Vista previa: texto y código, Markdown, imágenes, PDF (con páginas), audio y vídeo |
| `F5` | Volver a leer la carpeta |
| Clic derecho | Abrir, Abrir con…, cortar, copiar, pegar, duplicar, renombrar, papelera, copiar ruta, anclar |
| Botón de cuadrícula/lista | Cambiar la vista |
| Menú `⋮` | Ocultos, nueva carpeta o archivo, pegar, deshacer, anclar esta carpeta |
| `Esc` | Cierra, por orden: la ruta escrita, la vista previa, la búsqueda y el panel |

Si al pegar ya hay algo con el mismo nombre, pregunta: **Reemplazar** (lo que había va a la Papelera), **Conservar ambos** u **Omitir**, con la opción de hacer lo mismo con los demás. Las copias largas muestran el progreso abajo, con **Cancelar**.

Las carpetas ancladas aparecen en **Lugares**, debajo de las de siempre. Se guardan en `%APPDATA%\Kyora\directory.json`.

### Tareas (Win+T)

Tres columnas: **Filtros** (fecha de entrega: Todas, Hoy, Esta semana, Vencidas, Sin fecha; "Ver finalizadas"; y las **etiquetas**: clic para filtrar por una o varias, clic derecho para renombrar o borrar, y el campo "Nueva etiqueta"), la **lista** (punto de su etiqueta, nombre, subtareas y descripción, y la entrega con su reloj; en rojo si ya pasó; un punto verde si el cronómetro va) y el **detalle**.

En el detalle: nombre, descripción, entrega (escríbela o usa Hoy, Mañana, Sin fecha), tiempo esperado (por ejemplo `1 h 30 min`, `90` o `1:30`), tiempo real con **Empezar/Parar** del cronómetro, las fechas de creación, actualización y finalización, las etiquetas (clic para ponerla o quitarla), las **subtareas** en orden (casilla para finalizarla, doble clic para renombrarla) y **Finalizar/Reabrir** y **Borrar**. Se guarda solo al dejar de escribir.

No hay estados ni prioridades: una tarea solo se finaliza y se puede reabrir. Al borrar una tarea se borran sus subtareas; las etiquetas se quedan. Solo un cronómetro va a la vez, y sigue contando aunque cierres Kyora. Todo se guarda en `%APPDATA%\Kyora\tasks.db`.

| Tecla | Qué hace |
|---|---|
| `Ctrl+N` | Nueva tarea (escribe el nombre y Enter) |
| `Ctrl+Shift+N` | Nueva subtarea |
| `Ctrl+Enter` | Finalizar o reabrir |
| `Ctrl+T` | Empezar o parar el cronómetro |
| `Supr` (en la lista) | Borrar la tarea (pregunta antes) |
| `Ctrl+↑` / `Ctrl+↓` | Subir o bajar la subtarea elegida |

### Segundo Cerebro (Win+B)

La primera vez pregunta dónde crearlo (por defecto `Documentos\Segundo Cerebro`; la ruta se guarda en `%APPDATA%\Kyora\brain.json`). Es una carpeta normal de archivos `.md`, sin base de datos:

| Pieza | Qué es | En disco |
|---|---|---|
| **Notas** | Notas sueltas | `Notas\` |
| **Impulsos** | Ideas rápidas | `Notas\Impulsos\` (fecha y primeras palabras como nombre) |
| **Corteza** | Áreas de conocimiento | `Corteza\<Área>\` |
| **Dendrita** | Rama de un área | `Corteza\<Área>\<Dendrita>\` |
| **Neurona** | Nota principal | `<Dendrita>\<Título>.md`, con su plantilla de metadatos |
| **Axón** | Nota derivada de una neurona | Junto a ella, con `origen: [[Neurona]]`; en el árbol cuelga de su neurona |
| **Sinapsis** | Enlace a otra nota | `[[Título]]` en el texto |
| **Soma** | Índice de una nota | Sus títulos y lo que tiene (listas, tablas, código, citas, sinapsis); se calcula al vuelo |
| **Núcleo** | Índice de una dendrita | Sus neuronas y axones con sus títulos; sale al hacer clic en la dendrita |

A la izquierda: **Notas | Corteza**, el campo **Impulso** (escribe la idea y Enter), el buscador (títulos y contenido, sin importar tildes ni mayúsculas) y el árbol. El botón **+** y el clic derecho crean lo que toca según dónde estés (nota, área, dendrita, neurona o axón); el clic derecho también renombra y borra (a la Papelera, preguntando antes). Al renombrar una nota, sus sinapsis en las demás notas se actualizan.

En el centro, el **editor visual**: escribes con formato sin ver el código, y el archivo se guarda como `.md`. La barra tiene T1, T2, T3, negrita, cursiva, listas, cita, código y **[[ ]]** (sinapsis). Al escribir `[[` salen los títulos para elegir; `Ctrl`+clic en una sinapsis la abre. Se guarda solo un segundo después de dejar de escribir, al cambiar de nota y al cerrar el panel. Si otro programa cambió la nota mientras la tenías abierta, pregunta antes de guardar encima.

A la derecha: **Soma** (clic en un título para ir a él), **Sinapsis** (las que aún no existen dicen "crear": un clic la crea), **Enlaces de vuelta** (qué notas apuntan a esta) y los metadatos.

| Tecla | Qué hace |
|---|---|
| `Ctrl+N` | Nueva nota (en Notas) o neurona (en la dendrita elegida) |
| `Ctrl+Shift+I` | Ir al campo Impulso |
| `Ctrl+Shift+F` | Buscar |
| `Ctrl+S` | Guardar ya |
| `Ctrl+M` | Ver y editar el Markdown (otra vez vuelve al editor visual) |
| `Ctrl+B` / `Ctrl+I` | Negrita / cursiva |
| `Ctrl+Alt+1` / `2` / `3` (`0` lo quita) | Título 1 / 2 / 3 |
| `Ctrl+Shift+8` | Lista |

## Barra lateral (ratón)

Arriba, los escritorios; abajo, la hora y cuatro iconos. Cada icono abre su panel a la derecha **en cuanto pasas el ratón** y lo cierra en cuanto lo quitas del grupo de iconos y del panel (si haces clic para escribir, como la contraseña del wifi, se queda hasta que hagas clic fuera). Es un solo panel: si pasas de un icono a otro, no se cierra, se desliza y cambia de contenido. Cerca del fondo se apoya en el marco de abajo.

Los bordes de las ventanas llevan el mismo diseño que el marco (línea oscura, filete de luz y sombra suave); la ventana con el foco, además, una luz neón que gira con el color de tu fondo de pantalla.

| Pieza | Qué hace |
|---|---|
| Píldora de escritorios | Clic: ir a ese escritorio. Clic derecho: renombrar o cerrar. `+`: nuevo escritorio |
| Hora | Al pasar el ratón: la fecha |
| Wifi | Redes disponibles: conectar (con contraseña si hace falta), desconectar, buscar |
| Bluetooth | Encender o apagar, y tus dispositivos emparejados (conectados primero). Para emparejar uno nuevo, el botón abre la configuración de Windows |
| Calendario | El mes con hoy resaltado; `‹` `›` cambian de mes |
| Apagar | Apagar, Reiniciar o Suspender (también con `Win+X`) |

**Panel del wifi:** arriba el estado y los botones Buscar y Desconectar; debajo las redes, de mejor a peor señal, con su candado si tienen contraseña. Un clic en una red guardada o abierta conecta; en una con contraseña despliega el campo (con "Ver" para mostrarla). Si no sale ninguna red, Windows puede estar pidiendo permiso de ubicación para las apps de escritorio: el panel lo dice y tiene un botón para abrir ese ajuste.
