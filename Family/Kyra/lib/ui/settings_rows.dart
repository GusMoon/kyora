import 'package:flutter/material.dart';

import '../data/background_playback.dart';
import '../data/server_stats.dart';
import '../state/dock_controller.dart';
import '../state/music_controller.dart';
import '../state/server_controller.dart';
import '../state/wallpaper_controller.dart';
import '../state/weather_controller.dart';
import '../theme.dart';
import '../util/picker.dart';
import '../data/music_store.dart';
import 'apps_picker.dart';
import 'widgets/pixel_glyph.dart';

// Las filas de Configuración: lo que hay dentro de cada ficha del mosaico cuando se expande.

/// El fondo de pantalla: elegir una imagen de la galería o quitarla.
class WallpaperRow extends StatelessWidget {
  const WallpaperRow({super.key, required this.controller});

  final WallpaperController controller;

  Future<void> _choose(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final picked = await pickCoverImage();
    if (picked == null) return;
    final ok = await controller.set(picked);
    if (!ok) messenger?.showSnackBar(const SnackBar(content: Text('No se pudo usar esa imagen.')));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(
        children: [
          SettingsRow(
            key: const Key('settings-wallpaper'),
            icon: Icons.wallpaper_outlined,
            title: controller.hasWallpaper ? 'Cambiar imagen' : 'Elegir imagen',
            subtitle: controller.busy ? 'Guardando…' : (controller.hasWallpaper ? 'Hay un fondo puesto.' : 'Ahora hay el fondo liso de siempre.'),
            trailing: LcdIcon(Icons.chevron_right, color: c.dim),
            onTap: controller.busy ? null : () => _choose(context),
          ),
          if (controller.hasWallpaper) ...[
            Divider(height: 1, thickness: 1, color: c.edge),
            SettingsRow(
              key: const Key('settings-wallpaper-clear'),
              icon: Icons.hide_image_outlined,
              title: 'Quitar fondo',
              danger: true,
              onTap: controller.clear,
            ),
          ],
        ],
      ),
    );
  }
}

/// Las 8 ranuras del disco: cada una dice qué app tiene y abre la lista para cambiarla; abajo, volver a rellenarlas solas.
class DockRows extends StatefulWidget {
  const DockRows({super.key, required this.dock});

  final DockController dock;

  @override
  State<DockRows> createState() => _DockRowsState();
}

class _DockRowsState extends State<DockRows> {
  @override
  void initState() {
    super.initState();
    if (!widget.dock.loaded) widget.dock.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: widget.dock,
      builder: (context, _) {
        final slots = widget.dock.slots;
        return Column(
          children: [
            for (var i = 0; i < slots.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: c.edge),
              SettingsRow(
                key: Key('settings-dock-$i'),
                leading: slots[i] == null
                    ? Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(border: Border.all(color: c.edge)),
                        child: Icon(Icons.add_rounded, size: 18, color: c.dim),
                      )
                    : ClipOval(child: Image.memory(slots[i]!.icon, width: 32, height: 32, gaplessPlayback: true)),
                title: 'App ${i + 1}',
                subtitle: slots[i]?.label ?? 'Vacía',
                trailing: LcdIcon(Icons.chevron_right, color: c.dim),
                onTap: () => showAppsPicker(context, widget.dock, i),
              ),
            ],
            if (!widget.dock.automatic) ...[
              Divider(height: 1, thickness: 1, color: c.edge),
              SettingsRow(
                key: const Key('settings-dock-reset'),
                icon: Icons.auto_fix_high_outlined,
                title: 'Rellenar solo',
                subtitle: 'Vuelve a poner las apps más comunes.',
                onTap: widget.dock.reset,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// «Usar Kyra como pantalla de inicio»: dice si ya lo es y, al tocar, pide a Android que lo sea (o abre la lista para cambiarlo).
class LauncherRow extends StatelessWidget {
  const LauncherRow({super.key, required this.dock});

  final DockController dock;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: dock,
      builder: (context, _) => SettingsRow(
        key: const Key('settings-launcher'),
        icon: dock.isLauncher ? Icons.check_circle_outline : Icons.home_outlined,
        title: dock.isLauncher ? 'Kyra es tu pantalla de inicio' : 'Usar Kyra como pantalla de inicio',
        subtitle: dock.isLauncher ? 'Toca para cambiarla por otra.' : 'Al abrir el teléfono o pulsar el botón de inicio saldrá Kyra.',
        subtitleColor: dock.isLauncher ? c.accent : null,
        trailing: LcdIcon(Icons.chevron_right, color: c.dim),
        onTap: () => dock.chooseLauncher(),
      ),
    );
  }
}

/// «Empezar a sonar sola»: al abrir Música, si no suena nada, arranca sola el aleatorio entre todos los álbumes. Apagado, sale el botón
/// «Aleatorio» arriba.
class AutoShuffleRow extends StatelessWidget {
  const AutoShuffleRow({super.key, required this.music});

  final MusicController music;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: music,
      builder: (context, _) {
        final on = music.settings.autoShuffle;
        return SettingsRow(
          icon: Icons.shuffle_rounded,
          title: 'Empezar a sonar sola',
          subtitle: on ? 'Al abrir Música suena el aleatorio entre todos los álbumes.' : 'Al abrir Música sale el botón «Aleatorio».',
          trailing: Switch(
            key: const Key('settings-auto-shuffle'),
            value: on,
            activeThumbColor: c.onAccent,
            activeTrackColor: c.accent,
            onChanged: (value) => music.updateSettings(music.settings.copyWith(autoShuffle: value)),
          ),
        );
      },
    );
  }
}

/// Lo sensible que es la ruleta de álbumes (y el abanico de favoritas) al dedo.
class DeckSpeedRow extends StatefulWidget {
  const DeckSpeedRow({super.key, required this.music});

  final MusicController music;

  @override
  State<DeckSpeedRow> createState() => _DeckSpeedRowState();
}

class _DeckSpeedRowState extends State<DeckSpeedRow> {
  double? _moving;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = lcdStatus(color: c.dim);
    return ListenableBuilder(
      listenable: widget.music,
      builder: (context, _) => SettingsRow(
        icon: Icons.tune_rounded,
        title: 'Sensibilidad de la ruleta',
        subtitle: 'Cuánto gira al mover el dedo.',
        below: Row(
          children: [
            Text('Lenta', style: label),
            Expanded(
              child: Slider(
                key: const Key('settings-deck-speed'),
                min: MusicSettings.deckSpeedMin,
                max: MusicSettings.deckSpeedMax,
                divisions: 6,
                value: _moving ?? widget.music.settings.deckSpeed,
                onChanged: (value) => setState(() => _moving = value),
                onChangeEnd: (value) async {
                  await widget.music.updateSettings(widget.music.settings.copyWith(deckSpeed: value));
                  if (mounted) setState(() => _moving = null);
                },
              ),
            ),
            Text('Rápida', style: label),
          ],
        ),
      ),
    );
  }
}

/// Los límites del plan de Supabase con los que la Nube compara cuánto ocupa tu proyecto (base de datos y archivos, en MB). Por defecto los del
/// plan gratuito (500 MB y 1 GB); se cambian si cambias de plan. Se guarda con «Guardar» o al enviar un campo.
class ServerLimitsRow extends StatefulWidget {
  const ServerLimitsRow({super.key, required this.controller});

  final ServerController controller;

  @override
  State<ServerLimitsRow> createState() => _ServerLimitsRowState();
}

class _ServerLimitsRowState extends State<ServerLimitsRow> {
  late final TextEditingController _db = TextEditingController(text: '${widget.controller.limits.dbMb}');
  late final TextEditingController _files = TextEditingController(text: '${widget.controller.limits.filesMb}');
  String? _error;

  @override
  void dispose() {
    _db.dispose();
    _files.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final db = int.tryParse(_db.text.trim());
    final files = int.tryParse(_files.text.trim());
    if (validMb(db, 0) == 0 || validMb(files, 0) == 0) {
      setState(() => _error = 'Escribe un número entero de MB (de 1 a $maxLimitMb).');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    await widget.controller.setLimits(QuotaLimits(dbMb: db!, filesMb: files!));
  }

  Future<void> _reset() async {
    _db.text = '$freeDbMb';
    _files.text = '$freeFilesMb';
    setState(() => _error = null);
    await widget.controller.setLimits(const QuotaLimits());
  }

  Widget _field(String key, String label, TextEditingController controller) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      key: Key(key),
      controller: controller,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(labelText: label, suffixText: 'MB', isDense: true),
      onSubmitted: (_) => _save(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SettingsRow(
      key: const Key('settings-limits'),
      icon: Icons.storage_outlined,
      title: 'Límites del plan',
      subtitle: _error ?? 'La Nube avisa al llegar al 80 % de cada uno. Gratis: $freeDbMb MB de base de datos y $freeFilesMb MB de archivos.',
      subtitleColor: _error == null ? null : c.warn,
      below: Column(
        children: [
          _field('settings-limit-db', 'Base de datos', _db),
          _field('settings-limit-files', 'Archivos (Storage)', _files),
          Wrap(
            children: [
              TextButton(key: const Key('settings-limits-save'), onPressed: _save, child: Text('Guardar', style: TextStyle(color: c.accent))),
              TextButton(key: const Key('settings-limits-reset'), onPressed: _reset, child: Text('Volver al plan gratuito', style: TextStyle(color: c.dim))),
            ],
          ),
        ],
      ),
    );
  }
}

/// Una fila de un grupo: un icono (o algo en su lugar), el título, una línea de explicación y, si hace falta, algo a la derecha.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.danger = false,
    this.below,
    this.subtitleColor,
  });

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
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (leading != null || icon != null) ...[leading ?? LcdIcon(icon!, color: danger ? c.warn : c.accent, size: 24), const SizedBox(width: 14)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontFamily: appFont, color: tint, fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle!, style: TextStyle(fontFamily: appFont, color: subtitleColor ?? c.dim, fontSize: 15, height: 1.3)),
                      ),
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
    return Material(
      type: MaterialType.transparency,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

/// La ciudad del clima: se escribe y se guarda al enviar; debajo dice si la encontró.
class CityRow extends StatefulWidget {
  const CityRow({super.key, required this.weather});

  final WeatherController weather;

  @override
  State<CityRow> createState() => _CityRowState();
}

class _CityRowState extends State<CityRow> {
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
        return SettingsRow(
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
class BackgroundRow extends StatefulWidget {
  const BackgroundRow({super.key, required this.background});

  final BackgroundPlayback background;

  @override
  State<BackgroundRow> createState() => _BackgroundRowState();
}

class _BackgroundRowState extends State<BackgroundRow> with WidgetsBindingObserver {
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
    return SettingsRow(
      key: const Key('settings-background'),
      leading: LcdIcon(free == true ? Icons.battery_charging_full_rounded : Icons.battery_alert_rounded, color: free == true ? c.accent : c.warn, size: 24),
      title: 'Música en segundo plano',
      subtitle: free == null
          ? 'Comprobando…'
          : free
          ? 'Sin restricciones de batería: la música sigue sonando con la app en segundo plano.'
          : 'Android puede detener la música al salir de la app. Toca para quitar la restricción.',
      trailing: free == true ? null : LcdIcon(Icons.chevron_right, color: c.dim),
      onTap: free == true ? null : () async => widget.background.requestBatteryExemption(),
    );
  }
}
