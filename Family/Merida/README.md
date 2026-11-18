# Merida · la consola web de Kyora

Una web local para el navegador de la PC sobre **el mismo Supabase** que Kyora (escritorio) y Kyra (móvil):

| Sección | Qué hace |
|---|---|
| Tareas | El flujo Pendiente, Haciendo, Revisión, Hecha. Pulsar una tarea abre **todos sus campos** (nombre, estado, entrega, duración esperada, descripción, cronómetro, etiquetas, subtareas y los datos de solo lectura de la base de datos). Son las mismas tareas del móvil. |
| Calendario | Vistas de **día, semana (por defecto) y mes** (opciones a la izquierda; al pulsar un día se expande; añadir y buscar, desde `Ctrl+K`) con tus **eventos**, las tareas con fecha de entrega, **recordatorios** (avisan a su hora con la pestaña abierta) y los **hábitos** de Kyra (se marcan con un clic). Filtros por clase, búsqueda, arrastrar a otro día u hora y doble clic en una hora para crear. Tecla `K`. |
| Contraseñas | Una **bóveda cifrada en el navegador** (correo, usuario, contraseña, web y notas por servicio o aplicación), con generador, copiado que se borra solo y bloqueo automático. Supabase solo guarda texto cifrado; **sin la contraseña maestra no hay recuperación**. Tecla `P`. |
| Finanzas | Ingresos y gastos por mes con categorías, resumen, balance y búsqueda. Tecla `F`. |
| Mejoras | Lista de **mejoras pendientes** del proyecto, compartida con Kyra: escribes la sección que quieres agregar o mejorar, las funciones (una por línea) y una descripción, y queda registrada en Supabase (`feature_requests`). Cuando la función está terminada, **Hecho** la borra de la base de datos y deja de verse. Con las casillas de cada mejora (o «Todas») escoges cuáles quieres trabajar y **Copiar prompt (.md)** copia al portapapeles un prompt en Markdown (contexto, una tarea por mejora e instrucciones) listo para pegar en tu IDE. Tecla `J`. |
| Música | **Recibidas**: lo que te mandó la PC, con reproductor (sigue sonando aunque cambies de sección). **Mis listas de YouTube**: tus listas con las cookies de tu navegador; escuchar, descargar en MP3 y decidir a dónde va cada canción (Yo, un pasante o una carpeta de esta PC). |
| Nube | Los archivos compartidos por Supabase que hay ahora en el servidor: lo del chat (fotos, documentos) y las canciones que subió la PC. Filtros por tipo, miniaturas, **Abrir**, **Descargar** y **Eliminar** (se borra de verdad del servidor: el archivo en Storage y su fila; con confirmación). Arriba muestra **cuánto ocupa tu proyecto de Supabase** (base de datos y archivos) frente al plan gratuito y **avisa al llegar al 80 %** (panel, insignia en la tesela y notificación). |
| Chat | La conversación *General* en tiempo real, organizada como en Kyra. Lo que escribes aquí sale como `web`. Puedes **adjuntar archivos** (clip, arrastrar y soltar o pegar una imagen; hasta 10 de 50 MB) y **borrar** un mensaje o **vaciar el chat** (se borran de verdad del servidor, con sus archivos; con confirmación). Con los **avisos** activados, una notificación del navegador cuando llega un mensaje y no lo estás viendo. La pestaña **Familia** es el chat de mamá, papá y quien agregues: mensajes, imágenes, videos y documentos que se **borran a las 24 horas**, y botones para **llamar** (voz o video) a la familia; las llamadas suenan en cualquier sección. Cómo agregar a alguien y los límites de las llamadas: `Server/supabase/README.md`. |
| Configuración | Un cuadrado con un engranaje en el centro exacto del mosaico. Dentro: tu cuenta y cerrar sesión, métricas, efectos, qué se abre al entrar, color de acento, **atajos de teclado editables**, **avisos de mensajes**, la moneda de Finanzas, fondo de pantalla y los ajustes de música. |

## Arrancar

Doble clic en `Scripts\Merida\iniciar_merida.bat` (la primera vez instala los paquetes; necesita Node.js). Arranca también el **servicio de música** (Python de Kyora, en `http://127.0.0.1:5190`) y abre `http://127.0.0.1:5180`. Al cerrar la ventana se apagan los dos. Aparece una consola que te pide primero el correo y luego la contraseña: usa la misma cuenta que la PC y el móvil. `Esc` en la contraseña vuelve al correo.

- La URL y la clave pública salen de `Server\supabase\.env` (o de `%APPDATA%\Kyora\chat.env`, si existe), igual que en Kyora. **El correo y la contraseña del .env no llegan nunca al navegador**: se escriben en la pantalla de acceso, y la sesión la guarda el propio navegador.
- **Cuentas**: en Merida se entra con el **usuario** y la contraseña (el administrador, con su correo). Las cuentas **no se crean aquí**: solo el administrador las crea, en **Configuración → Administración → Usuarios** (nombre, contraseña y rol, sin correo). Al crearla se le da un **código de 6 dígitos** (una sola vez) que la persona escribe al entrar por primera vez; después basta su contraseña. Ese panel también muestra **quién está en línea** (punto de color o «hace 3 h»), deja pasar a alguien a administrador o visitante, pedir un código nuevo y quitar el acceso. Detalles y despliegue de la función `admin-users`: `Server/supabase/README.md`.
- La pantalla principal es un mosaico de 3×3 con Configuración en el centro (un cuadrado, solo con su icono) y las ocho secciones alrededor, de distintos tamaños. Al abrir una ocupa toda la pantalla y las demás se esconden en el borde izquierdo: pasa el cursor por ese borde para verlas como cuadrados con su icono. El botón **`× Mosaico [Esc]`** (arriba a la derecha) la cierra. Teclas (editables en Configuración → Atajos de teclado): `T` tareas, `K` calendario, `M` música, `N` nube, `C` chat, `P` contraseñas, `F` finanzas, `J` mejoras, `A` configuración, `I` o `Esc` para volver al inicio. **`Ctrl+K` abre la paleta de comandos** (secciones, acciones, tareas, webs del chat y, con la bóveda abierta, tus contraseñas).
- **Antes de usar Calendario, Contraseñas, Finanzas y Mejoras** hay que volver a ejecutar `Server/supabase/schema.sql` en el SQL Editor de Supabase (es seguro repetirlo): crea las tablas `events`, `reminders`, `vault_*`, `finance_*` y `feature_requests` y la función `server_stats()` (la Nube mide el espacio del servidor con ella) (los hábitos ya existen desde Kyra).
- **Servicio de música** (`Family/Kyora/kyora/merida/server.py`): usa el mismo motor que Kyora (yt-dlp con tus cookies, FFmpeg y la subida a Supabase con la cuenta del `.env`, que nunca sale de Python). Solo escucha en 127.0.0.1, solo atiende a la página de Merida y pide un token que escribe al arrancar en `%APPDATA%\Kyora\merida_service.json`. Sus ajustes van en `%APPDATA%\Kyora\merida.json` y su estado en `%APPDATA%\Kyora\merida\`; el `cookies.txt` lo comparte con Kyora.
- Si YouTube rechaza las cookies del navegador (pasa con Chrome a veces), en Mis listas puedes pegar un `cookies.txt` exportado con una extensión como «Get cookies.txt LOCALLY», o cambiar el navegador en Configuración.

- **Fondo de pantalla** (Configuración → Fondo de pantalla): eliges una imagen y se queda de fondo, oscurecida y con las líneas de Kyra; los contenedores dejan verla a través. Es **temporal**: dura mientras la sesión esté abierta (se borra al cerrar sesión o al cerrar la pestaña) y la imagen no sale de tu navegador. Mientras suena una canción con portada, la portada es el fondo, y el acento puede salir de ella (se apaga en la misma sección).

## Llevarla en un USB

La carpeta `usb/` es Merida **lista para copiar a un USB** (o para abrirla desde aquí): trae su propio Node, Python (con el servicio de música) y FFmpeg, así que la PC de destino no instala nada. No guarda credenciales: el correo y la contraseña se escriben en la pantalla de acceso, y lo único del servidor que lleva la web es la URL y la clave pública (anon).

```
npm run build:usb    # genera usb/ (web, servicio de música y runtime/); la 1.ª vez descarga Python y FFmpeg (≈ 250 MB en total)
npm run usb          # la abre desde aquí, igual que desde el USB
```

Para el USB copia el contenido de `usb/` **sin** `.cache/` y abre `Abrir Merida.bat` (Windows de 64 bits; el puerto 5180 libre). `--force` rehace `runtime/`; `--skip-build` reutiliza `dist/`. El script se detiene si encuentra un `.env`, `chat.env`, `cookies.txt` o la contraseña/correo del `.env` dentro de lo copiado. La música usa las cookies del navegador de esa PC (hay que tener YouTube abierto con tu sesión) y, sin credenciales, descarga y reproduce pero no sube a Supabase. Más detalles en `usb/LEEME.txt`.

## Lo que Merida no hace (a propósito)

- **No confirma «Recibido»** en la música ni en el chat. Esas confirmaciones permiten que la limpieza automática borre los archivos del servidor; las hacen el móvil y la PC.
- **No avisa con la pestaña cerrada.** Los avisos de mensajes usan notificaciones del navegador: funcionan con la pestaña abierta (aunque esté en segundo plano), no cerrada (haría falta Web Push).
- **No puede recuperar tu contraseña maestra.** Las contraseñas se cifran en el navegador con ella y Supabase solo ve texto cifrado: si la olvidas, la bóveda no se puede abrir.
- Los archivos que adjuntas por el chat *General* siguen la limpieza de siempre: el servidor los borra 24 h después de que el móvil o la PC confirmen «Recibido». Los de la pestaña *Familia* se borran a las 24 h de enviarlos, sin confirmación.
- **Las llamadas no suenan con Merida cerrada** (no hay Web Push) y no llevan servidor TURN: con algunas redes muy estrictas pueden no conectar.
- Lo que borras (mensajes, archivos de la Nube) **no se puede deshacer**: sale de Supabase.
- Las tareas se recargan al volver a la pestaña, no en tiempo real.

## Desarrollo

```
npm install
npm run dev          # http://127.0.0.1:5180
npm test             # pruebas (vitest). Si en tu Node (p. ej. 24.16) todas fallan con «Cannot read properties of undefined (reading 'config')»: npx vitest run --pool=vmForks
npm run typecheck
npm run build        # dist/
npm run check:live   # prueba real de solo lectura: entra con la cuenta del .env y cuenta tareas, canciones y mensajes
```

Para revisar el diseño sin servidor ni sesión: con `npm run dev` abierto, ve a `http://127.0.0.1:5180/preview.html#/inicio` (o `#/tareas`, `#/musica`, `#/nube`, `#/chat`, `#/configuracion`). Usa datos de ejemplo, no toca Supabase y no entra en `npm run build`.

El diseño (HUD de Kyra con Cyber Brutalism, sin nada redondeado, con el texto hacking y el holograma de Kyra) está en `src/styles/` y `src/ui/fx.ts`, y explicado en `Docs/DISEÑO.md`.
