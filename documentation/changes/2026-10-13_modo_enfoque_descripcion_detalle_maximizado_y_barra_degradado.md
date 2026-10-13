# Registro de Cambios: Modo enfoque de descripción, detalle maximizado y barra con degradado

- **Fecha y hora:** 2026-10-13 13:00:00
- **Archivos afectados:**
  - `+ core/matrix/ecosystems/motherBoard/globalComponents/gradient_progress_bar.py`
  - `* core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata/general/description_reader.py`
  - `* core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata/base_modal.py`
  - `* core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata/general/task_detail_dialog.py`
  - `* core/matrix/ecosystems/tasks/presentation/tasks_view.py`
  - `* core/matrix/ecosystems/tasks/presentation/taskCard.py`
- **Explicación breve:** La descripción se lee en un modo enfoque con el tablero desenfocado y la tarea identificada a su lado; la tarea abierta ocupa toda la ventana; las barras de completado de subtareas usan degradado.
- **Cambios lógicos:**
  - **Modo enfoque:** `DescriptionReader` pasa de panel centrado a overlay que cubre `TasksView`. A la izquierda, la tarjeta de descripción (título + texto, sin scroll horizontal); a su lado, una réplica no interactiva del `TaskCard` y los botones `ABRIR TAREA` / `CERRAR`. Se cierra con ✕, Esc, clic en el área vacía o al refrescarse el tablero.
  - **Desenfoque:** el tablero vive en `board_container`, al que `TasksView` aplica `QGraphicsBlurEffect` mientras el overlay está visible.
  - **Fábrica de cards:** `TasksView._build_card(task)` unifica la construcción para el tablero y la réplica.
  - **Detalle maximizado:** `SciFiBaseModal.fit_to_rect(rect)` ajusta el modal a la ventana principal y bloquea arrastre y redimensionado. Se usa solo en `TaskDetailDialog`; el diálogo de creación conserva su tamaño.
  - **Degradado:** nuevo `GradientProgressBar` (`#FFAA77` → `#A04A2C`, anclado al ancho completo de la pista). Reemplaza la barra de subtareas del `TaskCard` y de la pestaña Subtareas del detalle. La barra del cronómetro no cambia.
  - En `TaskCard` la barra se oculta durante el arrastre (estado fantasma) porque se pinta a mano y no obedece al QSS.
- **Instalaciones:** N/A
- **Toggles:** N/A
