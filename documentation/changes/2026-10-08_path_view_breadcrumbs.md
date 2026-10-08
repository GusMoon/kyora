*   **Fecha y hora:** `2026-10-08 16:20:00`
*   **Archivos afectados:** 
    *   `+ core/kioraUI/views/home/explorer/components/path_view.py`
    *   `* core/kioraUI/views/home/explorer/treeFiles.py`
*   **Explicación breve:** Se ha implementado un nuevo diseño en forma de pestañas (Breadcrumbs) para la ruta del explorador.
*   **Cambios lógicos:** 
    *   Se creó el componente `PathView` que inyecta cada carpeta de la ruta como un `QPushButton` independiente dentro de un `QScrollArea`.
    *   Se reemplazaron los botones "HOME" y " / " en `treeFiles.py` por la integración del nuevo componente `PathView`, conectando los eventos al método `go_to_path`.
    *   Se implementó auto-scroll a la derecha cuando se cambian las rutas.
    *   Se interceptó el evento `wheelEvent` en el `QScrollArea` para convertir los movimientos de la rueda en desplazamiento horizontal fluido.
*   **Instalaciones:** Ninguna
*   **Toggles:** N/A

### Actualización Posterior
*   **Archivos afectados:** `+ core/kioraUI/views/home/explorer/treeFiles.py` y `path_view.py`
*   **Cambios Lógicos Extras:**
    *   Se arregló el bug donde los discos aparecían duplicados en la lista de archivos al estar en "Este equipo" (`FileProxyModel`).
    *   Se redujo el espaciado entre pestañas (`spacing = -10`) para que estén casi tocándose, logrando una barra continua inmersiva.
    *   Se implementó la clase `FadeOverlay` con animación de opacidad, lo que proyecta sombras laterales sobre el `QScrollArea` **exclusivamente** durante 800ms al detectar cualquier desplazamiento (scroll), brindando un efecto moderno de desaparición dinámica.
