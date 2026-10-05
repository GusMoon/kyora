# Log de Cambios: Actualización de Estilo Base

**Fecha y hora:** 2026-10-05 11:22:00

**Archivos afectados:**
*   `+ c:\proyectos\kiora\documentation\uiKit\design_system.md`
*   `* c:\proyectos\kiora\core\kioraUI\views\main_window.py`

**Explicación breve:**
Se ha actualizado el estilo visual base de la ventana principal siguiendo un nuevo patrón de diseño basado en un gris rojizo oscuro y alta densidad de malla de puntos. También se ha ocultado la barra de título nativa del sistema operativo.

**Cambios lógicos:**
En `main_window.py`:
- Se agregó `self.setWindowFlag(Qt.FramelessWindowHint)` para crear una ventana sin bordes.
- Se cambió el color de fondo a `#241A1A`.
- Se redujo el spacing de la cuadrícula de puntos a 15px.

Se creó además la documentación de `uiKit` para estandarizar futuras decisiones estéticas.

**Instalaciones:**
N/A

**Toggles:**
- Se desactivó la barra de título (`FramelessWindowHint`).
