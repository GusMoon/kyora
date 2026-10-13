*   **Fecha y hora:** 2026-10-11 17:36:00
*   **Archivos afectados:**
    * `+ core/matrix/ecosystems/tasks/presentation/taskCard.py` (actualizado)
*   **Explicación breve:** "Se restauró el diseño original SciFi de TaskCard (barra de acento lateral según estado y panel de fecha vertical derecho), eliminando los badges de 'normal' y 'pendiente', manteniendo la vista previa de descripción con límite de 3 líneas y la vista expandida condicional."
*   **Cambios lógicos:**
    * "Se eliminaron todos los badges de 'Normal' y 'Pendiente' de la tarjeta."
    * "Se restableció el diseño original de Kiora:
        - Barra vertical de acento lateral izquierdo (5px) con el color de estado correspondiente (`#FFA500`, `#00BFFF`, `#00FA9A`).
        - Título de la tarea en `Space Grotesk` negrita con botón `✕` a la derecha.
        - Vista previa de la descripción debajo del título (hasta 3 líneas; si excede, muestra `... [+ Ver más]`).
        - Indicador inferior de subtareas solo si tiene (`☑ X/Y subtareas`).
        - Bloque lateral derecho SciFi para la fecha límite con día numérico grande, mes y punto de estado."
    * "Vista extendida condicionada: se activa con 1 clic únicamente si la descripción sobrepasa las 3 líneas para mostrar la descripción completa. Si tiene 3 líneas o menos, la opción de expandir permanece inhabilitada."
*   **Instalaciones:** "N/A"
*   **Toggles:** "N/A"
