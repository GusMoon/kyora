# Arquitectura de KioraUI

Esta carpeta contiene la interfaz gráfica de Kiora, la cual está diseñada respetando los principios de **Clean Architecture y MVVM (Model-View-ViewModel)**.

## Flujo de Datos (MVVM)
1. **Views (`views/`):** Contienen únicamente lógica visual y reaccionan a las señales del ViewModel. Instancian y pintan widgets de PySide6, pero NO interactúan con la lógica del negocio.
2. **ViewModels (`viewmodels/`):** Funcionan como el cerebro de la vista. Capturan eventos del usuario emitidos por la View, actualizan el estado interno de la pantalla y se comunican con los **Casos de Uso** (ubicados en `core/voice_engine/application` o similares).
3. **Punto de Entrada (`main.py` en raíz):** Es el único archivo autorizado para instanciar tanto los ViewModels como las Views. Inyecta el ViewModel dentro de la View. Ninguna clase aquí dentro instancia sus propias dependencias complejas.

## Componentes Actuales
*   `main_window.py`: Renderiza matemáticamente mediante `paintEvent` el fondo de cuadrícula de puntos y asegura la transparencia de la ventana.
*   `main_viewmodel.py`: Controla de forma abstracta el estado principal (actualmente en su etapa base).

## Reglas Obligatorias
*   Nunca usar `time.sleep()` ni realizar bucles infinitos en el hilo de la UI.
*   Nunca agregar consultas SQL o lógica de modelo de voz (Vosk) dentro de esta carpeta.
