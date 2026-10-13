*   **Fecha y hora:** 2026-10-11 17:40:00
*   **Archivos afectados:**
    * `+ core/matrix/ecosystems/tasks/presentation/taskCard.py` (actualizado)
*   **Explicación breve:** "Se corrigió el error de estiramiento vertical del TaskCard asignando una altura definida y fija como antes (65px sin descripción / 88px con descripción), evitando que el card ocupe todo el alto del contenedor."
*   **Cambios lógicos:**
    * "Se asignó `self.setFixedHeight(self.base_height)` en `taskCard.py` (65px para tareas sin descripción y 88px para tareas con descripción previa y subtareas)."
    * "Se fijó la altura de `compact_widget` y `date_frame` a `self.base_height` para mantener proporciones perfectas idénticas al diseño original de Kiora."
    * "Al alternar la vista extendida (`toggle_expand`), la altura pasa a `self.base_height + 80px` y regresa con precisión a `self.base_height` al colapsar."
*   **Instalaciones:** "N/A"
*   **Toggles:** "N/A"
