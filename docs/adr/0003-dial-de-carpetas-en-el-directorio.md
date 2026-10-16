# 0003. El dial de carpetas vive en el directorio, no en el reactor

* Estado: aceptado
* Reemplaza a: [0002](0002-reactor-como-dial-de-carpetas.md)
* Fecha: 2026-10-16

## Contexto y problema
El ADR 0002 hizo que el reactor aceptara listas de opciones (`wrap=False`) y dibujara los
nombres de las carpetas. Eso metió en un componente global lógica propia del directorio
(listas largas, hueco de anillos, gestos de lista, carpetas), con ramas `wrap` por todo
el reactor.

## Decisión
* El reactor vuelve a ser solo el navegador de módulos. Gana dos capacidades genéricas:
  `set_pinned` (tamaño completo, sin menú) y `set_gaps` (zonas libres de dibujo).
* El directorio es dueño de su navegación: `FolderDial` (en `rootDirectory.py`) es un
  widget transparente sobre el reactor que escribe y gira los nombres, y le pasa los
  huecos por señal. `ContentPanel` (`components/contentPanel.py`) muestra migas, título y
  tarjetas, y `RootDirectory` guarda el nivel de carpetas y los une.
* Los iconos de carpeta y archivo viven en `core/resources/icons/files/`.

Se mantiene del ADR 0002 que el reactor reposa reducido y crece al pasar el cursor, y que
en el directorio queda con su centro en el borde derecho.

## Consecuencias
* Un módulo con navegación propia pone su componente encima del reactor fijado en lugar de
  añadir modos al reactor.
* Reactor y dial comparten el tamaño del círculo mediante `unit()` y el reactor ya no
  conoce las carpetas.
