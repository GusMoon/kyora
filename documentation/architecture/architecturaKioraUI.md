# Arquitectura de KioraUI

Esta carpeta contiene la interfaz gráfica de Kiora, la cual está diseñada respetando los principios de **Clean Architecture y MVVM (Model-View-ViewModel)**.

## Flujo de Datos (MVVM y Clean Architecture UI)
1. **Views (`views/`):** Contienen únicamente lógica visual y reaccionan a las señales del ViewModel. Instancian y pintan widgets de PySide6, pero NO interactúan con la lógica del negocio.
2. **ViewModels (`viewmodels/`):** Funcionan como el cerebro de la vista. Capturan eventos del usuario emitidos por la View, actualizan el estado interno de la pantalla y se comunican con los **Casos de Uso** (ubicados en `application/use_cases`).
3. **Application (`application/`):** Contiene los Casos de Uso específicos de la interfaz (como la lógica para orquestar la obtención del clima).
4. **Infrastructure (`infrastructure/`):** Contiene los servicios que se conectan al mundo exterior (APIs) estrictamente vinculados a KioraUI.
5. **Punto de Entrada (`main.py` en raíz):** Es el único archivo autorizado para instanciar tanto los ViewModels como las Views. Inyecta el ViewModel dentro de la View. Ninguna clase aquí dentro instancia sus propias dependencias complejas.

## Componentes Actuales
*   `views/main_window.py`: Ventana base Frameless. Renderiza matemáticamente mediante `paintEvent` el fondo de cuadrícula de puntos.
*   `viewmodels/main_viewmodel.py`: Controla de forma abstracta el estado principal.
*   `views/home/configuration.py`: Panel arrastrable de configuraciones del sistema.
*   `views/home/explorer/treeFiles.py`: Componente principal del Explorador de Archivos, maneja el árbol del disco y Quick Access.
*   `views/home/explorer/filesType/`: Directorio especializado en los visores de extensiones.
    *   `image_viewer.py`, `audio_viewer.py`, `text_viewer.py`: Heredan de la abstracción gráfica `viewer_base.py`.
*   `views/global_ui/`: Componentes universales y compartidos (Ej. abstract `viewer_base.py` y `styles.py`).

## Reglas Obligatorias
*   Nunca usar `time.sleep()` ni realizar bucles infinitos en el hilo de la UI.
*   Nunca agregar consultas SQL o lógica de modelo de voz (Vosk) dentro de esta carpeta.
