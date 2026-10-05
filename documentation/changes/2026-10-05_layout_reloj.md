# Log de Cambios: Reorganización del Reloj y Clima

**Fecha y hora:** 2026-10-05 11:42:00

**Archivos afectados:**
*   `* c:\proyectos\kiora\core\kioraUI\views\main_window.py`
*   `* c:\proyectos\kiora\documentation\uiKit\designSystem.md`

**Explicación breve:**
Se ha ajustado el panel de información (reloj, fecha y clima) para que ocupe menos espacio visual. Se reubicó en la esquina superior derecha, inmediatamente al lado del botón de cierre. Adicionalmente, el color de acento se modificó de Cyan a un Azul Brillante (`#3399FF`) para todo el sistema, dándole una apariencia más pulida.

**Cambios lógicos:**
- Modificación del Layout: Se encapsularon los `QLabel` informativos dentro de un `QVBoxLayout` alineado a la derecha (`Qt.AlignRight | Qt.AlignTop`) y se integró dentro del layout superior (`top_layout`) junto con un espaciador.
- Reducción drástica del tamaño de fuente (`150px` -> `56px` para la hora, y `24px` -> `14px` para la fecha).
- Actualización del esquema de colores en la documentación del `uiKit`.

**Instalaciones:**
N/A

**Toggles:**
N/A
