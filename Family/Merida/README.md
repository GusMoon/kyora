# Merida · la consola web de Kyora

Una web local para el navegador de la PC con tres secciones sobre **el mismo Supabase** que Kyora (escritorio) y Kyra (móvil):

| Sección | Qué hace |
|---|---|
| Tareas | El flujo Pendiente, Haciendo, Revisión, Hecha. Añadir, mover, describir, subtareas y borrar. Son las mismas tareas del móvil. |
| Música | Las canciones que te mandó la PC: lista y reproductor. Sigue sonando aunque cambies de sección. |
| Chat | La conversación *General* en tiempo real. Lo que escribes aquí sale como `web`. |

## Arrancar

Doble clic en `Scripts\Merida\iniciar_merida.bat` (la primera vez instala los paquetes; necesita Node.js). Se abre `http://127.0.0.1:5180`. Aparece una consola que te pide primero el correo y luego la contraseña: usa la misma cuenta que la PC y el móvil. `Esc` en la contraseña vuelve al correo.

- La URL y la clave pública salen de `Server\supabase\.env` (o de `%APPDATA%\Kyora\chat.env`, si existe), igual que en Kyora. **El correo y la contraseña del .env no llegan nunca al navegador**: se escriben en la pantalla de acceso, y la sesión la guarda el propio navegador.
- La pantalla principal es un mosaico de teselas. Al abrir una, crece hasta ocupar la derecha y las demás se apilan en una columna a la izquierda; la `×` la cierra. Teclas: `T` tareas, `M` música, `C` chat, `I` o `Esc` para volver al inicio.

## Lo que Merida no hace (a propósito)

- **No confirma «Recibido»** en la música ni en el chat. Esas confirmaciones permiten que la limpieza automática borre los archivos del servidor; las hacen el móvil y la PC.
- No envía fotos ni archivos (sí abre los que lleguen).
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

Para revisar el diseño sin servidor ni sesión: con `npm run dev` abierto, ve a `http://127.0.0.1:5180/preview.html#/inicio` (o `#/tareas`, `#/musica`, `#/chat`). Usa datos de ejemplo, no toca Supabase y no entra en `npm run build`.

El diseño (HUD de Kyra con Cyber Brutalism, sin nada redondeado) está en `src/styles/tokens.css` y explicado en `Docs/DISEÑO.md`.
