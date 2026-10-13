*   **Fecha y hora:** 2026-10-11 17:33:00
*   **Archivos afectados:**
    * `- core/matrix/ecosystems/tasks/presentation/task_card.py` (eliminado)
    * `+ core/matrix/ecosystems/tasks/presentation/taskCard.py` (creado con nuevo diseño)
    * `+ core/matrix/ecosystems/tasks/presentation/tasks_view.py` (actualizado)
*   **Explicación breve:** "Se renombró el componente visual a taskCard.py y se rediseñó la vista previa del card para mostrar el nombre, badges de prioridad/estado, descripción con límite de 3 líneas y aviso de texto adicional, contador de subtareas y fecha de entrega, condicionando la vista expandida únicamente cuando la descripción excede las 3 líneas."
*   **Cambios lógicos:**
    * "Renombrado de `task_card.py` a `taskCard.py` y actualización de importación en `tasks_view.py`."
    * "Diseño del Card inspirado en la referencia visual:
        - Fila superior de tags redondeados: prioridad (`⚑ Alta` / `⚑ Normal`) y estado (`⏱ Pendiente`, `⚡ En progreso`, `✔ Completada`) junto al botón de eliminación `✕`.
        - Nombre de la tarea destacado en negrita con tipografía `Space Grotesk`.
        - Vista previa de la descripción: si tiene más de 3 líneas, muestra un extracto con el indicador `... [+ Ver más texto]` y activa la capacidad de despliegue. Si tiene 3 líneas o menos, se muestra completa directamente y la vista extendida se deshabilita.
        - Fila inferior (footer): muestra badge de subtareas si la tarea las tiene (`☑ X/Y subtareas`), badge de fecha límite amigable (`📅 Hoy`, `📅 Mañana`, `📅 15 Oct`) y flecha de acordeón solo si la expansión está disponible."
    * "Interacciones: 1 clic para expandir la descripción completa solo si sobrepasa 3 líneas; 2 clics para abrir el modal flotante de edición completa; arrastre Drag & Drop entre columnas Kanban."
*   **Instalaciones:** "N/A"
*   **Toggles:** "N/A"
