*   **Fecha y hora:** 2026-10-10 11:08:00
*   **Archivos afectados:** 
    * `+ core/matrix/ecosystems/tasks/presentation/views/components/task_card.py` (reescrito)
    * `+ core/matrix/ecosystems/tasks/presentation/views/tasks_view.py` (reescrito)
    * `+ core/matrix/ecosystems/tasks/domain/entities.py` (actualizado)
    * `+ core/matrix/ecosystems/tasks/infrastructure/repositories.py` (actualizado)
    * `+ core/matrix/ecosystems/tasks/presentation/viewmodels/tasks_viewmodel.py` (actualizado)
    * `+ core/matrix/ecosystems/rootView.py` (actualizado)
    * `+ core/matrix/ecosystems/global_config.json` (renombrado de mp3installer_config.json)
    * `+ core/matrix/ecosystems/studio/mp3installer.py` (actualizado)
    * `+ core/matrix/ecosystems/youtube_music.py` (actualizado)
*   **Explicación breve:** "Se integró el nuevo panel de tareas flotante, transparente y en escala de grises. Se añadió soporte de Markdown, diálogo de creación y Drag and Drop para tarjetas."
*   **Cambios lógicos:** 
    * "El repositorio ahora lee y escribe archivos `.task` en formato Markdown (compatible con `task_viewer.py`) en vez de JSON puro."
    * "Se unificó la configuración bajo `global_config.json`."
    * "Se añadió lógica de `QDrag` en `TaskCard` y recepción de drops en columnas de `tasks_view.py`."
    * "El panel ya no es un `KioraBaseContainer`, ahora es un QWidget sin bordes anclado en `(15, 15)` de la pantalla."
*   **Instalaciones:** "N/A"
*   **Toggles:** "N/A"
