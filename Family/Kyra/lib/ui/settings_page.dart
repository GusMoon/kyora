import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/account_backend.dart';
import '../data/background_playback.dart';
import '../models/profile.dart';
import '../state/dock_controller.dart';
import '../data/server_stats.dart' show QuotaId, percent;
import '../state/music_controller.dart';
import '../state/server_controller.dart';
import '../state/wallpaper_controller.dart';
import '../state/weather_controller.dart';
import '../theme.dart';
import 'folder_settings.dart';
import 'settings_mosaic.dart';
import 'settings_rows.dart';
import 'widgets/pixel_glyph.dart';
import 'widgets/cut_border.dart';

/// Abre Configuración **a pantalla completa**: aparece con un fundido y un leve crecimiento (≈300 ms) sobre el fondo de pantalla de la app. Se
/// cierra con «atrás» (primero cierra la ficha expandida, luego la página) o con la X de arriba.
Future<void> showSettings(BuildContext context, Widget page) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (context, animation, secondary, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: Tween<double>(begin: 0.96, end: 1).animate(curved), child: child),
        );
      },
    ),
  );
}

/// Configuración de Kyra como un **mosaico** de fichas de distinto tamaño (Fondo, Pantalla de inicio, Clima, Apps del disco, Música y Cuenta).
/// Cada ficha cerrada enseña un resumen en vivo; al tocarla se expande con sus ajustes y las demás se reacomodan en una franja de iconos.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.music,
    required this.role,
    required this.onSignOut,
    this.account,
    this.expired,
    this.onSignIn,
    this.username,
    this.background,
    this.weather,
    this.dock,
    this.wallpaper,
    this.server,
    this.initialTile,
  });

  final MusicController music;
  final Role role;

  /// El nombre de usuario, si ya se conoce (sin internet al abrir la app puede faltar).
  final String? username;

  final Future<void> Function() onSignOut;

  /// La cuenta, para saber si hay sesión (la ficha se actualiza sola al entrar o salir). Sin esto se da por hecho que hay sesión.
  final AccountBackend? account;

  /// `true` si la sesión se perdió sola (caducó) y toca volver a entrar para sincronizar.
  final ValueListenable<bool>? expired;

  /// Abre el acceso (entrar o crear cuenta). Sin esto no sale la opción «Iniciar sesión».
  final VoidCallback? onSignIn;

  /// El estado de la batería para la música en segundo plano. Sin esto no sale esa fila.
  final BackgroundPlayback? background;

  /// El clima y su ciudad. Sin esto no sale la ficha «Clima».
  final WeatherController? weather;

  /// Las 8 apps del disco de Inicio. Sin esto no salen las fichas «Apps del disco» ni «Pantalla de inicio».
  final DockController? dock;

  /// El fondo de pantalla de Inicio. Sin esto no sale la ficha «Fondo».
  final WallpaperController? wallpaper;

  /// El servidor de Supabase (para cambiar los límites del plan con los que avisa la Nube). Sin esto no sale la ficha «Servidor».
  final ServerController? server;

  /// Una ficha que se abre ya expandida (por ejemplo, la del clima desde Inicio).
  final String? initialTile;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late String? _open = widget.initialTile;

  void _expand(String? id) => setState(() => _open = id);

  List<MosaicEntry> _entries() {
    final music = widget.music;
    return [
      if (widget.wallpaper != null) _wallpaper(widget.wallpaper!),
      if (widget.dock != null) _launcher(widget.dock!),
      if (widget.weather != null) _weather(widget.weather!),
      if (widget.dock != null) _dock(widget.dock!),
      _musicEntry(music),
      if (widget.server != null) _serverEntry(widget.server!),
      _account(),
    ];
  }

  // ---- fichas ----

  MosaicEntry _wallpaper(WallpaperController wallpaper) => MosaicEntry(
    id: 'wallpaper',
    title: 'Fondo de pantalla',
    code: 'CFG·01',
    icon: Icons.wallpaper_outlined,
    colSpan: 2,
    rowSpan: 2,
    summary: (context, height) => ListenableBuilder(
      listenable: wallpaper,
      builder: (context, _) {
        final c = context.colors;
        final path = wallpaper.path;
        return ClipPath(
          clipper: const ShapeBorderClipper(shape: CutBorder(cut: 8)),
          child: DecoratedBox(
            decoration: BoxDecoration(border: Border.all(color: c.accent.withValues(alpha: 0.3))),
            child: path == null
                ? Center(child: Text('SIN FONDO', style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 1.5, color: c.dim)))
                : Image.file(
                    key: const Key('settings-wallpaper-preview'),
                    File(path),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    cacheWidth: 360,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
          ),
        );
      },
    ),
    detail: (context) => ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
      _hint(context, 'La imagen de Inicio y de toda la app. Los colores de la app salen de ella.'),
      WallpaperRow(controller: wallpaper),
    ]),
  );

  MosaicEntry _launcher(DockController dock) => MosaicEntry(
    id: 'launcher',
    title: 'Pantalla de inicio',
    code: 'CFG·02',
    icon: Icons.home_outlined,
    colSpan: 2,
    rowSpan: 1,
    summary: (context, height) => ListenableBuilder(
      listenable: dock,
      builder: (context, _) => _status(context, dock.isLauncher ? 'ACTIVO' : 'INACTIVO', on: dock.isLauncher),
    ),
    detail: (context) => ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
      _hint(context, 'Que Kyra sea lo primero que ves al abrir el teléfono.'),
      LauncherRow(dock: dock),
    ]),
  );

  MosaicEntry _weather(WeatherController weather) => MosaicEntry(
    id: 'weather',
    title: 'Clima',
    code: 'CFG·03',
    icon: Icons.cloud_outlined,
    colSpan: 2,
    rowSpan: 1,
    summary: (context, height) => ListenableBuilder(
      listenable: weather,
      builder: (context, _) {
        final w = weather.weather;
        return _status(context, w == null ? (weather.city ?? 'ELIGE CIUDAD').toUpperCase() : '${w.temperature.round()}° · ${w.city}'.toUpperCase(), on: w != null);
      },
    ),
    detail: (context) => ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
      _hint(context, 'La ciudad del clima de Inicio.'),
      CityRow(weather: weather),
    ]),
  );

  MosaicEntry _dock(DockController dock) => MosaicEntry(
    id: 'dock',
    title: 'Apps del disco',
    code: 'CFG·04',
    icon: Icons.apps_rounded,
    colSpan: 4,
    rowSpan: 1,
    summary: (context, height) => ListenableBuilder(
      listenable: dock,
      builder: (context, _) {
        final slots = dock.slots;
        return Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                for (final app in slots)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: app == null
                        ? Container(width: 24, height: 24, decoration: BoxDecoration(border: Border.all(color: Colors.white24)))
                        : ClipOval(child: Image.memory(app.icon, width: 24, height: 24, gaplessPlayback: true)),
                  ),
              ],
            ),
          ),
        );
      },
    ),
    detail: (context) => ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
      _hint(context, 'Las 8 apps de Inicio. Toca una ranura para cambiarla.'),
      DockRows(dock: dock),
    ]),
  );

  MosaicEntry _musicEntry(MusicController music) => MosaicEntry(
    id: 'music',
    title: 'Música',
    code: 'CFG·05',
    icon: Icons.music_note_outlined,
    colSpan: 3,
    rowSpan: 2,
    summary: (context, height) => ListenableBuilder(
      listenable: music,
      builder: (context, _) {
        final c = context.colors;
        return Align(
          alignment: Alignment.bottomLeft,
          child: Text(music.settings.where, maxLines: 3, overflow: TextOverflow.ellipsis, style: lcdStatus(size: 15, color: c.dim)),
        );
      },
    ),
    detail: (context) => ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
      _hint(context, 'Dónde se guardan las canciones y cómo suenan.'),
      ListenableBuilder(
        listenable: music,
        builder: (context, _) => SettingsRow(
          key: const Key('settings-folder'),
          icon: Icons.folder_open_outlined,
          title: 'Carpeta de las canciones',
          subtitle: music.settings.where,
          trailing: LcdIcon(Icons.chevron_right, color: context.colors.dim),
          onTap: () => showFolderSettings(context, music),
        ),
      ),
      AutoShuffleRow(music: music),
      DeckSpeedRow(music: music),
      if (widget.background != null) BackgroundRow(background: widget.background!),
    ]),
  );

  MosaicEntry _serverEntry(ServerController server) => MosaicEntry(
    id: 'server',
    title: 'Servidor',
    code: 'CFG·07',
    icon: Icons.storage_outlined,
    colSpan: 4,
    rowSpan: 1,
    summary: (context, height) => ListenableBuilder(
      listenable: server,
      builder: (context, _) {
        final q = server.quotaList;
        final text = q.isEmpty ? '${server.limits.dbMb} MB · ${server.limits.filesMb} MB' : q.map((e) => '${e.id == QuotaId.db ? 'BD' : 'ARCH'} ${percent(e.ratio)}').join(' · ');
        return _status(context, text, on: server.warnings.isEmpty);
      },
    ),
    detail: (context) => ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
      _hint(context, 'Los límites de tu plan de Supabase: la Nube avisa al llegar al 80 %.'),
      ServerLimitsRow(controller: server),
    ]),
  );

  /// Pinta la ficha según haya sesión o no (escucha la cuenta: al entrar o salir cambia sola).
  Widget _live(Widget Function(bool signedIn, bool expired) build) {
    final account = widget.account;
    if (account == null) return build(true, false);
    return StreamBuilder<void>(
      stream: account.authChanges,
      builder: (context, _) => ListenableBuilder(
        listenable: widget.expired ?? const _Never(),
        builder: (context, _) => build(account.signedIn, widget.expired?.value ?? false),
      ),
    );
  }

  MosaicEntry _account() => MosaicEntry(
    id: 'account',
    title: widget.username ?? 'Tu cuenta',
    code: 'CFG·06',
    icon: Icons.person_outline,
    colSpan: 1,
    rowSpan: 2,
    summary: (context, height) => _live((signedIn, expired) {
      final c = context.colors;
      final text = !signedIn ? (expired ? 'SESIÓN CADUCADA' : 'SIN SESIÓN') : (widget.role == Role.admin ? 'ADMIN' : 'PASANTE');
      return Align(
        alignment: Alignment.bottomLeft,
        child: Text(text, style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 0.5, color: signedIn ? c.accent : c.warn)),
      );
    }),
    detail: (context) => _live((signedIn, expired) => ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
      _hint(
        context,
        signedIn
            ? 'Con quién has entrado.'
            : expired
                ? 'La sesión caducó. Kyra sigue funcionando; entra de nuevo para el chat, la música de la PC y sincronizar.'
                : 'Kyra funciona sin sesión. Entra para el chat, la música de la PC y sincronizar tus tareas.',
      ),
      if (signedIn) ...[
        SettingsRow(
          key: const Key('settings-account'),
          icon: Icons.person_outline,
          title: widget.username ?? 'Tu cuenta',
          subtitle: widget.role == Role.admin ? 'Administrador' : 'Pasante',
        ),
        Divider(height: 1, thickness: 1, color: context.colors.edge),
        SettingsRow(
          key: const Key('settings-sign-out'),
          icon: Icons.logout,
          title: 'Cerrar sesión',
          danger: true,
          onTap: () async {
            // sigue en Inicio, ya sin sesión: se cierra lo que haya encima
            Navigator.of(context).popUntil((route) => route.isFirst);
            await widget.onSignOut();
          },
        ),
      ] else if (widget.onSignIn != null)
        SettingsRow(
          key: const Key('settings-sign-in'),
          icon: Icons.login,
          title: 'Iniciar sesión',
          subtitle: 'O crear una cuenta',
          trailing: LcdIcon(Icons.chevron_right, color: context.colors.dim),
          onTap: widget.onSignIn,
        ),
    ])),
  );

  // ---- piezas ----

  Widget _hint(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 4),
    child: Text(text, style: lcdStatus(size: 15, color: context.colors.dim)),
  );

  Widget _status(BuildContext context, String text, {required bool on}) {
    final c = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Container(width: 8, height: 8, color: on ? c.accent : c.dim),
          const SizedBox(width: 8),
          Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 0.5, color: c.ink))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final entries = _entries();
    final padding = MediaQuery.paddingOf(context);
    return PopScope(
      // «atrás» cierra primero la ficha expandida y después la página
      canPop: _open == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _expand(null);
      },
      child: Scaffold(
        key: const Key('settings-page'),
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // un velo oscuro sobre el fondo de pantalla (sin desenfoque)
            ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
            Padding(
              padding: EdgeInsets.fromLTRB(16, padding.top + 8, 16, padding.bottom + 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('CONFIGURACIÓN', key: const Key('settings-title'), style: hudLabel(size: 16, color: c.accent)),
                            Text('SYS//CFG · ${entries.length} MÓDULOS', style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 0.5, color: c.dim)),
                          ],
                        ),
                      ),
                      IconButton(key: const Key('settings-close'), tooltip: 'Cerrar', onPressed: () => Navigator.of(context).maybePop(), icon: Icon(Icons.close_rounded, color: c.ink)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(child: MosaicView(entries: entries, expandedId: _open, onExpand: _expand)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un `Listenable` que nunca avisa (cuando no hay nada que escuchar).
class _Never implements Listenable {
  const _Never();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
