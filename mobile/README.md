# Kyora Chat · la app del móvil (Android)

El chat de Kyora en tu teléfono: ves lo que mandas desde la PC (texto, fotos y archivos, con su hora y su estado) y también puedes escribir desde el móvil. Usa **tu misma cuenta de Supabase** que la PC; la PC se identifica como `pc` y el móvil como `movil`.

```
Kyora (PC)  ──►  Supabase (base de datos + archivos + tiempo real)  ──►  Kyora Chat (móvil)
            ◄──                                                     ◄──
```

## Instalar en tu teléfono (lo más fácil)
1. En la PC, ejecuta **`scripts\compilar_movil.bat`**. Crea el archivo **`mobile\KyoraChat.apk`** (la primera vez tarda varios minutos).
2. Pasa el APK al teléfono (cable USB, Google Drive, WhatsApp, correo…).
3. En el teléfono, ábrelo. Android pedirá permiso para **instalar apps desconocidas** desde la app que usaste (Archivos, Drive…): actívalo solo para esa app.
4. Abre **Kyora Chat** y entra con **el mismo correo y contraseña** que pusiste en `supabase\.env` (el usuario de Authentication > Users). La sesión queda guardada: no te la vuelve a pedir.

La app no lleva tu correo ni tu contraseña: solo la URL de tu proyecto y su clave pública (que salen de `supabase\.env` al compilar).

## Ejecutarla con el teléfono conectado por USB (para desarrollar)
1. En el teléfono: *Ajustes > Acerca del teléfono* → toca 7 veces el número de compilación → *Opciones de desarrollador* → activa **Depuración USB**.
2. Conéctalo y acepta el aviso «¿Permitir depuración USB?».
3. Ejecuta **`scripts\iniciar_movil.bat`** (si hay varios dispositivos: `iniciar_movil.bat -d <id>`; mira los ids con `flutter devices`).

## Qué hace
- **Acceso** con correo y contraseña; errores en español.
- **Historial** de la conversación *General* (50 mensajes; al subir carga los anteriores) y **tiempo real**: lo que manda la PC aparece solo. Si se corta la conexión, al volver recupera lo que se perdió.
- **Burbujas**: las tuyas a la derecha, las de la PC a la izquierda con su nombre; **hora de envío** y **estado**: reloj *En espera*, ✓ *enviado* o el error con *Reintentar*.
- **Enviar** texto, **fotos** (galería o cámara) y **archivos** (hasta 50 MB). El mensaje sale «en espera» al instante; sin internet se queda así y se manda solo al volver, sin duplicarse.
- **Fotos** con miniatura y pantalla completa con zoom; **archivos** como tarjeta (se abren con la app del teléfono).
- **Mantener pulsado** un mensaje: copiar el texto o borrarlo (también se borra en la PC).

No incluye (todavía): notificaciones con la app cerrada, que los mensajes «en espera» sobrevivan a cerrar la app, ni iPhone.

## Si algo no va
| Síntoma | Qué hacer |
|---|---|
| «Correo o contraseña incorrectos» | Usa el mismo usuario de *Authentication > Users* que pusiste en `supabase\.env`. |
| «Falta crear la base de datos» | Ejecuta `supabase\schema.sql` en Supabase > SQL Editor. |
| «Esta app se compiló sin los datos de Supabase» | Ejecuta `scripts\preparar_movil.bat` (crea `mobile\env.json`) y vuelve a compilar. |
| «Sin conexión» | Revisa internet; si estás conectado, la app reintenta sola cada pocos segundos. |
| Los mensajes de la PC no llegan al instante | Mira que `schema.sql` se ejecutó completo (publica `messages` y `attachments` en Realtime). Al reabrir la app se ponen al día. |
| Comprobar la PC → base de datos | `scripts\probar_chat.bat --send` manda un mensaje de prueba. |

## Para quien toque el código
- Flutter 3 + `supabase_flutter`. Carpeta `lib/`: `data/` (el contrato con Supabase: `chat_repository.dart`, y `chat_backend.dart` para poder probar con uno falso), `state/chat_controller.dart` (mensajes, bandeja «en espera», reintentos, Realtime y puesta al día), `ui/` (pantallas y burbujas), `models/`, `util/`.
- El contrato con Supabase es el mismo que usa la PC: ver `supabase\endpoints.md` (funciones `send_message`, `list_messages`…, bucket `chat-files`, Realtime).
- Pruebas: `flutter analyze` y `flutter test` (41 pruebas, sin red). La prueba **en vivo** usa el mismo repositorio contra tu Supabase real: `set KYORA_LIVE=1` y `flutter test test\live_test.dart` (lee `supabase\.env`, manda un mensaje con un archivo, comprueba el tiempo real, lo baja y lo borra).
- `mobile\env.json` (URL y clave pública) lo genera `scripts\preparar_movil.bat` y no se sube a git.
