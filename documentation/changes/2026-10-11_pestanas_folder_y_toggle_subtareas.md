*   **Fecha y hora:** 2026-10-11 16:56:00
*   **Archivos afectados:**
    * `+ core/matrix/ecosystems/tasks/presentation/task_dialogs.py` (actualizado)
*   **Explicación breve:** "Se implementó un diseño de dos apartados en pestañas estilo solapa de carpeta (Folder Tab) en el panel izquierdo de los diálogos de tareas ('General' y 'Subtareas'), integrando un interruptor tipo píldora (Pill Toggle) para la fecha de entrega y un entorno CRUD completo para subtareas."
*   **Cambios lógicos:**
    * "Se mantuvo la restricción de que todos los archivos de `presentation` permanezcan directamente en su carpeta raíz sin ninguna subcarpeta."
    * "Creación de `FolderTabButton` y `FolderTabBar`: emulan la estética de solapa de archivador de la referencia visual (esquina superior izquierda redondeada, corte diagonal achaflanado superior derecho, títulos en negrita y subtítulos descriptivos en dos niveles de texto)."
    * "Creación de `PillToggleSwitch`: widget de interruptor interactivo inspirado en la referencia ('Enabled' cálido), con track en cápsula terracota (`#5C3424`), thumb circular en tono durazno/naranja (`#FFAA77`) al estar activo, y estados oscuros al desactivarse."
    * "Pestaña 'General': alberga el campo obligatorio de nombre de tarea, metadatos y el `PillToggleSwitch` que despliega/activa dinámicamente el selector `QDateEdit` con atajos rápidos (+1 día, +3 días, +1 semana)."
    * "Pestaña 'Subtareas': ofrece entorno CRUD completo con:
        - Create: input de nueva subtarea con botón `+ AÑADIR` y soporte para tecla `Enter`.
        - Read: barra de estadísticas (`X de Y completadas`), barra de progreso porcentual y lista scrolleable en `QScrollArea`.
        - Update: checklist interactivo reactivo, edición directa de título y nota descriptiva complementaria in-place.
        - Delete: botón `✕` con retroalimentación visual de eliminación inmediata."
*   **Instalaciones:** "N/A"
*   **Toggles:** "N/A"
