*   **Fecha y hora:** `2026-10-08 16:49:00`
*   **Archivos afectados:** Directorio `core/kioraUI/` y todos sus archivos `.py` dependientes, además de `main.py`.
*   **Explicación breve:** Se refactorizó masivamente la estructura de la interfaz gráfica y su nomenclatura.
*   **Cambios lógicos:** 
    *   Renombre de `core/kioraUI` a `core/matrix`.
    *   Renombre de `core/matrix/views` a `core/matrix/ecosystems`.
    *   Renombre de `core/matrix/ecosystems/global_ui` a `core/matrix/ecosystems/motherBoard`.
    *   La carpeta `home` fue eliminada y todo su contenido (como `explorer`, `youtube_music`, etc.) fue extraído directamente hacia `core/matrix/ecosystems/`.
    *   Se ejecutó un script de actualización masiva que corrigió automáticamente las rutas de importación en todos los archivos `.py` para evitar que el programa se corrompa.
*   **Instalaciones:** Ninguna
*   **Toggles:** N/A
