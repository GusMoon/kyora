# Supabase · base de datos y endpoints del chat de Kyora

Esta carpeta es todo el "backend" del chat. Kyora (la PC) y tu móvil hablan con el mismo proyecto de Supabase y entran con **la misma cuenta tuya**. Nadie más ve nada: cada fila lleva tu `owner_id` y la seguridad por fila (RLS) lo obliga.

| Archivo | Para qué |
|---|---|
| `schema.sql` | El script que crea **todo**: tipos, tablas (también la de canciones, `music_tracks`), seguridad, bucket de archivos, Realtime y las funciones. Se puede ejecutar varias veces sin romper nada. |
| `.env` | Tus credenciales. **Está vacío**: lo rellenas tú. No se sube a git. |
| `endpoints.md` | Los endpoints que usa Kyora (y que puede usar tu móvil), con ejemplos. |

## Puesta en marcha (una sola vez)

1. Crea un proyecto en <https://supabase.com> (el plan gratuito sirve).
2. **SQL Editor** → *New query* → pega todo `schema.sql` → **Run**. Debe terminar con "Success". Si lo vuelves a ejecutar, no pasa nada.
3. **Authentication → Users → Add user → Create new user**: pon tu email y una contraseña (marca *Auto Confirm User*). Es la cuenta que usarán la PC y el móvil. Recomendado: en *Authentication → Sign In / Providers* desactiva *Allow new users to sign up* para que nadie más pueda registrarse.
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
- **Funciones** (se llaman por `POST /rest/v1/rpc/<nombre>`): `ensure_default_conversation`, `send_message`, `list_messages`, `delete_message`, `message_json`.

### Qué significa "en espera" y "enviado"

El mensaje nace **en espera** en el dispositivo (se guarda en su base local al instante, aunque no haya internet). Cuando `send_message` responde que llegó, pasa a **enviado**. Si no hay conexión, queda en espera y Kyora lo reintenta solo; como el `id` lo crea el dispositivo, un reintento nunca duplica el mensaje. En la base de Supabase, los mensajes que existen siempre quedan como `sent`; `pending` existe para los dispositivos que quieran guardarlo así.

### Añadir más estados o tipos después

```sql
alter type public.message_status add value if not exists 'delivered';
alter type public.message_kind   add value if not exists 'location';
```

## El móvil

La app de `mobile\` (Flutter, Android) usa **la misma cuenta** y se identifica como `movil` (la PC, como `pc`): así cada uno sabe de qué lado va cada mensaje. No hace falta tocar nada de aquí: entra con tu correo y contraseña y ve la misma conversación. Cómo compilarla e instalarla: `mobile\README.md`.
