# Arranque automático de Kyora (tarea programada)

Kyora arranca sola al iniciar sesión en Windows mediante una **tarea programada** llamada `Kyora`. Este documento explica qué hace, por qué se eligió este método frente a los demás, cómo comprobarlo y qué límites tiene.

## Uso rápido

| Quiero… | Hago… |
|---|---|
| Activar el arranque automático | Doble clic en `scripts\instalar_inicio.bat` |
| Desactivarlo | Doble clic en `scripts\quitar_inicio.bat` |
| Ver si está activo y cuándo corrió por última vez | `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\tarea_inicio.ps1 estado` |
| Probarlo ahora, sin reiniciar | `schtasks /run /tn Kyora` (abre Kyora igual que al iniciar sesión) |
| Ver o editar la tarea a mano | `Win+R`, escribe `taskschd.msc`, y busca **Kyora** en la Biblioteca del Programador de tareas |

`instalar_inicio.bat` se puede ejecutar varias veces: reemplaza la tarea. **No necesita permisos de administrador.**

## Qué hace la tarea

| Ajuste | Valor | Por qué |
|---|---|---|
| Cuándo | Al iniciar sesión, este usuario | Kyora es una interfaz gráfica: necesita el escritorio, no puede arrancar antes |
| Retraso | 5 segundos | Deja cargar el escritorio y la barra de Windows antes de que Kyora ponga su marco |
| Programa | `code\.venv\Scripts\pythonw.exe -m kyora` | Python sin ventana de consola. Se ejecuta directamente (no por `Kyora.vbs`) para que la tarea figure **En ejecución** mientras Kyora vive |
| Carpeta de trabajo | `code\` | Igual que `iniciar_kyora.bat` |
| Con batería | Arranca y no se detiene | Ver abajo |
| Límite de tiempo | Sin límite | Ver abajo |
| Varias instancias | Se ignora la nueva | Si Kyora ya está en la tarea, no se abre una segunda |
| Si se pasó el inicio | Arranca en cuanto pueda | Por si el equipo estaba suspendido o apagado a esa hora |
| Privilegios | Normales (no administrador) | Los mismos que al abrirla con doble clic |

**Por qué los ajustes de batería y de límite de tiempo.** Los valores por defecto de Windows habrían roto el arranque, y se comprobó en este equipo:

- Por defecto, una tarea **no arranca si el portátil va con batería** y se queda "En cola" sin hacer nada. Con la batería al 56 %, una tarea con los valores por defecto no se ejecutó.
- Por defecto, Windows **detiene una tarea que lleva más de 72 horas** ejecutándose. Kyora está abierta todo el día, así que la habría cerrado por sorpresa.

## Por qué la tarea programada y no otros métodos

| Método | Qué es | Veredicto para Kyora |
|---|---|---|
| **Acceso directo en la carpeta Inicio** (el que había antes) | Un archivo `Kyora.lnk` en `shell:startup` | Funciona, pero no hay control de batería ni de límite de tiempo, y el retraso depende de `Kyora.vbs` |
| **Clave del registro** (`HKCU\...\Run`) | Una entrada invisible como archivo | Equivale al acceso directo: sin control de ajustes |
| **Tarea programada** (el actual) | Una tarea en el Programador de tareas | Control explícito de retraso, batería y límite de tiempo; se puede lanzar a demanda y ver su estado |
| **Aplicación instalada** (MSIX o instalador) | Entrada en el menú Inicio, desinstalable | Lo más "nativo", pero exige empaquetar, firmar y mantener un instalador. Solo merece la pena para distribuir Kyora a otras personas |
| **Servicio de Windows** | Programa sin ventana, antes de iniciar sesión | **No sirve**: un servicio no tiene escritorio y Kyora es interfaz gráfica |

Para uso personal, los tres primeros son mecanismos normales de Windows para arrancar programas al iniciar sesión. La diferencia real entre ellos está en los ajustes que se pueden controlar, no en lo "nativos" que sean.

## Qué NO hace (límites)

- **No reinicia Kyora si se cae.** Se probó expresamente: con el ajuste "reiniciar si falla" de Windows, una tarea cuyo programa termina con error se ejecutó una sola vez y no se reinició. Por eso la tarea **no** lo incluye. Si Kyora se cierra por un fallo, vuelve en el siguiente inicio de sesión, o con `schtasks /run /tn Kyora`.
- **No la reabre si la cierras tú** con el botón de salir. Es lo esperado: la salida es voluntaria.
- **Solo al iniciar sesión.** No arranca antes de que inicies sesión, ni al desbloquear la pantalla.
- **Depende de `code\.venv`.** Si mueves la carpeta de Kyora o borras `.venv`, la tarea apunta a un sitio que ya no existe. Mueve la carpeta, y vuelve a ejecutar `instalar_inicio.bat`.
- **Solo para este usuario de Windows.**

## Qué pasa con el método anterior

`instalar_inicio.bat` **borra el acceso directo `Kyora.lnk`** de la carpeta Inicio si existe. Si quedaran los dos, Kyora se intentaría abrir dos veces (la segunda se ignora, pero es ruido). `quitar_inicio.bat` quita la tarea y también ese acceso directo, si quedara alguno.

## Abrir, cerrar y actualizar sin reiniciar el equipo

- **Cerrar Kyora:** botón de salir de la barra (dos clics) o `Ctrl+Alt+Shift+Q`. Devuelve las ventanas y la barra de tareas a Windows. No se reabre sola.
- **Volver a abrirla a mano, cuando quieras** (no hace falta reiniciar ni cerrar sesión):
  - doble clic en `Kyora.vbs` (sin consola);
  - `scripts\iniciar_kyora.bat` (con consola, para ver errores);
  - `schtasks /run /tn Kyora` (por la tarea; ver abajo).
- **Aplicar una actualización o un cambio de código:** Kyora carga el código al abrirse, así que basta con cerrarla y abrirla de nuevo. Lo más seguro es `scripts\actualizar_kyora.bat`: cierra Kyora, instala dependencias, pasa las pruebas y la abre por la tarea. Si alguna prueba falla, **no** la abre, y así no se queda una versión rota. No necesitas reiniciar el equipo.
- **Cambios en `config.json`** (atajos): también hace falta cerrar y abrir Kyora.

## Cómo hacer pruebas

| Quiero probar… | Hago… |
|---|---|
| El código, sin abrir nada | `code\.venv\Scripts\python -m pytest` (hoy pasan 219) |
| Kyora a mano, viendo errores | `scripts\iniciar_kyora.bat`; con `--no-taskbar` no oculta la barra de Windows |
| La tarea, sin reiniciar | `schtasks /run /tn Kyora` y luego `scripts\tarea_inicio.ps1 estado` |
| Una versión nueva | `scripts\actualizar_kyora.bat` |
| El instalador sin tocar la tarea real | `instalar_inicio.bat KyoraPrueba`, y después `quitar_inicio.bat KyoraPrueba` |
| Dejar de arrancar sola, temporalmente | `scripts\quitar_inicio.bat` (y `instalar_inicio.bat` para volver) |
| El arranque real al iniciar sesión | Cierra sesión y vuelve a entrar; después mira `kyora.log` |

Para probar con comodidad, usa `iniciar_kyora.bat --no-taskbar`: si algo sale mal, la barra de tareas sigue ahí.

## El registro (`kyora.log`)

- **Para qué sirve:** es el diario de Kyora. Apunta cada vez que arranca (`Kyora listo`) y se cierra (`Kyora cerrado`), los atajos que no pudo registrar, los avisos (por ejemplo, "No se pudo dar el foco a una ventana") y los errores con todo su detalle. Es lo primero que hay que mirar cuando algo no funciona, sobre todo si Kyora no llegó a abrirse y no ves ningún mensaje.
- **Dónde está:** `%APPDATA%\Kyora\kyora.log`, es decir, `C:\Users\<tu usuario>\AppData\Roaming\Kyora\kyora.log`. Cuando pesa más de 500 KB se archiva como `kyora.log.1` y `kyora.log.2`.
- **Cómo abrirlo:**
  - `Win+R`, escribe `%APPDATA%\Kyora` y pulsa Enter; abre `kyora.log` con el Bloc de notas;
  - o, en PowerShell, las últimas líneas: `Get-Content "$env:APPDATA\Kyora\kyora.log" -Tail 30`;
  - o seguirlo en vivo: `Get-Content "$env:APPDATA\Kyora\kyora.log" -Wait`.
- **Cómo leerlo:** cada línea lleva la hora, el nivel (`INFO` normal, `WARNING` aviso, `ERROR` fallo) y el mensaje. Busca `ERROR` y `Traceback`: debajo de un `Traceback` está la causa del fallo.

## El comando `schtasks /run /tn Kyora`

- **Qué es:** `schtasks` es una herramienta de Windows para manejar el Programador de tareas. `/run` ejecuta una tarea **ahora**, sin esperar a su disparador, y `/tn` indica el nombre de la tarea (`Kyora`).
- **Para qué sirve:** abrir Kyora exactamente como lo hace Windows al iniciar sesión (mismos ajustes, sin consola), sin reiniciar. Es la forma de probar la tarea y de volver a abrir Kyora tras cerrarla.
- **Cómo ejecutarlo:** abre una terminal (`Win+X`, **Terminal**, o busca *PowerShell* en el menú Inicio), escribe el comando y pulsa Enter. No imprime nada si todo va bien: Kyora aparece pasados unos segundos. También sirve `Win+R`, escribirlo y Enter.
- **Si ya está abierta:** no hace nada, porque la tarea ignora una segunda instancia. Ciérrala primero.
- **Si dice que no encuentra la tarea:** la tarea no está instalada; ejecuta `scripts\instalar_inicio.bat`.

## Si algo falla

| Síntoma | Qué hacer |
|---|---|
| No arrancó al iniciar sesión | Ejecuta el comando `estado` de arriba: mira **Ultima ejecucion** y su resultado. Después, mira la primera línea de la sesión en `%APPDATA%\Kyora\kyora.log` |
| "Ultima ejecucion: nunca" | Todavía no has iniciado sesión desde que se instaló. Pruébala con `schtasks /run /tn Kyora` |
| Resultado distinto de 0 | Kyora falló al arrancar: abre `scripts\iniciar_kyora.bat` (con consola) para ver el error |
| La tarea figura "En cola" | Algo impide que arranque (por ejemplo, el ajuste de batería). Vuelve a ejecutar `instalar_inicio.bat` |
| Moví la carpeta de Kyora | Ejecuta de nuevo `instalar_inicio.bat` desde la carpeta nueva |
| Ya no quiero que arranque sola | `quitar_inicio.bat` |

## Posibles mejoras (no activadas)

- **Reiniciar si se cae:** Windows no lo hace con este tipo de tarea. Habría que añadir un pequeño supervisor a Kyora (un arranque que la relance si termina con error).
- **Gestionar ventanas de apps con permisos de administrador:** la tarea puede ejecutarse con privilegios elevados sin pedir confirmación cada vez (nivel "Highest" en el Programador de tareas). Hoy no está activado: Kyora corre con permisos normales, y Windows no deja moverle las ventanas de programas elevados.

%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup