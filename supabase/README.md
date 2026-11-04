# Supabase · base de datos y endpoints del chat de Kyora

Esta carpeta es todo el "backend" del chat y de la música. Kyora (la PC) y tu móvil hablan con el mismo proyecto de Supabase y entran con **la misma cuenta tuya** (el **administrador**). Nadie más ve el chat: cada fila lleva tu `owner_id` y la seguridad por fila (RLS) lo obliga. Otras personas (**pasantes**) pueden crear su cuenta desde la app del móvil, pero solo reciben la música que tú les mandes desde la PC.

| Archivo | Para qué |
|---|---|
| `schema.sql` | El script que crea **todo**: tipos, tablas (también la de canciones, `music_tracks`), seguridad, bucket de archivos, Realtime y las funciones. Se puede ejecutar varias veces sin romper nada. |
| `cleanup.sql` + `functions/cleanup-expired/` | La limpieza automática (ver abajo). |
| `.env` | Tus credenciales. **Está vacío**: lo rellenas tú. No se sube a git. |
| `endpoints.md` | Los endpoints que usa Kyora (y que puede usar tu móvil), con ejemplos. |

## Puesta en marcha (una sola vez)

1. Crea un proyecto en <https://supabase.com> (el plan gratuito sirve).
2. **SQL Editor** → *New query* → pega todo `schema.sql` → **Run**. Debe terminar con "Success". Si lo vuelves a ejecutar, no pasa nada.
3. **Authentication → Users → Add user → Create new user**: pon tu email y una contraseña (marca *Auto Confirm User*). Es la cuenta que usarán la PC y el móvil. **Hazlo antes de que nadie se registre, y ejecuta `schema.sql` con tu usuario ya creado**: la primera vez que se ejecuta, los usuarios que existen pasan a ser administradores.
   Para que los pasantes puedan registrarse desde la app: en *Authentication → Sign In / Providers* deja activado *Allow new users to sign up* y, en *Email*, **desactiva *Confirm email*** (si no, el registro no devuelve sesión y la app solo dice «revisa tu correo»).
4. **Settings → API**: copia la *Project URL* y la clave **anon public** (nunca la `service_role`).
5. Rellena `supabase/.env`:
   ```
   SUPABASE_URL=https://xxxxxxxx.supabase.co
   SUPABASE_ANON_KEY=eyJ...
   CHAT_EMAIL=tu@correo.com
   CHAT_PASSWORD=tu-contraseña
   CHAT_DEVICE=pc
   ```
   (Si prefieres no dejar la contraseña dentro del repositorio, pon el mismo contenido en `%APPDATA%\Kyora\chat.env`: Kyora lo lee primero.)
6. Reinicia Kyora y abre el chat con `Ctrl+Shift+C`.

Sin credenciales, el chat solo dice qué falta y Kyora funciona igual que siempre.

## Cómo está hecho

- **`conversations`**: tus conversaciones (Kyora crea una llamada *General*).
- **`messages`**: cada mensaje, con su `kind` (`text`, `image`, `file`, `audio`, `video`, `other`), el texto, la **hora de envío** (`sent_at`, la del dispositivo), la hora en que llegó al servidor (`created_at`) y el **estado** (`status`: `pending` = en espera, `sent` = enviado).
- **`attachments`**: los archivos de un mensaje (varios por mensaje): nombre, tipo, tamaño, medidas, duración y la ruta en Storage.
- **Storage** `chat-files` (privado): `<tu_id>/<conversación>/<mensaje>/<archivo>`. 50 MB por archivo (el límite del plan gratuito).
- **Realtime**: `messages` y `attachments` están publicados, así que llegan al instante a todos tus dispositivos.
- **`profiles`**: una fila por cuenta con su `username` (único), `email` y `role` (`admin` = tú, `intern` = pasante). La crea un trigger al registrarse alguien; nadie puede cambiar su propio rol desde la app.
- **`music_tracks`**: una fila por canción **y destinatario** (`owner_id` = quien la manda, `recipient_id` = quien la recibe, `cover_url` = su carátula). El MP3 se sube una sola vez a `chat-files/<tu_id>/music/<vídeo>/…` y el destinatario puede bajarlo porque tiene una fila apuntando a esa ruta.
- **`tasks`, `tags`, `task_tags`**: las tareas del móvil, con el mismo modelo que las del escritorio (`code/kyora/tasks`): estados `pending`/`doing`/`review`/`done`, subtareas de un solo nivel (`parent_id`), etiquetas, entrega (`due`) y tiempos. El móvil las guarda primero en su SQLite y las sube aquí cuando hay internet (se leen y escriben con PostgREST: `upsert` y `select ... synced_at > ...`, sin RPC). Los ids son uuid creados por el dispositivo; el borrado es suave (`deleted_at`); si dos dispositivos cambian lo mismo gana el `updated_at` más reciente (`sync_guard`); `synced_at` lo pone el servidor y sirve de punto de partida para pedir solo las novedades. Cada quien ve solo lo suyo (`owner_id`). **El escritorio todavía no las sincroniza**: sigue con su `tasks.db` local.
- **Pasantes**: no pueden crear conversaciones, mensajes ni subir archivos (las políticas de escritura exigen `is_admin()`); solo leen las canciones que les mandas.
- **Funciones** (se llaman por `POST /rest/v1/rpc/<nombre>`): `ensure_default_conversation`, `send_message`, `list_messages`, `delete_message`, `message_json`; música y cuentas: `add_music_track`, `list_music_tracks`, `my_profile`, `list_recipients` (solo admin), `username_available` (la única que pueden llamar sin sesión).

### Qué significa "en espera" y "enviado"

El mensaje nace **en espera** en el dispositivo (se guarda en su base local al instante, aunque no haya internet). Cuando `send_message` responde que llegó, pasa a **enviado**. Si no hay conexión, queda en espera y Kyora lo reintenta solo; como el `id` lo crea el dispositivo, un reintento nunca duplica el mensaje. En la base de Supabase, los mensajes que existen siempre quedan como `sent`; `pending` existe para los dispositivos que quieran guardarlo así.

### Añadir más estados o tipos después

```sql
alter type public.message_status add value if not exists 'delivered';
alter type public.message_kind   add value if not exists 'location';
```

## Limpieza automática (para que la base de datos no se sature)

- **Mensajes** mandados desde el móvil: cuando la PC los guarda avisa con `confirm_messages_received` (`messages.received_at`). **24 horas después** se borran de Supabase el mensaje y sus archivos. La PC conserva su copia en su `chat.sqlite`.
- **Canciones**: el destinatario pulsa **«Recibido»** en la app (solo cuando la canción ya está guardada en su teléfono; `music_tracks.received_at`). En la siguiente pasada se borran el MP3 de Storage y las filas, pero solo si **todos** los destinatarios de esa canción ya la confirmaron (el MP3 es uno solo para todos).
- Nada se borra mientras `received_at` esté vacío. Los mensajes mandados desde la PC no se confirman y no se borran.

Lo hace la función `functions/cleanup-expired/index.ts`, que `pg_cron` llama cada hora. Se prepara una sola vez:

1. Ejecuta `schema.sql` de nuevo (trae `received_at` y las funciones de confirmación).
2. Instala la [CLI de Supabase](https://supabase.com/docs/guides/cli) y, desde la raíz del repositorio:
   ```
   supabase login
   supabase link --project-ref TU_PROYECTO
   supabase secrets set CLEANUP_SECRET=un-texto-largo-y-secreto
   supabase functions deploy cleanup-expired --no-verify-jwt
   ```
   (`SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` los pone Supabase solo: la clave `service_role` **no** va en ningún archivo tuyo.)
3. Abre `cleanup.sql`, cambia `TU_PROYECTO` y `TU_SECRETO` (el mismo de arriba), pégalo en el *SQL Editor* y ejecútalo. Programa la limpieza cada hora.
4. Para probarla ya, sin esperar: `curl -X POST https://TU_PROYECTO.supabase.co/functions/v1/cleanup-expired -H "x-cleanup-secret: TU_SECRETO"` responde `{"ok":true,"messages":N,"tracks":M}`.

Consecuencias: el historial del **móvil** no guarda copia, así que un mensaje borrado de Supabase desaparece también de allí; la PC lo conserva. Y si mandas otra vez a otra persona una canción ya borrada, `add_music_track` responde `file_missing` y la PC pide volver a mandarla.

## El móvil

Con tu cuenta (administrador) la app de `mobile\` (Flutter, Android) ve el chat y la música. Un pasante crea su cuenta desde la pantalla de acceso (usuario, correo y contraseña, una sola vez) y solo ve la música. La app de `mobile\` usa **la misma cuenta** tuya y se identifica como `movil` (la PC, como `pc`): así cada uno sabe de qué lado va cada mensaje. No hace falta tocar nada de aquí: entra con tu correo y contraseña y ve la misma conversación. Cómo compilarla e instalarla: `mobile\README.md`.
