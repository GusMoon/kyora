import 'dart:async';

import 'package:flutter/material.dart';

import '../data/device_info.dart';
import '../models/task.dart';
import '../state/task_controller.dart';
import '../state/wallpaper_controller.dart';
import '../state/weather_controller.dart';
import '../theme.dart';
import '../util/format.dart';
import 'widgets/palette_strip.dart';
import 'widgets/square_card.dart';

/// La pantalla de inicio de Kyra: arriba el día y la fecha, y el botón de configuración; debajo, tres tarjetas cuadradas con lo que
/// importa de un vistazo: las tareas pendientes, el clima y el almacenamiento del teléfono.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.onOpenSettings,
    this.tasks,
    this.weather,
    this.device,
    this.wallpaper,
    this.now,
  });

  /// Abre la configuración.
  final VoidCallback onOpenSettings;

  /// Las tareas (se abren en segundo plano). Sin esto no sale la tarjeta de tareas.
  final Future<TaskController>? tasks;

  /// El clima. Sin esto no sale la tarjeta del clima.
  final WeatherController? weather;

  /// El espacio del teléfono. Sin esto no sale la tarjeta de almacenamiento.
  final DeviceInfo? device;

  /// El fondo de pantalla: si tiene uno, se enseñan sus 5 colores bajo la fecha.
  final WallpaperController? wallpaper;

  /// El reloj (en las pruebas, uno fijo).
  final DateTime Function()? now;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  StorageInfo? _storage;
  late DateTime _today = _clock();

  DateTime _clock() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // al volver a la app puede haber cambiado el día, el clima y el espacio libre
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _today = _clock());
    unawaited(widget.weather?.refresh());
    final info = await widget.device?.storage();
    if (mounted && info != null) setState(() => _storage = info);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            unawaited(widget.weather?.refresh(force: true));
            await _refresh();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(weekdayName(_today), key: const Key('home-weekday'), style: TextStyle(color: c.ink, fontSize: 34, fontWeight: FontWeight.w700, height: 1.1)),
                        const SizedBox(height: 4),
                        Text(fullDate(_today), key: const Key('home-date'), style: TextStyle(color: c.dim, fontSize: 16)),
                      ],
                    ),
                  ),
                  _SettingsButton(onTap: widget.onOpenSettings),
                ],
              ),
              if (widget.wallpaper != null)
                ListenableBuilder(
                  listenable: widget.wallpaper!,
                  builder: (context, _) => widget.wallpaper!.palette.isEmpty
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 18),
                          child: PaletteStrip(colors: widget.wallpaper!.palette, height: 10),
                        ),
                ),
              const SizedBox(height: 26),
              if (widget.tasks != null) ...[
                _TasksCard(future: widget.tasks!),
                const SizedBox(height: 12),
              ],
              if (widget.weather != null || widget.device != null)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.weather != null) Expanded(child: _WeatherCard(controller: widget.weather!, onNeedCity: widget.onOpenSettings)),
                      if (widget.weather != null && widget.device != null) const SizedBox(width: 12),
                      if (widget.device != null) Expanded(child: _StorageCard(info: _storage)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El botón de configuración: un cuadrado con borde, como las tarjetas.
class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'Configuración',
      child: SizedBox(
        width: 48,
        height: 48,
        child: SquareCard(key: const Key('home-settings'), padding: EdgeInsets.zero, onTap: onTap, child: Center(child: Icon(Icons.settings_outlined, color: c.ink, size: 24))),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: Text(text, style: TextStyle(color: context.colors.ink, fontSize: 15, fontWeight: FontWeight.w700))),
          ?trailing,
        ],
      );
}

/// Tareas pendientes: cuántas son y las próximas.
class _TasksCard extends StatelessWidget {
  const _TasksCard({required this.future});

  final Future<TaskController> future;

  static const shown = 3;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TaskController>(
      future: future,
      builder: (context, snapshot) {
        final controller = snapshot.data;
        if (controller == null) {
          return const SquareCard(key: Key('home-tasks'), child: SizedBox(height: 96, child: Center(child: CircularProgressIndicator(strokeWidth: 2.4))));
        }
        return ListenableBuilder(listenable: controller, builder: (context, _) => _TasksBody(controller: controller));
      },
    );
  }
}

class _TasksBody extends StatelessWidget {
  const _TasksBody({required this.controller});

  final TaskController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final next = controller.roots(active: true);
    final count = controller.count(null);
    return SquareCard(
      key: const Key('home-tasks'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Title('Tareas pendientes'),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$count', key: const Key('home-tasks-count'), style: TextStyle(color: c.ink, fontSize: 48, fontWeight: FontWeight.w600, height: 1)),
              const SizedBox(width: 10),
              Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(count == 1 ? 'tarea' : 'tareas', style: TextStyle(color: c.dim, fontSize: 15))),
            ],
          ),
          const SizedBox(height: 12),
          if (next.isEmpty)
            Text('Todo al día', key: const Key('home-tasks-empty'), style: TextStyle(color: c.accent, fontSize: 15, fontWeight: FontWeight.w600))
          else
            for (final task in next.take(_TasksCard.shown)) _TaskLine(task: task),
        ],
      ),
    );
  }
}

class _TaskLine extends StatelessWidget {
  const _TaskLine({required this.task});

  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final due = task.due;
    final late = due != null && due.isBefore(DateTime.now().toUtc());
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 10), decoration: BoxDecoration(border: Border.all(color: late ? c.warn : c.accent, width: 1.5))),
          Expanded(child: Text(task.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.ink, fontSize: 15))),
          if (due != null) Padding(padding: const EdgeInsets.only(left: 8), child: Text(dayLabel(due), style: TextStyle(color: late ? c.warn : c.dim, fontSize: 15))),
        ],
      ),
    );
  }
}

/// El icono del estado del cielo.
IconData weatherIcon(int code) {
  if (code == 0 || code == 1) return Icons.wb_sunny_outlined;
  if (code == 2) return Icons.wb_cloudy_outlined;
  if (code == 3) return Icons.cloud_outlined;
  if (code == 45 || code == 48) return Icons.foggy;
  if (code >= 51 && code <= 67 || code >= 80 && code <= 82) return Icons.water_drop_outlined;
  if (code >= 71 && code <= 77 || code == 85 || code == 86) return Icons.ac_unit;
  if (code >= 95) return Icons.thunderstorm_outlined;
  return Icons.cloud_queue;
}

/// El clima de la ciudad elegida (o la invitación a elegirla).
class _WeatherCard extends StatelessWidget {
  const _WeatherCard({required this.controller, required this.onNeedCity});

  final WeatherController controller;
  final VoidCallback onNeedCity;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = context.colors;
        final weather = controller.weather;
        Widget body;
        if (controller.status == WeatherStatus.noCity) {
          body = Text('Elige tu ciudad en Configuración', key: const Key('home-weather-nocity'), style: TextStyle(color: c.dim, fontSize: 15, height: 1.3));
        } else if (controller.status == WeatherStatus.unknownCity) {
          body = Text('No encontré «${controller.city}»', key: const Key('home-weather-unknown'), style: TextStyle(color: c.warn, fontSize: 15, height: 1.3));
        } else if (weather == null) {
          body = Text(controller.status == WeatherStatus.offline ? 'Sin conexión' : 'Cargando…', key: const Key('home-weather-wait'), style: TextStyle(color: c.dim, fontSize: 15));
        } else {
          body = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${weather.temperature.round()}°C', key: const Key('home-weather-temp'), style: TextStyle(color: c.ink, fontSize: 40, fontWeight: FontWeight.w600, height: 1)),
              const SizedBox(height: 8),
              Text(weather.label, maxLines: 2, style: TextStyle(color: c.ink, fontSize: 15)),
              Text(controller.stale ? '${weather.city} · sin conexión' : weather.city, maxLines: 2, style: TextStyle(color: c.dim, fontSize: 15)),
            ],
          );
        }
        return SquareCard(
          key: const Key('home-weather'),
          onTap: controller.status == WeatherStatus.noCity || controller.status == WeatherStatus.unknownCity ? onNeedCity : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Title('Clima', trailing: weather == null ? null : Icon(weatherIcon(weather.code), color: c.accent, size: 26)),
              const SizedBox(height: 14),
              body,
            ],
          ),
        );
      },
    );
  }
}

/// El espacio libre del teléfono, con una barra de lo usado.
class _StorageCard extends StatelessWidget {
  const _StorageCard({required this.info});

  final StorageInfo? info;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final storage = info;
    return SquareCard(
      key: const Key('home-storage'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Title('Almacenamiento', trailing: Icon(Icons.sd_storage_outlined, color: c.accent, size: 24)),
          const SizedBox(height: 14),
          if (storage == null)
            Text('No disponible', key: const Key('home-storage-none'), style: TextStyle(color: c.dim, fontSize: 15))
          else ...[
            Text(humanSize(storage.free), key: const Key('home-storage-free'), style: TextStyle(color: c.ink, fontSize: 28, fontWeight: FontWeight.w600, height: 1)),
            const SizedBox(height: 8),
            Text('libres de ${humanSize(storage.total)}', style: TextStyle(color: c.dim, fontSize: 15)),
            const SizedBox(height: 12),
            // la barra, cuadrada también: lo usado en el acento (en rojo si casi no queda)
            Container(
              height: 8,
              decoration: BoxDecoration(color: c.field, border: Border.all(color: c.edge)),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: storage.usedFraction.clamp(0.0, 1.0),
                child: ColoredBox(key: const Key('home-storage-bar'), color: storage.usedFraction > 0.9 ? c.warn : c.accent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
