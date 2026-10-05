# Log de Cambios: Iconos Vectoriales Sci-Fi y Scrollbar Minimalista

**Fecha y hora:** 2026-10-05 15:58:00

**Archivos afectados:**
*   `+ c:\proyectos\kiora\core\kioraUI\views\global\styles.py`
*   `* c:\proyectos\kiora\core\kioraUI\views\home\explorer.py`

**Explicación breve:**
Se refinaron los componentes del explorador de archivos para alejarlos de la estética nativa y acercarlos más al diseño temático. Se crearon scrollbars estéticos y se reemplazaron los iconos de carpetas estándar por versiones dibujadas matemáticamente.

**Cambios lógicos:**
- **Scrollbar Global (`styles.py`):** Se creó una función inyectora de estilo que oculta las barras de desplazamiento antiestéticas por unas líneas rojas finas y elegantes sin flechas, compartible con toda la app.
- **SciFi Icon Provider (`explorer.py`):** Se sobreescribió el motor nativo de iconos del sistema operativo (`QFileIconProvider`). En su lugar, el sistema ahora dibuja usando vectores `QPainter` unos íconos geométricos minimalistas en color rojo vino y gris (directorios vs archivos).
- **Reducción Analítica:** Se ocultaron las columnas de Fecha y Tamaño para cumplir con la orden de minimalismo extremo (Nombre y Tipo únicamente).
- Se desactivó el ordenamiento clickeable en el Header.

**Instalaciones:**
N/A

**Toggles:**
N/A
