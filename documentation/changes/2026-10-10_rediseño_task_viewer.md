*   **Fecha y hora:** 2026-10-10 11:25:00
*   **Archivos afectados:** 
    * `M core/matrix/ecosystems/explorer/filesType/task_viewer.py`
    * `M core/matrix/ecosystems/tasks/domain/entities.py`
*   **Explicación breve:** "Se rediseñó el `task_viewer.py` para coincidir con la estética oscura y se mejoró la edición de subtareas."
*   **Cambios lógicos:** 
    * "Se eliminó el `QTreeWidget` rígido y los botones inferiores de control (Add Task, Add Subtask, Toggle Status)."
    * "Ahora la sección de `Tasks:` es un editor de texto libre puro (QTextEdit) donde el usuario puede escribir su propio markdown (ej. `- [ ] Tarea 1 \n  Descripción de tarea 1`), dando total flexibilidad."
    * "Se modificó `entities.py` para que guarde un `raw_tasks_text`. De este modo, si la tarea se mueve de columna en el Kanban, no se pierde el formato ni la descripción personalizada que se haya puesto bajo cada subtarea."
*   **Instalaciones:** "N/A"
*   **Toggles:** "N/A"
