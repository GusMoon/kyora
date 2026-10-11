*   **Fecha y hora:** 2026-10-11 14:42:00
*   **Archivos afectados:**
    * `+ core/matrix/ecosystems/tasks/infrastructure/database.py` (creado)
    * `+ core/matrix/ecosystems/tasks/domain/repositories.py` (creado)
    * `+ core/matrix/ecosystems/tasks/domain/entities.py` (actualizado)
    * `+ core/matrix/ecosystems/tasks/infrastructure/sqlite_task_repository.py` (creado)
    * `+ core/matrix/ecosystems/tasks/use_cases/manage_tasks.py` (actualizado)
    * `+ core/matrix/ecosystems/tasks/presentation/viewmodels/tasks_viewmodel.py` (actualizado)
    * `+ core/matrix/ecosystems/tasks/presentation/views/tasks_view.py` (actualizado)
    * `+ core/matrix/ecosystems/rootView.py` (actualizado)
*   **Explicación breve:** "Se implementó la persistencia relacional con SQLite para el ecosistema de Tareas, normalizando estados, tareas y subtareas con claves foráneas e integrándolo bajo la arquitectura Clean + MVVM."
*   **Cambios lógicos:**
    * "Se creó `DatabaseManager` con activación estricta de `PRAGMA foreign_keys = ON;`, inicialización automática del esquema (`task_statuses`, `tasks`, `subtasks`) e inserción del catálogo inicial de estados (`pending`, `in_progress`, `completed`)."
    * "Se incorporó la abstracción `TaskRepository` en la capa de Dominio para aplicar el principio de Inversión de Dependencias (DIP)."
    * "Se extendieron las entidades `Task` y `SubTask` e introdujo `TaskStatus`, agregando soporte para claves foráneas, prioridades, fechas de entrega (`due_date`) y ordenamiento relacional, preservando propiedades de compatibilidad (`status`, `creation_date`, `to_markdown`)."
    * "Se implementó `SqliteTaskRepository` con consultas parametrizadas, ordenamiento y mapeo sin problemas N+1, cascada de subtareas (`ON DELETE CASCADE`) y sincronización opcional con archivos `.task`."
    * "Se actualizó `TaskUseCases` para desacoplarlo de implementaciones concretas, unificando la nomenclatura de estados entre UI y Base de Datos."
    * "Se conectó `SqliteTaskRepository` en el punto de ensamblaje (`rootView.py`) y se enlazó la señal `task_saved` del visor para sincronizar las ediciones directamente con SQLite."
*   **Instalaciones:** "N/A"
*   **Toggles:** "N/A"
