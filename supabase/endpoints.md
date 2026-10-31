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
Devuelve un arreglo de mensajes (como arriba) **del más antiguo al más nuevo**. `p_before`: solo los enviados antes de esa hora (cargar más hacia atrás). `p_after`: solo los que llegaron al servidor después de esa hora (ponerse al día tras una desconexión). `p_limit` entre 1 y 200.

### `delete_message`
`{"p_id": "uuid"}` → el mensaje con `deleted_at` puesto (borrado suave).

## 3. Tablas (PostgREST), si hace falta algo suelto

`GET /rest/v1/messages?conversation_id=eq.<uuid>&order=sent_at.desc&limit=50&select=*,attachments(*)` (solo lectura recomendada; para escribir, usa `send_message`).

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
