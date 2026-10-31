# Kyora · Proyecto (versión Python + Qt)

> Versión 1.4 · 21 de octubre de 2026 · Documento único con objetivo, stack, tipo de arquitectura y funciones previstas de la Fase 1.
> Cambios de la 1.1: el stack pasa de Tauri/Rust a Python (sin Rust, sin sidecar), y el primer hito es el **entorno de ventanas** al estilo GlazeWM.
> Cambios de la 1.2: **todo es Python**, lógica e interfaz. La interfaz pasa de pywebview (HTML/CSS/JS) a **PySide6 (Qt)**, con un marco alrededor de la pantalla, barra vertical a la izquierda y un buscador que sobresale del marco.
> Cambios de la 1.3: el **Directorio (4.2)** está hecho: un explorador al estilo Nautilus, **con árbol de carpetas** (decisión de Gustavo), que sale del borde derecho (Win+E). La barra muestra clima, CPU, RAM, disco, volumen y brillo; el wifi permite conectarse a redes; la lechuza reúne las opciones de Kyora.
> Cambios del 21/10/2026 (tarde): el Directorio pasa al **panel de arriba** (Win+E) junto a Sistema y Kyora, con diseño de dashboard; la barra queda con escritorios, hora, wifi, Bluetooth, calendario y apagar (Win+X), que se abren al pasar el ratón.
> Cambios de la 1.4 (21/10/2026, noche): **Tasks (4.3)** y **SecondBrain (4.4)** están hechos. El panel de arriba tiene cinco secciones con la mini barra centrada: **Lobby** (sustituye a Sistema: hora, clima por horas, RAM, CPU, volumen, brillo, disco, batería y la semana), Archivos, Tareas, Segundo Cerebro y Kyora (Win+I/E/T/B/K). Estilo de placas de cristal sin tramas e iconos de archivo propios.
> Cambios del 22/10/2026: **el panel de arriba desaparece**. RAM, CPU, batería y clima pasan a la barra (iconos iguales, el activo en relieve); archivos, tareas, fondos y opciones de Kyora se usan desde el buscador con `>tree`, `/carpeta`, `@archivo`, `>task` (línea de tiempo y panel de la tarea a la derecha), `>wallpaper` y `>config`. El Segundo Cerebro deja de mostrarse (su núcleo se conserva).
> Cambios del 22/10/2026 (tarde): **los atajos globales pasan a la tecla Windows** (Win+F, Win+flechas, Win+Esc, Win+D, Win+E, Win+O, Win+1/2/3, Win+Espacio, Win+Alt+↑/↓, Win+Alt+Esc y Win mantenido + Esc dos veces para cerrarlo todo); los `Alt+…` quedan para las apps. La barra va en el color principal de Kyora. Las tareas se ven en tarjetas sencillas (nombre, descripción, etiquetas, subtareas, creación y hora para finalizar) y `Ctrl+N` crea una.
> Cambios del 23/10/2026: la barra se divide en dos (arriba CPU, RAM y batería; abajo apagar, hora con calendario, clima, wifi y Bluetooth) y la píldora de escritorios da paso a las **columnas de escritorios** (Win+Alt+←/→). Las tareas pasan a un checklist con panel minimalista (Ctrl+N, Ctrl+Enter, Ctrl+Supr) y un **tablero Kanban** (`>kanban`). Nuevas **notas** (`>notes`, archivos `.md` en Documentos\Notas Kyora). Los colores salen 100 % de los colores que más ocupan el fondo. Todo el diseño sigue la rúbrica de **`DISEÑO.md`** (skeumorfismo oscuro inspirado en Linux).
> Cambios del 23/10/2026 (tarde): **tareas y notas se manejan solo desde el buscador de abajo**. La tarea se abre ahí mismo (Esc vuelve), y `>kanban` y `>notes` ensanchan el buscador. Desaparecen el panel de la tarea de la derecha, las ventanas del tablero y de las notas y los diálogos de borrar: se borra pulsando dos veces. Tareas y notas pasan, por ahora, a un estilo **plano tipo GNOME** (excepción anotada en `DISEÑO.md`). El buscador se abre ahora **pulsando y soltando Windows sola** (antes Win+Espacio).
> Cambios del 24/10/2026: **Kyora va más ligera**. El gancho del teclado vive en su propio proceso, porque las teclas llegaban hasta 2 s tarde cuando Kyora estaba ocupada. Además, la luz de la ventana activa se dibuja una vez y se queda quieta, el marco guarda los bordes ya pintados, el núcleo consulta a Windows más despacio cuando nada cambia, y un vigía anota en kyora.log si la interfaz se traba. Las tareas se ven **como pasos** y el **Kanban** se abre con `Ctrl+K` dentro de `>task`. Las **notas** son un editor sencillo con barra de formato (negrita, cursiva, tachado, título, lista, cita y enlace) que guarda **Markdown** en el .md; ya no van apiladas ni hay mosaico.
> Cambios del 24/10/2026 (tarde): los escritorios se cambian con **Win+Alt+↑/↓** y se ven solo como **números centrados** (adiós columnas). La luz del borde da **5 vueltas durante 15 s**, creciendo como una serpiente hasta llenar el borde. Win+E es opaco e instantáneo. El **buscador** muestra los resultados en una caja gris, agrupados por secciones con icono y dos líneas, y un pie de teclas; se leen de arriba abajo. Transiciones más ligeras (no se repinta lo que no se ve). Se arregló el foco del buscador tras mover el gancho del teclado a otro proceso.
> Cambios del 24/10/2026 (noche): el fondo del **marco** (barra, buscador, paneles) es ahora el fondo de pantalla **desenfocado y oscurecido**, para que el texto se lea siempre. Las **ventanas se deslizan** a su hueco al abrirse o repartirse el espacio (opción `animate_windows`). La luz del borde es más fluida (60 fps, borde ya pintado y recortado con máscara).
> Cambios del 24/10/2026 (madrugada): las apps **ya no se mueven paso a paso** (las atoraba). Al abrir una, unas ventanas fantasma se acomodan primero (la nueva entra desde el borde derecho), debajo se colocan las apps de golpe y el panel se desvanece. El buscador pierde el pie de teclas y baja un poco su letra (14/13 px, a pedido de Gustavo). Los **números de escritorio** van en vertical sobre la franja de la barra, con un círculo de color, y duran 5 s; también salen al crear un escritorio.
> Cambios del 25/10/2026: al abrirse una ventana, **unas ventanas fantasma se acomodan primero** (la nueva entra deslizándose desde el borde derecho del marco) y **después** se colocan las apps reales, debajo, de golpe; así ninguna app se redimensiona a cada fotograma. El buscador pierde el pie de teclas y su letra baja a 14 px.

---

## 1. Objetivo del proyecto

**Kyora** será un agente personal tipo "JARVIS" que controla el ecosistema de trabajo de Gustavo en su laptop o escritorio con Windows. A largo plazo tendrá inteligencia artificial integrada, atenderá peticiones complejas y las ejecutará sobre el ordenador, y se podrá usar desde el móvil en cualquier lugar.

El proyecto avanza por fases:

| Fase | Meta |
|---|---|
| **1** | Control y accesos de toda la interfaz para mejorar los flujos de trabajo dentro del ordenador (**es lo que se construye ahora**). |
| 2 | Chat conectado entre ordenador y móvil: enviar documentos, archivos, recordatorios, mensajes y activar comandos, en ambos sentidos. |
| 3 | Reconocimiento de movimiento por cámara para manipular el ordenador sin ratón, dejando activo solo el teclado. |
| 4 | Modelos de IA para reconocimiento de voz, dictado inteligente, comandos y flujos por voz. |
| 5 | Modelos de IA que responden a las peticiones, escuchan con claridad y manipulan el ordenador a conciencia. |

**Principio rector:** toda función de Kyora es una **acción con nombre** que la interfaz invoca. En fases posteriores el móvil, la voz y la IA invocarán las mismas acciones, así que no habrá que reescribir lo que se construya ahora.

**Criterio de "Fase 1 terminada":** Gustavo puede pasar una jornada normal usando Kyora para gestionar archivos, tareas y notas, organizar ventanas, moverse entre escritorios virtuales y consultar el estado del equipo, sin abrir el Explorador de Windows.

---

## 2. Stack tecnológico

| Capa | Tecnología |
|---|---|
| Plataforma | Windows 10/11 (se diseña pensando en escalar a otros sistemas, sin implementarlo todavía) |
| Ventana y shell de escritorio | **PySide6 (Qt)** en Python: ventanas con transparencia real (marco de pantalla, barra lateral, buscador), atajos globales (`RegisterHotKey`), instancia única |
| Gestor de ventanas | **WM propio en Python** con la API Win32 (`SetWinEventHook`, `SetWindowPos`, DWM), inspirado en [GlazeWM](https://github.com/glzr-io/glazewm) (Rust, GPL-3.0: se toman las ideas, no el código) |
| Interfaz | **Solo Python con Qt** (widgets y pintura propia con `QPainter`); todo el diseño en `kyora/ui/theme.py` |
| Núcleo (lógica) | **Python 3.12+**, en el mismo proceso que la ventana |
| Comunicación interfaz ↔ núcleo | Los widgets llaman al registro de acciones; el núcleo avisa a la interfaz con señales de Qt (seguras entre hilos) |
| Datos de tareas | **SQLite** |
| Datos del Segundo Cerebro | Archivos `.md` en disco (**sin base de datos**) |
| Editor de notas | Editor visual de Qt (`QTextEdit`) que carga y guarda Markdown (TipTap era web y el stack es solo Qt) |
| Acceso a Windows | Librerías de Python (sistema, audio, brillo, escritorios virtuales, papelera, ventanas) |
| Calidad | `pytest` y `ruff` (núcleo e interfaz) |
| Herramientas de desarrollo | Python con un entorno `.venv` propio (PySide6-Essentials, pywin32, psutil) |

El editor de notas y las librerías de Windows de los módulos se validan cuando llegue su turno.

### Estilo visual

Paneles **planos oscuros** como la imagen de referencia (borde fino, esquinas suaves, texto pequeño gris, chips con contorno), con los colores del fondo de pantalla de Gustavo: azul marino profundo y un acento dorado paja que se reserva para lo activo, lo seleccionado y el destino de un arrastre. Sustituye al skeuomorfismo naranja de la versión 1.0.

Accesibilidad por la miopía de Gustavo: contraste alto y letra mínima de 15 px en el resto de la interfaz. **Excepción decidida por él:** la barra es solo para consultar de un vistazo, así que usa letra de 13 px. **Estilo "shell" (20/10/2026):** un marco fino rodea toda la pantalla con las esquinas interiores redondeadas; su parte ancha es la barra vertical de la izquierda (escritorios, ventanas en espera, disposición, wifi, reloj, salir). Los paneles **sobresalen del marco** como parte de la misma pieza, unidos con curvas cóncavas (radio invertido); por ahora solo el buscador (Alt+Espacio), que sale del borde inferior con el campo de escritura abajo y las opciones subiendo encima. La ventana con el foco lleva un borde fino con una luz sutil que gira por él (color principal del fondo de pantalla). Todo el diseño y el movimiento se definen en `kyora/ui/theme.py`.

### Uso diario (20/10/2026)

Barra lateral con cápsula de escritorios (1 arriba) e iconos reales de las aplicaciones en espera; panel vertical de ventanas en espera (Alt+E, capturas + iconos); atajos para ver 1, 2 o 3 ventanas y "solo esta ventana"; la tecla Windows suelta se ignora; arranque con el equipo con `scripts/instalar_inicio.bat`. Todo está explicado en `GUIA_KYORA.md` y los atajos en `COMANDOS.md`.

---

## 3. Tipo de arquitectura

**Modular, con núcleo y cliente separados, y orientada a acciones.**

1. **Interfaz y núcleo separados.** La interfaz (Qt, en Python) solo muestra y captura; el núcleo (Python) tiene toda la lógica. La interfaz no contiene reglas de negocio y el núcleo no sabe cómo se ve nada.
2. **Orientada a acciones (registro de comandos).** El núcleo expone un catálogo de acciones con nombre (por ejemplo `tasks.create`, `directory.move`). La interfaz y, más adelante, el móvil, la voz y la IA llaman a ese mismo catálogo. Las acciones devuelven un resultado estándar (éxito o error estructurado) y las destructivas piden confirmación.
3. **Monolito modular.** Cada módulo (Tasks, Directory, SecondBrain, GlobalFunctions) es independiente, con sus propias acciones, y no depende directamente de los demás.
4. **Capa de adaptación al sistema operativo.** Todo lo específico de Windows queda detrás de interfaces, para poder soportar otros sistemas en el futuro escribiendo un adaptador nuevo.
5. **Motor de ventanas independiente de la UI.** El WM (seguimiento de ventanas, layouts, escritorios propios) vive en el núcleo; el cálculo de layouts es una función pura y probable con `pytest`. Siempre debe poder devolver las ventanas y la barra de tareas a su estado normal (cierre limpio, atajo de emergencia y comprobación al arrancar).
6. **Eventos del núcleo a la interfaz.** Progreso de copias, datos del equipo, cronómetro y cambios de ventanas se envían en tiempo real a la interfaz.
7. **Seguridad local.** Servidor de archivos solo en `127.0.0.1` con token por sesión, y confirmaciones en acciones destructivas.
8. **Rendimiento.** Sin animaciones continuas ni consultas frecuentes en reposo; las tareas pesadas corren en el núcleo, nunca bloquean la interfaz.

---

## 4. Funciones previstas (Fase 1)

### 4.1 Transversales

- Paleta de comandos (`Ctrl+K`) para ejecutar cualquier acción.
- Atajos de teclado en todos los módulos.
- Confirmación en acciones destructivas.
- Escala de interfaz ajustable.
- Configuración de preferencias (carpetas ancladas, ruta del Segundo Cerebro, ubicación).

### 4.2 Directory (Directorio) · hecho el 21/10/2026

Sección Archivos del panel de arriba (Win+E), con lugares, **árbol de carpetas** y vista previa. Núcleo en `kyora/directory/`, interfaz en `kyora/ui/explorer/` y `kyora/ui/hub/`; teclas en `COMANDOS.md`. La vista previa usa PySide6-Addons (audio y vídeo) y pypdfium2 (PDF).

- Ver carpetas y archivos sin usar el Explorador de Windows; carpetas principales y posibilidad de anclar más.
- Navegar, ver y modificar la ruta, y buscar archivos y carpetas.
- Crear, renombrar, abrir y cerrar.
- Copiar (duplicar en el mismo directorio o en otro destino), pegar y mover (desplazar el original).
- Borrar: envía a la papelera de Windows (Kyora no tiene papelera propia por ahora).
- Selección normal (un elemento), múltiple (varios juntos) y múltiple avanzada (separados, en el mismo directorio o en distintos directorios).
- Comando para mostrar u ocultar archivos ocultos.
- Vista previa de `.txt`, `.md`, código (`.py`, `.json`, `.gitignore`, etc.), `.mp3`, `.mp4`, `.pdf`, `.png` y `.jpg` (Word queda descartado por ahora).
- Manejo de conflictos de nombre, deshacer y progreso en operaciones largas.

### 4.3 Tasks (Tareas) · hecho el 21/10/2026

Sección Tareas del panel de arriba (Win+T). Núcleo en `kyora/tasks/` (SQLite en `tasks.db`), interfaz en `kyora/ui/hub/tasks_page.py`; teclas en `COMANDOS.md`.

- Crear, editar y borrar tareas (nombre, descripción, tiempo esperado, tiempo real, fecha de creación, de actualización, de entrega y de finalización).
- Subtareas con orden.
- Etiquetas independientes que se pueden asignar a varias tareas.
- Cuatro estados (decisión de Gustavo del 22/10/2026, en lugar de "sin estados"): pendiente, en proceso, en revisión y finalizada. Sin checklist y sin prioridad.
- Cronómetro que suma al tiempo real.
- Al borrar una tarea se borran sus subtareas; las etiquetas se conservan.
- Filtros por etiqueta y fecha de entrega.

### 4.4 SecondBrain (Segundo Cerebro) · hecho el 21/10/2026

Sección Segundo Cerebro del panel de arriba (Win+B). Núcleo en `kyora/brain/` (solo archivos `.md`; Soma y Núcleo se calculan al vuelo, sin archivos de índice), interfaz en `kyora/ui/hub/brain_page.py`. Esquema en disco: `Notas/` (con `Impulsos/`) y `Corteza/<Área>/<Dendrita>/<Neurona>.md`; los axones van junto a su neurona con `origen: [[Neurona]]`. Teclas en `COMANDOS.md`.

- Primer arranque: elegir la ruta donde se creará (nombre por defecto "Segundo Cerebro").
- Dos espacios: **Notas** (incluye los **Impulsos**, ideas rápidas guardadas como notas) y **Corteza** (áreas de conocimiento).
- Metáfora neuronal: Corteza (área), Dendrita (rama), Neurona (nota principal), Soma (índice de la neurona por títulos, subtítulos, componentes y formatos), Sinapsis (enlace entre notas), Axón (nota derivada), Núcleo (índice de una dendrita) e Impulso (idea rápida).
- Plantilla de metadatos que se inserta al crear una neurona.
- Editor visual con formatos de texto, sin mostrar el código; un comando permite ver el Markdown. El archivo siempre se guarda como `.md`.
- Enlaces entre notas con enlaces de vuelta, búsqueda por título y contenido, y guardado seguro.

### 4.5 GlobalFunctions (Funciones Globales)

- **Datos del equipo:** hora y fecha, RAM, memoria (CPU, disco, batería), ubicación, clima según la ubicación, IP del dispositivo e IP de la red wifi.
- **Ver y configurar:** wifi (ver y encender/apagar), bluetooth (ver estado), volumen, brillo y fondo de pantalla.
- **Aplicaciones y ventanas:** abrir y cerrar aplicaciones, ver las ventanas abiertas y organizarlas con un **máximo de 3 ventanas**: una ventana sola, dos en vertical, dos en horizontal, o una de un lado con dos apiladas del lado contrario. Nunca se permiten 4.
- **Ecosistemas:** son los escritorios virtuales de Windows; listar, cambiar, saltar a una aplicación abierta en otro escritorio, crear, renombrar y cerrar.

---

## 5. Fuera de la Fase 1

Papelera propia dentro de Kyora, emparejar bluetooth, redes wifi de empresa (con usuario, 802.1X), gestor de ventanas con 4 divisiones, Word y Office, y las Fases 2 a 5 (móvil, cámara, voz e IA).

---

## 6. Orden de construcción

Se avanza paso a paso, y cada hito lo prueba Gustavo en su pantalla antes de seguir:

0. Prueba técnica.
1. Esqueleto: ventana anclada arriba, puente UI↔Python, registro de acciones y atajo de emergencia.
2. Mosaico: máximo 3 ventanas visibles (1; 2 en vertical u horizontal; 1 + 2 apiladas), el resto en espera.
3. Escritorios propios de Kyora.
4. Barra superior (reloj, wifi, ventanas en espera, escritorios) y búsqueda de apps.
5. Funciones prácticas y módulos (paleta de comandos, Tasks, Directory, SecondBrain, GlobalFunctions), solo a petición y de una en una.
