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
import 'data/device_info.dart';
import 'data/duration_cache.dart';
import 'data/favorites_store.dart';
import 'data/just_audio_engine.dart';
import 'data/music_store.dart';
import 'data/reminder_scheduler.dart';
import 'data/reminder_store.dart';
import 'data/role_cache.dart';
import 'data/task_store.dart';
import 'data/wallpaper_store.dart';
import 'data/weather_service.dart';
import 'data/weather_store.dart';
import 'state/cover_theme.dart';
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
  // La sesión de audio: música (así Android sabe qué es, baja el volumen ante un aviso y la respeta en segundo plano).
  await (await AudioSession.instance).configure(const AudioSessionConfiguration.music());
  // La notificación y los controles de la pantalla de bloqueo del reproductor. El servicio sigue en primer plano también en pausa
  // (si no, al pausar —una llamada, quitar los auriculares— Android lo trata como una app cualquiera y puede detenerlo).
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.kyora.kyora_chat.audio',
    androidNotificationChannelName: 'Música de Kyra',
    androidNotificationOngoing: false,
    androidStopForegroundOnPause: false,
  );
  await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseAnonKey);
  final store = await PrefsMusicStore.open();
  final roles = await PrefsRoleCache.open();
  final durations = await PrefsDurationCache.open();
  final favorites = FavoritesController(await PrefsFavoritesStore.open());
  final covers = await PrefsCoverStore.open();
  final wallpaper = WallpaperController(await PrefsWallpaperStore.open());
  final weather = WeatherController(OpenMeteoWeather(), await PrefsWeatherStore.open());
  runApp(
    KyoraChatApp(
      repository: ChatRepository(Supabase.instance.client),
      musicStore: store,
      saver: AndroidTrackSaver(),
      roleCache: roles,
      durations: durations,
      favorites: favorites,
      covers: covers,
      wallpaper: wallpaper,
      weather: weather,
      device: AndroidDeviceInfo(),
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
    this.wallpaper,
    this.weather,
    this.device,
  });

  final ChatRepository repository;
  final MusicStore musicStore;
  final TrackSaver saver;
  final RoleCache roleCache;
  final DurationCache? durations;
  final FavoritesController? favorites;
  final CoverStore? covers;

  /// El fondo de pantalla y sus 5 colores; con uno puesto, mandan sobre el color de la carátula.
  final WallpaperController? wallpaper;
  final WeatherController? weather;
  final DeviceInfo? device;

  @override
  State<KyoraChatApp> createState() => _KyoraChatAppState();
}

class _KyoraChatAppState extends State<KyoraChatApp> {
  /// El color de la carátula que suena: toda la app se viste con él.
  final _cover = CoverTheme();

  @override
  void dispose() {
    _cover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // la pantalla de entrada se construye una vez; solo el tema cambia con la carátula o el fondo (con una transición suave entre colores)
    return ListenableBuilder(
      listenable: Listenable.merge([_cover, if (widget.wallpaper != null) widget.wallpaper!]),
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
        coverTheme: _cover,
        wallpaper: widget.wallpaper,
        weather: widget.weather,
        device: widget.device,
        background: AndroidBackgroundPlayback(),
        levels: AndroidAudioLevels(),
        tasks: widget.repository,
        openTaskStore: SqliteTaskStore.open,
        openReminderStore: PrefsReminderStore.open,
        reminderScheduler: LocalNotificationScheduler(),
      ),
      builder: (context, home) => MaterialApp(
        title: 'Kyra',
        debugShowCheckedModeBanner: false,
        // con un fondo de pantalla puesto mandan sus colores; sin él, el de la carátula que suena (o los de siempre)
        theme: buildCoverTheme(widget.wallpaper?.seed ?? _cover.value),
        themeMode: ThemeMode.dark,
        themeAnimationDuration: const Duration(milliseconds: 600),
        themeAnimationCurve: Curves.easeInOut,
        builder: (context, child) => AppBackdrop(wallpaper: widget.wallpaper, child: child ?? const SizedBox.shrink()),
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
              'Ejecuta scripts\\preparar_movil.bat (crea mobile\\env.json desde supabase\\.env) y vuelve a compilarla.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
