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

### Segunda Fase del Refactor (Back-end)
*   **Archivos afectados:** Directorios `core/ecosistema` y `core/ecosystems`.
*   **Cambios lógicos:** 
    *   Se crearon las carpetas `studio` y `settings` y se movieron dentro de `core/matrix/ecosystems/`.
    *   Se movió la lógica del ecosistema de música (`core/ecosystems/music/*`) hacia `core/matrix/ecosystems/studio/`.
    *   Se movió el archivo del ecosistema del explorador (`file_system_ecosystem.py`) hacia `core/matrix/ecosystems/explorer/`.
    *   Se reubicó el archivo de configuración `mp3installer_config.json` (desde `core/ecosistema/config/`) hacia `core/matrix/ecosystems/`.
    *   Se actualizaron internamente las rutas y las importaciones relativas en `youtube_music.py`, `treeFiles.py` y `mp3installer.py` para asegurar que el sistema encuentre correctamente los nuevos destinos.
    *   Se eliminaron definitivamente los antiguos directorios `core/ecosistema` y `core/ecosystems` ya que estaban vacíos.

### Tercera Fase del Refactor (MotherBoard y RootView)
*   **Archivos afectados:** `core/matrix/ecosystems/main_window.py` y componentes en `motherBoard`.
*   **Cambios lógicos:**
    *   Se renombró `main_window.py` a `rootView.py`.
    *   Se crearon las subcarpetas `globalComponents` y `rootComponents` dentro de `motherBoard`.
    *   Se separaron los componentes moviendo `styles.py`, `base_container.py`, `viewer_base.py` y `simple_dialogs.py` hacia `globalComponents`.
    *   Se movió `top_navigation_bar.py` hacia `rootComponents`.
    *   Se corrió un script de actualización global que ajustó todas las importaciones en 9 archivos `.py` (`main.py`, `configuration.py`, etc.) hacia las nuevas rutas.
