# Log de Cambios: Rediseño del Módulo Explorador (SciFi HUD)

**Fecha y hora:** 2026-10-06 08:58:00

**Archivos afectados:**
*   `core/kioraUI/views/home/explorer/treeFiles.py`
*   `core/kioraUI/views/main_window.py`

**Explicación breve:**
Se reconstruyó el módulo del explorador de archivos para adaptarlo visualmente a un menú estilo HUD holográfico, integrándolo orgánicamente en la ventana principal.

**Cambios lógicos:**
- Se eliminó la herencia de `KioraBaseContainer` en `ExplorerPanel`, quitando la cabecera roja y los bordes para usar `QWidget` con fondo transparente.
- En `main_window.py` se cambió la posición del panel, anclándolo ahora fijamente en la esquina superior izquierda `(40, 80)` y excluyéndolo del sistema automático de centrado de ventanas flotantes.
- En `treeFiles.py` se implementó la clase `SciFiItemDelegate` (un `QStyledItemDelegate` personalizado) para sobreescribir el método `paint` en `QTreeView`. Ahora la lista se dibuja utilizando formas geométricas (`QPainterPath`) con esquinas anguladas, incluye marcadores de flecha interactivos (`▶`) y números de índice a la derecha (`01`, `02`, etc), imitando fielmente la imagen de referencia.
- Se ajustaron opacidades, separaciones de texto y colores (brillo cyan y azul) para destacar los elementos sobre el fondo oscuro.
- Se configuró el delegado para ocultar la flecha en las carpetas principales (sidebar).
- Se redujo el tamaño de fuente (de 11 a 9) para que quepan los nombres largos en el menú izquierdo.
- Se implementó que un solo clic expanda la carpeta (estilo árbol) y dos clics naveguen hacia adentro de la carpeta, proporcionando una mejor navegación.
- Se eliminaron las flechas nativas (branches) del QTreeView mediante CSS y se removió la línea verde de focus (outline).
- Se rediseñó el componente a un estilo "Deathmatch": eliminando el icono de carpeta nativo, añadiendo una barra gruesa gris a la izquierda y bordes luminosos con la flecha Sci-Fi para expansión interactiva.
- Se ajustó el `explorer_panel` en `main_window.py` para estirarse automáticamente hasta el 100% de la pantalla hacia abajo.
- Se activó `ScrollPerPixel` para fluidez y se codificó un increíble efecto "Ruleta 3D" en `paintEvent`, modificando la opacidad y escalado basado en coseno para simular profundidad conforme se esconden los archivos.
- Se refinó el efecto 3D para que sea mucho más sutil y funcional: ahora solo afecta el 5% de los márgenes superior e inferior (cuando los elementos están por desaparecer), manteniendo la zona central al 100% para evitar perjudicar la lectura.
- Se desactivó el efecto 3D en la barra de Acceso Rápido (carpetas principales) para que siempre permanezcan fijas.
- Se forzó el CSS de PySide6 para aplastar el estilo de color verde nativo por defecto en ítems seleccionados que contaminaba el diseño holográfico.
- Se implementó discriminación de archivos/carpetas en el delegado (`isDir()`): las carpetas conservan la flecha expansora, mientras que los archivos muestran el `QIcon` (texto, pdf, imagen, etc).
- Se transformó la animación de ocultamiento en los bordes: ahora aplica un vector de traslación horizontal negativo, dando la sensación mecánica de que el archivo se "guarda" o se "desliza por detrás" en lugar de solo hacerse transparente.
- Se reemplazó completamente el sistema de alertas gigantes (RadialContextMenu y diálogos overlay) por un diseño nativo encapsulado: menú contextual estándar, y clases `SciFiInputDialog` y `SciFiConfirmDialog` basadas en `QDialog` sin bordes y estilo holográfico de Kiora para mantener la coherencia gráfica.

**Instalaciones:**
N/A

**Toggles:**
N/A
