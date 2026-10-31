# Guía de Kyora

Kyora es tu entorno de ventanas para Windows 11. Sin marco: las ventanas se reparten solas en un **mosaico** de hasta 3 (las demás esperan a la izquierda) Tiene escritorios propios, un buscador y dos paneles que salen de los bordes (arriba: los accesos a Buscar, Tareas, Notas, Música y Fondos; abajo a la derecha: lo que suena en una cápsula, hora, clima, wifi, Bluetooth, batería, RAM y ajustes; a la izquierda: las ventanas en espera). Está hecha solo en Python (PySide6 y pywin32).

## 1. Uso diario

| Quiero… | Hago… |
|---|---|
| Abrir Kyora | Doble clic en **Kyora.vbs** (sin consola) o en el acceso directo |
| Abrirla con consola (para depurar) | `scripts\iniciar_kyora.bat` |
| Abrirla sin ocultar la barra de Windows (pruebas) | `scripts\iniciar_kyora.bat --no-taskbar` |
| Cerrarla | icono de ajustes de la barra de arriba → Ejecutables → **Desconectar Kyora** (dos pulsaciones), o `Ctrl+Alt+Shift+Q` |
| Dejar todo como estaba si algo falla | `scripts\rescate_kyora.bat` |

Al cerrarla, Kyora devuelve todas las ventanas y la barra de tareas de Windows.

## 2. Atajos de teclado

La lista completa está en **`COMANDOS.md`**.

| Atajo | Acción |
|---|---|
| `Ctrl+Shift+Espacio` | Buscador (apps, archivos y carpetas; `<` apps, `/` carpetas, `@` archivos) |
| `Ctrl+Shift+T` / `Ctrl+Shift+N` / `Ctrl+Shift+C` | Tareas / notas / chat (Supabase) |
| `Ctrl+Shift+flechas` | Mover la ventana un paso (en el mosaico, cambiar de hueco) |
| `Ctrl+Shift+Alt+flechas` | Orientación: pegarla arriba, abajo o a un lado; abajo otra vez la minimiza |
| `Ctrl+Shift+F` | Pasar el foco a la siguiente ventana |
| `Ctrl+Shift+R` | Reemplazar la ventana con foco por otra que no se ve |
| `Ctrl+Shift+W` | Fondos de pantalla (los colores de Kyora los siguen) |
| `Ctrl+Shift+E` | Nuevo escritorio |
| `Ctrl+Shift+RePág/AvPág` | Escritorio anterior / siguiente (la pantalla se desliza) |
| `Ctrl+Shift+X` | Apagar, reiniciar o suspender (con el fondo desenfocado) |
| `Ctrl+Shift+Q` | Cerrar la ventana con foco |
| `Ctrl+Shift+Alt+X` | Cerrar todas las ventanas de todos los escritorios |
| `Ctrl+Shift+1/2/3` | Dejar 1, 2 o 3 ventanas en el mosaico |
| `Ctrl+Shift+Alt+E` | Cerrar este escritorio |
| `Ctrl+Shift+M` | Música: listas de YouTube y descarga en MP3 |
| `Ctrl+Alt+Shift+Q` | Salida de emergencia |

El icono de ajustes de la barra de arriba muestra todos los atajos (por sección o por tecla) y los ejecutables.

**Paneles:** arriba (cursor en el borde superior) los accesos a Buscar, Tareas, Notas, el chat, la música (también `Ctrl+Shift+M`) y los fondos; abajo a la derecha (cursor en esa esquina) la hora y la fecha con su calendario, el clima, el wifi, el Bluetooth, la batería, la RAM y los ajustes; a la izquierda (cursor en el borde izquierdo) el número del escritorio y las ventanas que no se ven. **El móvil:** la carpeta `mobile\` es una app Flutter (Android) con el mismo chat, para ver en el teléfono lo que mandas desde la PC (ver `mobile\README.md`). **Diseño:** todo sigue la rúbrica de `DISEÑO.md`. **Buscador (`Ctrl+Shift+Espacio`):** ventanas, páginas web (las que añades en Configuración › Atajos › Páginas web, con el navegador que eliges en Configuración › Predeterminados), apps, carpetas y archivos; `/ y @` (archivos en árbol), `/carpeta` y `@archivo`; `Ctrl+Shift+T` (tareas como pasos; `Enter` abre una ahí mismo y `Esc` vuelve; `Ctrl+N` nueva, `Ctrl+Enter` terminar, `Ctrl+Supr` dos veces borrar, `Ctrl+K` el tablero Kanban) y `Ctrl+Shift+N` (notas con formato, guardadas en Markdown), con el buscador más ancho en el Kanban y las notas. Tareas y notas se manejan todas desde el buscador, sin ventanas aparte ni diálogos; `Ctrl+Shift+W` (fondo y colores); `Win+C` (desconectar, reiniciar o actualizar Kyora…) y `Win+C` (los atajos). **Música (`Ctrl+Shift+M`):** muestra las listas de tu cuenta de YouTube (con las cookies de tu navegador: pon `"music": {"browser": "firefox"}` en `config.json` si Chrome no funciona; por defecto `chrome`). `Enter` (o clic) abre una lista o **reproduce** la canción en streaming, sin bajarla (la barra del pie tiene pausa, siguiente y tiempo; `Espacio` pausa y al acabar sigue con la siguiente); `D` (o la flecha de la fila) la baja; `Descargar` baja todas las que faltan, `Detener` corta, y volver a pulsar `Descargar` (`Reintentar`) solo baja las que no se pudieron. Si Chrome o Edge fallan al leer las cookies (error de DPAPI), exporta un `cookies.txt` con una extensión del navegador (formato Netscape) y guárdalo como `%APPDATA%\Kyora\cookies.txt` (o pon su ruta en `music.cookies_file`): si existe, se usa en vez del navegador. Los MP3 van directo a tu carpeta Música. Necesita FFmpeg: si falta, la página ofrece instalarlo con winget. El foco con el ratón ya no tiene atajo (se cambia con `focus_follows_mouse` en `config.json`). El clima sale de donde estés (por tu IP); si prefieres una ciudad fija, ponla en `%APPDATA%\Kyora\config.json`: `"weather": {"city": "Tu ciudad"}` y reinicia Kyora.

## 3. Cómo se ve y cómo se ajusta

- **Todo el diseño** está en `code\kyora\ui\theme.py`: colores, márgenes del mosaico, borde y sombra de los paneles, contorno de la ventana activa, ancho y zona del panel superior (`top_width`, `top_zone`), zona del panel izquierdo (`left_zone`) y tiempos de las animaciones. Edita el valor, guarda y reinicia Kyora.
  - `window_gap`: separación entre ventanas del mosaico (6).
  - `animate_windows` (`true`): las ventanas se deslizan a su hueco al abrirse o repartirse (`false`: aparecen de golpe).
- `window_margin_single`, `window_margin_multi`: margen entre el mosaico y el borde de la pantalla (12, con una ventana o con varias).
  - `dock_corner`, `dock_tab`, `dock_shadow_size`, `dock_shadow_alpha`: esquinas, pestañitas y sombra de los paneles de los bordes. `scrim_alpha`, `scrim_ms`: cuánto y con qué rapidez se oscurece la pantalla al salir un panel.
  - `focus_width`, `focus_gap`, `focus_radius`: el contorno de la ventana activa, justo sobre su borde (radio 8, el de Windows 11).
  - `focus_glow`, `focus_glow_alpha`: intensidad de la luz del contorno, que se enciende cerca del cursor.
- **Ventanas:** Kyora no toca su aspecto: esquinas, borde y sombra son los de Windows. Solo las coloca en el mosaico.
- **Los colores** salen de tu fondo de pantalla: el acento (borde de la ventana activa, selección, anillos) es su color vivo más presente; los paneles, siempre oscuros, llevan su tono; el texto y los iconos, claros con un toque del acento. Se calculan al arrancar y cada vez que cambias el fondo con `Ctrl+Shift+W` (o `Ctrl+Shift+W` en el buscador); si lo cambias desde Windows, reinicia Kyora.
- **Escritorios:** cada uno guarda sus ventanas. `Ctrl+Shift+E` crea uno, `Ctrl+Shift+RePág/AvPág` se mueve entre ellos (la pantalla se desliza) y `Ctrl+Shift+Alt+E` cierra el actual. El panel izquierdo muestra su número.

## 4. Que Kyora arranque al encender el equipo

1. Doble clic en `scripts\instalar_inicio.bat`. Registra una **tarea programada** de Windows llamada "Kyora" (no necesita permisos de administrador).
2. Al iniciar sesión, Kyora espera 5 segundos a que cargue el escritorio y arranca sin consola. Si Kyora se cae, no se reinicia sola hasta el siguiente inicio de sesión.
3. Para quitarlo: `scripts\quitar_inicio.bat`.

Cómo funciona, por qué se eligió este método y cómo comprobarlo: `scripts\ARRANQUE.md`.

## 5. Actualizar Kyora

1. Cierra Kyora (icono de ajustes → Ejecutables → Desconectar Kyora).
2. Haz una copia de seguridad de `%APPDATA%\Kyora\config.json` (tus atajos) si los personalizaste.
3. Reemplaza los archivos del proyecto con la versión nueva (la carpeta `code\kyora`, la carpeta `scripts` y `Kyora.vbs`). **No borres** `code\.venv` salvo que quieras reinstalar el entorno.
4. Doble clic en `scripts\actualizar_kyora.bat`. Cierra Kyora si seguía abierta, instala dependencias (`requirements-dev.txt`), pasa las pruebas y abre Kyora. Si algo falla se detiene y no abre una versión rota.
5. Si el archivo `config.json` es de una versión anterior, Kyora lo guarda como `config.old.json` y crea uno nuevo con los valores por defecto. Puedes copiar tus atajos de ahí.

**Reinstalar el entorno desde cero** (por ejemplo, equipo nuevo):

```
cd code
py -3.14 -m venv .venv
.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
```

## 6. Si algo no va bien

| Síntoma | Qué hacer |
|---|---|
| No arranca | Abre `scripts\iniciar_kyora.bat` (con consola) y mira el error; el registro completo está en `%APPDATA%\Kyora\kyora.log` |
| Faltan ventanas o la barra de tareas | `scripts\rescate_kyora.bat` |
| "Kyora ya está en marcha" | Ya hay una abierta; ciérrala con el icono de ajustes (Ejecutables) o con `Ctrl+Alt+Shift+Q` |
| Una ventana no se mueve | Si es de un programa ejecutado como administrador, Windows no deja a Kyora moverla (ejecuta Kyora también como administrador si lo necesitas) |
| Una aplicación no cabe en su hueco | En el mosaico, algunas (Calculadora, Fotos) imponen un tamaño mínimo: Kyora lo detecta y mueve la división para darle sitio. Si ni así cabe, reparte el espacio lo mejor que puede |
| La tecla Windows abre el menú | El gancho de teclado no se instaló (Kyora lo avisa al arrancar). Reinicia Kyora |
| Una ventana desapareció | Si quedó fuera de la pantalla, está en el panel izquierdo (cursor en el borde izquierdo): un clic la trae. Si algo falla, `scripts\rescate_kyora.bat` |
| Los atajos no responden | Otra aplicación puede estar usando el mismo atajo; Kyora avisa cuáles fallaron. Cámbialos en `config.json` |

## 7. Qué hay en la carpeta

- `Kyora.vbs`: abre Kyora sin consola (doble clic o acceso directo). El arranque con Windows va por la tarea programada.
- `scripts\`: los scripts esenciales; `scripts\LEEME.md` explica cada uno y `scripts\ARRANQUE.md` el arranque automático.
- `COMANDOS.md`: todos los atajos y lo que hace cada pieza de los paneles.
- `code\kyora\ui`: interfaz (Qt). `code\kyora\wm`: gestor de ventanas. `code\kyora\system`: Windows. `code\kyora\tasks`: Tareas (SQLite). `code\kyora\brain`: Segundo Cerebro (archivos .md). `code\tests`: pruebas.
- `kyoraBase.md`: documento del proyecto (objetivo, stack, arquitectura).
