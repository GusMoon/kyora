# Log de Cambios: Creación de UI Base

**Fecha y hora:** 2026-10-05 11:15:00

**Archivos afectados:**
*   `+ c:\proyectos\kiora\requirements.txt`
*   `+ c:\proyectos\kiora\main.py`
*   `+ c:\proyectos\kiora\core\kioraUI\views\main_window.py`
*   `+ c:\proyectos\kiora\core\kioraUI\viewmodels\main_viewmodel.py`
*   `+ c:\proyectos\kiora\core\kioraUI\ARCHITECTURE.md`

**Explicación breve:**
Se ha creado la estructura inicial para la interfaz gráfica utilizando PySide6. La ventana principal tiene ahora un fondo oscuro (`#373047`) renderizado eficientemente usando `paintEvent`, con una cuadrícula de puntos decorativos y una opacidad en toda la ventana del 97% (3% de transparencia).

**Cambios lógicos:**
Se ha implementado el patrón MVVM y Clean Architecture como fue solicitado. El `main.py` actúa como inyector de dependencias, creando la `MainViewModel` (capa lógica de UI) y pasándoselo al `MainWindow` (capa de presentación pura).

**Instalaciones:**
Ninguna nueva requerida, PySide6 ya estaba instalado en el entorno. Se creó el `requirements.txt` con la declaración `PySide6`.

**Toggles:**
N/A
