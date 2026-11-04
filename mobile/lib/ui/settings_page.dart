import 'dart:io';

import 'package:flutter/material.dart';

import '../data/background_playback.dart';
import '../models/profile.dart';
import '../state/music_controller.dart';
import '../state/wallpaper_controller.dart';
import '../state/weather_controller.dart';
import '../theme.dart';
import '../util/picker.dart';
import 'folder_settings.dart';
import 'widgets/palette_strip.dart';
import 'widgets/square_card.dart';

/// Configuración de Kyra, en grupos con su explicación: Apariencia (fondo y colores), Clima, Música y Cuenta.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.music,
    required this.role,
    required this.onSignOut,
    this.username,
    this.background,
    this.wallpaper,
    this.weather,
    this.pickImage = pickCoverImage,
  });

  final MusicController music;
  final Role role;

  /// El nombre de usuario, si ya se conoce (sin internet al abrir la app puede faltar).
  final String? username;

  final Future<void> Function() onSignOut;

  /// El estado de la batería para la música en segundo plano. Sin esto no sale esa fila.
  final BackgroundPlayback? background;

  /// El fondo de pantalla y sus colores. Sin esto no sale el grupo «Apariencia».
  final WallpaperController? wallpaper;

  /// El clima y su ciudad. Sin esto no sale el grupo «Clima».
  final WeatherController? weather;

  /// Elige una imagen de la galería: su ruta, o `null` si se cancela (en las pruebas, una falsa).
  final Future<String?> Function() pickImage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (wallpaper != null)
            _Group(
              title: 'Apariencia',
              about: 'El fondo de la app y los colores que salen de él.',
              children: [_WallpaperRow(wallpaper: wallpaper!, pickImage: pickImage), _ColorsRow(wallpaper: wallpaper!)],
            ),
          if (weather != null)
            _Group(
              title: 'Clima',
              about: 'La ciudad de la tarjeta de Inicio.',
              children: [_CityRow(weather: weather!)],
            ),
          _Group(
            title: 'Música',
            about: 'Dónde se guardan las canciones y cómo suenan.',
            children: [
              ListenableBuilder(
                listenable: music,
                builder: (context, _) => _Row(
                  key: const Key('settings-folder'),
                  icon: Icons.folder_open_outlined,
                  title: 'Carpeta de las canciones',
                  subtitle: music.settings.where,
                  trailing: Icon(Icons.chevron_right, color: c.dim),
                  onTap: () => showFolderSettings(context, music),
                ),
              ),
              if (background != null) _BackgroundRow(background: background!),
            ],
          ),
          _Group(
            title: 'Cuenta',
            about: 'Con quién has entrado.',
            children: [
              _Row(
                key: const Key('settings-account'),
                icon: Icons.person_outline,
                title: username ?? 'Tu cuenta',
                subtitle: role == Role.admin ? 'Administrador' : 'Pasante',
              ),
              _Row(
                key: const Key('settings-sign-out'),
                icon: Icons.logout,
                title: 'Cerrar sesión',
                danger: true,
                onTap: () async {
                  // la pantalla de acceso aparece en la base de la pila: se cierra lo que haya encima
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  await onSignOut();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Un grupo: su título en el acento, una línea que explica para qué sirve y, debajo, las filas en una tarjeta cuadrada.
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.about, required this.children});

  final String title;
  final String about;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: c.accent, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(about, style: TextStyle(color: c.dim, fontSize: 14)),
          const SizedBox(height: 10),
          SquareCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: c.edge),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Una fila de un grupo: un icono (o algo en su lugar), el título, una línea de explicación y, si hace falta, algo a la derecha.
class _Row extends StatelessWidget {
  const _Row({super.key, this.icon, this.leading, required this.title, this.subtitle, this.trailing, this.onTap, this.danger = false, this.below, this.subtitleColor});

  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  /// El color de la línea de explicación (por defecto, el atenuado).
  final Color? subtitleColor;

  /// Algo bajo el texto, a todo el ancho (los colores, por ejemplo).
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = danger ? c.warn : c.ink;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (leading != null || icon != null) ...[leading ?? Icon(icon, color: danger ? c.warn : c.accent, size: 24), const SizedBox(width: 14)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: tint, fontSize: 16, fontWeight: FontWeight.w600)),
                    if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle!, style: TextStyle(color: subtitleColor ?? c.dim, fontSize: 14, height: 1.3))),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          if (below != null) Padding(padding: const EdgeInsets.only(top: 12), child: below),
        ],
      ),
    );
    if (onTap == null) return content;
    return Material(type: MaterialType.transparency, child: InkWell(onTap: onTap, child: content));
  }
}

/// El fondo de pantalla: una miniatura, elegir o cambiar la imagen y, con una puesta, quitarla.
class _WallpaperRow extends StatelessWidget {
  const _WallpaperRow({required this.wallpaper, required this.pickImage});

  final WallpaperController wallpaper;
  final Future<String?> Function() pickImage;

  Future<void> _choose(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final path = await pickImage();
    if (path == null) return;
    final done = await wallpaper.set(path);
    if (!done) messenger.showSnackBar(const SnackBar(content: Text('No se pudo usar esa imagen.')));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: wallpaper,
      builder: (context, _) {
        final path = wallpaper.path;
        final thumb = SizedBox(
          width: 48,
          height: 48,
          child: path == null
              ? DecoratedBox(decoration: BoxDecoration(color: c.field, border: Border.all(color: c.edge)), child: Icon(Icons.wallpaper_outlined, color: c.accent))
              : DecoratedBox(
                  decoration: BoxDecoration(border: Border.all(color: c.edge)),
                  child: Image.file(File(path), key: const Key('settings-wallpaper-thumb'), fit: BoxFit.cover, cacheWidth: 96, errorBuilder: (context, _, _) => ColoredBox(color: c.field)),
                ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Row(
              key: const Key('settings-wallpaper'),
              leading: thumb,
              title: 'Fondo de pantalla',
              subtitle: wallpaper.busy ? 'Leyendo la imagen…' : (path == null ? 'Gris oscuro. Toca para elegir una imagen.' : 'Toca para cambiar la imagen.'),
              trailing: wallpaper.busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2)) : Icon(Icons.chevron_right, color: c.dim),
              onTap: wallpaper.busy ? null : () => _choose(context),
            ),
            if (path != null) ...[
              Divider(height: 1, thickness: 1, color: c.edge),
              _Row(key: const Key('settings-wallpaper-clear'), icon: Icons.close, title: 'Quitar el fondo', subtitle: 'Vuelve el gris oscuro.', onTap: wallpaper.busy ? null : wallpaper.clear),
            ],
          ],
        );
      },
    );
  }
}

/// Los 5 colores del fondo, con su código.
class _ColorsRow extends StatelessWidget {
  const _ColorsRow({required this.wallpaper});

  final WallpaperController wallpaper;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: wallpaper,
      builder: (context, _) {
        final palette = wallpaper.palette;
        return _Row(
          key: const Key('settings-colors'),
          icon: Icons.palette_outlined,
          title: 'Colores',
          subtitle: palette.isEmpty ? 'Elige un fondo y aquí salen sus 5 colores.' : 'Los 5 colores del fondo; con ellos se viste toda la app.',
          below: palette.isEmpty ? null : PaletteStrip(colors: palette, height: 36, showHex: true),
        );
      },
    );
  }
}

/// La ciudad del clima: se escribe y se guarda al enviar; debajo dice si la encontró.
class _CityRow extends StatefulWidget {
  const _CityRow({required this.weather});

  final WeatherController weather;

  @override
  State<_CityRow> createState() => _CityRowState();
}

class _CityRowState extends State<_CityRow> {
  late final TextEditingController _text = TextEditingController(text: widget.weather.city ?? '');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save(String value) async {
    FocusScope.of(context).unfocus();
    await widget.weather.setCity(value);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: widget.weather,
      builder: (context, _) {
        final status = widget.weather.status;
        final (String line, Color color) = switch (status) {
          WeatherStatus.noCity => ('Escribe tu ciudad y pulsa enviar.', c.dim),
          WeatherStatus.loading => ('Buscando…', c.dim),
          WeatherStatus.ready => ('Encontrada: ${widget.weather.weather?.city ?? widget.weather.city}.', c.accent),
          WeatherStatus.unknownCity => ('No encontré esa ciudad. Prueba con otro nombre.', c.warn),
          WeatherStatus.offline => ('Sin conexión: se guardó la ciudad y el clima saldrá al volver internet.', c.dim),
        };
        return _Row(
          key: const Key('settings-city'),
          icon: Icons.location_city_outlined,
          title: 'Ciudad',
          subtitle: line,
          subtitleColor: color,
          below: TextField(
            key: const Key('settings-city-field'),
            controller: _text,
            textInputAction: TextInputAction.search,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 16),
            decoration: const InputDecoration(hintText: 'Tu ciudad', isDense: true),
            onSubmitted: _save,
          ),
        );
      },
    );
  }
}

/// «Música en segundo plano»: dice si Android puede detener la app al salir de ella (la optimización de batería) y deja quitar esa
/// restricción. Sin esto, algunos teléfonos (Xiaomi, Samsung, Huawei…) cortan la música a los pocos minutos con la pantalla apagada.
class _BackgroundRow extends StatefulWidget {
  const _BackgroundRow({required this.background});

  final BackgroundPlayback background;

  @override
  State<_BackgroundRow> createState() => _BackgroundRowState();
}

class _BackgroundRowState extends State<_BackgroundRow> with WidgetsBindingObserver {
  bool? _free;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check(); // al volver del aviso del sistema
  }

  Future<void> _check() async {
    final free = await widget.background.batteryUnrestricted();
    if (mounted) setState(() => _free = free);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final free = _free;
    return _Row(
      key: const Key('settings-background'),
      leading: Icon(free == true ? Icons.battery_charging_full_rounded : Icons.battery_alert_rounded, color: free == true ? c.accent : c.warn, size: 24),
      title: 'Música en segundo plano',
      subtitle: free == null
          ? 'Comprobando…'
          : free
              ? 'Sin restricciones de batería: la música sigue sonando con la app en segundo plano.'
              : 'Android puede detener la música al salir de la app. Toca para quitar la restricción.',
      trailing: free == true ? null : Icon(Icons.chevron_right, color: c.dim),
      onTap: free == true ? null : () async => widget.background.requestBatteryExemption(),
    );
  }
}
