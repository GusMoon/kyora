# motherboardRoot: elementos visuales

Elementos visuales de [motherboardRoot.py](../../core/matrix/motherboard/motherboardRoot.py),
la ventana raíz de Kyora. Se agregan aquí a medida que se implementan.

## Ventana
| Propiedad | Valor |
|---|---|
| Clase | `MotherboardRoot` (`QMainWindow`) |
| Marco | Sin marco (`Qt.FramelessWindowHint`) |
| Tamaño | Maximizada |
| Cierre | Tecla `Esc` |

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
Componente circular sci-fi en el centro de la ventana. Código:
[reactor.py](../../core/matrix/motherboard/globalArtifacts/reactor.py). Fondo transparente, no captura el ratón.

| Propiedad | Valor |
|---|---|
| Clase | `Reactor` (`QWidget`) |
| Tamaño | `REACTOR_SIZE_FACTOR` = 0.5 × lado menor de la ventana, cuadrado y centrado |
| Colores | `BRIGHT` `#ebeef2`, `MID` `#969ba2`, `DIM` `#5a5e64`, `FAINT` blanco α22 |
| Animación de entrada | `INTRO_MS` = 3400 ms, una sola vez |
| Mirada del icono | Los ojos siguen al cursor (también fuera de la ventana); `LOOK_FOLLOW` = 0.22 de suavizado por cuadro de `LOOK_TICK_MS` = 16 ms |
| Rotación continua | `SPIN_MS` = 90000 ms por vuelta, en bucle |

Capas, de afuera hacia adentro (radio como % del radio del widget):
- Banda tenue en 90 con círculos finos en 97, 92, 70, 58 y 46.
- Arcos exteriores en 100, arriba y abajo.
- Anillo principal en 78–80, con arcos gruesos en 74 y 64.
- Marcas de graduación cada 3° entre 84 y 87.5 (mayor cada 15°).
- 70 puntos dispersos entre 83 y 93 (semilla fija).
- Búho central, dibujado en `Reactor._draw_owl` en `MID`: dos aros (ojos) con el centro hueco, dos cejas concéntricas a cada ojo que se unen arriba en el eje, y un pico en rombo entre los aros. Semiancho `OWL_HALF_WIDTH` = 42, justo dentro del círculo fino de 46.

Etapas de la entrada. El icono se dibuja primero (fracción de `INTRO_MS`
0.00–`ICON_INTRO_END` = 0.45); los anillos empiezan en `RINGS_INTRO_START` = 0.35
y sus intervalos son fracción de ese tramo restante:

| Etapa | Elemento | Efecto | Intervalo |
|---|---|---|---|
| 0 | Búho central | Se trazan los aros de los ojos; después las cejas desde su punta exterior; al final el pico crece desde su centro | 0.00–0.45 de la entrada |
| 1 | Banda y círculos finos | Se trazan dando la vuelta | 0.00–0.35 |
| 2 | Anillo principal | Se traza dando la vuelta | 0.15–0.50 |
| 3 | Arcos exteriores | Crecen desde su centro | 0.35–0.60 |
| 4 | Arcos gruesos | Crecen en barrido | 0.45–0.80 |
| 5 | Marcas de graduación | Aparecen en barrido | 0.55–0.90 |
| 6 | Puntos | Aparecen escalonados | 0.70–1.00 |

Mirada: cada aro de ojo se desplaza hasta `OWL_LOOK_RANGE` = 4 (píxeles del
diseño de referencia) hacia el cursor; las cejas y el pico no se mueven. El
reactor calcula la dirección con el cursor respecto al centro; la fuerza satura
a una distancia de 30 % del lado menor del reactor.

Rotación continua: los arcos gruesos de 74 giran en un sentido, los de 64 en el
contrario a 1.5× la velocidad; las marcas giran a 0.2× y los puntos a 0.5×.

## Información (esquina superior izquierda)
Columna `info_panel` de `MotherboardRoot`, en `INFO_MARGIN` = (16, 12) px desde la
esquina superior izquierda, con `INFO_ROW_SPACING` = 10 px entre elementos. Arriba va
la hora en grande; debajo, una `InfoRow` por atributo (patrón en
[globalKyoraUI.md](globalKyoraUI.md#fila-de-información)).

| Elemento | Componente | Icono | Muestra | Fuente |
|---|---|---|---|---|
| Hora | [dateAndHour.py](../../core/matrix/motherboard/internalArtifacts/dateAndHour.py) `DateAndHour` | ninguno | `HH:MM` (72 pt, negrita), cada segundo | Reloj del sistema |
| Fecha | `DateAndHour` | [calendar.py](../../core/resources/icons/information/calendar.py) | `dd/mm/aaaa` | Reloj del sistema |
| Ubicación | [location.py](../../core/matrix/motherboard/internalArtifacts/location.py) `Location` | [location.py](../../core/resources/icons/information/location.py) | `Ciudad, País`; `Ubicación desconocida` si falla | `http://ip-api.com/json/` por IP, espera 5 s |
| Clima | [weather.py](../../core/matrix/motherboard/internalArtifacts/weather.py) `Weather` | [weather.py](../../core/resources/icons/information/weather.py) | Temperatura `NN.N°C`; `--°C` si falla o no hay coordenadas | Open-Meteo `current_weather`, espera 5 s |

Flujo: `Location.located(lat, lon)` está conectada a `Weather.set_coordinates`,
así que la temperatura se consulta al conocerse la ubicación. Las consultas de
red corren en un hilo aparte y no bloquean la interfaz. Si la IP pertenece a
Cloudflare WARP y la ciudad es Cancún, `fetch_location` fuerza Mérida, México.

Tipografía y colores: ver [globalKyoraUI.md](globalKyoraUI.md).
