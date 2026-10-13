# Registro de Cambios: Card con subtareas legibles, fecha opcional y lector de descripción

- **Fecha y hora:** 2026-10-13 12:00:00
- **Archivos afectados:**
  - `* core/matrix/ecosystems/tasks/presentation/taskCard.py`
  - `* core/matrix/ecosystems/tasks/presentation/tasks_view.py`
  - `+ core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata/general/description_reader.py`
  - `* core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata/general/__init__.py`
  - `* core/matrix/ecosystems/tasks/presentation/rootComponents/taskMetadata/taskMetadataMain.py`
- **Explicación breve:** Se mejoró la legibilidad de las subtareas en el card, se ocultó el panel de fecha cuando la tarea no tiene fecha y la descripción pasó a leerse en un panel flotante independiente.
- **Cambios lógicos:**
  - **Subtareas:** nueva fila propia `SUBTAREAS n/total` (11px) con barra de progreso fina del color de acento del estado. Solo aparece si la tarea tiene subtareas.
  - **Altura:** el card pasa de 68px a 84px, uniforme en todos los cards.
  - **Fecha opcional:** sin `due_date` (o con formato inválido) no se crea el panel derecho `TBD --`; el contenido usa todo el ancho.
  - **Descripción:** se eliminó la expansión dentro del card (`toggle_expand`, `eventFilter`, scroll interno). El clic emite `description_requested(task_id)` y `TasksView` abre `DescriptionReader`, un panel centrado que solo muestra título y texto con ajuste de línea (incluso palabras largas), sin scroll horizontal, scroll vertical y cierre con ✕ o Esc.
  - El doble clic sigue abriendo el detalle de la tarea.
- **Instalaciones:** N/A
- **Toggles:** N/A
