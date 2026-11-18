import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/alarm_scheduler.dart';
import 'data/chat_notifier.dart';
import 'data/clock_store.dart';
import 'app_flavor.dart';
import 'config.dart';
import 'data/account_backend.dart';
import 'data/audio_levels.dart';
import 'data/background_playback.dart';
import 'data/chat_repository.dart';
import 'data/calendar_view_store.dart';
import 'data/cover_store.dart';
import 'data/dock_store.dart';
import 'data/duration_cache.dart';
import 'data/event_store.dart';
import 'data/favorites_store.dart';
import 'data/finance_store.dart';
import 'data/habit_store.dart';
import 'data/installed_apps.dart';
import 'data/just_audio_engine.dart';
import 'data/music_store.dart';
import 'data/nav_hint_store.dart';
import 'data/reminder_scheduler.dart';
import 'data/reminder_store.dart';
import 'data/remembered_account.dart';
import 'data/role_cache.dart';
import 'data/server_stats.dart';
import 'data/task_store.dart';
import 'data/appearance_store.dart';
import 'data/voice_reader.dart';
import 'data/wallpaper_store.dart';
import 'data/weather_service.dart';
import 'data/weather_store.dart';
import 'state/contacts_controller.dart';
import 'state/dock_controller.dart';
import 'state/vault_controller.dart';
import 'ui/widgets/kyra_keyboard.dart';
import 'data/contacts_source.dart';
import 'data/vault_source.dart';
import 'state/now_playing_backdrop.dart';
import 'state/system_controller.dart';
import 'data/system_info.dart';
import 'state/appearance_controller.dart';
import 'state/voice_controller.dart';
import 'state/wallpaper_controller.dart';
import 'state/weather_controller.dart';
import 'theme.dart';
import 'ui/auth_gate.dart';
import 'ui/widgets/app_backdrop.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!AppConfig.isConfigured) {
    runApp(const _MissingConfigApp());
    return;
  }
  // Todo lo que no depende de lo demás arranca a la vez (antes iba una cosa tras otra y la primera pantalla tardaba la suma de todas).
  // La sesión de audio: música (así Android sabe qué es, baja el volumen ante un aviso y la respeta en segundo plano).
  final audioReady = AudioSession.instance.then((session) => session.configure(const AudioSessionConfiguration.music()));
  // La notificación y los controles de la pantalla de bloqueo del reproductor. El servicio sigue en primer plano también en pausa
  // (si no, al pausar —una llamada, quitar los auriculares— Android lo trata como una app cualquiera y puede detenerlo).
  final backgroundReady = JustAudioBackground.init(
    androidNotificationChannelId: 'com.kyora.kyora_chat.audio',
    androidNotificationChannelName: 'Música de Kyra',
    androidNotificationIcon: 'drawable/ic_kyra_notification',
    androidNotificationOngoing: false,
    androidStopForegroundOnPause: false,
  );
  final supabaseReady = Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseAnonKey);
  final (store, roles, durations, favoritesStore, covers, weatherStore, navHint) = await (
    PrefsMusicStore.open(),
    PrefsRoleCache.open(),
    PrefsDurationCache.open(),
    PrefsFavoritesStore.open(),
    PrefsCoverStore.open(),
    PrefsWeatherStore.open(),
    PrefsNavHintStore.open(),
  ).wait;
  final (wallpaperStore, dockStore, vaultStore, serverStore, remembered) = await (PrefsWallpaperStore.open(), PrefsDockStore.open(), PrefsVaultStore.open(), PrefsServerStore.open(), PrefsRememberedAccount.open()).wait;
  final financeSettings = await FinanceSettings.open();
  final calendarView = await PrefsCalendarViewStore.open();
  final clockStore = await PrefsClockStore.open();
  final appearanceStore = await PrefsAppearanceStore.open();
  await Future.wait([audioReady, backgroundReady, supabaseReady]);
  final favorites = FavoritesController(favoritesStore);
  final weather = WeatherController(OpenMeteoWeather(), weatherStore);
  runApp(
    KyoraChatApp(
      repository: ChatRepository(Supabase.instance.client),
      musicStore: store,
      saver: AndroidTrackSaver(),
      roleCache: roles,
      remembered: remembered,
      durations: durations,
      favorites: favorites,
      covers: covers,
      weather: weather,
      navHint: navHint,
      dock: DockController(dockStore, AndroidInstalledApps()),
      wallpaper: WallpaperController(wallpaperStore),
      appearance: AppearanceController(appearanceStore),
      // la voz que lee los mensajes con la pantalla apagada: solo en KyraAdmin
      voice: AppFlavor.current == AppFlavor.admin ? VoiceController(AndroidVoiceReader()) : null,
      contacts: ContactsController(AndroidContactsSource()),
      vault: VaultController(AndroidVaultSource(), vaultStore),
      serverStore: serverStore,
      financeSettings: financeSettings,
      calendarView: calendarView,
      clockStore: clockStore,
      alarmScheduler: LocalAlarmScheduler(),
    ),
  );
}

class KyoraChatApp extends StatefulWidget {
  const KyoraChatApp({
    super.key,
    required this.repository,
    required this.musicStore,
    required this.saver,
    required this.roleCache,
    this.remembered,
    this.durations,
    this.favorites,
    this.covers,
    this.weather,
    this.navHint,
    this.dock,
    this.wallpaper,
    this.appearance,
    this.voice,
    this.contacts,
    this.vault,
    this.financeSettings,
    this.calendarView,
    this.clockStore,
    this.alarmScheduler,
    this.serverStore,
  });

  final ChatRepository repository;
  final MusicStore musicStore;
  final TrackSaver saver;
  final RoleCache roleCache;

  /// El nombre del visitante que ya entró en este teléfono (la próxima vez solo se pide la contraseña).
  final RememberedAccount? remembered;
  final DurationCache? durations;
  final FavoritesController? favorites;
  final CoverStore? covers;

  final WeatherController? weather;

  /// Si ya se enseñó cómo abrir el menú circular.
  final NavHintStore? navHint;

  /// Las 8 apps del disco de Inicio y el fondo de pantalla.
  final DockController? dock;
  final WallpaperController? wallpaper;

  /// El tema de colores y el modo oscuro de KyraFamily.
  final AppearanceController? appearance;

  /// La voz de KyraAdmin.
  final VoiceController? voice;

  /// Los contactos del teléfono y el Vault (carpeta del almacenamiento).
  final ContactsController? contacts;
  final VaultController? vault;

  /// Los límites del plan de Supabase y los avisos de espacio ya dados (los que recuerda la Nube).
  final ServerStore? serverStore;

  /// La moneda de las finanzas, recordada en el teléfono.
  final FinanceSettings? financeSettings;

  /// La vista con la que se abre el calendario (semana o mes). Sin esto siempre abre la semana y Configuración no ofrece elegirla.
  final CalendarViewStore? calendarView;

  /// Dónde guarda el reloj sus alarmas y su cronómetro (solo en el teléfono) y cómo suenan las alarmas. Sin el almacén no hay sección «Reloj».
  final ClockStore? clockStore;
  final AlarmScheduler? alarmScheduler;

  @override
  State<KyoraChatApp> createState() => _KyoraChatAppState();
}

class _KyoraChatAppState extends State<KyoraChatApp> {
  /// La portada de lo que suena: mientras suena algo, el fondo de toda la app es su portada.
  final NowPlayingBackdrop _nowPlaying = NowPlayingBackdrop();

  /// El estado del teléfono para el tablero de Inicio.
  final SystemController _system = SystemController(AndroidSystemInfo());

  /// El teclado propio de Kyra: sustituye al del sistema en toda la app.
  final KyraKeyboardController _keyboard = KyraKeyboardController();

  @override
  void dispose() {
    _keyboard.dispose();
    _nowPlaying.dispose();
    _system.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // la pantalla de entrada se construye una vez; solo el tema cambia con la carátula (con una transición suave entre colores)
    return ListenableBuilder(
      listenable: Listenable.merge([?widget.wallpaper, _nowPlaying]),
      child: AuthGate(
        flavor: AppFlavor.current, // KyraAdmin o KyraFamily, según con qué --flavor se compiló
        account: widget.repository,
        chat: widget.repository,
        music: widget.repository,
        musicStore: widget.musicStore,
        saver: widget.saver,
        roleCache: widget.roleCache,
        engine: JustAudioEngine.new,
        admin: widget.repository,
        direct: widget.repository,
        chatNotifier: LocalChatNotifier(),
        remembered: widget.remembered,
        durations: widget.durations,
        favorites: widget.favorites,
        covers: widget.covers,
        weather: widget.weather,
        navHint: widget.navHint,
        dock: widget.dock,
        system: _system,
        contacts: widget.contacts,
        vault: widget.vault,
        server: widget.repository,
        cloud: widget.repository,
        serverStore: widget.serverStore,
        wallpaper: widget.wallpaper,
        appearance: widget.appearance,
        voice: widget.voice,

        nowPlaying: _nowPlaying,
        background: AndroidBackgroundPlayback(),
        levels: AndroidAudioLevels(),
        tasks: widget.repository,
        openTaskStore: SqliteTaskStore.open,
        habits: widget.repository,
        openHabitStore: SqliteHabitStore.open,
        openReminderStore: PrefsReminderStore.open,
        reminderScheduler: LocalNotificationScheduler(),
        reminderBackend: widget.repository.reminderBackend,
        events: widget.repository.eventBackend,
        openEventStore: PrefsEventStore.open,
        financeCategories: widget.repository.financeCategoryBackend,
        financeEntries: widget.repository.financeEntryBackend,
        openFinanceCategoryStore: PrefsFinanceCategoryStore.open,
        openFinanceEntryStore: PrefsFinanceEntryStore.open,
        financeSettings: widget.financeSettings,
        calendarView: widget.calendarView,
        clockStore: widget.clockStore,
        alarmScheduler: widget.alarmScheduler,
        passwords: widget.repository.passwordBackend,
        improvements: widget.repository.improvementBackend,
        live: widget.repository,
      ),
      builder: (context, home) => MaterialApp(
        title: AppFlavor.current.appName,
        debugShowCheckedModeBanner: false,
        scrollBehavior: const KyraScrollBehavior(),
        // mientras suena una canción, los colores son los de su portada; si no, salen del fondo de pantalla (los de siempre si no hay ninguno)
        theme: buildAccentTheme(_nowPlaying.accent ?? widget.wallpaper?.accent, widget.wallpaper?.extras ?? const []),
        themeMode: ThemeMode.dark,
        themeAnimationDuration: const Duration(milliseconds: 220),
        themeAnimationCurve: Curves.easeInOut,
        builder: (context, child) => AppBackdrop(wallpaper: widget.wallpaper, nowPlaying: _nowPlaying, child: KyraKeyboardHost(controller: _keyboard, child: child ?? const SizedBox.shrink())),
        home: home,
      ),
    );
  }
}

/// Se ve solo si la app se compiló sin los datos de Supabase (falta env.json).
class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: buildTheme(),
      builder: (context, child) => AppBackdrop(child: child ?? const SizedBox.shrink()),
      home: const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(28),
          child: Center(
            child: Text(
              'Esta app se compiló sin los datos de Supabase.\n\n'
              'Ejecuta Scripts\\Kyra\\preparar_movil.bat (crea Family\\Kyra\\env.json desde Server\\supabase\\.env) y vuelve a compilarla.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
