# Log de Cambios: Paneles Flotantes Arrastrables

**Fecha y hora:** 2026-10-05 15:38:00

**Archivos afectados:**
*   `* c:\proyectos\kiora\core\kioraUI\views\home\configuration.py`
*   `* c:\proyectos\kiora\core\kioraUI\views\main_window.py`

**Explicación breve:**
Se ha dotado al panel de configuración (`ConfigurationPanel`) de libertad espacial. Ahora el usuario puede arrastrar libremente el menú de configuraciones a cualquier parte de la ventana principal de Kiora, lo cual es útil si necesita interactuar con elementos que el panel tapa en el centro.

**Cambios lógicos:**
- Se sobrescribieron los eventos `mousePressEvent`, `mouseMoveEvent` y `mouseReleaseEvent` en el componente del panel para capturar la diferencia vectorial en la posición del ratón e inyectarla a la posición local de la ventana.
- **Bounding Box Restrictivo:** Se agregó una función matemática estricta (`max`/`min`) en el movimiento del panel para garantizar que nunca pueda arrastrarse más allá de los límites de `main_window`, impidiendo que el panel quede fuera del alcance en la pantalla.
- Se agregó una bandera `user_moved = True` para evitar que `resizeEvent` de `main_window.py` obligue al panel a regresar al centro si el usuario ya lo movió.

**Instalaciones:**
N/A

**Toggles:**
N/A
