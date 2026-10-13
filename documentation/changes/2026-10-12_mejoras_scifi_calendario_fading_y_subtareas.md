*   **Fecha y hora:** 2026-10-12 23:15:00
*   **Archivos afectados:**
    * `+ core/matrix/ecosystems/motherBoard/globalComponents/icons/calendar.py` (creado)
    * `+ core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata/base_modal.py` (actualizado)
    * `+ core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata/task_detail_dialog.py` (actualizado)
    * `+ core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata/task_create_dialog.py` (actualizado)
    * `+ core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata/fading_text_edit.py` (actualizado)
    * `+ core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata/taskMetadataMain.py` (actualizado)
    * `+ core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata/__init__.py` (actualizado)
    * `+ core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata/subtask_item.py` (actualizado)
    * `+ core/matrix/ecosystems/tasks/presentation/taskCard.py` (actualizado)
*   **Explicación breve:** "Se implementó el icono Sci-Fi vectorial de calendario, acceso al calendario mediante botón interactivo, fecha completa sin truncar, efecto sutil de scroll con animación de desvanecimiento suave (aplicado también al card) y auto-adaptabilidad de altura para notas de subtareas."
*   **Cambios lógicos:**
    * "Creación de `calendar.py` con dibujo vectorial `QPainter` (marco tecnológico biselado, pines superiores, matriz digital y celda activa) y generadores `get_calendar_icon` / `get_calendar_pixmap`."
    * "Reemplazo de `QLabel('📅')` por `btn_calendar` (`QPushButton`) en `TaskDetailDialog` y `TaskCreateDialog` que alterna dinámicamente el popup de calendario nativo de `QDateEdit`."
    * "Ajuste de dimensiones fijas (`135px`) y refinamiento de estilos CSS para `QDateEdit` y `QCalendarWidget` en `base_modal.py`, asegurando que la fecha completa `dd/MM/yyyy` sea 100% visible sin recortes."
    * "Reducción del degradado de scroll (`fade_height`) de 38px a 18px en `ScrollFadeOverlay` e implementación de animación suave de opacidad (fade-out en 240ms) al detener el desplazamiento, eliminando el corte abrupto."
    * "Creación de `FadingScrollArea` y su integración en `TaskCard` para aplicar el efecto de desvanecimiento sutil a la vista previa de la descripción extendida al hacer 1 clic."
    * "Creación de `AutoResizeSubtaskEdit` en `subtask_item.py` con cálculo dinámico del documento y ancho de viewport, ajustando la altura de notas de 1 línea a 24px-28px y creciendo reactivamente según las líneas escritas hasta 110px."
    * "Corrección del estiramiento vertical en `SubtaskEditorItem` (estableciendo `QSizePolicy.Maximum`, alineación `Qt.AlignTop` y `addStretch()` en el contenedor scrolleable de subtareas), reduciendo la altura total por subtarea de 137px a 64px con nota y 36px sin nota, evitando que ocupen todo el espacio disponible."
*   **Instalaciones:** "N/A"
*   **Toggles:** "N/A"
