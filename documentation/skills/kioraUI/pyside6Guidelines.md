---
name: PySide6 Specific Guidelines
description: Reglas y convenciones específicas al programar con PySide6 y Qt en Kiora.
version: 1.0
---

# Lineamientos Específicos para PySide6

PySide6 ofrece herramientas robustas para arquitecturas desacopladas. Su correcto uso es vital para el rendimiento de KioraUI.

## 1. Señales y Slots
*   Utiliza el sistema de **Señales y Slots** de Qt para comunicar cambios entre objetos. 
*   Esta es la base fundamental del ViewModel: cuando el estado cambia en el `ViewModel`, este emite una señal. La `View` debe estar conectada (slot) a esa señal para actualizarse de forma pasiva.
*   NUNCA actualices widgets visuales desde un hilo secundario (worker thread). Utiliza siempre una señal para enviar los datos procesados al hilo principal.

## 2. Componentes Model / View
*   Para tablas grandes, listas o árboles jerárquicos, es MANDATORIO usar `QTableView`, `QListView` o `QTreeView` en conjunto con modelos personalizados (`QAbstractTableModel`, `QAbstractListModel`).
*   No coloques cientos o miles de elementos iterando directamente en widgets como `QTableWidget` o instanciando componentes individuales. Separa los datos de su presentación.

## 3. Manejo de Tareas Asíncronas
*   Dado que Kiora interactúa con el sistema operativo y un motor de voz local (Vosk), estas tareas pesadas deben estar aisladas de la UI.
*   Utiliza `QThread` o `QRunnable` para instanciar workers en segundo plano.
*   La comunicación del progreso, estado, texto detectado o errores debe fluir estrictamente mediante señales desde el worker hacia la interfaz gráfica.
