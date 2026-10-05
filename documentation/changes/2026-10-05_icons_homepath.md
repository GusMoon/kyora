# Log de Cambios: Iconos Rediseñados y Home Path

**Fecha y hora:** 2026-10-05 16:03:00

**Archivos afectados:**
*   `* c:\proyectos\kiora\documentation\uiKit\designSystem.md`
*   `* c:\proyectos\kiora\core\kioraUI\views\home\explorer.py`

**Explicación breve:**
Se ha mejorado visualmente el reconocimiento del explorador de archivos, inyectando colores representativos (Amarillo y Gris) pero manteniendo la estética minimalista y programática. También se configuró la carpeta del Usuario como punto de inicio por defecto.

**Cambios lógicos:**
- **Punto de Inicio por Defecto (`homePath`):** El explorador ahora resuelve mediante `QDir.homePath()` el directorio del usuario de Windows (Escritorio, Documentos, Descargas, etc.) para que se visualice por defecto, en lugar de mostrar el aburrido root de las unidades de disco.
- **Iconos (Yellow & Gray):** El `SciFiIconProvider` fue reescrito para utilizar primitivas de relleno (`QBrush`). 
  - Las carpetas usan el tono Amarillo Sci-Fi (`#E8B923`) y dibujan una forma de carpeta clásica pero afilada.
  - Los archivos usan un tono Gris (`#A0A0A0`) con una esquina superior doblada en gris claro y pequeñas líneas negras simulando líneas de código o texto.
- Todo esto fue oficializado en la documentación de Kit de UI.

**Instalaciones:**
N/A

**Toggles:**
N/A
