# Guía de Ejecución de KioraUI

Para levantar la interfaz gráfica de Kiora, debes ejecutar siempre el punto de entrada principal del sistema (`main.py`) desde la raíz del proyecto. No ejecutes los archivos internos de `kioraUI` de manera aislada, ya que `main.py` es el encargado de resolver las rutas, ensamblar las dependencias (ViewModels) y conectar la arquitectura correctamente.

## Pasos para ejecutar:

1. **Abre tu terminal** (PowerShell) y ubícate en la raíz del proyecto:
   ```powershell
   cd c:\proyectos\kiora
   ```

2. **Activa el entorno virtual** donde instalamos PySide6:
   ```powershell
   .\.venv\Scripts\Activate.ps1
   ```
   *(Verás que tu terminal muestra `(.venv)` indicando que el entorno está activo).*

3. **Ejecuta el archivo principal:**
   ```powershell
   python main.py
   ```

## Solución de problemas frecuentes

*   **Error: `ModuleNotFoundError: No module named 'core'`**
    Asegúrate de estar ejecutando `python main.py` exactamente desde `c:\proyectos\kiora` y no desde subcarpetas.
*   **Error: `No module named 'PySide6'`**
    Significa que olvidaste activar el entorno virtual en el paso 2 o no se instalaron las dependencias. Puedes reinstalarlas corriendo `pip install -r requirements.txt`.
