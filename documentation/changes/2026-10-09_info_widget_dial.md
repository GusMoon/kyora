*   **Fecha y hora:** 2026-10-09 10:47:00
*   **Archivos afectados:** 
    * `* core/matrix/ecosystems/explorer/rootComponents/internal/widget.py`
*   **Explicación breve:** "Se implementó un dial rotatorio (estilo perilla) para el InfoWidget."
*   **Cambios lógicos:** "Se agregó física de arrastre (drag & drop radial) usando `math.atan2` y un `QTimer` para crear una rotación fluida con auto-snap (alineación automática al incremento de 90° más cercano). El panel central ahora evalúa en tiempo real cuál opción (`clock`, `weather`, `config`, `close`) está en la parte inferior (a los 90° relativas al centro) y reemplaza su contenido de texto. Se añadió un efecto de haz de luz (`QLinearGradient`) indicando la selección activa."
*   **Instalaciones:** "N/A"
*   **Toggles:** "N/A"
