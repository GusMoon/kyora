# 0001. El reactor es la navegación de todos los módulos

* Estado: aceptado
* Fecha: 2026-10-15

## Contexto y problema
El directorio tenía su propio control de navegación (un dial semicircular pegado al borde
derecho), distinto del anillo de opciones del reactor. Dos controles para lo mismo
fragmentan la interfaz y duplican el código de gestos (arrastre, rueda, selección).

## Decisión
El reactor es la navegación de Kyora, tanto entre módulos como dentro de ellos. Acepta
cualquier lista de opciones (`Reactor.set_options`), emite `option_changed` al girar y
`option_selected` al pulsar, y cada módulo le entrega sus opciones.

En el directorio el reactor se desliza a la derecha y su anillo muestra las carpetas del
nivel actual precedidas de la opción `ATRÁS`; el dial semicircular se elimina y
`RootDirectory` queda como vista de migas, título y archivos.

## Alternativas descartadas
* Mantener el dial en el directorio y el reactor solo para los módulos: dos controles y
  código de gestos duplicado.
* Reactor centrado con el listado de archivos encima: la lista quedaba demasiado estrecha.

## Consecuencias
* Los próximos módulos con navegación interna deben ofrecer sus opciones al reactor en
  lugar de crear controles propios.
* El anillo con muchas opciones (carpetas) no envuelve y solo muestra las cercanas a la
  elegida; el nombre completo aparece en el núcleo, no en el anillo.
