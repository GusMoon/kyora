# Log de Cambios: Estética Azul Sci-Fi

**Fecha y hora:** 2026-10-06 08:42:00

**Archivos afectados:**
*   `core/kioraUI/views/main_window.py`
*   `core/kioraUI/views/global_ui/base_container.py`
*   `core/kioraUI/views/global_ui/custom_dialogs.py`
*   `core/kioraUI/views/global_ui/styles.py`
*   `core/kioraUI/views/home/configuration.py`
*   `core/kioraUI/views/home/explorer/treeFiles.py`
*   `core/kioraUI/views/home/explorer/filesType/audio_viewer.py`
*   `core/kioraUI/views/home/explorer/filesType/image_viewer.py`
*   `core/kioraUI/views/home/explorer/filesType/pdf_viewer.py`
*   `core/kioraUI/views/home/explorer/filesType/text_viewer.py`

**Explicación breve:** 
Se reemplazó el color de acento de la interfaz gráfica (Rojo Vino / Naranja) por una paleta Azul Sci-Fi con matices cyan y bordes brillantes a petición del usuario.

**Cambios lógicos:**
- Se cambió el color primario estático `#D96600` por `#4D94FF`.
- Se cambió el color de acento/hover `#D48800` por `#80BFFF`.
- Se cambiaron todas las representaciones RGBA `rgba(217, 102, 0, x)` por `rgba(77, 148, 255, x)`.

**Instalaciones:** 
N/A

**Toggles:** 
N/A
