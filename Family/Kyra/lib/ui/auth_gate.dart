import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/calendar_view_store.dart';
import '../data/account_backend.dart';
import '../data/admin_backend.dart';
import '../data/chat_notifier.dart';
import '../data/direct_backend.dart';
import '../data/alarm_scheduler.dart';
import '../data/clock_store.dart';
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
import '../state/clock_controller.dart';
import '../state/contacts_controller.dart';
import '../state/dock_controller.dart';
import '../state/event_controller.dart';
import '../state/habit_controller.dart';
import '../state/local_music_controller.dart';
import '../state/music_controller.dart';
import '../state/player_controller.dart';
import '../state/presence_beat.dart';
import '../state/users_controller.dart';
import '../state/reminder_controller.dart';
import '../state/server_controller.dart';
import '../state/task_controller.dart';
import '../state/now_playing_backdrop.dart';
import '../state/system_controller.dart';
import '../state/vault_controller.dart';
import '../state/appearance_controller.dart';
import '../state/direct_chat_controller.dart';
import '../state/voice_controller.dart';
import '../state/wallpaper_controller.dart';
import '../state/weather_controller.dart';
import '../data/finance_store.dart';
import '../data/improvement_backend.dart';
import '../data/password_vault.dart';
import '../models/finance.dart';
import '../models/improvement.dart';
import '../state/finance_controller.dart';
import '../app_flavor.dart';
import '../theme.dart';
import 'clock_page.dart';
import 'contacts_page.dart';
import 'direct_chats_page.dart';
import 'finance_page.dart';
import 'improvements_page.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'music_page.dart';
import 'nube_page.dart';
import 'passwords_page.dart';
import 'settings_page.dart';
import 'guest_shell.dart';
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
    this.admin,
    this.direct,
    this.chatNotifier,
    this.remembered,
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
    this.financeCategories,
    this.financeEntries,
    this.openFinanceCategoryStore,
    this.openFinanceEntryStore,
    this.financeSettings,
    this.calendarView,
    this.clockStore,
    this.alarmScheduler,
    this.passwords,
    this.improvements,
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
    this.appearance,
    this.voice,
    this.nowPlaying,
    this.navHint,
    this.now,
    this.flavor,
  });

  final AccountBackend account;
  final ChatBackend chat;
  final MusicBackend music;
  final MusicStore musicStore;
  final TrackSaver saver;
  final RoleCache roleCache;

  /// Crea el motor de audio del reproductor (el real usa `just_audio`; los tests, uno falso).
  final AudioEngine Function() engine;

  /// La presencia (el latido «sigo aquí») y lo que el administrador hace con las cuentas. Sin esto no hay latido ni panel «Usuarios».
  final AdminBackend? admin;

  /// El chat privado 1 a 1 (KyraFamily y la sección «Chats» de KyraAdmin). Sin esto no hay chat.
  final DirectBackend? direct;

  /// El aviso del teléfono cuando llega un mensaje con la app en segundo plano. Sin esto no hay aviso.
  final ChatNotifier? chatNotifier;

  /// El nombre del visitante que ya entró en este teléfono (para pedirle solo la contraseña). Sin esto, siempre se pide el nombre.
  final RememberedAccount? remembered;

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

  /// Supabase para las finanzas (categorías y movimientos) y la base local de las de esa cuenta (sin ella, una en memoria). Sin Supabase no hay
  /// sección «Finanzas». `financeSettings` recuerda la moneda elegida.
  final RowBackend<FinanceCategory>? financeCategories;
  final RowBackend<FinanceEntry>? financeEntries;
  final Future<FinanceCategoryStore> Function(String userId)? openFinanceCategoryStore;
  final Future<FinanceEntryStore> Function(String userId)? openFinanceEntryStore;
  final FinanceSettings? financeSettings;

  /// La vista con la que se abre el calendario (semana o mes), que se elige en Configuración.
  final CalendarViewStore? calendarView;

  /// El reloj (alarmas y cronómetro): dónde se guarda, solo en el teléfono, y cómo suenan las alarmas. Sin el almacén no hay sección «Reloj».
  final ClockStore? clockStore;
  final AlarmScheduler? alarmScheduler;

  /// La bóveda de contraseñas en Supabase (la misma que la de Merida). Sin esto no hay sección «Contraseñas».
  final PasswordBackend? passwords;

  /// Las mejoras pendientes del proyecto en Supabase (las mismas que usa Merida). Sin esto no hay sección «Mejoras».
  final ImprovementBackend? improvements;

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

  /// El tema de colores y el modo oscuro del modo visitante (KyraFamily). Sin esto, el tema de siempre en claro.
  final AppearanceController? appearance;

  /// La voz que lee los mensajes con la pantalla apagada (solo KyraAdmin). Sin esto no hay ficha «Voz».
  final VoiceController? voice;

  /// La portada de lo que suena, para el fondo de toda la app: aquí se le da el reproductor. Sin esto el fondo no cambia al sonar.
  final NowPlayingBackdrop? nowPlaying;

  /// Si ya se enseñó cómo abrir el menú circular (la pista de Inicio). Sin esto no hay pista.
  final NavHintStore? navHint;

  /// El reloj de Inicio (en las pruebas, uno fijo).
  final DateTime Function()? now;

  /// Cuál de las dos apps es: **KyraAdmin** solo deja entrar a cuentas de administrador (sin sesión pide el acceso) y **KyraFamily** no deja
  /// entrar a ninguna (solo tiene el modo visitante). Sin esto (las pruebas) vale cualquier cuenta, como antes de separarlas.
  final AppFlavor? flavor;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  MusicController? _music;
  PlayerController? _player;
  LocalMusicController? _local;

  /// El álbum que Inicio pide abrir al entrar a Música (el botón del álbum del reproductor); `MusicPage` lo lee y lo vacía.
  final ValueNotifier<String?> _albumRequest = ValueNotifier(null);
  Future<TaskController>? _tasks;
  Future<ReminderController>? _reminders;
  AlarmController? _alarmController;
  StopwatchController? _stopwatchController;
  Future<HabitController>? _habits;
  Future<EventController>? _events;
  Future<FinanceController>? _finance;
  ServerController? _server;
  CloudController? _cloud;
  UsersController? _users;

  /// El chat privado del administrador (la sección «Chats»): se abre con su sesión y se cierra al salir.
  DirectChatsController? _dm;
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

  /// El latido de presencia: con sesión, cada 30 s le dice al servidor que sigues aquí.
  late final PresenceBeat? _presence = widget.admin == null ? null : PresenceBeat(widget.admin!);

  /// Por qué se echó a la última cuenta que intentó entrar (no es de esta app); lo enseñan el acceso y Ajustes hasta el siguiente intento.
  final ValueNotifier<String?> _accessNotice = ValueNotifier<String?>(null);

  /// Ya se está echando a una cuenta que no puede entrar (para no repetirlo en cada repintado).
  bool _rejecting = false;

  /// El nombre del visitante recordado en este teléfono (la próxima vez solo se pide la contraseña).
  final ValueNotifier<String?> _remembered = ValueNotifier<String?>(null);

  /// Con quién se acaba de entrar (para recordarlo cuando la cuenta ya esté verificada).
  String? _pendingName;

  /// Sube cada vez que hay que volver a leer el perfil (por ejemplo, tras canjear el código).
  final ValueNotifier<int> _profileTick = ValueNotifier<int>(0);

  // Las tareas y los hábitos hablan con Supabase a través de estas puertas: sin sesión no llaman a nadie (y no dan error), y al volver
  // a entrar se ponen al día solos.
  late final TaskBackend? _tasksGate = widget.tasks == null ? null : _GatedTasks(widget.tasks!, widget.account);
  late final HabitBackend? _habitsGate = widget.habits == null ? null : _GatedHabits(widget.habits!, widget.account);
  late final RowBackend<Reminder>? _remindersGate = widget.reminderBackend == null ? null : _GatedRows<Reminder>(widget.reminderBackend!, widget.account);
  late final ServerBackend? _serverGate = widget.server == null ? null : _GatedServer(widget.server!, widget.account);
  late final CloudBackend? _cloudGate = widget.cloud == null ? null : _GatedCloud(widget.cloud!, widget.account);
  late final RowBackend<CalendarEvent>? _eventsGate = widget.events == null ? null : _GatedRows<CalendarEvent>(widget.events!, widget.account);
  late final RowBackend<FinanceCategory>? _financeCategoriesGate = widget.financeCategories == null ? null : _GatedRows<FinanceCategory>(widget.financeCategories!, widget.account);
  late final RowBackend<FinanceEntry>? _financeEntriesGate = widget.financeEntries == null ? null : _GatedRows<FinanceEntry>(widget.financeEntries!, widget.account);
  late final PasswordBackend? _passwordsGate = widget.passwords == null ? null : _GatedPasswords(widget.passwords!, widget.account);
  late final ImprovementBackend? _improvementsGate = widget.improvements == null ? null : _GatedImprovements(widget.improvements!, widget.account);

  @override
  void initState() {
    super.initState();
    _authSub = widget.account.authChanges.listen((_) => _onAuth());
    WidgetsBinding.instance.addObserver(this);
    if (widget.account.signedIn) _presence?.start();
    unawaited(_loadRemembered());
  }

  Future<void> _loadRemembered() async {
    final name = await widget.remembered?.read();
    if (mounted) _remembered.value = name;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // al volver a la app se vuelve a medir el servidor (por si se llenó mientras tanto)
    if (state == AppLifecycleState.resumed && widget.account.signedIn) {
      unawaited(_server?.measure());
      _presence?.nudge();
    }
  }

  /// La sesión cambió: al entrar se conecta la música de la PC y se sincroniza; al salir (o caducar) se pausa lo del servidor.
  void _onAuth() {
    if (!mounted) return;
    final account = widget.account;
    if (account.signedIn) {
      _expired.value = false;
      _accessNotice.value = null; // un intento nuevo: el aviso del anterior ya no vale
      _presence?.start();
      unawaited(_music?.connect());
      _syncAgenda();
      _startLive();
      unawaited(_server?.measure());
      return;
    }
    _stopLive();
    _presence?.stop();
    _rejecting = false;
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

  /// Si ya se le dijo a Android si Kyra puede ser la pantalla de inicio (`null` = aún no).
  bool? _launcherAllowed;

  /// Kyra solo se ofrece como pantalla de inicio al administrador; con un visitante (o sin sesión) es una app normal. Solo se avisa a Android
  /// cuando eso cambia.
  void _allowLauncher(bool allowed) {
    if (_launcherAllowed == allowed) return;
    _launcherAllowed = allowed;
    unawaited(widget.dock?.allowLauncher(allowed));
  }

  /// Por qué esta cuenta no puede entrar en esta app, o `null` si puede. KyraAdmin solo acepta administradores verificados; KyraFamily no acepta
  /// administradores. (Sin `flavor`, las pruebas, todas.)
  String? _rejection(Role role, bool verified) {
    switch (widget.flavor) {
      case AppFlavor.admin:
        if (role != Role.admin) return 'KyraAdmin es solo para cuentas de administrador. Tu cuenta entra en KyraFamily.';
        if (!verified) return 'Esta cuenta de administrador aún no está verificada.';
        return null;
      case AppFlavor.family:
        return role == Role.admin ? 'Las cuentas de administrador no entran en KyraFamily. Usa KyraAdmin.' : null;
      case null:
        return null;
    }
  }

  /// Echa a la cuenta que acaba de entrar y no es de esta app: cierra su sesión y deja el motivo en [_accessNotice].
  void _reject(String reason) {
    if (_rejecting) return;
    _rejecting = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _accessNotice.value = reason;
      unawaited(_signOut().catchError((Object _) {})); // sin red no se pudo cerrar: la pantalla ya no la deja pasar
    });
  }

  Future<void> _signOut() {
    _signingOut = true;
    return widget.account.signOut();
  }

  /// El acceso del visitante: nombre + contraseña. Si ya entró antes aquí y la cuenta está verificada, se recuerda su nombre (la próxima
  /// vez solo la contraseña); si falta el código, se recuerda cuando lo canjee.
  Future<void> _visitorSignIn(String name, String password) async {
    await widget.account.signIn(name, password);
    _pendingName = name.trim().toLowerCase();
    try {
      final profile = await widget.account.myProfile();
      if (profile != null && profile.verified && !profile.isAdmin) await _remember();
    } on ChatException {
      // sin red: se recordará al canjear el código o en el siguiente acceso
    }
  }

  Future<void> _remember() async {
    final name = _pendingName;
    if (name == null) return;
    await widget.remembered?.write(name);
    if (mounted) _remembered.value = name;
    _pendingName = null;
  }

  /// Canjea el código de 6 dígitos y, ya verificada la cuenta, recuerda el nombre y vuelve a leer el perfil.
  Future<void> _claim(String code) async {
    await widget.account.claimAccount(code);
    await _remember();
    _profileTick.value++;
  }

  /// «No soy yo»: se olvida el nombre y se vuelve a pedir.
  Future<void> _forget() async {
    await widget.remembered?.clear();
    _remembered.value = null;
  }

  /// Pone al día todo lo del calendario con Supabase (tareas, hábitos, recordatorios y eventos).
  void _syncAgenda() {
    unawaited(_tasks?.then((c) => c.sync()));
    unawaited(_habits?.then((c) => c.sync()));
    unawaited(_reminders?.then((c) => c.sync()));
    unawaited(_events?.then((c) => c.sync()));
    unawaited(_finance?.then((c) => c.sync()));
  }

  /// Escucha los cambios de Supabase (Realtime): al llegar uno, o varios seguidos, se pone todo al día una sola vez.
  void _startLive() {
    final live = widget.live;
    if (live == null || _liveSub != null) return;
    _liveSub = live.changes(const ['tasks', 'habits', 'habit_checks', 'events', 'reminders', 'finance_categories', 'finance_entries']).listen((_) {
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

  /// El reloj: se crea una vez (las alarmas y el cronómetro siguen aunque se cambie de sección) y lee lo guardado en el teléfono.
  Widget _clockPage() {
    _openClock();
    return ClockPage(alarms: _alarmController!, stopwatch: _stopwatchController!, now: widget.now);
  }

  /// Crea (una vez) los controladores del reloj, para la sección y para el panel de Inicio. Sin almacén no hay reloj.
  void _openClock() {
    final store = widget.clockStore;
    if (store == null) return;
    _alarmController ??= AlarmController(store, widget.alarmScheduler, now: widget.now)..start().ignore();
    _stopwatchController ??= StopwatchController(store, now: widget.now)..start().ignore();
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

  /// Las finanzas de esta cuenta: categorías y movimientos, que se abren una vez y se ponen al día con Supabase.
  Future<FinanceController>? _financeController(String userId) {
    final categoriesBackend = _financeCategoriesGate;
    final entriesBackend = _financeEntriesGate;
    if (categoriesBackend == null || entriesBackend == null) return null;
    return _finance ??= () async {
      FinanceCategoryStore categoryStore;
      FinanceEntryStore entryStore;
      try {
        categoryStore = await (widget.openFinanceCategoryStore?.call(userId) ?? Future<FinanceCategoryStore>.value(MemoryFinanceCategoryStore()));
        entryStore = await (widget.openFinanceEntryStore?.call(userId) ?? Future<FinanceEntryStore>.value(MemoryFinanceEntryStore()));
      } catch (_) {
        categoryStore = MemoryFinanceCategoryStore(); // el teléfono no dejó abrir el almacén: las finanzas valen mientras la app siga abierta
        entryStore = MemoryFinanceEntryStore();
      }
      final settings = widget.financeSettings;
      final controller = FinanceController(
        FinanceCategories(categoryStore, categoriesBackend),
        FinanceEntries(entryStore, entriesBackend),
        currency: settings?.currency ?? 'MXN',
        persistCurrency: settings?.setCurrency,
      );
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

  /// El panel «Usuarios» del administrador (quién está en línea, crear cuentas...). Sin la parte de administración no hay panel.
  UsersController? _usersController() {
    final backend = widget.admin;
    if (backend == null) return null;
    return _users ??= UsersController(backend);
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
    unawaited(_finance?.then((c) => c.dispose()));
    _finance = null;
    _server?.dispose();
    _server = null;
    _cloud?.dispose();
    _cloud = null;
    _users?.dispose();
    _users = null;
    _dm?.dispose();
    _dm = null;
    _stopLive();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_authSub?.cancel());
    _expired.dispose();
    _remembered.dispose();
    _accessNotice.dispose();
    _profileTick.dispose();
    _presence?.stop();
    _albumRequest.dispose();
    _alarmController?.dispose();
    _stopwatchController?.dispose();
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
          refresh: _profileTick,
          builder: (context, role, username, ownerId, verified) {
            if (_owner != null && _owner != ownerId) _stopMusic(); // otra cuenta: empieza de cero
            _owner = ownerId;
            final signedIn = account.signedIn;
            final rejection = signedIn ? _rejection(role, verified) : null;
            if (rejection != null) _reject(rejection);
            // Solo el administrador verificado ve toda la app (y nunca en KyraFamily). Si su sesión caducó sola (no la cerró él) sigue lo que
            // tenía abierto.
            final admin = widget.flavor != AppFlavor.family && rejection == null && role == Role.admin && verified && (signedIn || _expired.value);
            _allowLauncher(admin);
            if (!admin && widget.flavor == AppFlavor.admin) {
              // KyraAdmin sin un administrador con sesión: solo el acceso (correo y contraseña). Nada de lo demás se abre.
              return LoginPage(key: const ValueKey('admin-login'), onSignIn: account.signIn, notice: _accessNotice);
            }
            final music = _musicController();
            final local = _localController(music);
            final player = _playerController(local);
            if (!admin) {
              // El visitante (y quien acaba de instalar Kyra): solo Música y Chat, con barra de navegación. Nada de lo demás se abre.
              return GuestShell(
                key: const ValueKey('guest-shell'),
                music: music,
                player: player,
                local: local,
                direct: widget.direct,
                notifier: widget.chatNotifier,
                ownerId: ownerId,
                signedIn: signedIn && rejection == null,
                verified: verified,
                role: role,
                username: username,
                remembered: _remembered,
                onSignIn: _visitorSignIn,
                onClaim: _claim,
                onForget: _forget,
                onSignOut: _signOut,
                // en KyraFamily no hay acceso de administrador
                onAdminLogin: widget.flavor == AppFlavor.family ? null : () => unawaited(_openLogin(context)),
                notice: _accessNotice,
                canExit: () => !(widget.dock?.isLauncher ?? false),
                appearance: widget.appearance,
                favorites: widget.favorites,
              );
            }
            final tasks = _taskController(ownerId);
            final reminders = _reminderController(ownerId);
            final habits = _habitController(ownerId);
            final events = _eventController(ownerId);
            final finance = _financeController(ownerId);
            final server = _serverController();
            final cloud = _cloudController();
            if (signedIn) _startLive();
            // el chat privado del administrador arranca ya (no al abrir «Chats»): así los mensajes que lleguen se avisan aunque no esté en esa sección
            if (signedIn && widget.direct != null) _dm ??= DirectChatsController(widget.direct!, notifier: widget.chatNotifier)..start().ignore();
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
              users: _usersController(),
              calendarView: widget.calendarView,
              vault: widget.vault,
              voice: widget.voice,
              initialTile: tile,
            );
            _openClock();
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
                    albumRequest: _albumRequest,
                    albumOf: local.albumIdOf,
                    now: widget.now,
                    alarms: _alarmController,
                    stopwatch: _stopwatchController,
                    tasks: tasks,
                    reminders: reminders,
                    habits: habits,
                    events: events,
                    calendarView: widget.calendarView,
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
                      player: player,
                      onOpenSettings: () => unawaited(showSettings(context, settingsPage(tile: 'vault'))),
                      onSignIn: () => _openLogin(context),
                      now: widget.now,
                    ),
                  ),
                if (widget.clockStore != null)
                  AppSection(
                    id: 'clock',
                    icon: Icons.alarm_outlined,
                    glyph: PixelGlyphs.alarm,
                    label: 'Reloj',
                    builder: (_) => _clockPage(),
                  ),
                if (_dm != null)
                  AppSection(
                    id: 'chats',
                    icon: Icons.forum_outlined,
                    glyph: PixelGlyphs.chat,
                    label: 'Chats',
                    builder: (_) => DirectChatsPage(
                      chats: _dm!,
                      backend: widget.direct!,
                    ),
                  ),
                AppSection(
                  id: 'music',
                  icon: Icons.music_note_outlined,
                  glyph: PixelGlyphs.music,
                  label: 'Música',
                  builder: (_) => MusicPage(controller: music, player: player, local: local, favorites: widget.favorites, openAlbum: _albumRequest),
                ),
                if (widget.contacts != null)
                  AppSection(
                    id: 'contacts',
                    icon: Icons.contacts_outlined,
                    glyph: PixelGlyphs.contacts,
                    label: 'Contactos',
                    builder: (_) => ContactsPage(controller: widget.contacts!),
                  ),
                if (finance != null)
                  AppSection(
                    id: 'finance',
                    icon: Icons.account_balance_wallet_outlined,
                    glyph: PixelGlyphs.wallet,
                    label: 'Finanzas',
                    builder: (_) => FutureBuilder<FinanceController>(
                      future: finance,
                      builder: (context, snapshot) => snapshot.hasData
                          ? FinancePage(controller: snapshot.data!, now: widget.now)
                          : const Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
                    ),
                  ),
                if (_improvementsGate != null)
                  AppSection(
                    id: 'improvements',
                    icon: Icons.checklist_rounded,
                    glyph: PixelGlyphs.checklist,
                    label: 'Mejoras',
                    builder: (_) => ImprovementsPage(backend: _improvementsGate),
                  ),
                if (_passwordsGate != null)
                  AppSection(
                    id: 'passwords',
                    icon: Icons.lock_outline_rounded,
                    glyph: PixelGlyphs.lock,
                    label: 'Contraseñas',
                    builder: (_) => PasswordsPage(backend: _passwordsGate),
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
  const _RoleResolver({super.key, required this.account, required this.cache, required this.builder, required this.onSignOut, this.refresh});

  final AccountBackend account;
  final RoleCache cache;
  final Future<void> Function() onSignOut;

  /// Avisa cuando hay que volver a leer el perfil (por ejemplo, después de canjear el código de 6 dígitos).
  final Listenable? refresh;

  /// `ownerId` es de quién son los datos locales que se abren (la cuenta con sesión, la última que entró, o `local`).
  /// `verified`: la cuenta ya canjeó su código (sin sesión o sin dato, `true`: no se bloquea nada).
  final Widget Function(BuildContext context, Role role, String? username, String ownerId, bool verified) builder;

  @override
  State<_RoleResolver> createState() => _RoleResolverState();
}

/// El dueño de los datos locales cuando nunca entró nadie en este teléfono.
const _localOwner = 'local';

class _RoleResolverState extends State<_RoleResolver> {
  Role? _role;
  String? _username;
  bool _verified = true;
  String? _ownerId;
  ChatException? _error;
  StreamSubscription<void>? _sub;
  bool _attached = false;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _sub = widget.account.authChanges.listen((_) => unawaited(_resolve()));
    widget.refresh?.addListener(_onRefresh);
    unawaited(_resolve());
    _attached = true;
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(_onRefresh);
    unawaited(_sub?.cancel());
    super.dispose();
  }

  void _onRefresh() => unawaited(_resolve());

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
        _verified = true;
        _error = null;
      });
      return;
    }
    if (_ownerId != id) {
      // otra cuenta (o la primera con sesión): no se hereda nada de la anterior
      _set(() {
        _role = null;
        _username = null;
        _verified = true;
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
        _verified = profile?.verified ?? true;
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
    if (role != null && owner != null) return widget.builder(context, role, _username, owner, _verified);
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

/// El acceso del administrador (se abre desde Ajustes): correo y contraseña, con una X para cerrarla. Se cierra sola al entrar. Ya no
/// se puede crear una cuenta: las crea el administrador.
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
      // si hay otra pantalla encima, esa se cierra sola después: aquí solo se quita esta
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
        LoginPage(onSignIn: account.signIn),
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

  @override
  Future<void> uploadCloudFile(String name, String mime, Uint8List bytes) => _account.signedIn ? _inner.uploadCloudFile(name, mime, bytes) : Future<void>.error(_noSession);
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

/// La bóveda de contraseñas habla con Supabase solo si hay sesión; sin ella avisa de que no hay conexión (sin llamar a nadie).
class _GatedPasswords implements PasswordBackend {
  _GatedPasswords(this._inner, this._account);

  final PasswordBackend _inner;
  final AccountBackend _account;

  @override
  Future<VaultMeta?> loadMeta() => _account.signedIn ? _inner.loadMeta() : Future<VaultMeta?>.error(_noSession);

  @override
  Future<void> createMeta(VaultMeta meta) => _account.signedIn ? _inner.createMeta(meta) : Future<void>.error(_noSession);

  @override
  Future<List<VaultEntryRow>> loadRows() => _account.signedIn ? _inner.loadRows() : Future<List<VaultEntryRow>>.error(_noSession);

  @override
  Future<void> saveRow(VaultEntryRow row) => _account.signedIn ? _inner.saveRow(row) : Future<void>.error(_noSession);

  @override
  Future<void> deleteRow(String id, DateTime at) => _account.signedIn ? _inner.deleteRow(id, at) : Future<void>.error(_noSession);
}

/// Las mejoras hablan con Supabase solo si hay sesión; sin ella avisan de que no hay conexión (sin llamar a nadie).
class _GatedImprovements implements ImprovementBackend {
  _GatedImprovements(this._inner, this._account);

  final ImprovementBackend _inner;
  final AccountBackend _account;

  @override
  Future<List<Improvement>> list() => _account.signedIn ? _inner.list() : Future<List<Improvement>>.error(_noSession);

  @override
  Future<void> add(Improvement item) => _account.signedIn ? _inner.add(item) : Future<void>.error(_noSession);

  @override
  Future<void> finish(String id) => _account.signedIn ? _inner.finish(id) : Future<void>.error(_noSession);
}
