# Merida · la consola web de Kyora

Una web local para el navegador de la PC sobre **el mismo Supabase** que Kyora (escritorio) y Kyra (móvil):

| Sección | Qué hace |
|---|---|
| Tareas | El flujo Pendiente, Haciendo, Revisión, Hecha. Añadir, mover, describir, subtareas y borrar. Son las mismas tareas del móvil. |
| Música | **Recibidas**: lo que te mandó la PC, con reproductor (sigue sonando aunque cambies de sección). **Mis listas de YouTube**: tus listas con las cookies de tu navegador; escuchar, descargar en MP3 y decidir a dónde va cada canción (Yo, un pasante o una carpeta de esta PC). |
| Nube | Los archivos compartidos por Supabase que hay ahora en el servidor: lo del chat (fotos, documentos) y las canciones que subió la PC. Filtros por tipo, miniaturas, **Abrir**, **Descargar** y **Eliminar** (se borra de verdad del servidor: el archivo en Storage y su fila; con confirmación). |
| Chat | La conversación *General* en tiempo real, organizada como en Kyra. Lo que escribes aquí sale como `web`. Puedes **borrar** un mensaje o **vaciar el chat** (se borran de verdad del servidor, con sus archivos; con confirmación). |
| Configuración | Un cuadrado con un engranaje en el centro exacto del mosaico. Dentro: tu cuenta y cerrar sesión, métricas, efectos, qué se abre al entrar, color de acento, fondo de pantalla y los ajustes de música. |

## Arrancar

Doble clic en `Scripts\Merida\iniciar_merida.bat` (la primera vez instala los paquetes; necesita Node.js). Arranca también el **servicio de música** (Python de Kyora, en `http://127.0.0.1:5190`) y abre `http://127.0.0.1:5180`. Al cerrar la ventana se apagan los dos. Aparece una consola que te pide primero el correo y luego la contraseña: usa la misma cuenta que la PC y el móvil. `Esc` en la contraseña vuelve al correo.

- La URL y la clave pública salen de `Server\supabase\.env` (o de `%APPDATA%\Kyora\chat.env`, si existe), igual que en Kyora. **El correo y la contraseña del .env no llegan nunca al navegador**: se escriben en la pantalla de acceso, y la sesión la guarda el propio navegador.
- La pantalla principal es un mosaico de teselas con Configuración en el centro (un cuadrado, solo con su icono). Al abrir una ocupa toda la pantalla y las demás se esconden en el borde izquierdo: pasa el cursor por ese borde para verlas como cuadrados con su icono. La `×` la cierra. Teclas: `T` tareas, `M` música, `N` nube, `C` chat, `A` configuración, `I` o `Esc` para volver al inicio.
- **Servicio de música** (`Family/Kyora/kyora/merida/server.py`): usa el mismo motor que Kyora (yt-dlp con tus cookies, FFmpeg y la subida a Supabase con la cuenta del `.env`, que nunca sale de Python). Solo escucha en 127.0.0.1, solo atiende a la página de Merida y pide un token que escribe al arrancar en `%APPDATA%\Kyora\merida_service.json`. Sus ajustes van en `%APPDATA%\Kyora\merida.json` y su estado en `%APPDATA%\Kyora\merida\`; el `cookies.txt` lo comparte con Kyora.
- Si YouTube rechaza las cookies del navegador (pasa con Chrome a veces), en Mis listas puedes pegar un `cookies.txt` exportado con una extensión como «Get cookies.txt LOCALLY», o cambiar el navegador en Configuración.

- **Fondo de pantalla** (Configuración → Fondo de pantalla): eliges una imagen y se queda de fondo, oscurecida y con las líneas de Kyra; los contenedores dejan verla a través. Es **temporal**: dura mientras la sesión esté abierta (se borra al cerrar sesión o al cerrar la pestaña) y la imagen no sale de tu navegador. Mientras suena una canción con portada, la portada es el fondo, y el acento puede salir de ella (se apaga en la misma sección).

## Lo que Merida no hace (a propósito)

- **No confirma «Recibido»** en la música ni en el chat. Esas confirmaciones permiten que la limpieza automática borre los archivos del servidor; las hacen el móvil y la PC.
- No envía fotos ni archivos por el chat (sí abre los que lleguen).
- Lo que borras (mensajes, archivos de la Nube) **no se puede deshacer**: sale de Supabase.
- Las tareas se recargan al volver a la pestaña, no en tiempo real.

## Desarrollo

```
npm install
npm run dev          # http://127.0.0.1:5180
npm test             # pruebas (vitest)
npm run typecheck
npm run build        # dist/
npm run check:live   # prueba real de solo lectura: entra con la cuenta del .env y cuenta tareas, canciones y mensajes
```

Para revisar el diseño sin servidor ni sesión: con `npm run dev` abierto, ve a `http://127.0.0.1:5180/preview.html#/inicio` (o `#/tareas`, `#/musica`, `#/nube`, `#/chat`, `#/configuracion`). Usa datos de ejemplo, no toca Supabase y no entra en `npm run build`.

El diseño (HUD de Kyra con Cyber Brutalism, sin nada redondeado, con el texto hacking y el holograma de Kyra) está en `src/styles/` y `src/ui/fx.ts`, y explicado en `Docs/DISEÑO.md`.
