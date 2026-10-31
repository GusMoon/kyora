# Comandos de Kyora

Es la lista de todo lo que se puede hacer con el teclado y el ratón. Úsala como referencia para pedir cambios.

Los atajos se pueden cambiar en `%APPDATA%\Kyora\config.json` (sección `hotkeys`). Cada atajo apunta a una acción por su nombre (columna **Acción**).

## Atajos globales

Sirven en todos los escritorios y todos usan `Ctrl+Shift` (los `Alt+…` quedan libres para las apps).

| Atajo | Qué hace | Acción |
|---|---|---|
| `Ctrl+Shift+Espacio` | Buscador (sale del borde de arriba, en el sitio del panel superior); otra vez, lo cierra | `search.toggle` |
| `Ctrl+Shift+T` / `Ctrl+Shift+N` / `Ctrl+Shift+C` | **Tareas** (abren **directo el tablero Kanban**) / **notas** / **chat**, en el buscador | `search.open_mode` |
| `Ctrl+Shift+←/→/↑/↓` | Mover la ventana con foco: se intercambia con la vecina de ese lado | `wm.move` |
| `Ctrl+Shift+Alt+←/→/↑/↓` | Orientación de la ventana con foco: la ventana grande del mosaico pasa a ese lado (`↓` otra vez la **minimiza** al panel izquierdo) | `wm.arrange` |
| `Ctrl+Shift+F` | Pasar el foco a la siguiente ventana del mosaico | `wm.focus_next` |
| `Ctrl+Shift+R` | **Reemplazar**: carrusel con las ventanas en espera; la elegida ocupa el sitio de la enfocada (ver abajo) | `switcher.toggle` |
| `Ctrl+Shift+W` | **Fondos de pantalla**: solo se ven los fondos y el escritorio; las flechas los cambian y los colores de Kyora los siguen (ver abajo) | `wallpaper.mode` |
| `Ctrl+Shift+E` | Nuevo escritorio (y se va a él, deslizando la pantalla) | `desktop.create` |
| `Ctrl+Shift+RePág` / `Ctrl+Shift+AvPág` | Ir al escritorio anterior / siguiente: la pantalla se desliza. El panel izquierdo asoma con su número | `desktop.step` |
| `Ctrl+Shift+X` | **Apagar, reiniciar o suspender** en el centro, con todo lo demás desenfocado (ver abajo) | `power.menu` |
| `Ctrl+Shift+Q` | Cerrar la ventana con foco | `wm.close` |
| `Ctrl+Shift+1` / `2` / `3` | Dejar 1, 2 o 3 ventanas en el mosaico (aparca las que sobran o trae las que esperan) | `wm.show_count` |
| `Ctrl+Shift+Alt+E` | Cerrar este escritorio: sus ventanas pasan al anterior | `desktop.close_current` |
| `Ctrl+Shift+Alt+X` | Cerrar todas las ventanas de todos los escritorios (cierre amable: las apps pueden preguntar si guardar) | `wm.close_all` |
| `Ctrl+Shift+M` | Música: abre el panel de arriba con tus listas de YouTube; entra a una lista y **escucha** sus canciones sin bajarlas o **descárgalas** en MP3 a la carpeta Música | `music.panel` |
| `Ctrl+Alt+Shift+Q` | Salida de emergencia: devuelve todo a Windows y cierra Kyora | `app.release` |

**La tecla Windows está bloqueada.** Kyora la traga entera mientras está abierta: no abre el menú de inicio ni forma ningún atajo de Windows (`Ctrl+Shift+E`, `Win+D`, `Ctrl+Shift+Tab`…). Tampoco funciona `Ctrl+Esc` (que abre el Inicio). La excepción es `Win+L` (bloquear el equipo): lo resuelve Windows antes que ningún programa y no se puede bloquear. Un atajo con `win` en `config.json` se rechaza y se avisa en el log. Ojo: Kyora se traga también `Ctrl+Shift+flechas` y `Ctrl+Shift+RePág/AvPág`, que editores y navegadores usan para seleccionar palabras o mover pestañas; cámbialos en `config.json` si te estorban.

**El mosaico siempre está activo.** Desde que abres un escritorio, las ventanas nuevas entran solas en un mosaico de hasta 3 (las demás esperan en el **panel izquierdo**); una ventana nueva ocupa el sitio de la que tiene el foco y esta pasa a la espera si ya hay 3. Cada escritorio tiene hasta **4 ejes** (ramas de trabajo): cada eje es su propio mosaico de máx. 3 ventanas con su espera. Solo se ve un eje a la vez (`Win+Shift+flechas` para pasar de uno a otro); los demás se ven en el mapa (`Ctrl+Shift+Tab`). Ya no hay pizarrón infinito ni ventanas libres.

**Dentro del panel de Ctrl+Shift+R** (se abre sobre la ventana con foco; opaco, una placa sólida sin transparencias; las capturas se ven nítidas y la elegida lleva un borde del color de Kyora):

| Tecla | Qué hace |
|---|---|
| `↑` / `↓` (o `K` / `J`, o la rueda) | Elegir otra ventana |
| `Enter` o clic | Ponerla en el sitio de la ventana enfocada: la que estaba ahí pasa al panel izquierdo |
| `Supr` | Cerrar la ventana elegida |
| `Esc` | Salir |

Si no hay ventanas fuera de la pantalla, el panel muestra "No hay ventanas fuera de la pantalla".

**Dentro del buscador:** escribe para buscar **ventanas, apps, carpetas y archivos** a la vez; `↑`/`↓` eligen, `Enter` abre y `Esc` cierra. Tres caracteres especiales acotan la búsqueda. Además:

| Escribe | Qué sale |
|---|---|
| `<texto` | **Solo aplicaciones** |
| `/texto` | **Solo carpetas**: las que se llaman así, en toda tu carpeta personal y tus otras unidades, con su ruta |
| `@texto` | **Solo archivos**, con su tamaño y su ruta |
| `Ctrl+Shift+T` | Tus tareas: directo el **tablero Kanban** (ver abajo) |
| `Ctrl+Shift+N` | Tus notas, con formato, en el mismo buscador, que se ensancha |

**Archivos (``/` y `@``, `/`, `@`):** en el árbol, `→` despliega una carpeta, `←` la pliega (o sube a la de arriba), `Enter` en un archivo lo abre con su programa y `Ctrl+Enter` abre la carpeta en el Explorador de Windows. En los resultados de `/`, `Enter` abre esa carpeta como árbol. Para buscar rápido, Kyora guarda un índice de tus carpetas y archivos (sin AppData, `.git`, `node_modules`, entornos de Python ni lo oculto) que rehace cada 15 minutos; al arrancar tarda unos segundos.

**Tareas (`Ctrl+Shift+T`):** abren **directo el tablero Kanban**, que es lo único que hay (ya no existe la lista cronológica). El buscador se ensancha y su campo de arriba, con el cursor ya puesto, **solo sirve para crear una tarea nueva**: escribes el nombre y `Enter` la crea y la abre. Si no escribes nada, el tablero se recorre con el teclado como siempre.

Cuatro columnas, **Pendiente · En proceso · En revisión · Finalizada**, con tarjetas pequeñas (título, etiquetas, fecha y subtareas). Si una columna tiene más tareas de las que caben, **se desplaza con la rueda** (sin barra) y sus bordes se oscurecen mientras tanto, para que nada se vea cortado en seco; el efecto se desvanece al parar. El **+** de cada columna crea una tarea con ese estado.

Comandos de esta sección (solo valen aquí; también están en Configuración › Atajos › Tareas):

| Tecla | Qué hace |
|---|---|
| `↑` `↓` `←` `→` | Elegir tarjeta (con algo escrito arriba, `←`/`→` mueven el cursor del texto) |
| `Enter` | Abrir la tarjeta elegida (con algo escrito arriba, crea una tarea nueva) |
| `Ctrl+←` / `Ctrl+→` | Pasar la tarjeta al estado anterior / siguiente |
| `Ctrl+Enter` | Terminarla (otra vez: reabrirla) |
| `Ctrl+Supr` dos veces | Borrarla: la primera vez solo avisa en la tarjeta, la segunda la borra |
| Arrastrar · clic · rueda | Cambiar de columna · abrirla · desplazar la columna |
| `Esc` | Cerrar el buscador (con una tarea abierta: volver al tablero) |

**La tarea abierta:** el campo de arriba se va y el detalle ocupa su sitio directamente en la barra, más ancho. A la **izquierda** las **subtareas** (círculo para terminarlas, arrastrar para ordenar, `×` para borrar, doble clic para renombrar) y a la **derecha** la **descripción**. Arriba, el nombre, su fecha de entrega, las **etiquetas** (`+ etiqueta` y `Enter`; se crean si no existen y se sugieren las que ya hay; la `×` de cada una la quita) y el estado a la derecha. Abajo, el campo para añadir subtareas. `Esc` vuelve al tablero.

**Chat (`Ctrl+Shift+C`):** mensajes de texto, fotos, archivos y todo lo demás entre tus dispositivos (esta PC y tu móvil, con una sola cuenta tuya), con **Supabase** de servidor. Se abre en el mismo buscador, más estrecho (una columna), sin el campo de arriba. Los de este dispositivo van a la derecha y los de los otros a la izquierda, con el nombre del dispositivo; cada uno lleva su **hora de envío** y su **estado**: **en espera** (un reloj y «En espera») mientras no ha salido y **enviado** (✓) cuando ya llegó. Si no hay internet, el mensaje se guarda y sale solo al volver (sin duplicarse). Los mensajes de los otros dispositivos llegan **al instante** (Supabase Realtime) y, con el chat cerrado, avisan con un aviso corto. Arriba a la derecha se ve la conexión: *En línea*, *Sin conexión*, *Sin configurar* (faltan datos en `supabase/.env`) o *No se pudo entrar* (correo o contraseña mal).

| Tecla | Qué hace |
|---|---|
| `Enter` / `Shift+Enter` | Envía / salta de línea |
| `+`, `@` o `Ctrl+O` | Abre a la derecha **tu árbol de carpetas** (el mismo de `/`); **un clic en un archivo lo envía**; una carpeta se despliega |
| `Ctrl+V` | Pega texto, **fotos** del portapapeles o **archivos** copiados (también se pueden **soltar** desde el Explorador) |
| `RePág` / `AvPág` o la rueda | Desplaza; arriba del todo, carga mensajes anteriores |
| Pasar el cursor por un mensaje | Enseña su **hora** (y ✓) arriba y, debajo, **Copiar**, **Descargar** (si lleva archivo, a tu carpeta Descargas) y **Borrar** (pide una segunda pulsación) |
| Clic en una foto o documento | Se baja (si hace falta) y se abre; el icono de bajar de la tarjeta de un documento lo guarda en Descargas |
| Clic en un error rojo | Reintenta enviarlo |
| `Esc` | Cierra el árbol de archivos; con el árbol cerrado, el chat |

Los mensajes de otros dispositivos llevan una **lechuza** y el nombre del dispositivo; los tuyos, un cuadro redondeado. Los documentos (PDF, Word, TXT, MD) salen como una **tarjeta** con su nombre, un extracto del contenido y su tamaño.

**Mandar un archivo al chat desde el buscador:** con `/` abres el árbol de carpetas; elige un archivo y pulsa `Ctrl+Enter` para enviarlo al chat sin abrirlo (el buscador sigue abierto y un aviso lo confirma). `→` lo previsualiza y `Enter` lo abre.

Archivos: hasta 50 MB cada uno (el límite del plan gratuito de Supabase; se cambia en `chat.max_mb` de `config.json`). Los archivos preparados salen como una tarjeta con su ✕ encima del campo. **Puesta en marcha:** ver `supabase/README.md` (el script de la base es `supabase/schema.sql` y las credenciales van en `supabase/.env`, que no se sube a git).

**El chat en el móvil:** la app `mobile\` (Flutter, Android) enseña la misma conversación: lo que mandas desde la PC aparece en el teléfono al instante y lo que escribes en el teléfono llega a la PC (en el chat, a la izquierda, con el nombre `movil`). Se instala con `scripts\compilar_movil.bat` (crea `mobile\KyoraChat.apk`); detalles en `mobile\README.md`. `scripts\probar_chat.bat --send` comprueba desde la PC que todo guarda bien en la base de datos.

**Notas (`Ctrl+Shift+N`):** una nota a la vista, en el mismo buscador (que se ensancha). Arriba, la **barra de formato**: **negrita**, *cursiva*, ~~tachado~~, título, lista, cita y enlace (el enlace se escribe en un campo que aparece debajo de la barra: Enter lo pone, Esc lo cancela). Debajo, "TÍTULO" con la fecha y `‹ 2 / 5 ›`, el título de la nota, una línea fina y el texto. Se guarda solo al dejar de escribir.

| Tecla | Qué hace |
|---|---|
| `Ctrl+N` | Nota nueva: el contenido se desvanece y queda la hoja en blanco |
| `Ctrl+RePág` / `Ctrl+AvPág` (o las flechas de arriba) | Nota anterior / siguiente, con el mismo desvanecido |
| `Ctrl+B` · `Ctrl+I` · `Ctrl+K` | Negrita · cursiva · enlace |
| `Ctrl+Supr` dos veces | Borrar la nota: la primera vez avisa abajo, la segunda la manda a la Papelera. Sin ventana de confirmación |
| `Esc` | Cerrar el buscador |

Cada nota es un archivo `.md` en `Documentos\Notas Kyora`, con el texto en **Markdown** (`**negrita**`, `> cita`, `- lista`, `[enlace](https://…)`): se puede abrir con cualquier programa. Las notas de antes, de texto plano, se abren sin perder sus saltos de línea.

**Fondos de pantalla (`Ctrl+Shift+W`):** solo se ve el fondo y, abajo, la tira de fondos de `Imágenes\wallpapers` (el elegido grande en el centro y los vecinos inclinados); no se muestra ninguna ventana ni panel. `←`/`→` (o la rueda) cambian de fondo: el nuevo aparece sobre el anterior con un barrido circular y un aro de luz, y **los colores de Kyora cambian con él** al instante: salen **100 % del fondo** (el acento es el color que más ocupa la imagen; si el fondo es gris, un gris claro). `Enter` deja ese fondo (lo pone en Windows) y `Esc` vuelve al fondo y a los colores que tenías. El carrusel de `>wallpaper` en el buscador sigue existiendo.

**Apagar (`Ctrl+Shift+X`):** la pantalla se desenfoca con todo lo que haya (ventanas y paneles) y en el centro salen **Apagar, Reiniciar y Suspender**. `←`/`→` (o `1`, `2`, `3`) eligen y `Enter` ejecuta; `Esc` o un clic fuera lo cierran. Apagar y reiniciar devuelven antes las ventanas a Windows, así que las apps que tengan algo sin guardar te lo preguntan.

**Tecla Windows:** está bloqueada (ver arriba): pulsarla no hace nada. El buscador se abre con `Ctrl+Shift+Espacio`.

## Paneles de los bordes (ratón)

No hay marco ni barra: las ventanas usan toda la pantalla. Dos paneles salen de los bordes al acercar el cursor y se esconden al quitarlo. Los dos son piezas pequeñas y sueltas con el mismo estilo minimalista: placa oscura plana, sin relieve en el borde y solo una sombra sutil; nacen del borde de la pantalla con dos pestañitas y, mientras están fuera, el resto de la pantalla se oscurece un poco. Con un salto fluido al abrir.

**Buscador y páginas web:** si escribes el nombre de una página guardada en Configuración › Atajos › Páginas web, sale en la sección **Páginas** (con el icono del navegador elegido y su dirección debajo) y `Enter` la abre en ese navegador.

**Música → móvil:** cada canción que bajas con **Descargar** sube sola a tu cuenta de Supabase (con la misma sesión del chat; hasta 50 MB por canción) y la app del móvil la muestra y la **guarda sola en su carpeta** (por omisión, *Música/Kyora*; se cambia desde el móvil). En la página de Música, la línea de avisos dice *Mandando «…» a tu móvil…* y *En tu móvil: «…»*; sin internet, la canción queda pendiente (`%APPDATA%\Kyora\music_sync.json`) y sale al volver. Pulsar el icono de descarga de una canción **ya bajada** la manda al móvil si no había ido (el botón general no reenvía lo viejo, para no llenar tu espacio gratis de Supabase: 1 GB). Se apaga con `"sync": false` en la sección `music` de `config.json`. **Requiere** volver a ejecutar `supabase\schema.sql` una vez (crea la tabla `music_tracks`).

**Lo que suena (panel de abajo a la derecha):** al reproducir algo desde Música, encima de la hora sale una **tarjeta** con el diseño de la referencia: un reproductor de bolsillo oscuro y casi cuadrado. Arriba, la **pantalla**: la **carátula** hecha pixeles gordos, con rayas de monitor, motas y una sombra interior en el borde (sin marco aparte), teñida con los colores del fondo de pantalla (sin carátula, solo esa luz de colores y una nota). Sobre la imagen: el **nombre** del audio arriba (se desliza si no cabe) y abajo el **tiempo** en grande y las **ondas** (cada barra es un trozo de la canción y su alto, lo fuerte que sonó ahí; lo que ya sonó es claro y lo que falta son puntitos) con la **línea de reproducción** en el color de acento. Los botones **solo salen al pasar el cursor por la carátula**: a los lados, **‹** (anterior: si ya sonaron más de 3 s, vuelve al principio de la misma) y **›** (siguiente; no sale en la última) y, en el medio, tres botones iguales de los de las flechas (círculos planos, sin relieve) con el icono a línea: **pausa/seguir** (el icono va en el acento mientras suena), **descargar** (baja la canción que suena a tu carpeta Música y la manda al móvil; el icono va en el acento mientras baja y pasa a ✓ al acabar; si ya estaba bajada, la vuelve a mandar al móvil) y **cerrar** (detiene la música y cierra la tarjeta). El panel crece (unos 340 px; menos si la pantalla es baja, para que siempre se vea entera) para dejarle sitio y se encoge al detener; cerrar quita la tarjeta, **no el panel**.

**Panel superior** (cursor en el centro del borde de arriba): una píldora con las cinco secciones, sin líneas entre ellas: **Buscar** (`Ctrl+Shift+Espacio`), **Tareas** (`Ctrl+Shift+T`), **Notas** (`Ctrl+Shift+N`), **Chat** (`Ctrl+Shift+C`) y **Música** (`Ctrl+Shift+M`; lo que suena **ya no sale aquí**: se ve en la cápsula del panel de abajo a la derecha). La sección bajo el cursor se aclara y **la abierta se expande hasta ocupar todo el ancho que sobra** del panel: su círculo se ensancha en una píldora hundida con el icono y su nombre (Buscar, Tareas, Notas, Chat, Música), y se encoge al abrir otra. Las secciones van directo sobre el fondo del panel, sin recuadro detrás. **La píldora no desaparece al entrar en una sección**: Buscar, Tareas, Notas y Chat se abren en el mismo panel, con la píldora arriba (la sección abierta destacada) y su contenido desplegado debajo; pulsar otra sección cambia a ella, pulsar la abierta no hace nada (dentro de una tarea, vuelve al tablero) y Música cierra el buscador y abre su página arriba. Dentro del buscador la píldora no enseña lo que suena. Música se abre debajo de la píldora; las otras abren lo suyo en el mismo sitio y el panel se esconde. Los fondos de pantalla ya no tienen icono: `Ctrl+Shift+W`.

**Panel de sistema** (cursor en la esquina de abajo a la derecha): sobre un fondo gris oscuro con un desenfoque sutil de lo que hay detrás (cuando está quieto), dos tarjetas un poco más claras. La de arriba junta toda la información en grande: la **hora** y la **fecha** (pulsa esa parte: el calendario del mes), el **clima de ahora** (temperatura, cielo y lugar) y la **RAM** y la **batería** (porcentaje y detalle; en rojo si la RAM pasa del 90 % o la batería baja del 15 % sin cargar). La de abajo, solo los iconos de **Wi‑Fi** (se enciende si hay red), **Bluetooth** y **Ajustes**. Los iconos de Wi‑Fi y Bluetooth se ven **hundidos** (como un botón pulsado, con el acento encendido) cuando están conectados. Pulsar la hora o un icono abre su página en el mismo panel, con una flechita para volver; el panel se queda abierto mientras lo uses (se cierra con `Esc` o pulsando fuera). El panel nace de la esquina con una curva a cada lado, como si saliera de los dos bordes de la pantalla.

| Pieza | Qué hace |
|---|---|
| Hora y fecha | Pulsarla: la hora en grande, la fecha y el calendario del mes (`‹` `›` cambian de mes) |
| Clima | La temperatura de ahora donde estés (por tu IP, o la ciudad de `config.json`: `"weather": {"city": "Tu ciudad"}`); el estado y el lugar al dejar el ratón encima |
| Wifi | Pulsarlo: redes disponibles, conectar (con contraseña si hace falta), desconectar, buscar |
| Bluetooth | Pulsarlo: encender o apagar, y tus dispositivos emparejados (conectados primero) |
| Batería y RAM | Su porcentaje; el detalle al dejar el ratón encima |

**Panel izquierdo** (cursor en el centro del borde izquierdo): una tira estrecha con solo los **iconos de las ventanas que no se ven** (fuera de la pantalla o minimizadas); el nombre sale como ayuda al pasar el ratón por encima. Si no hay ninguna, no sale.

- **Un clic** en una ventana la trae al centro de la pantalla.
- **Arrastrarla** la deja donde la sueltes: si la sueltas sobre una zona del mosaico, ocupa ese sitio. Soltarla pegada al borde izquierdo cancela.
- Al **crear un escritorio o cambiar de uno a otro** (la pantalla se encoge, se centra y se desliza al otro escritorio, y vuelve a su tamaño) la tira asoma sola y su luz se mueve con el deslizamiento, en tiempo real, con otra página: una barra con los **números de los escritorios**, donde el nuevo se ilumina. Pulsar un número va a ese escritorio.

La ventana con el foco lleva una línea fina con el color de tu fondo de pantalla que **se ilumina donde pasa el cursor**: al acercarlo a menos de unos 150 px del borde, una luz neón sube alrededor del cursor y lo sigue por el contorno; al alejarlo se apaga. Nada gira ni se anima en reposo.

**Letra e iconos:** en toda la aplicación hay un solo tamaño de letra (`font_px`, 12) y un solo tamaño de iconos (`icon_px`, 18) en `theme.py`; lo único que distingue un título es la negrita.

**Mosaico (siempre activo):** hay dos columnas, izquierda y derecha, y como mucho 3 ventanas: una columna entera y la otra partida en dos (arriba y abajo). Una ventana nueva se abre a un lado mientras haya menos de 3. Al **arrastrar** una ventana se ven los **4 sitios** donde puede quedar (izquierda-arriba, izquierda-abajo, derecha-arriba, derecha-abajo) y el rectángulo donde quedaría de verdad según el sitio bajo el cursor; al soltarla ahí, las demás se acomodan solas: con 2 se parte la columna donde sueltes (arriba o abajo) y con 3 la ventana cambia con la de ese sitio, que pasa al panel izquierdo. Soltarla fuera de la pantalla la devuelve a su hueco.

**Acomodo de Windows:** mientras Kyora está abierta se apagan el acoplado a los bordes, la maximización al llevar una ventana arriba y el encogerse al arrastrar una maximizada (`"disable_snap": false` en `config.json` lo deja como Windows).

**Panel del wifi:** arriba el estado y los botones Buscar y Desconectar; debajo las redes, de mejor a peor señal, con su candado si tienen contraseña. Un clic en una red guardada o abierta conecta; en una con contraseña despliega el campo (con "Ver" para mostrarla). Si no sale ninguna red, Windows puede estar pidiendo permiso de ubicación para las apps de escritorio: el panel lo dice y tiene un botón para abrir ese ajuste.

## Borde luminoso

El borde de **todas** las ventanas visibles se enciende donde está el cursor cuando se acerca (a menos de 150 px), tengan el foco o no. La ventana con foco además lleva siempre una línea fina.
## Configuración (botón de la barra de arriba)

No tiene atajo: se abre con la ficha **Ajustes** del panel de sistema (esquina de abajo a la derecha). Se abre en ese mismo panel, crece hacia arriba y es alta y no tan ancha (720 × 580) y se divide en dos zonas:

- **Barra lateral:** las áreas, **Atajos**, **Ejecutables**, **Fondos**, **Rendimiento** y **Predeterminados**, con su contador (menos Predeterminados).
- **Atajos:** un campo para **filtrar** (por las teclas o por lo que hacen), el orden **por sección** (Navegación, Ventanas, Escritorios, Sistema, Tareas) o **por tecla** principal (Ctrl+Shift, Ctrl+Shift+Alt, Ctrl, Alt, Otras). Todo va en **una sola lista con scroll vertical** (sin barra a la vista), con secciones que tienen su título y una línea de explicación, y cada atajo con sus **teclas dibujadas** a la izquierda y lo que hace a la derecha.
- **Cambiar un atajo:** al pasar el cursor por una fila de Atajos sale **Editar**. Pulsas la combinación nueva (la página la dibuja al momento), `Enter` o **Guardar** la aplica y `Esc` o **Cancelar** la deja como estaba. Se guarda en `config.json` y vale al instante, sin reiniciar. **Restaurar** (arriba a la derecha, con confirmación) vuelve a los atajos de fábrica. En un grupo (las flechas, `1/2/3`, `T/N`) **las teclas se quedan** (se ven atenuadas) y solo se escribe lo previo: pulsa los **modificadores** nuevos (Ctrl, Mayús, Alt) y mira cómo queda, por ejemplo `Ctrl` `Alt` + `←/→/↑/↓`; `Enter` guarda.
- **Comprobaciones:** la página no deja guardar una combinación que no valga y dice por qué: usa la tecla Windows (bloqueada), no tiene Ctrl ni Alt, es de las que usan todas las apps (`Ctrl+C`, `Ctrl+V`, `Alt+F4`…), **ya la usa otro atajo de Kyora** (te dice cuál) u otro programa ya la tiene registrada.
- **Atajos › Páginas web:** junto al título de Atajos hay dos píldoras, **Teclas** (lo de arriba) y **Páginas web**. En Páginas web cada fila es una página con su **nombre** (lo que escribes en el buscador) y su **dirección** (lo que se abre); aparece con el icono del navegador elegido. Al pasar el cursor salen **Editar** y **Borrar** (Borrar pide una segunda pulsación: «¿Borrar?»); **+ Añadir página** abre dos campos en la misma fila (nombre y dirección), `Enter` o **Guardar** la aplica y `Esc` o **Cancelar** la deja. Se guarda en `web_shortcuts` de `config.json`. Si la dirección no lleva `https://`, se pone sola.
- **Predeterminados › Navegador:** el navegador con el que se abren las páginas web. Al pulsar **Cambiar** se despliegan los navegadores instalados (los de Windows: Brave, Chrome, Edge, Firefox…) y **Predeterminado de Windows** (el que tengas puesto en el sistema); el elegido lleva una marca. Se guarda en `defaults.browser` de `config.json`.
- **Ejecutables:** reiniciar, actualizar, abrir con consola, rescate, arrancar con Windows y desconectar, por secciones. Cada uno tiene un botón **Ejecutar** que pide confirmar ahí mismo.
- **Scroll:** al desplazar (rueda, touchpad, `↑`/`↓`, `RePág`/`AvPág`) los bordes de arriba y de abajo de la lista se oscurecen muy pegados al límite, solo mientras te desplazas; al parar, el efecto se desvanece solo.

- **Fondos:** una cuadrícula de **miniaturas** de las imágenes de `Imágenes\wallpapers`. Las flechas mueven la elección (borde de énfasis y su nombre abajo) y **el fondo solo cambia con `Enter` o con un clic**; el que está puesto lleva la etiqueta **En uso** y los colores de Kyora siguen al nuevo. Cada miniatura enseña abajo a la derecha, como cuatro puntos, **los 4 colores que más se repiten** de esa imagen (del que más al que menos); con ellos Kyora define su paleta: el acento (1.º), el segundo, el tercero y el cuarto. Los fondos oscuros no cambian nunca. Las miniaturas se leen solo cuando se ven (en un hilo, ya reducidas) y en memoria quedan 48 como mucho.
- **Rendimiento:** el **Modo ligero** (activado por defecto) apaga el deslizamiento al cambiar de escritorio y el borde luminoso de las ventanas. Se cambia con un interruptor y vale al momento. Además, Kyora ya no guarda el fondo desenfocado de pantalla y guarda menos y más pequeñas las capturas de ventanas (12 de 640 px como mucho).

**Panel superior:** al dejar el cursor un instante (45 ms) sobre el icono de Música se abre su página **al instante**, sin clic ni animación de transformación (no hace capturas de las páginas); pulsar el icono de la página abierta la repliega.

Dentro: escribir filtra, `Tab` cambia de área y `Esc` borra el filtro (o cierra).

Al agrandar o achicar una ventana no hay animación con capturas estiradas: se coloca al instante.
