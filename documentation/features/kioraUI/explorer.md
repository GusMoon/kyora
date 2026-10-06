# Kiora File Explorer Features

Esta documentación describe las funciones y capacidades implementadas en el módulo explorador de archivos (`ExplorerPanel` / `treeFiles.py`) de Kiora.

## 1. Navegación Básica y Vistas
- **Quick Access / Home**: Vista inicial que agrupa accesos directos a las carpetas principales del sistema (Escritorio, Descargas, Documentos, Imágenes, Música, Videos y "Este equipo").
- **Barra de Navegación (Address Bar)**: Barra superior editable que muestra la ruta actual. Permite escribir directamente una ruta para navegar hacia ella. Soporta autocompletado en tiempo real de directorios del sistema operativo (`QCompleter`).
- **Navegación Intuitiva**: El usuario puede entrar a las carpetas con un solo clic.

## 2. Visibilidad y Diseño Sci-Fi
- **Estética Inmersiva**: El explorador utiliza la clase `KioraBaseContainer` ofreciendo fondos oscuros (glassmorphism transparente), bordes rojo-vino, barra de arrastre y redimensionamiento dinámico desde las esquinas.
- **Columnas Inteligentes**: La columna del "Nombre" de los archivos se auto-ajusta siempre al contenido sin truncarse. La columna de "Tipo" se comprime y ajusta dinámicamente como información secundaria.
- **Iconografía**: Incluye un proveedor de iconos personalizado (`SciFiIconProvider`) que dibuja carpetas amarillo-anaranjado y archivos gris-futurista de manera nativa sin usar recursos de imágenes externas.

## 3. Radial Context Menu (Menú Hexagonal)
En lugar de un clásico menú de lista de Windows, el explorador de archivos integra un menú futurista de tipo overlay (`RadialContextMenu`).
- **Diseño Hexagonal**: Al dar clic derecho, aparece un panel oscuro translúcido. Un botón central de "Cancelar" se conecta a través de líneas con nodos hexagonales ubicados radialmente a su alrededor, simulando una interfaz de ciencia ficción.
- **Efecto de Desenfocado (Blur)**: Cuando el menú se abre, el árbol de archivos (QTreeView) en el fondo aplica inmediatamente un `QGraphicsBlurEffect` para perder foco visual y destacar el menú, revirtiéndose al cerrarse.
- **Opciones Operativas**: Los nodos te permiten realizar acciones como `New Folder`, `New File`, `Rename` y `Delete`.

## 4. Diálogos Kiora Nativos (Modales)
Los ingresos de texto y alertas (tradicionalmente renderizados con formularios por defecto de Windows como `QInputDialog` o `QMessageBox`) han sido reemplazados por componentes propios (`SciFiInputDialog` y `SciFiConfirmDialog`).
- **Aspecto**: Modales asíncronas con estilo Kiora (fuentes futuristas, bordes marcados en rojo vino `A31F34`, fondo oscuro).
- **Inmersión**: Estas modales, al igual que el menú radial, actúan como un overlay que nubla (blur) la ventana trasera para forzar la interacción sin romper la estética del entorno Kiora.

## 5. Integración con Visores
Al hacer clic sobre un archivo (en lugar de una carpeta), el explorador emite la señal `file_opened(str)`. Esta señal es capturada por la vista principal para lanzar automáticamente visores especializados de acuerdo al tipo de archivo (Visor de Imágenes, Visor de Audio, Visor de Código/Texto), los cuales también respetan los estándares de UI de Kiora y heredan de `KioraBaseContainer`.
