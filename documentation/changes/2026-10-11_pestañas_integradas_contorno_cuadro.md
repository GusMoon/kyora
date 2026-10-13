*   **Fecha y hora:** 2026-10-11 17:03:00
*   **Archivos afectados:**
    * `+ core/matrix/ecosystems/tasks/presentation/task_dialogs.py` (actualizado)
*   **Explicación breve:** "Se unificaron las pestañas del panel izquierdo para que formen parte del contorno superior del cuadro (Folder Container), eliminando el anidamiento interior y logrando que la pestaña activa y el cuerpo del contenedor compartan una superficie continua e indivisa."
*   **Cambios lógicos:**
    * "Se implementó `FolderContainer` con trazado perimetral dinámico vía `QPainterPath`, donde la solapa activa ('General' o 'Subtareas') sobresale como el borde superior real del cuadro, compartiendo el mismo fondo `#1C1C1C` y borde `#333333` sin líneas divisorias entre la pestaña y el interior."
    * "La solapa inactiva se dibuja adyacente en segundo plano (`#141414`), con detección de hover interactiva y cambio suave al hacer clic."
    * "Se extrajo el encabezado del modal a una barra superior unificada de ventana (`window_header`), con el título y tag de estado a la izquierda (draggable para mover el modal por la pantalla) y botón de cierre `✕` a la derecha."
    * "Se preservó el interruptor cálido tipo píldora (`PillToggleSwitch`) para la activación opcional de fecha de entrega, el entorno CRUD completo para subtareas y el panel derecho para textos y notas extensas con scroll."
*   **Instalaciones:** "N/A"
*   **Toggles:** "N/A"
