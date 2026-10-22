# Scripts de Kyora

Aquí están solo los scripts esenciales. Para abrir Kyora a diario no hace falta ninguno: usa **`Kyora.vbs`** (en la carpeta de arriba) o el acceso directo. Abre Kyora sin ventana de consola.

| Script | Para qué sirve | Cuándo usarlo |
|---|---|---|
| `iniciar_kyora.bat` | Abre Kyora **con consola**, para ver los errores si algo falla. Con `--no-taskbar` no oculta la barra de tareas de Windows. | Cuando Kyora no arranca, o para probar algo con cuidado. |
| `rescate_kyora.bat` | Vuelve a mostrar las ventanas que Kyora ocultó y la barra de tareas de Windows. | Si Kyora se cerró mal y faltan ventanas o la barra de tareas. |
| `actualizar_kyora.bat` | Cierra Kyora, instala las dependencias, pasa las pruebas y la vuelve a abrir. Si algo falla, se detiene y **no** abre una versión rota. | Después de reemplazar los archivos de Kyora por una versión nueva. |
| `instalar_inicio.bat` | Hace que Kyora arranque sola al iniciar sesión: registra una **tarea programada** de Windows (ver `ARRANQUE.md`). No necesita administrador. | Una vez, si quieres que Kyora arranque con el equipo. |
| `quitar_inicio.bat` | Quita ese arranque automático (borra la tarea programada). | Si ya no quieres que Kyora arranque sola. |

## Qué hace cada uno, paso a paso

**`iniciar_kyora.bat`**
1. Entra en la carpeta `code`.
2. Arranca Kyora con el Python del entorno (`code\.venv`). Le pasa lo que escribas detrás, por ejemplo `--no-taskbar`.
3. Si Kyora termina con un error, deja la consola abierta y te dice dónde está el registro (`%APPDATA%\Kyora\kyora.log`).

**`rescate_kyora.bat`**
1. Ejecuta `python -m kyora --rescue`.
2. Kyora muestra otra vez las ventanas que dejó ocultas, restaura la barra de tareas y dice cuántas ventanas devolvió.

**`actualizar_kyora.bat`**
1. Cierra Kyora si estaba abierta y hace un rescate por si acaso.
2. Instala las dependencias de `code\requirements-dev.txt`.
3. Pasa todas las pruebas. Si alguna falla, se detiene.
4. Abre Kyora: por la tarea programada si el arranque automático está instalado, y si no, con `Kyora.vbs`.

**`instalar_inicio.bat`** / **`quitar_inicio.bat`**
- Llaman a `tarea_inicio.ps1`, que registra o borra la tarea programada `Kyora`. Al instalar, quitan también el acceso directo antiguo de la carpeta de Inicio, si existe.
- Para probarlos sin tocar la tarea real, pásales un nombre de prueba: `instalar_inicio.bat KyoraPrueba` y después `quitar_inicio.bat KyoraPrueba`.

**`tarea_inicio.ps1`** (ayudante, no se ejecuta a mano)
- Acepta `instalar`, `quitar` o `estado`. El estado muestra cuándo se activa, qué ejecuta y su última ejecución.

## Arranque automático

Está explicado aparte, con lo que hace la tarea, por qué se eligió este método, sus límites y cómo comprobarlo: **[`ARRANQUE.md`](ARRANQUE.md)**.
