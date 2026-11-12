import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'data/account_backend.dart';
import 'data/audio_levels.dart';
import 'data/background_playback.dart';
import 'data/chat_repository.dart';
import 'data/cover_store.dart';
import 'data/dock_store.dart';
import 'data/duration_cache.dart';
import 'data/favorites_store.dart';
import 'data/habit_store.dart';
import 'data/installed_apps.dart';
import 'data/just_audio_engine.dart';
import 'data/music_store.dart';
import 'data/nav_hint_store.dart';
import 'data/reminder_scheduler.dart';
import 'data/reminder_store.dart';
import 'data/role_cache.dart';
import 'data/task_store.dart';
import 'data/wallpaper_store.dart';
import 'data/weather_service.dart';
import 'data/weather_store.dart';
import 'state/contacts_controller.dart';
import 'state/dock_controller.dart';
import 'state/vault_controller.dart';
import 'data/contacts_source.dart';
import 'data/vault_source.dart';
import 'state/now_playing_backdrop.dart';
import 'state/system_controller.dart';
import 'data/system_info.dart';
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
  final (wallpaperStore, dockStore, vaultStore) = await (PrefsWallpaperStore.open(), PrefsDockStore.open(), PrefsVaultStore.open()).wait;
  await Future.wait([audioReady, backgroundReady, supabaseReady]);
  final favorites = FavoritesController(favoritesStore);
  final weather = WeatherController(OpenMeteoWeather(), weatherStore);
  runApp(
    KyoraChatApp(
      repository: ChatRepository(Supabase.instance.client),
      musicStore: store,
      saver: AndroidTrackSaver(),
      roleCache: roles,
      durations: durations,
      favorites: favorites,
      covers: covers,
      weather: weather,
      navHint: navHint,
      dock: DockController(dockStore, AndroidInstalledApps()),
      wallpaper: WallpaperController(wallpaperStore),
      contacts: ContactsController(AndroidContactsSource()),
      vault: VaultController(AndroidVaultSource(), vaultStore),
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
    this.durations,
    this.favorites,
    this.covers,
    this.weather,
    this.navHint,
    this.dock,
    this.wallpaper,
    this.contacts,
    this.vault,
  });

  final ChatRepository repository;
  final MusicStore musicStore;
  final TrackSaver saver;
  final RoleCache roleCache;
  final DurationCache? durations;
  final FavoritesController? favorites;
  final CoverStore? covers;

  final WeatherController? weather;

  /// Si ya se enseñó cómo abrir el menú circular.
  final NavHintStore? navHint;

  /// Las 8 apps del disco de Inicio y el fondo de pantalla.
  final DockController? dock;
  final WallpaperController? wallpaper;

  /// Los contactos del teléfono y el Vault (carpeta del almacenamiento).
  final ContactsController? contacts;
  final VaultController? vault;

  @override
  State<KyoraChatApp> createState() => _KyoraChatAppState();
}

class _KyoraChatAppState extends State<KyoraChatApp> {
  /// La portada de lo que suena: mientras suena algo, el fondo de toda la app es su portada.
  final NowPlayingBackdrop _nowPlaying = NowPlayingBackdrop();

  /// El estado del teléfono para el tablero de Inicio.
  final SystemController _system = SystemController(AndroidSystemInfo());

  @override
  void dispose() {
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
        account: widget.repository,
        chat: widget.repository,
        music: widget.repository,
        musicStore: widget.musicStore,
        saver: widget.saver,
        roleCache: widget.roleCache,
        engine: JustAudioEngine.new,
        durations: widget.durations,
        favorites: widget.favorites,
        covers: widget.covers,
        weather: widget.weather,
        navHint: widget.navHint,
        dock: widget.dock,
        system: _system,
        contacts: widget.contacts,
        vault: widget.vault,
        wallpaper: widget.wallpaper,
        nowPlaying: _nowPlaying,
        background: AndroidBackgroundPlayback(),
        levels: AndroidAudioLevels(),
        tasks: widget.repository,
        openTaskStore: SqliteTaskStore.open,
        habits: widget.repository,
        openHabitStore: SqliteHabitStore.open,
        openReminderStore: PrefsReminderStore.open,
        reminderScheduler: LocalNotificationScheduler(),
      ),
      builder: (context, home) => MaterialApp(
        title: 'Kyra',
        debugShowCheckedModeBanner: false,
        scrollBehavior: const KyraScrollBehavior(),
        // mientras suena una canción, los colores son los de su portada; si no, salen del fondo de pantalla (los de siempre si no hay ninguno)
        theme: buildAccentTheme(_nowPlaying.accent ?? widget.wallpaper?.accent),
        themeMode: ThemeMode.dark,
        themeAnimationDuration: const Duration(milliseconds: 220),
        themeAnimationCurve: Curves.easeInOut,
        builder: (context, child) => AppBackdrop(wallpaper: widget.wallpaper, nowPlaying: _nowPlaying, child: child ?? const SizedBox.shrink()),
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
