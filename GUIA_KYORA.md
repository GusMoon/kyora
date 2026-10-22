# Guía de Kyora

Kyora es tu entorno de ventanas para Windows 11. Pone un marco alrededor de la pantalla con una barra a la izquierda. Dentro del marco, separadas un poco de él y entre sí, las ventanas forman un mosaico: como máximo 3 visibles, y el resto espera. Tiene escritorios propios, un buscador y un panel de ventanas en espera. Está hecha solo en Python (PySide6 y pywin32).

## 1. Uso diario

| Quiero… | Hago… |
|---|---|
| Abrir Kyora | Doble clic en **Kyora.vbs** (sin consola) o en el acceso directo |
| Abrirla con consola (para depurar) | `scripts\iniciar_kyora.bat` |
| Abrirla sin ocultar la barra de Windows (pruebas) | `scripts\iniciar_kyora.bat --no-taskbar` |
| Cerrarla | `Win+K` → **Desconectar Kyora**, o `Ctrl+Alt+Shift+Q` |
| Dejar todo como estaba si algo falla | `scripts\rescate_kyora.bat` |

Al cerrarla, Kyora devuelve todas las ventanas y la barra de tareas de Windows.

## 2. Atajos de teclado

La lista completa está en **`COMANDOS.md`**.

| Atajo | Acción |
|---|---|
| `Alt+F` | Pasar el foco a la siguiente ventana |
| `Alt+flechas` | Mover la ventana a otro hueco |
| `Alt+Esc` | Cerrar la ventana con foco |
| `Alt+D` | Nuevo escritorio |
| `Alt+E` | Cambiar de app (ventanas en espera) |
| `Alt+O` | Girar la ventana grande (arriba, derecha, abajo, izquierda) |
| `Alt+1/2/3` | Ver 1, 2 o 3 ventanas |
| `Alt+Espacio` | Buscador |
| `Alt+M` | Foco con el ratón |
| `Win+↑/↓` | Escritorio de arriba / de abajo |
| `Win+Esc` (dos veces) | Cerrar todas las ventanas |
| `Win+-` | Cerrar este escritorio |
| `Win+X` | Apagar, reiniciar o suspender |
| `Win+I` / `Win+E` / `Win+T` / `Win+B` / `Win+K` | Panel de arriba en Lobby / Archivos / Tareas / Segundo Cerebro / Kyora (dentro: `Ctrl+1…5`, `Ctrl+Tab`) |
| `Ctrl+Alt+Shift+Q` | Salida de emergencia |

En el buscador, escribe `commands` para ver todos los atajos.

**Barra:** arriba los escritorios; abajo la hora y los iconos de wifi, Bluetooth, calendario y apagar, que abren su panel al pasar el ratón. **Panel de arriba:** Lobby (`Win+I`: hora, clima por horas, RAM, CPU, volumen, brillo, disco, batería y la semana), Archivos (`Win+E`), Tareas (`Win+T`), Segundo Cerebro (`Win+B`) y Kyora (`Win+K`: desconectar o reiniciar Kyora, actualizar, consola, rescate y arranque con Windows). Para el clima, pon tu ciudad en `%APPDATA%\Kyora\config.json`: `"weather": {"city": "Tu ciudad"}` y reinicia Kyora desde la sección Kyora.

## 3. Cómo se ve y cómo se ajusta

- **Todo el diseño** está en `code\kyora\ui\theme.py`: colores, grosor del marco, ancho de la barra, márgenes, borde y sombra del hueco, contorno de la ventana activa y tiempos de las animaciones. Edita el valor, guarda y reinicia Kyora.
  - `window_gap`: separación entre ventanas (6).
  - `window_margin_single`, `window_margin_multi`: margen entre el mosaico y el marco (12, con una ventana o con varias).
  - `edge_dark`, `edge_light`, `edge_shadow_size`, `edge_shadow_alpha`: borde en relieve del hueco y su sombra.
  - `focus_width`, `focus_gap`, `focus_radius`: el contorno de la ventana activa, justo sobre su borde (radio 8, el de Windows 11).
  - `focus_spin_ms`, `focus_glow_alpha`, `focus_base_alpha`: velocidad e intensidad de la luz del contorno.
- **Ventanas del mosaico:** Kyora no toca su aspecto: esquinas, borde y sombra son los de Windows. Solo las coloca en el mosaico.
- **El color de énfasis** se toma de tu fondo de pantalla (el color vivo más presente) cada vez que Kyora arranca. Si cambias el fondo, reinicia Kyora.
- **Barra lateral:** escritorios, hora, wifi, Bluetooth, calendario y apagar; los datos del equipo están en el Lobby del panel de arriba (`Win+I`).
- **Escritorios:** la píldora de arriba de la barra tiene un punto por escritorio. Los puntos claros tienen ventanas y los oscuros están vacíos. El activo se ve grande y con su número. Clic para cambiar, clic derecho para renombrar o cerrar, y `+` para crear uno.

## 4. Que Kyora arranque al encender el equipo

1. Doble clic en `scripts\instalar_inicio.bat`. Registra una **tarea programada** de Windows llamada "Kyora" (no necesita permisos de administrador).
2. Al iniciar sesión, Kyora espera 5 segundos a que cargue el escritorio y arranca sin consola. Si Kyora se cae, no se reinicia sola hasta el siguiente inicio de sesión.
3. Para quitarlo: `scripts\quitar_inicio.bat`.

Cómo funciona, por qué se eligió este método y cómo comprobarlo: `scripts\ARRANQUE.md`.

## 5. Actualizar Kyora

1. Cierra Kyora (`Win+K` → Desconectar Kyora).
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
| "Kyora ya está en marcha" | Ya hay una abierta; ciérrala desde `Win+K` o con `Ctrl+Alt+Shift+Q` |
| Una ventana no se mueve | Si es de un programa ejecutado como administrador, Windows no deja a Kyora moverla (ejecuta Kyora también como administrador si lo necesitas) |
| Una aplicación no cabe en su hueco | Algunas (Calculadora, Fotos) imponen un tamaño mínimo: Kyora lo detecta y mueve la división para darle sitio. Si ni así cabe, reparte el espacio lo mejor que puede |
| La tecla Windows abre el menú | El gancho de teclado no se instaló (Kyora lo avisa al arrancar). Reinicia Kyora |
| Los atajos no responden | Otra aplicación puede estar usando el mismo atajo; Kyora avisa cuáles fallaron. Cámbialos en `config.json` |

## 7. Qué hay en la carpeta

- `Kyora.vbs`: abre Kyora sin consola (doble clic o acceso directo). El arranque con Windows va por la tarea programada.
- `scripts\`: los scripts esenciales; `scripts\LEEME.md` explica cada uno y `scripts\ARRANQUE.md` el arranque automático.
- `COMANDOS.md`: todos los atajos y lo que hace cada pieza de la barra.
- `code\kyora\ui`: interfaz (Qt). `code\kyora\wm`: gestor de ventanas. `code\kyora\system`: Windows. `code\kyora\tasks`: Tareas (SQLite). `code\kyora\brain`: Segundo Cerebro (archivos .md). `code\tests`: pruebas.
- `kyoraBase.md`: documento del proyecto (objetivo, stack, arquitectura).
