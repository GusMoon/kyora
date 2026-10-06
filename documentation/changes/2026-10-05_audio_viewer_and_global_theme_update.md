# Actualización: Visor de Audio Avanzado y Nuevo Tema Espacial
**Fecha:** 2026-10-05

## 1. Modificación Global de Paleta de Colores (Theme Refactor)
Se aplicó un cambio radical a nivel de toda la aplicación (global), abandonando la paleta "Vino Tinto/Rojo" original por una estética de "Holograma Naranja Espacial" inspirada en visores ópticos.
- **Fondos oscuros (`#1E1E1E`, `#161616`)** fueron reemplazados por un Azul Espacial Profundo (`#0A1118`, `#060A0F`).
- **Acentos Rojos (`#A31F34`, `#7A1727`)** fueron sustituidos por un Naranja Quemado/Cobre (`#D96600`, `#FFAA00`).
- **Bordes oscuros (`#3A2326`)** pasaron a ser azules acorazados o marrones oscuros (`#182533`).
Estos reemplazos afectaron a todos los paneles: configuraciones, explorador, reproductor de música, y visores (texto, imagen, pdf).

## 2. Mejoras al Menú Radial y Overlays (`custom_dialogs.py`)
- **Fondo Desenfocado Inteligente (Blur Effect)**: Se integró `QGraphicsBlurEffect` apuntando estrictamente al `viewport()` del widget hijo. Esto logra que cuando se despliega el menú radial, la lista de archivos o código se vuelva borrosa, pero los **bordes exteriores del panel principal se mantengan totalmente nítidos**.
- **Centrado Absoluto**: El menú radial ahora ignora la posición del ratón e intercepta dinámicamente el centro (`width // 2`, `height // 2`) del panel padre para mostrarse siempre en el medio geométrico exacto de la pantalla.
- **Escala de Botones y Textos**: Se incrementó drásticamente el tamaño del hexágono y se añadió la funcionalidad de renderizar de manera visible el nombre de la acción ("EDIT", "COPY", "DELETE") debajo de cada icono.

## 3. Reescritura del Reproductor de Audio (`audio_viewer.py`)
- **Desacoplamiento Base**: El `AudioViewerPanel` dejó de heredar de `SciFiViewerBase`. Se reestructuró como `AudioPlayerWidget` (un QWidget independiente) sin bordes globales de ventana, integrándose de forma flotante en la esquina inferior izquierda de `main_window.py`.
- **Motor de Audio Nativo**: Se conectó a `PySide6.QtMultimedia` (`QMediaPlayer`, `QAudioOutput`) para reproducir verdaderamente el archivo `.mp3`, `.wav`, etc., permitiendo pausar y alterar el tiempo real.
- **SciFiAudioWaveTimeline (Barra de Progreso Holográfica)**:
  - Se eliminó el `QSlider` estándar en favor de un renderizador vectorial (`QPainter`) completamente personalizado.
  - Consta de una **línea punteada** con anclajes circulares, y un **cabezal de reproducción luminoso**.
  - **Ondas Matemáticas Sensibles**: De fondo, dibuja ondas senoidales entrelazadas. Detectan algoritmicamente las crestas y valles para dibujar nodos (círculos huecos), mimetizándose idénticamente a las referencias de diseño de Kiora.
  - **Reacción Caótica (Espectro Falso)**: En lugar de analizar el FFT nativo de la canción (el cual no está disponible puramente en PySide6 moderno), cada onda tiene una memoria independiente de su `target_amp` y `current_amp`. Mediante ráfagas rítmicas pseudoaleatorias por onda (con un temporizador a 30 FPS), las ondas suben y bajan creando un efecto audiovisual altísimamente orgánico e individual.
- **Escalabilidad Visual**: La UI del reproductor se expandió a un área mayor (500x140) para acomodar iconos más gruesos y textos expansivos.
