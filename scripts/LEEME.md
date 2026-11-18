# Scripts de Kyora

Aquí están solo los scripts esenciales. Para abrir Kyora a diario no hace falta ninguno: usa **`Scripts\Kyora\Kyora.vbs`** o el acceso directo. Abre Kyora sin ventana de consola.

| Script | Para qué sirve | Cuándo usarlo |
|---|---|---|
| `iniciar_kyora.bat` | Abre Kyora **con consola**, para ver los errores si algo falla. Con `--no-taskbar` no oculta la barra de tareas de Windows. | Cuando Kyora no arranca, o para probar algo con cuidado. |
| `cerrar_kyora.bat` | Cierra Kyora y su proceso del teclado a la fuerza y devuelve las ventanas ocultas y la barra de tareas. | Si Kyora no responde o quieres cerrarla sin usar `Win+C`. |
| `rescate_kyora.bat` | Vuelve a mostrar las ventanas que Kyora ocultó y la barra de tareas de Windows. | Si Kyora se cerró mal y faltan ventanas o la barra de tareas. |
| `actualizar_kyora.bat` | Cierra Kyora, instala las dependencias, pasa las pruebas y la vuelve a abrir. Si algo falla, se detiene y **no** abre una versión rota. | Después de reemplazar los archivos de Kyora por una versión nueva. |
| `probar_chat.bat` | Comprueba el chat desde la PC: inicia sesión en tu Supabase, saca la conversación *General* y lista los últimos mensajes. Con `--send` manda además un mensaje de prueba. Si algo falla dice qué es y cómo arreglarlo. | Después de rellenar `Server\supabase\.env`, o si el chat no conecta. |
| `preparar_movil.bat` | Crea `Family\Kyra\env.json` (la URL y la clave pública de tu Supabase, **sin** correo ni contraseña) y descarga los paquetes de la app del móvil. | Una vez, antes de compilar la app (o si cambias de proyecto de Supabase). |
| `compilar_admin.bat` | Compila **KyraAdmin** (la app del administrador: solo cuentas de administrador y gestión de todas las cuentas) y deja `Family\Kyra\KyraAdmin.apk`. | Para instalar o actualizar la app del administrador. |
| `compilar_family.bat` | Compila **KyraFamily** (la app de la familia: no acepta administradores) y deja `Family\Kyra\KyraFamily.apk`. | Para instalar o actualizar la app de la familia. |
| `compilar_movil.bat` | Compila las dos: `KyraAdmin.apk` y `KyraFamily.apk`. | Para actualizar las dos apps de golpe. |
| `iniciar_movil.bat` / `iniciar_family.bat` | Ejecuta KyraAdmin / KyraFamily en un teléfono Android conectado por USB (con la depuración USB activada). | Para probar cambios en la app sin crear el APK. |
| `instalar_inicio.bat` | Hace que Kyora arranque sola al iniciar sesión: registra una **tarea programada** de Windows (ver `ARRANQUE.md`). No necesita administrador. | Una vez, si quieres que Kyora arranque con el equipo. |
| `quitar_inicio.bat` | Quita ese arranque automático (borra la tarea programada). | Si ya no quieres que Kyora arranque sola. |
| `Merida\iniciar_merida.bat` | Abre Merida, la app web local (tareas, música, nube, chat y configuración), en `http://127.0.0.1:5180`, junto con su servicio de música (tus listas de YouTube, con el Python de Kyora). La primera vez instala sus paquetes (necesita Node.js). Si Merida ya está abierta, solo abre el navegador. Ver `Family\Merida\README.md`. | Cuando quieras usar Merida en el navegador. Cierra la ventana para apagar Merida y su servicio. |

## Qué hace cada uno, paso a paso

**`iniciar_kyora.bat`**
1. Entra en la carpeta `Family\Kyora`.
2. Arranca Kyora con el Python del entorno (`Family\Kyora\.venv`). Le pasa lo que escribas detrás, por ejemplo `--no-taskbar`.
3. Si Kyora termina con un error, deja la consola abierta y te dice dónde está el registro (`%APPDATA%\Kyora\kyora.log`).

**`rescate_kyora.bat`**
1. Ejecuta `python -m kyora --rescue`.
2. Kyora muestra otra vez las ventanas que dejó ocultas, restaura la barra de tareas y dice cuántas ventanas devolvió.

**`actualizar_kyora.bat`**
1. Cierra Kyora si estaba abierta y hace un rescate por si acaso.
2. Instala las dependencias de `Family\Kyora\requirements-dev.txt`.
3. Pasa todas las pruebas. Si alguna falla, se detiene.
4. Abre Kyora: por la tarea programada si el arranque automático está instalado, y si no, con `Scripts\Kyora\Kyora.vbs`.

**`probar_chat.bat`**
1. Lee las credenciales de `Server\supabase\.env` (o de `%APPDATA%\Kyora\chat.env` si existe).
2. Inicia sesión, saca (o crea) la conversación *General* y, con `--send`, manda «Prueba desde Kyora (PC → móvil)».
3. Enseña los últimos mensajes con su dispositivo y estado. Nunca imprime tu correo ni tu contraseña.

**`preparar_movil.bat`** → **`compilar_movil.bat`**
1. `preparar_movil.bat` escribe `Family\Kyra\env.json` y ejecuta `flutter pub get`.
2. `compilar_admin.bat` y `compilar_family.bat` analizan el código, compilan el APK (`flutter build apk --release --flavor admin|family`) y lo copian a `Family\Kyra\KyraAdmin.apk` y `KyraFamily.apk` (`compilar_movil.bat` hace las dos). Necesita Flutter, Java y el SDK de Android (ver `Family\Kyra\README.md`).

**`instalar_inicio.bat`** / **`quitar_inicio.bat`**
- Llaman a `tarea_inicio.ps1`, que registra o borra la tarea programada `Kyora`. Al instalar, quitan también el acceso directo antiguo de la carpeta de Inicio, si existe.
- Para probarlos sin tocar la tarea real, pásales un nombre de prueba: `instalar_inicio.bat KyoraPrueba` y después `quitar_inicio.bat KyoraPrueba`.

**`tarea_inicio.ps1`** (ayudante, no se ejecuta a mano)
- Acepta `instalar`, `quitar` o `estado`. El estado muestra cuándo se activa, qué ejecuta y su última ejecución.

## Arranque automático

Está explicado aparte, con lo que hace la tarea, por qué se eligió este método, sus límites y cómo comprobarlo: **[`ARRANQUE.md`](ARRANQUE.md)**.
