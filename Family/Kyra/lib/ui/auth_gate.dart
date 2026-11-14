import 'dart:async';

import 'package:flutter/material.dart';

import '../data/account_backend.dart';
import '../data/audio_engine.dart';
import '../data/audio_levels.dart';
import '../data/background_playback.dart';
import '../data/chat_backend.dart';
import '../data/cloud_files.dart';
import '../data/cover_store.dart';
import '../data/duration_cache.dart';
import '../data/event_store.dart';
import '../data/favorites_store.dart';
import '../data/habit_backend.dart';
import '../data/habit_store.dart';
import '../data/music_backend.dart';
import '../data/music_store.dart';
import '../data/nav_hint_store.dart';
import '../data/reminder_scheduler.dart';
import '../data/reminder_store.dart';
import '../data/server_stats.dart';
import '../data/sync_rows.dart';
import '../data/task_backend.dart';
import '../data/task_store.dart';
import '../models/event.dart';
import '../models/habit.dart';
import '../models/profile.dart';
import '../models/reminder.dart';
import '../models/task.dart';
import '../state/cloud_controller.dart';
import '../state/contacts_controller.dart';
import '../state/dock_controller.dart';
import '../state/event_controller.dart';
import '../state/habit_controller.dart';
import '../state/local_music_controller.dart';
import '../state/music_controller.dart';
import '../state/player_controller.dart';
import '../state/reminder_controller.dart';
import '../state/server_controller.dart';
import '../state/task_controller.dart';
import '../state/now_playing_backdrop.dart';
import '../state/system_controller.dart';
import '../state/vault_controller.dart';
import '../state/wallpaper_controller.dart';
import '../state/weather_controller.dart';
import '../theme.dart';
import 'contacts_page.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'music_page.dart';
import 'nube_page.dart';
import 'settings_page.dart';
import 'section_host.dart';
import 'widgets/app_section.dart';
import 'widgets/pixel_glyph.dart';

/// La puerta de entrada. **La app siempre abre** (también como launcher): sin sesión se ve Inicio, la música ya guardada, los contactos, el Vault y
/// las tareas, hábitos y recordatorios locales de la última cuenta; solo se pausa lo que necesita el servidor (el chat, la música que manda la
/// PC y la sincronización). El acceso (o crear una cuenta) se abre desde Configuración → cuenta. Con sesión mira qué rol tiene la cuenta y abre
/// las secciones de la app, que se recorren con el menú circular (`SectionHost`): Inicio · Nube · Música · Contactos. La **Nube** junta lo del
/// servidor (cuánto ocupa tu Supabase y sus archivos), lo local (el Vault) y, solo para el administrador, el chat: sin sesión solo funciona Local. Las tareas, recordatorios y hábitos (y el calendario) viven en la hora de Inicio: tocarla la expande. La configuración se abre desde el menú. Con sesión también arranca la música: las canciones que lleguen se guardan solas
/// aunque estés en otra sección.
class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.account,
    required this.chat,
    required this.music,
    required this.musicStore,
    required this.saver,
    required this.roleCache,
    required this.engine,
    this.durations,
    this.favorites,
    this.covers,
    this.levels,
    this.tasks,
    this.openTaskStore,
    this.habits,
    this.openHabitStore,
    this.openReminderStore,
    this.reminderScheduler,
    this.reminderBackend,
    this.events,
    this.openEventStore,
    this.live,
    this.server,
    this.cloud,
    this.serverStore,
    this.background,
    this.weather,
    this.dock,
    this.system,
    this.contacts,
    this.vault,
    this.wallpaper,
    this.nowPlaying,
    this.navHint,
    this.now,
  });

  final AccountBackend account;
  final ChatBackend chat;
  final MusicBackend music;
  final MusicStore musicStore;
  final TrackSaver saver;
  final RoleCache roleCache;

  /// Crea el motor de audio del reproductor (el real usa `just_audio`; los tests, uno falso).
  final AudioEngine Function() engine;

  /// Lo que duran las canciones, recordado en el teléfono (sin esto solo se recuerda mientras la app está abierta).
  final DurationCache? durations;

  /// Las canciones favoritas (los corazones). Sin esto no hay corazones.
  final FavoritesController? favorites;

  /// Las imágenes elegidas para las canciones enviadas, recordadas en el teléfono.
  final CoverStore? covers;

  /// De dónde se lee el sonido, para el círculo del disco.
  final AudioLevels? levels;

  /// Supabase para las tareas. Sin esto el Calendario no tiene tareas.

  /// Abre la base local de las tareas de esa cuenta (sin esto, una en memoria).
  final TaskBackend? tasks;

  final Future<TaskStore> Function(String userId)? openTaskStore;

  /// Supabase para los hábitos y la base local de los de esa cuenta (sin la base, una en memoria). Sin Supabase no hay hábitos.
  final HabitBackend? habits;
  final Future<HabitStore> Function(String userId)? openHabitStore;

  /// Dónde se guardan los recordatorios de esa cuenta y cómo se programan sus avisos (también los de los hábitos). Sin el programador el
  /// Calendario no tiene recordatorios.
  final Future<ReminderStore> Function(String userId)? openReminderStore;
  final ReminderScheduler? reminderScheduler;

  /// Supabase para los recordatorios (sin esto solo viven en el teléfono) y para los eventos del calendario (sin esto no hay eventos), con
  /// la base local de los de esa cuenta (sin ella, una en memoria).
  final RowBackend<Reminder>? reminderBackend;
  final RowBackend<CalendarEvent>? events;
  final Future<EventStore> Function(String userId)? openEventStore;

  /// Avisa cuando cambia algo en Supabase (tareas, hábitos, recordatorios, eventos) para ponerse al día al instante. Sin esto solo se
  /// sincroniza al abrir, al volver a la app, tras un cambio y con el botón «Actualizar».
  final LiveBackend? live;

  /// Supabase para medir cuánto ocupa el proyecto (la Nube lo enseña y avisa al llegar al 80 %) y para listar y borrar los archivos del servidor.
  /// Sin esto la Nube no tiene esas partes. `serverStore` recuerda los límites y los avisos (sin él, solo mientras la app esté abierta).
  final ServerBackend? server;
  final CloudBackend? cloud;
  final ServerStore? serverStore;

  /// Dónde se recuerda si los álbumes se ven en pila o en cuadrícula.


  /// Lo que mantiene la música sonando en segundo plano (red despierta, permiso de notificaciones) y el estado de la batería (Ajustes).
  final BackgroundPlayback? background;


  /// El clima de Inicio y su ciudad. Sin esto no hay tarjeta del clima ni grupo «Clima».
  final WeatherController? weather;

  /// Las 8 apps del disco de Inicio. Sin esto no hay disco ni grupo «Apps del disco».
  final DockController? dock;

  /// El estado del teléfono para Inicio (batería, memoria, almacenamiento, Wi-Fi y Bluetooth). Sin esto esos paneles dicen que no hay.
  final SystemController? system;

  /// Los contactos del teléfono (la sección «Contactos»). Sin esto la sección no sale.
  final ContactsController? contacts;

  /// El Vault: una carpeta del almacenamiento para ver sus archivos e imágenes (la sección «Vault»). Sin esto la sección no sale.
  final VaultController? vault;

  /// El fondo de pantalla de Inicio. Sin esto no hay fondo ni grupo «Fondo de pantalla».
  final WallpaperController? wallpaper;

  /// La portada de lo que suena, para el fondo de toda la app: aquí se le da el reproductor. Sin esto el fondo no cambia al sonar.
  final NowPlayingBackdrop? nowPlaying;

  /// Si ya se enseñó cómo abrir el menú circular (la pista de Inicio). Sin esto no hay pista.
  final NavHintStore? navHint;

  /// El reloj de Inicio (en las pruebas, uno fijo).
  final DateTime Function()? now;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  MusicController? _music;
  PlayerController? _player;
  LocalMusicController? _local;
  Future<TaskController>? _tasks;
  Future<ReminderController>? _reminders;
  Future<HabitController>? _habits;
  Future<EventController>? _events;
  ServerController? _server;
  CloudController? _cloud;
  StreamSubscription<void>? _liveSub;
  Timer? _liveDebounce;
  late final DurationCache _durations = widget.durations ?? MemoryDurationCache();

  /// La persona pidió cerrar sesión (Ajustes o la pantalla de error): ahí sí se para la música. Si la sesión caduca sola (Supabase no
  /// pudo renovarla al volver a la app) la música sigue sonando y todo sigue abierto: Configuración avisa de que hay que volver a entrar.
  bool _signingOut = false;

  /// La sesión se perdió sola (no la cerró la persona). Configuración lo avisa para que vuelva a entrar y se retome la sincronización.
  final ValueNotifier<bool> _expired = ValueNotifier<bool>(false);

  /// De quién es lo que hay abierto: si entra otra cuenta, no se hereda lo de la anterior.
  String? _owner;

  StreamSubscription<void>? _authSub;

  // Las tareas y los hábitos hablan con Supabase a través de estas puertas: sin sesión no llaman a nadie (y no dan error), y al volver
  // a entrar se ponen al día solos.
  late final TaskBackend? _tasksGate = widget.tasks == null ? null : _GatedTasks(widget.tasks!, widget.account);
  late final HabitBackend? _habitsGate = widget.habits == null ? null : _GatedHabits(widget.habits!, widget.account);
  late final RowBackend<Reminder>? _remindersGate = widget.reminderBackend == null ? null : _GatedRows<Reminder>(widget.reminderBackend!, widget.account);
  late final ServerBackend? _serverGate = widget.server == null ? null : _GatedServer(widget.server!, widget.account);
  late final CloudBackend? _cloudGate = widget.cloud == null ? null : _GatedCloud(widget.cloud!, widget.account);
  late final RowBackend<CalendarEvent>? _eventsGate = widget.events == null ? null : _GatedRows<CalendarEvent>(widget.events!, widget.account);

  @override
  void initState() {
    super.initState();
    _authSub = widget.account.authChanges.listen((_) => _onAuth());
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // al volver a la app se vuelve a medir el servidor (por si se llenó mientras tanto)
    if (state == AppLifecycleState.resumed && widget.account.signedIn) unawaited(_server?.measure());
  }

  /// La sesión cambió: al entrar se conecta la música de la PC y se sincroniza; al salir (o caducar) se pausa lo del servidor.
  void _onAuth() {
    if (!mounted) return;
    final account = widget.account;
    if (account.signedIn) {
      _expired.value = false;
      unawaited(_music?.connect());
      _syncAgenda();
      _startLive();
      unawaited(_server?.measure());
      return;
    }
    _stopLive();
    if (_signingOut) {
      // la persona cerró sesión: se para lo que suena y se cierra lo abierto (se vuelve a abrir, ya sin servidor, al reconstruir)
      _signingOut = false;
      _expired.value = false;
      _owner = null;
      _stopMusic();
    } else {
      _expired.value = true;
      unawaited(_music?.disconnect());
    }
  }

  Future<void> _signOut() {
    _signingOut = true;
    return widget.account.signOut();
  }

  /// Pone al día todo lo del calendario con Supabase (tareas, hábitos, recordatorios y eventos).
  void _syncAgenda() {
    unawaited(_tasks?.then((c) => c.sync()));
    unawaited(_habits?.then((c) => c.sync()));
    unawaited(_reminders?.then((c) => c.sync()));
    unawaited(_events?.then((c) => c.sync()));
  }

  /// Escucha los cambios de Supabase (Realtime): al llegar uno, o varios seguidos, se pone todo al día una sola vez.
  void _startLive() {
    final live = widget.live;
    if (live == null || _liveSub != null) return;
    _liveSub = live.changes(const ['tasks', 'habits', 'habit_checks', 'events', 'reminders']).listen((_) {
      _liveDebounce?.cancel();
      _liveDebounce = Timer(const Duration(milliseconds: 400), _syncAgenda);
    });
  }

  void _stopLive() {
    _liveDebounce?.cancel();
    _liveDebounce = null;
    unawaited(_liveSub?.cancel());
    _liveSub = null;
  }

  /// Abre el acceso (o crear una cuenta) desde Configuración. Se cierra solo al entrar.
  Future<void> _openLogin(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => _LoginRoute(account: widget.account)),
  );

  /// Las tareas de esta cuenta: se abren una vez (empiezan a ponerse al día con Supabase al instante) y se cierran al cerrar sesión.
  Future<TaskController>? _taskController(String userId) {
    final backend = _tasksGate;
    if (backend == null) return null;
    return _tasks ??= () async {
      TaskStore store;
      try {
        store = await (widget.openTaskStore?.call(userId) ?? Future<TaskStore>.value(MemoryTaskStore()));
      } catch (_) {
        store = MemoryTaskStore(); // el teléfono no dejó abrir la base: las tareas valen mientras la app siga abierta
      }
      final controller = TaskController(store, backend);
      await controller.start();
      return controller;
    }();
  }

  Future<ReminderController>? _reminderController(String userId) {
    final scheduler = widget.reminderScheduler;
    if (scheduler == null) return null;
    return _reminders ??= () async {
      ReminderStore store;
      try {
        store = await (widget.openReminderStore?.call(userId) ?? Future<ReminderStore>.value(MemoryReminderStore()));
      } catch (_) {
        store = MemoryReminderStore();
      }
      final controller = ReminderController(store, scheduler, backend: _remindersGate);
      await controller.start();
      return controller;
    }();
  }

  /// Los eventos de esta cuenta: como las tareas, se abren una vez y se ponen al día con Supabase. Sin Supabase de eventos no hay eventos.
  Future<EventController>? _eventController(String userId) {
    final backend = _eventsGate;
    if (backend == null) return null;
    return _events ??= () async {
      EventStore store;
      try {
        store = await (widget.openEventStore?.call(userId) ?? Future<EventStore>.value(MemoryEventStore()));
      } catch (_) {
        store = MemoryEventStore(); // el teléfono no dejó abrir el almacén: los eventos valen mientras la app siga abierta
      }
      final controller = EventController(store, backend);
      await controller.start();
      return controller;
    }();
  }

  /// Los hábitos de esta cuenta: como las tareas, se abren una vez y se ponen al día con Supabase.
  Future<HabitController>? _habitController(String userId) {
    final backend = _habitsGate;
    if (backend == null) return null;
    return _habits ??= () async {
      HabitStore store;
      try {
        store = await (widget.openHabitStore?.call(userId) ?? Future<HabitStore>.value(MemoryHabitStore()));
      } catch (_) {
        store = MemoryHabitStore(); // el teléfono no dejó abrir la base: los hábitos valen mientras la app siga abierta
      }
      final scheduler = widget.reminderScheduler;
      try {
        await scheduler?.init();
      } catch (_) {
        // sin notificaciones los hábitos se siguen viendo y marcando
      }
      final controller = HabitController(store, backend, scheduler: scheduler);
      await controller.start();
      return controller;
    }();
  }

  /// Lo que ocupa el servidor de esta sesión: se abre una vez, mide al abrir, al volver a la app y cada 30 min, y avisa al llegar al 80 %.
  ServerController? _serverController() {
    final backend = _serverGate;
    if (backend == null) return null;
    return _server ??= ServerController(backend, widget.serverStore ?? MemoryServerStore(), scheduler: widget.reminderScheduler)..start().ignore();
  }

  CloudController? _cloudController() {
    final backend = _cloudGate;
    if (backend == null) return null;
    return _cloud ??= CloudController(backend);
  }

  MusicController _musicController() {
    final existing = _music;
    if (existing != null) return existing;
    final created = MusicController(widget.music, widget.musicStore, widget.saver);
    _music = created;
    created.start(remote: widget.account.signedIn); // sin sesión solo lo local
    return created;
  }

  PlayerController _playerController(LocalMusicController local) {
    final existing = _player;
    if (existing != null) return existing;
    final created = PlayerController(widget.music, widget.engine(), durations: _durations, art: local, levels: widget.levels, hooks: widget.background);
    _player = created;
    widget.nowPlaying?.attach(created);
    return created;
  }

  LocalMusicController _localController(MusicController music) =>
      _local ??= LocalMusicController(music, widget.saver, durations: _durations, covers: widget.covers)..refresh();

  void _stopMusic() {
    widget.nowPlaying?.attach(null);
    _player?.dispose(); // al cerrar sesión la música se para
    _player = null;
    _local?.dispose();
    _local = null;
    _music?.dispose();
    _music = null;
    unawaited(_tasks?.then((c) => c.dispose()));
    _tasks = null;
    unawaited(_reminders?.then((c) => c.dispose()));
    _reminders = null;
    unawaited(_habits?.then((c) => c.dispose()));
    _habits = null;
    unawaited(_events?.then((c) => c.dispose()));
    _events = null;
    _server?.dispose();
    _server = null;
    _cloud?.dispose();
    _cloud = null;
    _stopLive();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_authSub?.cancel());
    _expired.dispose();
    _stopMusic();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    return StreamBuilder<void>(
      stream: account.authChanges,
      builder: (context, _) {
        return _RoleResolver(
          key: const ValueKey('role-resolver'),
          account: account,
          cache: widget.roleCache,
          onSignOut: _signOut,
          builder: (context, role, username, ownerId) {
            if (_owner != null && _owner != ownerId) _stopMusic(); // otra cuenta: empieza de cero
            _owner = ownerId;
            final signedIn = account.signedIn;
            final music = _musicController();
            final local = _localController(music);
            final player = _playerController(local);
            final tasks = _taskController(ownerId);
            final reminders = _reminderController(ownerId);
            final habits = _habitController(ownerId);
            final events = _eventController(ownerId);
            final server = _serverController();
            final cloud = _cloudController();
            if (signedIn) _startLive();
            final admin = role == Role.admin && signedIn; // el chat vive en el servidor: sin sesión no sale
            // Las secciones, en el orden del menú circular. Se abre en Inicio; Configuración es una opción más del menú (abre su hoja).
            // El pasante no tiene chat.
            Widget settingsPage({String? tile}) => SettingsPage(
              music: music,
              role: role,
              username: username,
              onSignOut: _signOut,
              account: account,
              expired: _expired,
              onSignIn: () => _openLogin(context),
              background: widget.background,
              weather: widget.weather,
              dock: widget.dock,
              wallpaper: widget.wallpaper,
              server: server,
              initialTile: tile,
            );
            return SectionHost(
              key: ValueKey('home-$ownerId'),
              initial: 0,
              canExit: () => !(widget.dock?.isLauncher ?? false),
              dock: widget.dock,
              hint: widget.navHint,
              actions: [
                NavAction(
                  id: 'settings',
                  icon: Icons.settings_outlined,
                  glyph: PixelGlyphs.settings,
                  label: 'Configuración',
                  run: (context) => unawaited(showSettings(context, settingsPage())),
                ),
              ],
              sections: [
                AppSection(
                  id: 'home',
                  icon: Icons.home_outlined,
                  glyph: PixelGlyphs.home,
                  label: 'Inicio',
                  builder: (context) => HomePage(
                    onOpenSettings: () => unawaited(showSettings(context, settingsPage(tile: 'weather'))),
                    weather: widget.weather,
                    dock: widget.dock,
                    system: widget.system,
                    player: player,
                    favorites: widget.favorites,
                    now: widget.now,
                    tasks: tasks,
                    reminders: reminders,
                    habits: habits,
                    events: events,
                  ),
                ),
                if (widget.vault != null || server != null || cloud != null || admin)
                  AppSection(
                    id: 'nube',
                    icon: Icons.cloud_outlined,
                    glyph: PixelGlyphs.cloud,
                    label: 'Nube',
                    builder: (context) => NubePage(
                      account: account,
                      admin: admin,
                      server: server,
                      cloud: cloud,
                      vault: widget.vault,
                      chat: widget.chat,
                      onSignIn: () => _openLogin(context),
                      now: widget.now,
                    ),
                  ),
                AppSection(
                  id: 'music',
                  icon: Icons.music_note_outlined,
                  glyph: PixelGlyphs.music,
                  label: 'Música',
                  builder: (_) => MusicPage(controller: music, player: player, local: local, favorites: widget.favorites),
                ),
                if (widget.contacts != null)
                  AppSection(
                    id: 'contacts',
                    icon: Icons.contacts_outlined,
                    glyph: PixelGlyphs.contacts,
                    label: 'Contactos',
                    builder: (_) => ContactsPage(controller: widget.contacts!),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Averigua quién es y qué rol tiene. Con sesión pregunta por el perfil (sin internet usa el rol de la última vez; si no hay ninguno,
/// lo dice y deja reintentar). **Sin sesión no bloquea nada**: usa la última cuenta que entró en este teléfono (o un perfil local si nunca
/// entró ninguna) para abrir sus datos locales. Cuando la sesión cambia no tira lo que hay abierto: solo actualiza el rol y el nombre.
class _RoleResolver extends StatefulWidget {
  const _RoleResolver({super.key, required this.account, required this.cache, required this.builder, required this.onSignOut});

  final AccountBackend account;
  final RoleCache cache;
  final Future<void> Function() onSignOut;

  /// `ownerId` es de quién son los datos locales que se abren (la cuenta con sesión, la última que entró, o `local`).
  final Widget Function(BuildContext context, Role role, String? username, String ownerId) builder;

  @override
  State<_RoleResolver> createState() => _RoleResolverState();
}

/// El dueño de los datos locales cuando nunca entró nadie en este teléfono.
const _localOwner = 'local';

class _RoleResolverState extends State<_RoleResolver> {
  Role? _role;
  String? _username;
  String? _ownerId;
  ChatException? _error;
  StreamSubscription<void>? _sub;
  bool _attached = false;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _sub = widget.account.authChanges.listen((_) => unawaited(_resolve()));
    unawaited(_resolve());
    _attached = true;
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  void _set(VoidCallback change) {
    if (_attached) {
      setState(change);
    } else {
      change(); // dentro de initState no hace falta (ni se puede) repintar
    }
  }

  Future<void> _resolve() async {
    final token = ++_token;
    final account = widget.account;
    final id = account.userId;
    if (id == null) {
      if (_role != null) return; // se perdió la sesión: sigue lo que había abierto
      final last = await widget.cache.readLast();
      if (!mounted || token != _token) return;
      _set(() {
        _role = last?.role ?? Role.intern;
        _ownerId = last?.userId ?? _localOwner;
        _error = null;
      });
      return;
    }
    if (_ownerId != id) {
      // otra cuenta (o la primera con sesión): no se hereda nada de la anterior
      _set(() {
        _role = null;
        _username = null;
        _ownerId = id;
        _error = null;
      });
    }
    try {
      final profile = await account.myProfile();
      final role = profile?.role ?? Role.intern;
      await widget.cache.write(id, role);
      if (!mounted || token != _token) return;
      _set(() {
        _username = profile?.username;
        _role = role;
        _error = null;
      });
    } on ChatException catch (e) {
      final cached = await widget.cache.read(id);
      if (!mounted || token != _token) return;
      _set(() {
        if (cached != null) {
          _role = cached;
          _error = null;
        } else if (_role == null) {
          _error = e;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = _role;
    final owner = _ownerId;
    if (role != null && owner != null) return widget.builder(context, role, _username, owner);
    final error = _error;
    if (error == null) return const Scaffold(body: Center(child: CircularProgressIndicator(strokeWidth: 2.4)));
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error.message,
                key: const Key('role-error'),
                textAlign: TextAlign.center,
                style: TextStyle(color: context.colors.warn),
              ),
              const SizedBox(height: 8),
              TextButton(key: const Key('role-retry'), onPressed: () => unawaited(_resolve()), child: const Text('Reintentar')),
              TextButton(onPressed: widget.onSignOut, child: const Text('Cerrar sesión')),
            ],
          ),
        ),
      ),
    );
  }
}

/// El acceso que se abre desde Configuración: la pantalla de entrada de siempre (y crear cuenta), con una X para cerrarla. Se cierra sola
/// al entrar.
class _LoginRoute extends StatefulWidget {
  const _LoginRoute({required this.account});

  final AccountBackend account;

  @override
  State<_LoginRoute> createState() => _LoginRouteState();
}

class _LoginRouteState extends State<_LoginRoute> {
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.account.authChanges.listen((_) {
      if (!mounted || !widget.account.signedIn) return;
      final route = ModalRoute.of(context);
      if (route == null) return;
      // si «crear cuenta» está encima, esa se cierra sola después: aquí solo se quita esta pantalla
      if (route.isCurrent) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).removeRoute(route);
      }
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    return Stack(
      children: [
        LoginPage(
          onSignIn: account.signIn,
          onSignUp: (u, e, p) => account.signUp(username: u, email: e, password: p),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: IconButton(
              key: const Key('login-close'),
              tooltip: 'Cerrar',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: Icon(Icons.close_rounded, color: context.colors.ink),
            ),
          ),
        ),
      ],
    );
  }
}

const _noSession = ChatException('Sin sesión: entra desde Configuración para sincronizar.', retryable: true, code: 'no_session');

/// Las tareas hablan con Supabase solo si hay sesión; sin ella avisan de que no hay conexión (sin llamar a nadie) y siguen guardando en el teléfono.
class _GatedTasks implements TaskBackend {
  _GatedTasks(this._inner, this._account);

  final TaskBackend _inner;
  final AccountBackend _account;

  @override
  Future<void> push(TaskData changes) => _account.signedIn ? _inner.push(changes) : Future<void>.error(_noSession);

  @override
  Future<TaskData> pull({String? tasksSince, String? tagsSince, String? linksSince}) => _account.signedIn
      ? _inner.pull(tasksSince: tasksSince, tagsSince: tagsSince, linksSince: linksSince)
      : Future<TaskData>.error(_noSession);
}

class _GatedRows<T extends SyncRow> implements RowBackend<T> {
  _GatedRows(this._inner, this._account);

  final RowBackend<T> _inner;
  final AccountBackend _account;

  @override
  Future<void> push(List<T> rows) => _account.signedIn ? _inner.push(rows) : Future<void>.error(_noSession);

  @override
  Future<List<T>> pull(String? since) => _account.signedIn ? _inner.pull(since) : Future<List<T>>.error(_noSession);
}

class _GatedServer implements ServerBackend {
  _GatedServer(this._inner, this._account);

  final ServerBackend _inner;
  final AccountBackend _account;

  @override
  Future<ServerStats> serverStats() => _account.signedIn ? _inner.serverStats() : Future<ServerStats>.error(_noSession);
}

class _GatedCloud implements CloudBackend {
  _GatedCloud(this._inner, this._account);

  final CloudBackend _inner;
  final AccountBackend _account;

  @override
  Future<List<CloudFile>> listCloud() => _account.signedIn ? _inner.listCloud() : Future<List<CloudFile>>.error(_noSession);

  @override
  Future<String> cloudUrl(String path, {String? download}) => _account.signedIn ? _inner.cloudUrl(path, download: download) : Future<String>.error(_noSession);

  @override
  Future<CloudDeleteResult> deleteCloudFile(CloudFile file) => _account.signedIn ? _inner.deleteCloudFile(file) : Future<CloudDeleteResult>.error(_noSession);
}

class _GatedHabits implements HabitBackend {
  _GatedHabits(this._inner, this._account);

  final HabitBackend _inner;
  final AccountBackend _account;

  @override
  Future<void> pushHabits(HabitData changes) => _account.signedIn ? _inner.pushHabits(changes) : Future<void>.error(_noSession);

  @override
  Future<HabitData> pullHabits({String? habitsSince, String? checksSince}) =>
      _account.signedIn ? _inner.pullHabits(habitsSince: habitsSince, checksSince: checksSince) : Future<HabitData>.error(_noSession);
}
