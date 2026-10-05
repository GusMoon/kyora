# Log de Cambios: Extracción y rediseño Sci-Fi del Configuration Panel

**Fecha y hora:** 2026-10-05 15:35:00

**Archivos afectados:**
*   `+ c:\proyectos\kiora\core\kioraUI\views\home\configuration.py`
*   `* c:\proyectos\kiora\core\kioraUI\views\main_window.py`

**Explicación breve:**
Se ha refactorizado la vista principal, extrayendo el panel de configuración hacia su propia clase y archivo dentro de una nueva jerarquía `views/home`. Adicionalmente, el diseño del panel se modificó para que asimile una interfaz Sci-Fi similar a la referencia ("File Transfer Sequence").

**Cambios lógicos:**
- **Refactorización modular:** Se creó la carpeta `home` para ir introduciendo los componentes que conforman la pantalla central de Kiora. El primero en habitarla es `configuration.py`.
- **Diseño del Panel (`ConfigurationPanel`):** 
  - Se dividió en un `<header>` (Barra de título rojo vino sólido, letras blancas en negrita esparcidas y botón de cierre nativo).
  - Se dividió en un `<body>` con fondo oscuro (`#161616`) y la lista de opciones.
  - La lista (`QListWidget`) ahora posee bordes izquierdos rojos interactivos (`border-left`) y fondos semitransparentes cuando se selecciona un elemento, imitando una consola de mando tecnológica.

**Instalaciones:**
N/A

**Toggles:**
N/A
