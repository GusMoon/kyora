# motherboardRoot: elementos visuales

Elementos visuales de [motherboardRoot.py](../../core/matrix/motherboard/motherboardRoot.py),
la ventana raíz de Kyora. Se agregan aquí a medida que se implementan.

## Ventana
| Propiedad | Valor |
|---|---|
| Clase | `MotherboardRoot` (`QMainWindow`) |
| Marco | Sin marco (`Qt.FramelessWindowHint`) |
| Tamaño | Maximizada |
| Cierre | Tecla `Esc` (primero oculta el módulo abierto) u opción Cerrar del reactor |

## Fondo
Pintado en `paintEvent`: color base más un halo radial centrado en la ventana.

| Elemento | Constante | Valor |
|---|---|---|
| Color base | `BASE_COLOR` | `#101010` |
| Centro del halo | `GLOW_STOPS` posición 0.0 | `#3c3c3c` |
| Halo | `GLOW_STOPS` posición 0.3 | `#2c2c2c` |
| Halo | `GLOW_STOPS` posición 0.65 | `#181818` |
| Borde del halo | `GLOW_STOPS` posición 1.0 | `#0e0e0e` |
| Radio del halo | `GLOW_RADIUS_FACTOR` | 0.6 × lado mayor de la ventana |

## Reactor
Componente circular sci-fi, centrado en la ventana, con su centro en el borde derecho mientras se navega el [directorio](rootDirectoryUI.md). Código:
[reactor.py](../../core/matrix/motherboard/artifacts/globalArtifacts/reactor.py). Fondo transparente.

| Propiedad | Valor |
|---|---|
| Clase | `Reactor` (`QWidget`) |
| Tamaño | `REACTOR_SIZE_FACTOR` = 0.5 × lado menor de la ventana (tamaño completo), cuadrado. En reposo se dibuja al `REST_SCALE` = 0.55 de ese tamaño y crece al abrirse el menú |
| Colores | `BRIGHT` `#ebeef2`, `MID` `#969ba2`, `DIM` `#5a5e64`, `FAINT` blanco α22 |
| Animación de entrada | `INTRO_MS` = 2400 ms, una sola vez |
| Rotación continua | `SPIN_MS` = 90000 ms por vuelta, en bucle |

Capas, de afuera hacia adentro (radio como % del radio del widget):
- Círculos finos en 96 y 92.
- Arcos gruesos opuestos en 94 y arcos finos en 99 que giran en sentido contrario.
- Anillo principal en 78–80.
- Marcas de graduación cada 3° entre 69/71 y 75 (mayor cada 15°).
- Cuatro grupos de tres puntos junto al círculo exterior.
- Centro vacío, dentro del anillo de marcas.

Etapas de la entrada (intervalos como fracción de `INTRO_MS`):

| Etapa | Elemento | Efecto | Intervalo |
|---|---|---|---|
| 1 | Círculos finos | Se trazan dando la vuelta | 0.00–0.45 |
| 2 | Anillo principal | Se traza dando la vuelta | 0.15–0.50 |
| 3 | Arcos gruesos y finos | Crecen en barrido | 0.35–0.80 |
| 4 | Marcas de graduación | Aparecen en barrido | 0.50–0.90 |
| 5 | Puntos | Aparecen | 0.70–1.00 |

Rotación continua: los arcos gruesos giran a 0.5×, los finos a −0.8×, las marcas a 0.2× y los puntos a 0.1×.

## Reactor como navegador
Con la entrada terminada y el cursor dentro del círculo del reactor aparece el menú
en su centro; al salir del círculo se retira. El reactor conserva todas
sus capas. Navega entre los módulos (`MODULES`) y emite `option_selected(str)` al activar uno;
`MotherboardRoot.open_module` atiende el id. La navegación de carpetas del directorio no
vive aquí ([ADR 0003](../adr/0003-dial-de-carpetas-en-el-directorio.md)).

| Propiedad | Valor |
|---|---|
| Transición | `MENU_MS` = 700 ms, en ambos sentidos (al salir se reproduce al revés). Primero crece (hasta `GROW_END` = 0.45) y después aparece el menú |
| Abrir | El cursor sobre el círculo reducido; una vez abierto lo mantiene el círculo completo |
| Interacción | La rueda recibe clics y arrastre desde `MENU_OPEN_AT` = 0.9 de la transición |
| Opciones | Se reparten por todo el círculo y la rueda envuelve |
| Nombre en el núcleo | Se recorta con «…» a `CORE_LABEL_WIDTH` = 50 % del radio |

### Aparición del menú
Etapas, como fracción de la transición:

| Etapa | Efecto | Intervalo |
|---|---|---|
| Crecimiento | El reactor pasa de `REST_SCALE` a su tamaño completo | 0.00–0.45 |
| Núcleo | El anillo, el icono y el nombre crecen desde el 60 % mientras se encienden | 0.30–0.70 |
| Banda | El anillo de opciones se expande desde el núcleo hasta su tamaño | 0.40–0.85 |
| Opciones | Los iconos giran `MENU_SPIN_IN` = 120° hasta su sitio, crecen y se encienden; entra la sombra | 0.55–1.00 |

### Estructura del menú
Todo concéntrico al centro del reactor, de dentro hacia fuera:

1. **Núcleo:** radio `CENTER_HIT` = 27 %, con el icono y el nombre de la opción elegida. El cambio de opción es inmediato; el anillo fino da un destello de `FLASH_MS` = 160 ms.
2. **Espacio** libre entre el núcleo y la banda de opciones.
3. **Banda de opciones:** anillo relleno entre `RING_INNER` = 33 % y `RING_OUTER` = 62 % del radio, con borde en ambos radios. Un icono por opción, repartidos por igual en todo el círculo; la elegida (la más cercana a la posición de abajo, `SELECTED_ANGLE` = 270°) va más grande y brillante.
4. **Sombra:** tramo de ±`SHADOW_SPAN` = 34° que cubre solo la banda, bajo la opción elegida.

### Giro del anillo
| Acción | Efecto |
|---|---|
| Arrastrar alrededor del centro (más de `DRAG_THRESHOLD` = 4 px) | Los iconos siguen al cursor; al soltar queda la opción más cercana abajo |
| Rueda del ratón | Gira un paso por muesca; hacia arriba retrocede |
| Clic en el núcleo o en la opción de abajo | Emite su id |
| Girar y dejar una opción abajo `HOLD_MS` = 2000 ms | Emite su id sin soltar ni pulsar. La cuenta empieza en cuanto la opción queda abajo (a menos de `ALIGN_TOL` = 0.1 opciones), con el ratón soltado o no, y rellena en el sentido del reloj tres anillos (principal en 78 %, borde de la banda y borde del núcleo). Cambiar de opción, desalinearla o cerrarse el menú la reinicia. Solo corre tras girar el anillo (arrastre o rueda), así que la opción inicial no se ejecuta sola |

El cursor es una mano abierta sobre el menú, cerrada al arrastrar y de puntero sobre lo que activa.

### Fijado para el directorio
`set_pinned(True)` deja el reactor a tamaño completo, sin menú ni gestos (el cursor es una
flecha). `set_gaps(path)` le quita del dibujo (anillos, arcos, marcas) las zonas del
`QPainterPath` dado, en coordenadas del widget; el [directorio](rootDirectoryUI.md) lo usa
para escribir los nombres de las carpetas encima. Al soltarlo (`set_pinned(False)`) vuelve
a su tamaño de reposo sin mostrar el menú mientras se cierra.

| Opción | Id emitido | Icono | Resultado |
|---|---|---|---|
| Directorio | `DIRECTORY` | [explorer.py](../../core/resources/icons/explorer.py) | Desliza el reactor al borde derecho y muestra [rootDirectory](rootDirectoryUI.md) |
| Calendario | `CALENDAR` | [agenda.py](../../core/resources/icons/agenda.py) | Abre `CalendarView` a pantalla completa, en el día de hoy |
| Cerrar | `CLOSE` | [close.py](../../core/resources/icons/close.py) | Cierra la aplicación |

Los módulos se construyen la primera vez que se abren. `Esc` retrocede un nivel: cierra el
panel abierto, después sube un nivel en el directorio y, desde sus carpetas principales,
vuelve al reactor centrado; desde el reactor cierra la ventana. El reactor no recibe
pulsaciones mientras se desliza (`REACTOR_SLIDE_MS` = 450 ms). El calendario abre sin recordatorios ni salto a Tareas, y los archivos
pulsados en el directorio aún no abren ningún visor.
