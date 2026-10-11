*   **Fecha y hora:** 2026-10-11 15:09:00
*   **Archivos afectados:**
    * `+ core/matrix/ecosystems/tasks/presentation/views/components/task_card.py` (actualizado)
    * `+ core/matrix/ecosystems/tasks/presentation/views/components/task_dialogs.py` (actualizado)
    * `+ core/matrix/ecosystems/tasks/presentation/views/tasks_view.py` (actualizado)
*   **Explicación breve:** "Se implementó la visualización de información de la tarjeta mediante despliegue (acordeón) con 1 clic, doble clic para editar y ventana de edición flotante movible por la pantalla."
*   **Cambios lógicos:**
    * "En `TaskCard`: se integró un contenedor desplegable con la descripción detallada, fecha de registro e indicador visual (▼/▲). Se programó la diferenciación precisa entre clic simple (desplegar/colapsar), arrastre sostenido (drag & drop para cambio de columna) y doble clic (editar)."
    * "En `task_dialogs.py`: se implementó arrastre interactivo en `SciFiBaseModal` (`mousePressEvent`, `mouseMoveEvent`), permitiendo que `TaskDetailDialog` se desplace libremente por cualquier parte de la pantalla mediante cálculo de posición global del cursor."
    * "En `tasks_view.py`: se inyectaron los datos de descripción y fecha de registro a las tarjetas durante la carga de tareas."
*   **Instalaciones:** "N/A"
*   **Toggles:** "N/A"
