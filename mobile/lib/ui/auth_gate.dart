import 'dart:async';

import 'package:flutter/material.dart';

import '../data/account_backend.dart';
import '../data/audio_engine.dart';
import '../data/audio_levels.dart';
import '../data/background_playback.dart';
import '../data/chat_backend.dart';
import '../data/cover_store.dart';
import '../data/duration_cache.dart';
import '../data/favorites_store.dart';
import '../data/habit_backend.dart';
import '../data/habit_store.dart';
import '../data/music_backend.dart';
import '../data/music_store.dart';
import '../data/nav_hint_store.dart';
import '../data/reminder_scheduler.dart';
import '../data/reminder_store.dart';
import '../data/task_backend.dart';
import '../data/task_store.dart';
import '../models/profile.dart';
import '../state/contacts_controller.dart';
import '../state/dock_controller.dart';
import '../state/habit_controller.dart';
import '../state/local_music_controller.dart';
import '../state/music_controller.dart';
import '../state/player_controller.dart';
import '../state/reminder_controller.dart';
import '../state/task_controller.dart';
import '../state/now_playing_backdrop.dart';
import '../state/system_controller.dart';
import '../state/vault_controller.dart';
import '../state/wallpaper_controller.dart';
import '../state/weather_controller.dart';
import '../theme.dart';
import 'calendar_page.dart';
import 'chat_page.dart';
import 'contacts_page.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'music_page.dart';
import 'settings_page.dart';
import 'section_host.dart';
import 'vault_page.dart';
import 'widgets/app_section.dart';
import 'widgets/pixel_glyph.dart';

/// La puerta de entrada: sin sesión pide el acceso (o crear una cuenta); con sesión mira qué rol tiene la cuenta y abre
/// las secciones de la app, que se recorren con el menú circular (`SectionHost`): el administrador, Inicio · Chat · Música · Calendario
/// (tareas, recordatorios y hábitos) · Contactos · Vault; el pasante, lo mismo sin el chat. La configuración se abre desde el menú. Con sesión también arranca la música: las canciones que lleguen se guardan solas
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

class _AuthGateState extends State<AuthGate> {
  MusicController? _music;
  PlayerController? _player;
  LocalMusicController? _local;
  Future<TaskController>? _tasks;
  Future<ReminderController>? _reminders;
  Future<HabitController>? _habits;
  late final DurationCache _durations = widget.durations ?? MemoryDurationCache();

  /// La persona pidió cerrar sesión (Ajustes o la pantalla de error): ahí sí se para la música. Si la sesión caduca sola (Supabase no
  /// pudo renovarla al volver a la app) la música sigue sonando: se pide entrar otra vez, pero no se corta lo que suena.
  bool _signingOut = false;

  /// De quién es lo que hay abierto: si entra otra cuenta, no se hereda lo de la anterior.
  String? _owner;

  Future<void> _signOut() {
    _signingOut = true;
    return widget.account.signOut();
  }

  /// Las tareas de esta cuenta: se abren una vez (empiezan a ponerse al día con Supabase al instante) y se cierran al cerrar sesión.
  Future<TaskController>? _taskController(String userId) {
    final backend = widget.tasks;
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
      final controller = ReminderController(store, scheduler);
      await controller.start();
      return controller;
    }();
  }

  /// Los hábitos de esta cuenta: como las tareas, se abren una vez y se ponen al día con Supabase.
  Future<HabitController>? _habitController(String userId) {
    final backend = widget.habits;
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

  MusicController _musicController() {
    final existing = _music;
    if (existing != null) return existing;
    final created = MusicController(widget.music, widget.musicStore, widget.saver);
    _music = created;
    created.start();
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
  }

  @override
  void dispose() {
    _stopMusic();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    return StreamBuilder<void>(
      stream: account.authChanges,
      builder: (context, _) {
        if (!account.signedIn) {
          if (_signingOut) {
            _signingOut = false;
            _owner = null;
            _stopMusic();
          }
          return LoginPage(
            onSignIn: account.signIn,
            onSignUp: (u, e, p) => account.signUp(username: u, email: e, password: p),
          );
        }
        return _RoleResolver(
          key: ValueKey(account.userId),
          account: account,
          cache: widget.roleCache,
          onSignOut: _signOut,
          builder: (context, role, username) {
            if (_owner != null && _owner != account.userId) _stopMusic(); // otra cuenta: empieza de cero
            _owner = account.userId;
            final music = _musicController();
            final local = _localController(music);
            final player = _playerController(local);
            final userId = account.userId ?? '';
            final tasks = _taskController(userId);
            final reminders = _reminderController(userId);
            final habits = _habitController(userId);
            final admin = role == Role.admin;
            // Las secciones, en el orden del menú circular. Se abre en Inicio; Configuración es una opción más del menú (abre su hoja).
            // El pasante no tiene chat.
            Widget settingsPage({String? tile}) => SettingsPage(
              music: music,
              role: role,
              username: username,
              onSignOut: _signOut,
              background: widget.background,
              weather: widget.weather,
              dock: widget.dock,
              wallpaper: widget.wallpaper,
              initialTile: tile,
            );
            return SectionHost(
              key: ValueKey('home-${account.userId}'),
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
                  ),
                ),
                if (admin)
                  AppSection(
                    id: 'chat',
                    icon: Icons.cloud_outlined,
                    glyph: PixelGlyphs.cloud,
                    label: 'Chat',
                    builder: (_) => ChatPage(backend: widget.chat),
                  ),
                AppSection(
                  id: 'music',
                  icon: Icons.music_note_outlined,
                  glyph: PixelGlyphs.music,
                  label: 'Música',
                  builder: (_) => MusicPage(controller: music, player: player, local: local, favorites: widget.favorites),
                ),
                if (tasks != null || reminders != null || habits != null)
                  AppSection(
                    id: 'calendar',
                    icon: Icons.calendar_month_outlined,
                    glyph: PixelGlyphs.calendar,
                    label: 'Calendario',
                    builder: (_) => CalendarPage(tasks: tasks, reminders: reminders, habits: habits, now: widget.now),
                  ),
                if (widget.contacts != null)
                  AppSection(
                    id: 'contacts',
                    icon: Icons.contacts_outlined,
                    glyph: PixelGlyphs.contacts,
                    label: 'Contactos',
                    builder: (_) => ContactsPage(controller: widget.contacts!),
                  ),
                if (widget.vault != null)
                  AppSection(
                    id: 'vault',
                    icon: Icons.inventory_2_outlined,
                    glyph: PixelGlyphs.vault,
                    label: 'Vault',
                    builder: (_) => VaultPage(controller: widget.vault!),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Averigua el rol de la cuenta con sesión. Sin internet usa el de la última vez; si no hay ninguno, lo dice y deja reintentar.
class _RoleResolver extends StatefulWidget {
  const _RoleResolver({super.key, required this.account, required this.cache, required this.builder, required this.onSignOut});

  final AccountBackend account;
  final RoleCache cache;
  final Future<void> Function() onSignOut;
  final Widget Function(BuildContext context, Role role, String? username) builder;

  @override
  State<_RoleResolver> createState() => _RoleResolverState();
}

class _RoleResolverState extends State<_RoleResolver> {
  late Future<Role> _role = _resolve();
  String? _username;

  Future<Role> _resolve() async {
    final id = widget.account.userId ?? '';
    try {
      final profile = await widget.account.myProfile();
      _username = profile?.username;
      final role = profile?.role ?? Role.intern;
      await widget.cache.write(id, role);
      return role;
    } on ChatException {
      final cached = await widget.cache.read(id);
      if (cached != null) return cached;
      rethrow;
    }
  }

  void _retry() {
    final next = _resolve();
    setState(() {
      _role = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Role>(
      future: _role,
      builder: (context, snapshot) {
        if (snapshot.hasData) return widget.builder(context, snapshot.data!, _username);
        if (snapshot.hasError) {
          final error = snapshot.error;
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      error is ChatException ? error.message : 'No se pudo abrir tu cuenta.',
                      key: const Key('role-error'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.colors.warn),
                    ),
                    const SizedBox(height: 8),
                    TextButton(key: const Key('role-retry'), onPressed: _retry, child: const Text('Reintentar')),
                    TextButton(onPressed: widget.onSignOut, child: const Text('Cerrar sesión')),
                  ],
                ),
              ),
            ),
          );
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator(strokeWidth: 2.4)));
      },
    );
  }
}
