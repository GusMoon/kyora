# Endpoints del chat

Todos cuelgan de `SUPABASE_URL`. Cabeceras comunes: `apikey: <SUPABASE_ANON_KEY>` y, después de entrar, `Authorization: Bearer <access_token>`. Los errores vuelven como `{"code", "message", "details", "hint"}` con el estado HTTP que corresponda.

## 1. Sesión (Supabase Auth)

| Qué | Petición | Cuerpo | Respuesta |
|---|---|---|---|
| Entrar | `POST /auth/v1/token?grant_type=password` | `{"email", "password"}` | `{"access_token", "refresh_token", "expires_in", "user": {"id"}}` |
| Renovar | `POST /auth/v1/token?grant_type=refresh_token` | `{"refresh_token"}` | igual que arriba |

El `access_token` caduca (normalmente en 1 h): Kyora lo renueva antes de que pase y vuelve a entrar si el `refresh_token` falla.

## 2. Funciones (RPC): `POST /rest/v1/rpc/<nombre>`

### `ensure_default_conversation`
Cuerpo `{}` → el `uuid` de tu conversación *General* (la crea si no existe).

### `send_message`
Envía un mensaje. Se puede repetir con el mismo `p_id` sin duplicar: devuelve el mensaje que ya existía.

```json
{
  "p_id": "0b9e...-uuid generado por el dispositivo",
  "p_conversation_id": "uuid",
  "p_body": "Hola",
  "p_sent_at": "2026-10-30T09:12:44.120Z",
  "p_device": "pc",
  "p_attachments": [
    {"storage_path": "<owner>/<conv>/<msg>/foto.jpg", "file_name": "foto.jpg", "mime_type": "image/jpeg",
     "size_bytes": 482113, "width": 1920, "height": 1080}
  ]
}
```
Respuesta: el mensaje con sus adjuntos, `{"id", "conversation_id", "owner_id", "sender_device", "kind", "body", "status": "sent", "sent_at", "created_at", "edited_at", "deleted_at", "metadata", "attachments": [ {"id", "storage_path", "file_name", "mime_type", "size_bytes", "width", "height", "duration_ms", "thumb_path", ...} ]}`.
`kind` lo calcula la función: `image/*` → `image`, `audio/*` → `audio`, `video/*` → `video`, otro tipo → `file`, sin tipo → `other`, sin adjuntos → `text`.
Errores: `empty_message` (ni texto ni adjuntos, 22023), `attachments_must_be_an_array` (22023), `message_id_taken` (ese id es de otra cuenta, 42501), `not_authenticated` (28000).

### `list_messages`
```json
{"p_conversation_id": "uuid", "p_before": null, "p_after": null, "p_limit": 50}
```
Devuelve un arreglo de mensajes (como arriba, con `received_at`) **del más antiguo al más nuevo**. `p_before`: solo los enviados antes de esa hora (cargar más hacia atrás). `p_after`: solo los que llegaron al servidor después de esa hora (ponerse al día tras una desconexión). `p_limit` entre 1 y 200.

### `delete_message`
`{"p_id": "uuid"}` → el mensaje con `deleted_at` puesto (borrado suave).

### `confirm_messages_received`
`{"p_ids": ["uuid", ...], "p_device": "pc"}` → cuántos mensajes se marcaron ahora (`integer`). Lo llama el dispositivo de destino (la PC) cuando ya guardó los mensajes que llegaron de otro dispositivo: pone `received_at = now()` solo en mensajes de la cuenta cuyo `sender_device` es distinto de `p_device` y que aún no tenían confirmación. Repetirlo no cambia nada. **24 horas después** la limpieza automática (`functions/cleanup-expired`) borra el mensaje y sus archivos.

### Cuentas y música

| Función | Quién | Cuerpo → respuesta |
|---|---|---|
| `username_available` | cualquiera, **sin sesión** (solo `apikey`) | `{"p_username"}` → `true`/`false` |
| `my_profile` | con sesión | `{}` → `{"id", "username", "email", "role": "admin" \| "intern", "created_at", "verified"}` (o `null`) |
| `claim_account` | con sesión | `{"p_code": "123456"}` → `true`. Canjea el código de 6 dígitos (errores: `code_invalid`, `code_expired`, `code_locked`) |
| `touch_presence` | con sesión | `{}` → nada. «Sigo aquí» (cada ~30 s) |
| `list_presence` | solo administrador | `{}` → `[{"id", "username", "role", "verified", "last_seen", "online", "code_pending", "me"}]` |
| `list_recipients` | solo admin | `{}` → `[{"id", "username", "role", "me"}]`, primero el propio (`me: true`, la PC lo muestra como «Yo») |
| `add_music_track` | solo admin | `{"p_id", "p_title", "p_file_name", "p_storage_path", "p_mime_type", "p_size_bytes", "p_playlist", "p_recipient_id", "p_cover_url"}` → la fila de `music_tracks`. `p_recipient_id` vacío = quien llama. Repetir el mismo `p_id` no duplica. Error `file_missing` si el MP3 ya no está en Storage (la limpieza lo borró tras recibirse): hay que volver a subirlo. |
| `list_music_tracks` | con sesión | `{"p_limit": 100}` → las canciones que **recibe** quien llama, de la más nueva a la más antigua; cada fila trae `received_at` (`null` hasta que se confirme) |
| `confirm_track_received` | con sesión (el destinatario) | `{"p_id": "<uuid de la canción>"}` → la fila con `received_at` puesto. Es el botón «Recibido» de la app móvil: solo se llama cuando la canción ya está guardada en el teléfono. Solo el destinatario puede, sobre sus canciones; repetirlo no cambia la hora. Error `unknown_track` si no existe o no es suya. Nada se borra de Supabase mientras `received_at` sea `null`. |

**Ya no hay registro público** (`/auth/v1/signup` debe estar apagado en Supabase). Las cuentas las crea el administrador con la función `POST /functions/v1/admin-users` (cabecera `Authorization: Bearer <sesión del administrador>`) y `{"action": "create", "username", "password", "role": "intern" | "admin"}` → `{"id", "username", "role", "code"}` (el código de 6 dígitos sale una sola vez). Otras acciones: `set_role` (`user_id`, `role`), `regenerate_code` (`user_id`) → `{"code"}` y `remove` (`user_id`). Errores: `invalid_username`, `invalid_password`, `username_taken`, `not_admin` (403), `unauthorized` (401), `cannot_change_self`, `user_not_found`. Se entra con `POST /auth/v1/token?grant_type=password` y el correo `<nombre>@kyra.local`.

### Chat privado 1 a 1 (Kyra, `schema.sql` §19)

Los mensajes son **permanentes**: «borrar para mí» solo oculta para quien lo pide; borrar de la base de datos solo lo hace el administrador.
Hace falta una cuenta verificada (si no: `not_verified`). Tiempo real: la tabla `dm_messages` (la seguridad por fila decide quién recibe cada fila).

| Función | Quién | Cuerpo → respuesta |
|---|---|---|
| `dm_directory` | con sesión | `{}` → `[{"id", "username", "role", "online"}]`: todas las cuentas verificadas menos la propia |
| `dm_open_thread` | con sesión | `{"p_user"}` → la conversación con esa persona (se crea si no existe): `{"id", "other", "last", "unread", "last_message_at"}` |
| `dm_list_threads` | con sesión | `{}` → las conversaciones propias con algo que enseñar, la más reciente primero (mismo formato) |
| `dm_list_messages` | participante | `{"p_thread", "p_before", "p_after", "p_limit"}` → `[{"id", "thread_id", "sender_id", "sender_device", "body", "sent_at", "created_at"}]`, sin lo oculto ni lo vaciado |
| `dm_send` | participante | `{"p_id", "p_thread", "p_body", "p_sent_at", "p_device"}` → el mensaje. Repetir el mismo `p_id` no duplica |
| `dm_hide_message` | participante | `{"p_id"}` → nada. «Borrar para mí» |
| `dm_clear_thread` | participante | `{"p_thread"}` → nada. «Vaciar chat» solo para quien llama |
| `dm_mark_read` | participante | `{"p_thread"}` → nada. Pone a cero los no leídos |
| `dm_admin_threads` | solo admin | `{}` → `[{"id", "a", "b", "count", "last_message_at"}]` |
| `dm_admin_messages` | solo admin | `{"p_thread", "p_before", "p_limit"}` → todos los mensajes (también los ocultos), con `sender_name` |
| `dm_admin_delete_message` / `dm_admin_delete_thread` | solo admin | `{"p_id"}` / `{"p_thread"}` → nada. Borran de verdad |

## 3. Tablas (PostgREST), si hace falta algo suelto

`GET /rest/v1/messages?conversation_id=eq.<uuid>&order=sent_at.desc&limit=50&select=*,attachments(*)` (solo lectura recomendada; para escribir, usa `send_message`).

### Comandos del chat: `chat_commands`

Sin RPC, con PostgREST (cada cuenta ve solo lo suyo; crear y cambiar exige ser administrador).

- **Listar**: `GET /rest/v1/chat_commands?select=id,name,command,url&order=command`.
- **Crear**: `POST /rest/v1/chat_commands` con `{"name": "YouTube", "command": "youtube", "url": "https://youtube.com"}`. `command` va sin «/», en minúsculas, `[a-z0-9_-]{1,24}`; `url` debe empezar por `http://` o `https://`. Repetir un `command` da `23505`.
- **Quitar**: `DELETE /rest/v1/chat_commands?id=eq.<uuid>`.

### Tareas: `tasks`, `tags`, `task_tags`

Sin RPC: se usan directamente con PostgREST (cada cuenta solo ve y toca lo suyo; no hace falta ser administrador).

- **Subir** (idempotente): `POST /rest/v1/tasks?on_conflict=id` con `Prefer: resolution=merge-duplicates` y un arreglo de filas `{"id", "parent_id", "position", "name", "description", "status", "expected_min", "real_s", "timer_started", "due", "finished", "created_at", "updated_at", "deleted_at"}`. `status`: `pending`, `doing`, `review`, `done`. Igual `tags` (`{"id","name","color","updated_at","deleted_at"}`, `on_conflict=id`) y `task_tags` (`{"task_id","tag_id","updated_at","deleted_at"}`, `on_conflict=task_id,tag_id`). Las horas van en UTC (ISO 8601).
- **Bajar las novedades**: `GET /rest/v1/tasks?synced_at=gt.<última hora leída>&order=synced_at.asc&limit=500` (sin el filtro la primera vez). `synced_at` lo pone el servidor en cada escritura aceptada.
- **Borrar**: no hay `DELETE`; se sube la fila con `deleted_at` puesto (y un `updated_at` más nuevo).
- **Conflictos**: una escritura con `updated_at` igual o más viejo que el guardado se ignora en silencio (trigger `sync_guard`): gana el cambio más reciente.

## 4. Archivos (Storage), bucket privado `chat-files`

| Qué | Petición | Notas |
|---|---|---|
| Subir | `POST /storage/v1/object/chat-files/<owner>/<conv>/<msg>/<archivo>` | Cuerpo = los bytes del archivo; `Content-Type` = su tipo; `x-upsert: true` para poder reintentar. Primero se sube y luego se llama a `send_message`. |
| Bajar | `GET /storage/v1/object/authenticated/chat-files/<ruta>` | Con `Authorization`. |
| URL firmada | `POST /storage/v1/object/sign/chat-files/<ruta>` con `{"expiresIn": 3600}` | Devuelve `{"signedURL"}` (relativa a `/storage/v1`), útil para abrir en un navegador. |

La primera carpeta de la ruta tiene que ser **tu** `user.id`: es lo que comprueba la política.

## 5. Tiempo real (Realtime, WebSocket)

`wss://<proyecto>.supabase.co/realtime/v1/websocket?apikey=<ANON_KEY>&vsn=1.0.0`

1. Unirse (mensaje al abrir):
   ```json
   {"topic": "realtime:kyora-chat", "event": "phx_join", "ref": "1", "join_ref": "1",
    "payload": {"config": {"broadcast": {"self": false}, "presence": {"key": ""},
                           "postgres_changes": [
                             {"event": "*", "schema": "public", "table": "messages"},
                             {"event": "*", "schema": "public", "table": "attachments"}]},
                "access_token": "<access_token>"}}
   ```
   Respuesta: `phx_reply` con `"status": "ok"`.
2. Latido cada 25 s: `{"topic": "phoenix", "event": "heartbeat", "payload": {}, "ref": "<n>"}`.
3. Cambios: llegan como `{"event": "postgres_changes", "payload": {"data": {"type": "INSERT" | "UPDATE" | "DELETE", "table", "record", "old_record", "commit_timestamp"}}}`. `INSERT` en `messages` = mensaje nuevo; un `UPDATE` con `deleted_at` = mensaje borrado; `INSERT` en `attachments` = adjunto del mensaje.
4. Al renovar el token: `{"topic": "realtime:kyora-chat", "event": "access_token", "payload": {"access_token": "<nuevo>"}, "ref": "<n>"}`.
5. Si se corta, reconectar con espera creciente y, al volver, llamar a `list_messages` con `p_after` = el `created_at` del último mensaje que se tenía.
