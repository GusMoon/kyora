# Cambio Global de Tema: Azul Holográfico Sci-Fi

**Fecha:** 2026-10-07

## Resumen
Se actualizó toda la paleta de colores de la aplicación Kiora para adoptar un estilo de "Holograma Sci-Fi", reemplazando el antiguo azul primario (`#4D94FF`) y adoptando tonos cyan brillantes y oro pálido para resaltar los contrastes.

## Cambios Principales

1. **Color Primario (Acento Global):**
   - Se reemplazó el color primario anterior `#4D94FF` en toda la aplicación (excepto el fondo principal) por un azul cyan holográfico brillante: `#00E5FF`.
   - Se actualizó también su versión en rgba a `rgba(0, 229, 255)`.
   - Esto afecta todas las vistas, botones, bordes de ventanas, navegadores, pestañas musicales y contornos de carpetas.

2. **Números e Índices:**
   - Para generar un fuerte contraste sci-fi con los tonos fríos, los números de índice de las listas de archivos y carpetas ahora usan un color amarillo/dorado casi blanquecino: `#FFF2B2`.

3. **Fondos de Carpetas (Explorer):**
   - El relleno de las carpetas en el `ExplorerDelegate` se modificó para usar un tono azul puro y translúcido (`rgba(0, 80, 255, 60)`), el cual se vuelve más intenso (`rgba(0, 150, 255, 140)`) al seleccionarse, brindando una estética de volumen y luz sobre el fondo ultra-oscuro de la app.

## Archivos Afectados
El color se modificó mediante reemplazo global en los siguientes componentes principales:
- `main_window.py`
- `global_ui/base_container.py`
- `global_ui/simple_dialogs.py`
- `global_ui/top_navigation_bar.py`
- `home/configuration.py`
- `home/youtube_music.py`
- Componentes del Explorer (`treeFiles.py`, `explorer_delegate.py`, `sidebar_delegate.py`)
- Múltiples visores de archivos (`audio_viewer.py`, `image_viewer.py`, `pdf_viewer.py`, `task_viewer.py`, `text_viewer.py`)
