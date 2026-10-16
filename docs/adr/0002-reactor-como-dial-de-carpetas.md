# 0002. El reactor como dial de carpetas, en reposo reducido

* Estado: aceptado
* Reemplaza a: [0001](0001-reactor-como-navegacion-unica.md)
* Fecha: 2026-10-15

## Contexto y problema
El ADR 0001 hizo del reactor la navegación del directorio, pero con el anillo de iconos
de los módulos: las carpetas solo se distinguían por el nombre del núcleo y se perdía la
lectura de lista que daba el semicírculo anterior. Además el reactor a tamaño completo en
reposo ocupaba demasiado la ventana raíz.

## Decisión
* En reposo el reactor se dibuja reducido (`REST_SCALE`) y, al pasar el cursor, crece a
  su tamaño completo antes de mostrar el menú de módulos.
* Con una lista de opciones (`set_options(..., wrap=False)`) el reactor pasa a ser un
  dial de lista: siempre a tamaño completo, con los nombres escritos dentro del círculo y
  el elegido a la izquierda del centro.
* En el directorio el reactor se coloca con su centro en el borde derecho de la ventana,
  de modo que se ve como el semicírculo anterior, y la vista del directorio ocupa lo que
  queda a su izquierda.

Se mantiene del ADR 0001 que el reactor es la navegación de todos los módulos y que cada
módulo le entrega sus opciones.

## Consecuencias
* Los nombres largos se recortan: solo caben entre su posición en el círculo y el borde
  de la ventana.
* Los módulos nuevos con navegación interna usan el dial de lista si tienen muchas
  opciones, o el anillo de iconos si tienen pocas.
