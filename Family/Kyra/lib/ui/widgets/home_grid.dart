import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/system_info.dart';
import '../../state/system_controller.dart';
import '../../state/weather_controller.dart';
import '../../theme.dart';
import '../../util/format.dart';
import 'cyber_panel.dart';
import 'cut_border.dart';
import 'hack_text.dart';
import 'pixel_glyph.dart';
import 'section_motion.dart';
import 'weather_detail.dart';

/// El tablero de Inicio: una **cuadrícula de 2 × 2** paneles ciberpunk — la hora, el clima, el estado del sistema (batería, memoria y
/// almacenamiento) y los accesos rápidos (Wi-Fi y Bluetooth). Cada panel aparece en su turno.
///
/// **Tocar la hora** ([onOpenTime]) o **el clima** ([onOpenWeather]) no agranda la tesela: la pantalla de Inicio (`HomePage`) disuelve el
/// tablero y enseña esa información a pantalla completa, sin marco, directamente sobre el fondo.
class HomeGrid extends StatelessWidget {
  const HomeGrid({super.key, required this.now, this.weather, this.system, this.onNeedCity, this.onOpenTime, this.onOpenWeather});

  final DateTime now;

  /// El clima. Sin esto el panel dice que no hay.
  final WeatherController? weather;

  /// El estado del teléfono. Sin esto el panel del sistema y los accesos dicen que no hay.
  final SystemController? system;

  /// Se toca el clima cuando falta la ciudad (abre la configuración).
  final VoidCallback? onNeedCity;

  /// Se toca la hora: abre la agenda a pantalla completa. Sin esto la hora no se toca.
  final VoidCallback? onOpenTime;

  /// Se toca el clima ya cargado: abre el detalle a pantalla completa. Sin esto se abre el detalle en un panel flotante.
  final VoidCallback? onOpenWeather;

  /// El alto de cada fila y el hueco entre paneles.
  static const rowHeight = 176.0;
  static const gap = 10.0;

  /// El tablero mide dos filas y el hueco.
  static const collapsedHeight = rowHeight * 2 + gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final cw = (box.maxWidth - gap) / 2; // ancho de una celda de la cuadrícula
        Widget panel(Rect rect, int order, MotionEdge edge, Widget child) => Positioned.fromRect(
          rect: rect,
          child: FlyIn(edge: edge, order: order, child: CyberPanel(child: child)),
        );

        return SizedBox(
          key: const Key('home-grid'),
          height: collapsedHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              panel(Rect.fromLTWH(0, 0, cw, rowHeight), 0, MotionEdge.left, _TimeTile(now: now, onTap: onOpenTime)),
              panel(Rect.fromLTWH(cw + gap, 0, cw, rowHeight), 1, MotionEdge.right, _WeatherTile(controller: weather, onNeedCity: onNeedCity, onOpen: onOpenWeather)),
              panel(Rect.fromLTWH(0, rowHeight + gap, cw, rowHeight), 2, MotionEdge.left, _SystemTile(controller: system)),
              panel(Rect.fromLTWH(cw + gap, rowHeight + gap, cw, rowHeight), 3, MotionEdge.right, _QuickTile(controller: system)),
            ],
          ),
        );
      },
    );
  }
}

/// La cabecera técnica de un panel: un código corto en mono y el icono.
class _TileHeader extends StatelessWidget {
  const _TileHeader(this.code, {this.glyph});

  final String code;
  final PixelGlyph? glyph;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(child: HackText(code, maxLines: 1, overflow: TextOverflow.clip, style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 1.2, color: c.accent))),
        if (glyph != null) PixelIcon(glyph!, size: 20, color: c.accent),
      ],
    );
  }
}

/// La hora (con su fecha). Con [onTap] se puede tocar: abre la agenda a pantalla completa.
class _TimeTile extends StatelessWidget {
  const _TimeTile({required this.now, this.onTap});

  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TileHeader('SYS::TIME', glyph: onTap == null ? null : PixelGlyphs.calendar),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(clockText(now), key: const Key('home-time'), style: display(size: 46, color: c.ink, weight: FontWeight.w500).copyWith(height: 1)),
          ),
          const SizedBox(height: 6),
          HackText(longDate(now), textKey: const Key('home-date'), order: 1, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim)),
        ],
      ),
    );
    if (onTap == null) return body;
    return Semantics(
      button: true,
      label: 'Abrir la agenda: tareas, hábitos y recordatorios',
      child: GestureDetector(key: const Key('home-time-tile'), behavior: HitTestBehavior.opaque, onTap: onTap, child: body),
    );
  }
}

class _WeatherTile extends StatelessWidget {
  const _WeatherTile({required this.controller, this.onNeedCity, this.onOpen});

  final WeatherController? controller;
  final VoidCallback? onNeedCity;

  /// Abre el detalle a pantalla completa; sin esto, en un panel flotante.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final controller = this.controller;
    if (controller == null) return const Padding(padding: EdgeInsets.all(14), child: _TileHeader('ENV::WEATHER'));
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final weather = controller.weather;
        final status = controller.status;
        final needsCity = status == WeatherStatus.noCity || status == WeatherStatus.unknownCity;
        final String line;
        if (status == WeatherStatus.noCity) {
          line = 'Elige tu ciudad';
        } else if (status == WeatherStatus.unknownCity) {
          line = 'No encontré «${controller.city}»';
        } else if (weather == null) {
          line = status == WeatherStatus.offline ? 'Sin conexión' : 'Cargando…';
        } else {
          line = '${weather.label}${controller.stale ? ' · sin conexión' : ''}';
        }
        return GestureDetector(
          key: const Key('home-weather'),
          behavior: HitTestBehavior.opaque,
          onTap: needsCity ? onNeedCity : (weather == null ? null : (onOpen ?? () => unawaited(showWeatherDetail(context, controller)))),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TileHeader('ENV::WEATHER', glyph: weather == null ? PixelGlyphs.cloud : pixelWeatherGlyph(weather.code)),
                const Spacer(),
                if (weather != null)
                  Text('${weather.temperature.round()}°', key: const Key('home-weather-temp'), style: display(size: 40, color: c.ink, weight: FontWeight.w500).copyWith(height: 1)),
                const SizedBox(height: 4),
                HackText(line, textKey: const Key('home-weather-text'), order: 2, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: needsCity ? c.accent : c.dim)),
                if (weather != null)
                  Text(weather.city, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim.withValues(alpha: 0.7))),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Mientras se ve, lee el estado del teléfono cada poco (y deja de hacerlo al irse).
class _Watching extends StatefulWidget {
  const _Watching({required this.controller, required this.builder});

  final SystemController controller;
  final Widget Function(BuildContext context, SystemStats? stats) builder;

  @override
  State<_Watching> createState() => _WatchingState();
}

class _WatchingState extends State<_Watching> {
  @override
  void initState() {
    super.initState();
    widget.controller.watch();
  }

  @override
  void dispose() {
    widget.controller.unwatch();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: widget.controller, builder: (context, _) => widget.builder(context, widget.controller.stats));
}

class _SystemTile extends StatelessWidget {
  const _SystemTile({required this.controller});

  final SystemController? controller;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    Widget body(SystemStats? s) => Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TileHeader('SYS::STATUS'),
          const Spacer(),
          _Meter(key: const Key('home-battery'), label: 'BAT', value: s?.battery == null ? null : s!.battery! / 100, text: s?.battery == null ? '--' : '${s!.battery}%${s.charging ? '+' : ''}'),
          const SizedBox(height: 5),
          _Meter(key: const Key('home-ram'), label: 'RAM', value: s?.ramUsed, text: s?.ramUsed == null ? '--' : '${(s!.ramUsed! * 100).round()}%'),
          const SizedBox(height: 5),
          _Meter(key: const Key('home-storage'), label: 'ALM', value: s?.storageUsed, text: s?.storageFree == null ? '--' : humanSize(s!.storageFree!)),
        ],
      ),
    );
    if (controller == null) return KeyedSubtree(key: const Key('home-system'), child: body(null));
    return KeyedSubtree(key: const Key('home-system'), child: _Watching(controller: controller, builder: (context, s) => body(s)));
  }
}

/// Una métrica: la etiqueta y el valor y, debajo, una barra de segmentos.
class _Meter extends StatelessWidget {
  const _Meter({super.key, required this.label, required this.value, required this.text});

  final String label;
  final double? value;
  final String text;

  static const segments = 10;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lit = value == null ? 0 : (value! * segments).round().clamp(0, segments);
    final mono = TextStyle(fontFamily: monoFont, fontSize: 15, height: 1.2, color: c.dim);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(label, style: mono),
            const SizedBox(width: 6),
            Expanded(child: Text(text, key: Key('$label-value'), textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.clip, style: mono.copyWith(color: c.ink))),
          ],
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            for (var i = 0; i < segments; i++)
              Expanded(child: Container(height: 6, margin: const EdgeInsets.only(right: 2), color: i < lit ? c.accent : c.accent.withValues(alpha: 0.16))),
          ],
        ),
      ],
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.controller});

  final SystemController? controller;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    Widget body(SystemStats? s) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _TileHeader('NET::LINK'),
          const Spacer(),
          _QuickButton(
            key: const Key('quick-wifi'),
            icon: Icons.wifi_rounded,
            label: 'WI-FI',
            on: s?.wifi,
            onTap: controller == null ? null : () => unawaited(controller.openWifi()),
            onLongPress: controller == null ? null : () => unawaited(controller.openNetworkSettings()),
          ),
          const SizedBox(height: 6),
          _QuickButton(
            key: const Key('quick-data'),
            icon: Icons.signal_cellular_alt_rounded,
            label: 'DATOS',
            on: s?.mobileData,
            inUse: true,
            onTap: controller == null ? null : () => unawaited(controller.openInternetPanel()),
            onLongPress: controller == null ? null : () => unawaited(controller.openMobileData()),
          ),
          const SizedBox(height: 6),
          _QuickButton(
            key: const Key('quick-bluetooth'),
            icon: Icons.bluetooth_rounded,
            label: 'BT',
            on: s?.bluetooth,
            onTap: controller == null ? null : () => unawaited(controller.openBluetooth()),
          ),
        ],
      ),
    );
    if (controller == null) return KeyedSubtree(key: const Key('home-quick'), child: body(null));
    return KeyedSubtree(key: const Key('home-quick'), child: _Watching(controller: controller, builder: (context, s) => body(s)));
  }
}

/// Un acceso rápido: el icono, el nombre y si está encendido. Tocarlo abre el panel del sistema; mantenerlo, sus ajustes. Con [inUse] el
/// estado es «en uso» (no se puede leer el interruptor).
class _QuickButton extends StatelessWidget {
  const _QuickButton({super.key, required this.icon, required this.label, required this.on, required this.onTap, this.onLongPress, this.inUse = false});

  final IconData icon;
  final String label;
  final bool? on;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool inUse;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lit = on == true;
    return Semantics(
      button: true,
      label: '$label ${inUse ? (lit ? 'en uso' : 'sin uso') : (lit ? 'encendido' : 'apagado')}',
      onLongPress: onLongPress,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: cutDecoration(color: lit ? c.accent.withValues(alpha: 0.22) : Colors.black.withValues(alpha: 0.3), edge: lit ? c.accent : c.edge, cut: 8),
          child: Row(
            children: [
              LcdIcon(icon, size: 20, color: lit ? c.accent : c.dim),
              const SizedBox(width: 8),
              Expanded(child: Text(label, maxLines: 1, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.ink))),
              Text(on == null ? '--' : (lit ? 'ON' : 'OFF'), key: Key('$label-state'), style: TextStyle(fontFamily: monoFont, fontSize: 15, fontWeight: FontWeight.w700, color: lit ? c.accent : c.dim)),
            ],
          ),
        ),
      ),
    );
  }
}
