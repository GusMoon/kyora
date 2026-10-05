# Log de Cambios: Quick Access y Generación de File Viewers

**Fecha y hora:** 2026-10-05 16:11:00

**Archivos afectados:**
*   `+ c:\proyectos\kiora\core\kioraUI\views\global_ui\viewer_base.py`
*   `+ c:\proyectos\kiora\core\kioraUI\views\home\image_viewer.py`
*   `+ c:\proyectos\kiora\core\kioraUI\views\home\audio_viewer.py`
*   `+ c:\proyectos\kiora\core\kioraUI\views\home\text_viewer.py`
*   `* c:\proyectos\kiora\core\kioraUI\views\home\explorer.py`
*   `* c:\proyectos\kiora\core\kioraUI\views\main_window.py`

**Explicación breve:**
Se ha desarrollado la funcionalidad de inicio rápido (Quick Access) con carpetas del sistema, navegación y la inyección de visores especializados de archivos (Audio, Imagen, Texto). Todo respeta la herencia Sci-Fi estipulada en Kiora.

**Cambios lógicos:**
- **Explorer Quick Access:** `explorer.py` arranca ahora inyectando un modelo de datos plano (`QStandardItemModel`) poblado con las rutas de Escritorio, Documentos, Imágenes, etc., extraídas universalmente usando `QStandardPaths`.
- **Navegación:** Se agregaron botones retrofuturistas de `BACK` y `HOME` para moverse por las carpetas del explorador con clicks en un modelo jerárquico.
- **Creación de Viewers:** 
  - Para ahorrar código y respetar DRY, se creó una superclase `SciFiViewerBase` (`viewer_base.py`) que tiene toda la lógica de los paneles superpuestos, la barra roja, el "X" de cierre y la matemática para arrastrar los paneles con el mouse.
  - Se generaron 3 archivos que heredan de este panel: `image_viewer.py`, `audio_viewer.py` y `text_viewer.py`, inyectando sus correspondientes widgets y lógicas para abrir archivos reales.
- **Orquestación:** `main_window.py` escucha si un archivo recibe "doble clic", lee su extensión, decide cuál visor invocar y le pasa la ruta local.
- Todas las tareas del checklist C fueron marcadas con `[x]`.

**Instalaciones:**
N/A

**Toggles:**
N/A
