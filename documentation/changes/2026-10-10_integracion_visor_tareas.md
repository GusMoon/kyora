*   **Fecha y hora:** 2026-10-10 11:18:00
*   **Archivos afectados:** 
    * `M core/matrix/ecosystems/tasks/use_cases/manage_tasks.py`
    * `M core/matrix/ecosystems/tasks/presentation/viewmodels/tasks_viewmodel.py`
    * `M core/matrix/ecosystems/tasks/presentation/views/components/task_card.py`
    * `M core/matrix/ecosystems/tasks/presentation/views/tasks_view.py`
    * `M core/matrix/ecosystems/rootView.py`
*   **Explicación breve:** "Se unificó el flujo de creación de tareas con el visor `task_viewer.py`."
*   **Cambios lógicos:** 
    * "El ID y nombre de archivo ahora se generan basados en el título sanitizado en lugar de un UUID."
    * "Se eliminó el diálogo de creación largo (`SciFiTaskDialog`) y se reemplazó por un `SciFiInputDialog` simple para pedir solo el título."
    * "Al añadir o hacer doble clic en una tarea desde el Kanban, se emite una señal que `rootView.py` intercepta para abrir el archivo en `task_viewer.py` automáticamente."
*   **Instalaciones:** "N/A"
*   **Toggles:** "N/A"
