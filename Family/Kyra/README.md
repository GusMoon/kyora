# Kyra · la app del móvil (Android) de Kyora

El chat de Kyora en tu teléfono: ves lo que mandas desde la PC (texto, fotos y archivos, con su hora y su estado) y también puedes escribir desde el móvil. Usa **tu misma cuenta de Supabase** que la PC; la PC se identifica como `pc` y el móvil como `movil`.

```
Kyora (PC)  ──►  Supabase (base de datos + archivos + tiempo real)  ──►  Kyra (móvil)
            ◄──                                                     ◄──
```

## Dos apps: KyraAdmin y KyraFamily
Salen del mismo código (`flutter build apk --flavor admin|family`) pero son **dos apps distintas** que se instalan a la vez en el mismo teléfono, cada una con sus datos y su sesión:

| | **KyraAdmin** (`KyraAdmin.apk`) | **KyraFamily** (`KyraFamily.apk`) |
|---|---|---|
| Quién entra | **Solo cuentas de administrador** (correo y contraseña). Cualquier otra cuenta es rechazada y se le cierra la sesión. | Los miembros de la familia (nombre y contraseña). **Las cuentas de administrador son rechazadas** y se les cierra la sesión («Usa KyraAdmin»). |
| Qué tiene | Todo: Inicio, Nube, **Chats** (tus chats privados y la **supervisión** de todas las conversaciones), Reloj, Contactos, Finanzas, Contraseñas… y **Configuración → Usuarios** para gestionar todas las cuentas. **Configuración → Voz**: con la pantalla apagada lee en voz alta los mensajes de las apps que elijas. Puede ser tu launcher. | Música, Chat y Ajustes con diseño **cyber-brutalista** (cuadrícula, filos finos, títulos condensados, etiquetas mono `/01`). **10 temas de colores** (clásicos, extravagantes, tiernos y rudos) y **modo oscuro** en Ajustes. Barra inferior de celdas iguales: en la elegida crece el icono y se pinta del color del tema. **Deslizar a los lados** cambia de pantalla: los bloques corren borrosos uno por uno y llegan los nuevos. La música tiene lo mismo que KyraAdmin (nuevo álbum, cambiar nombre, foto, borrar, mover, marcar varias, buscar, favoritas, guardar/recibido, repetir y velocidad). Nunca es launcher. |
| Sin sesión | Pide el acceso de administrador. | Modo visitante (Música y Ajustes para entrar). |
| Identificador | `com.kyora.kyora_chat` | `com.kyora.kyora_chat.family` |

La regla se aplica en `AuthGate` (`lib/ui/auth_gate.dart`) según `AppFlavor` (`lib/app_flavor.dart`). Ojo: es una comprobación de la app; el servidor sigue siendo quien decide qué datos puede leer cada rol.

**Servidor:** el chat privado necesita la sección **§19** de `Server/supabase/schema.sql` (tablas `dm_*` y sus funciones). Vuelve a ejecutar el archivo entero en Supabase > SQL Editor (es idempotente). El chat de grupo de Merida (`family_*`) sigue igual.

**Voz (KyraAdmin):** en Configuración → Voz, enciéndela, toca «Dar acceso a notificaciones» y activa «Voz de Kyra» en los ajustes de Android, y marca las apps (WhatsApp, el chat de Kyra…). Con la pantalla apagada dice «Mensaje de WhatsApp. Ana dice: …» o «Ana te escribió: …»; al encender la pantalla se calla.

## Los dos modos de la interfaz: visitante y administrador
- **Al instalarla (y para cualquier visitante)** Kyra solo enseña **Música** y **Chat**, con una barra de navegación abajo (**Música · Chat · Ajustes**) y un diseño **cyber-brutalista** (el tema de colores y el modo oscuro se eligen en Ajustes). La música es la de tu carpeta del teléfono (y la que el administrador te mande); el chat es **privado, uno a uno**: cada quien le escribe a cualquier otra cuenta (lista de todas en «Nuevo chat»). Los mensajes se quedan en el servidor; «Borrar para mí» (mantener presionado) y «Vaciar chat» solo los ocultan para ti. Solo el administrador borra de verdad. Necesita sesión y la cuenta verificada. Si llega un mensaje con la app en segundo plano, sale un aviso del teléfono (sin Firebase: si Android cierra Kyra, el aviso llega al volver a abrirla).
- **Las cuentas no se crean aquí**: las crea el administrador (Configuración → **Usuarios**). En **Ajustes** el visitante entra con su **nombre y contraseña**; la primera vez escribe el **código de 6 dígitos** que le dio el administrador. Después, en ese teléfono, **solo pide la contraseña** (la app recuerda quién es; «No soy yo» lo olvida).
- **El administrador** entra desde **Ajustes → Acceso administrador** (correo y contraseña de siempre) y aparece **todo lo de siempre** (Inicio, Nube, Reloj, Contactos, Finanzas, Contraseñas…) con el diseño sci-fi. Si cierra sesión, la app vuelve al modo visitante.
- **Configuración → Usuarios** (administrador): quién está en línea (punto verde o «hace 3 h»), rol y si ya verificó; crear cuenta (te da el código de 6 dígitos, una sola vez), pasar a administrador/visitante, código nuevo y quitar el acceso.

## Instalar en tu teléfono (lo más fácil)
1. En la PC, ejecuta **`Scripts\Kyra\compilar_movil.bat`**. Crea **`Family\Kyra\KyraAdmin.apk`** (para ti) y **`Family\Kyra\KyraFamily.apk`** (para la familia); la primera vez tarda varios minutos. Para compilar solo una: `compilar_admin.bat` o `compilar_family.bat`.
2. Pasa el APK al teléfono (cable USB, Google Drive, WhatsApp, correo…).
3. En el teléfono, ábrelo. Android pedirá permiso para **instalar apps desconocidas** desde la app que usaste (Archivos, Drive…): actívalo solo para esa app.
4. Abre **KyraAdmin** y entra con **el mismo correo y contraseña** que pusiste en `Server\supabase\.env` (el usuario de Authentication > Users). La sesión queda guardada. Kyra **abre siempre**, también sin sesión (es un launcher): Inicio, la música ya guardada, contactos, Vault y tus tareas, hábitos y recordatorios locales siguen ahí; solo se pausan el chat, la música que manda la PC y la sincronización. Si la sesión caduca, Configuración → tu cuenta lo avisa y deja volver a entrar sin cerrar nada.

La app no lleva tu correo ni tu contraseña: solo la URL de tu proyecto y su clave pública (que salen de `Server\supabase\.env` al compilar).

## Ejecutarla con el teléfono conectado por USB (para desarrollar)
1. En el teléfono: *Ajustes > Acerca del teléfono* → toca 7 veces el número de compilación → *Opciones de desarrollador* → activa **Depuración USB**.
2. Conéctalo y acepta el aviso «¿Permitir depuración USB?».
3. Ejecuta **`Scripts\Kyra\iniciar_movil.bat`** (si hay varios dispositivos: `iniciar_movil.bat -d <id>`; mira los ids con `flutter devices`).

## Qué hace
- **Acceso** con correo y contraseña; errores en español.
- **Historial** de la conversación *General* (50 mensajes; al subir carga los anteriores) y **tiempo real**: lo que manda la PC aparece solo. Si se corta la conexión, al volver recupera lo que se perdió.
- **Burbujas**: las tuyas a la derecha, las de la PC a la izquierda con su nombre; **hora de envío** y **estado**: reloj *En espera*, ✓ *enviado* o el error con *Reintentar*.
- **Enviar** texto, **fotos** (galería o cámara) y **archivos** (hasta 50 MB). El mensaje sale «en espera» al instante; sin internet se queda así y se manda solo al volver, sin duplicarse.
- **Fotos** con miniatura y pantalla completa con zoom; **archivos** como tarjeta (se abren con la app del teléfono).
- **Mantener pulsado** un mensaje: copiar el texto o borrarlo (también se borra en la PC).
- **Música** (el icono ♪ de arriba): las canciones que bajas en la PC con **Descargar** suben solas a tu cuenta y salen aquí. Con la app abierta (aunque estés en el chat) **se guardan solas** en la carpeta que elijas (por omisión, *Música/Kyora*, y salen en el reproductor del teléfono). Con la carpeta (icono de arriba) eliges *Música* o *Descargas*, la subcarpeta y si se guardan solas. Las canciones anteriores a la primera vez que abriste la app quedan pendientes: tócalas o pulsa **Guardar todas**.

## Y además del chat (rondas 12 a 16)
- **Inicio** (la pantalla de siempre; el administrador puede usar Kyra como launcher: solo se ofrece como pantalla de inicio cuando entra el administrador; para un visitante es una app normal): un tablero con la hora, el **clima** (tócalo para ver el día **hora a hora**), el estado del teléfono y los accesos **NET** (Wi-Fi, Bluetooth y datos: un toque abre el panel del sistema y mantener abre los ajustes; Android no deja encenderlos desde una app).
- **Calendario**: toca la hora de Inicio y se abre a pantalla completa, sin botón de cerrar («atrás» lo cierra). Arriba solo van ‹ título ›, «Hoy» y, en la esquina, **Actualizar** y «+». Dos vistas, **Semana** (la de por defecto) y **Mes**: se cambia **pellizcando** (juntar los dedos pasa a Mes; separarlos, a Semana; el cambio se materializa con el efecto de holograma) y la que se abre por defecto se elige en **Configuración → Calendario**. El **Mes** ocupa toda la pantalla: el número grande del día elegido, el mes y el año, una cuadrícula de cuadros con acabado sci-fi que se estira hasta llenarla y las tarjetas de ese día debajo; la **Semana** apila los siete días en bandas de cristal oscuro, de borde a borde y con el efecto ciberpunk del fondo (la columna llega hasta abajo de la pantalla), y el elegido se abre con sus tarjetas y un campo para **añadir una tarea** a ese día. Todo se ve en **tarjetas** (hora en 12 h en un bloque de color, título, subtítulo y pie). Siempre se ve todo (**eventos, tareas, recordatorios y hábitos**), sin filtros. **Se actualiza solo** (Realtime, al volver a la app y tras cada cambio) y tiene botón **Actualizar**. Los recordatorios y los eventos se sincronizan con Supabase (tablas `reminders` y `events`): **vuelve a ejecutar `schema.sql`** para publicarlas en tiempo real.
- **Colores de la app**: el acento sale del fondo de pantalla y, ahora, también **otros tonos del fondo que no son el predominante** (aunque pesen poco) para las **tareas, los recordatorios y los hábitos** (en ese orden); si el fondo no da tonos suficientes se completan girando el del acento, y sin fondo quedan los de siempre. Los campos de escribir son de cristal (un velo del acento), no negros, y la **ficha de una tarea** es plana, como el detalle del clima: un rótulo apagado (ESTADO, ENTREGA…) y debajo el dato, sin paneles ni campos con caja.
- **Reloj** (menú circular → *Reloj*): **Alarmas** (hora con rueda, AM/PM, días que se repiten, nombre, interruptor; suenan con la app cerrada con una notificación de alarma de Android) y **Cronómetro** (iniciar, pausar, vueltas con la más rápida y la más lenta marcadas, reiniciar; sigue contando aunque salgas). Si hay un cronómetro en marcha o una alarma próxima, sale también como un panel en **Inicio**. Todo es **local**: se guarda en el teléfono (`SharedPreferences`) y no toca ninguna base de datos. La primera alarma pide el permiso de notificaciones y de alarmas exactas.
- **Música**: los álbumes salen en **cuadrícula, tres por fila**, pegados (margen muy pequeño e igual) y sin nombre (tocar uno lo abre con el efecto de holograma; mantenerlo presionado abre sus opciones). **Mantener presionado el disco** abre un **reactor de opciones** sobre un velo oscuro, solo con iconos: mover (muestra los álbumes en cuadrícula), borrar, cambiar nombre y **velocidad y tono**; al elegir esa última el propio reactor se vuelve un **dial** y se ajusta girando el dedo por el aro (de 0,5× a 1,5×). Con la lista abierta, el fondo es la portada oscurecida.
- **Estilo plano**: Finanzas, Mejoras, Contraseñas, Contactos (y la ficha de tarea y el clima) comparten la misma organización: una cabecera `> TÍTULO` con una línea fina, cada dato con su rótulo apagado encima y el valor debajo, filas separadas por líneas finas, campos que se ven como texto (sin caja) y opciones como texto con un cuadrito (la elegida, en el acento y subrayada). Sin paneles ni cajas. Las piezas están en `lib/ui/widgets/flat_form.dart`.
- **Teclado de Kyra**: la app trae su propio teclado, en su estilo (teclas cuadradas con filo de neón, `?123` para números y signos, mayúsculas con un toque / fija con dos, **mantener una vocal** abre sus acentos, flechas de cursor, pad numérico para números y teléfonos, y `@` / `.com` en los campos de correo). Sustituye al del sistema en **toda** la app (se instala con `TextInput.setInputControl`, sin tocar cada campo), sube las pantallas y los paneles como lo haría el del sistema, y se esconde con ⌄ o al soltar el foco. Pegar y copiar siguen con el menú de selección de Flutter.
- **Paneles de opciones**: todos (álbumes, avisos, menús…) oscurecen lo de atrás para que el panel mande; aparecen con el holograma y se apagan rápido y sin parpadeo.
- **Nube**: la pestaña **Local** es el **Vault**, la carpeta de tu almacenamiento donde se guarda lo tuyo; **la carpeta se elige en Configuración → Vault** (la sección solo la muestra). **Exportar** (arriba) abre el selector del sistema (almacenamiento interno, tarjeta, otros dispositivos) y **mueve** lo elegido al Vault (si el origen no deja borrar, queda copiado y lo avisa). Se ven dentro de la app **imágenes, vídeos, audios y textos**; PDF, Word y demás se abren con la app que tengas. **Mantener presionado** un archivo: abrir, **enviar a alguien** (menú de compartir del sistema), **subir a mi nube** (Storage `<tú>/cloud/`, hasta 50 MB; sale en la pestaña Nube y no necesita cambios en `schema.sql`), cambiar nombre y ver atributos.

No incluye (todavía): guardar canciones con la app cerrada (se ponen al día al abrirla), notificaciones con la app cerrada, que los mensajes «en espera» sobrevivan a cerrar la app, ni iPhone.

## Si algo no va
| Síntoma | Qué hacer |
|---|---|
| «Correo o contraseña incorrectos» | Usa el mismo usuario de *Authentication > Users* que pusiste en `Server\supabase\.env`. |
| «Falta crear la base de datos» o «Falta la parte de música» | Ejecuta `Server\supabase\schema.sql` en Supabase > SQL Editor (también si lo ejecutaste antes de que existiera la música: es seguro repetirlo). |
| «Esta app se compiló sin los datos de Supabase» | Ejecuta `Scripts\Kyra\preparar_movil.bat` (crea `Family\Kyra\env.json`) y vuelve a compilar. |
| «Sin conexión» | Revisa internet; si estás conectado, la app reintenta sola cada pocos segundos. |
| Los mensajes de la PC no llegan al instante | Mira que `schema.sql` se ejecutó completo (publica `messages` y `attachments` en Realtime). Al reabrir la app se ponen al día. |
| Comprobar la PC → base de datos | `Scripts\Kyora\probar_chat.bat --send` manda un mensaje de prueba. |

## Para quien toque el código
- Flutter 3 + `supabase_flutter`. Carpeta `lib/`: `data/` (el contrato con Supabase: `chat_repository.dart`, y `chat_backend.dart` para poder probar con uno falso), `state/chat_controller.dart` (mensajes, bandeja «en espera», reintentos, Realtime y puesta al día), `ui/` (pantallas y burbujas), `models/`, `util/`. La música: `state/music_controller.dart`, `data/music_backend.dart` y `data/music_store.dart` (ajustes y guardado; el guardado real es código nativo en `android/.../MainActivity.kt`, con MediaStore).
- El contrato con Supabase es el mismo que usa la PC: ver `Server\supabase\endpoints.md` (funciones `send_message`, `list_messages`…, bucket `chat-files`, Realtime).
- Pruebas: `flutter analyze` y `flutter test` (41 pruebas, sin red). La prueba **en vivo** usa el mismo repositorio contra tu Supabase real: `set KYORA_LIVE=1` y `flutter test test\live_test.dart` (lee `Server\supabase\.env`, manda un mensaje con un archivo, comprueba el tiempo real, lo baja y lo borra).
- `Family\Kyra\env.json` (URL y clave pública) lo genera `Scripts\Kyra\preparar_movil.bat` y no se sube a git.
