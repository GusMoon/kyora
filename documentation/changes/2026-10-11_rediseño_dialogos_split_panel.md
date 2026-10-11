*   **Fecha y hora:** 2026-10-11 16:39:00
*   **Archivos afectados:**
    * `+ core/matrix/ecosystems/tasks/presentation/views/components/task_dialogs.py` (actualizado)
*   **Explicación breve:** "Se rediseñaron los modales de creación y edición de tareas bajo una arquitectura Split-Panel de dos columnas (panel izquierdo gris oscuro para inputs y panel derecho negro para descripciones extensas con scroll)."
*   **Cambios lógicos:**
    * "Se respetó la restricción de no crear nuevas carpetas dentro de `presentation`."
    * "En `TaskCreateDialog` y `TaskDetailDialog`, se transformó el layout a dos paneles horizontales proporcionales (45% izquierda / 55% derecha) inspirados en el diseño de tarjeta técnica de la referencia visual."
    * "Panel izquierdo (`#1C1C1C`): alberga cabecera con indicador de arrastre movible, campo de nombre de tarea, selector de fecha de entrega, sección scrolleable de subtareas y botones de acción (`GUARDAR`, `CANCELAR`, `ELIMINAR TAREA`)."
    * "Panel derecho (`#0A0A0A` con borde `#282828`): contenedor dedicado para descripciones extensas con tipografía `Space Grotesk`, padding generoso y scrollbar vertical automático que se activa si el texto excede la altura."
    * "Se mantuvieron todas las propiedades flotantes y arrastrables por pantalla en `SciFiBaseModal`."
*   **Instalaciones:** "N/A"
*   **Toggles:** "N/A"
