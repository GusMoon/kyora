import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

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

/// El tablero de Inicio: una **cuadrícula de 2 × 2** paneles ciberpunk — la hora, el clima, el estado del sistema (batería, memoria y
/// almacenamiento) y los accesos rápidos (Wi-Fi y Bluetooth). Cada panel aparece en su turno.
///
/// Con [agenda], **tocar la hora la expande**: la tesela de la hora crece hasta ocupar el tablero —ahí vive la agenda: tareas, y deslizando,
/// hábitos y recordatorios, con el calendario— y las otras tres se reacomodan en una franja compacta debajo, con lo esencial de cada una.
class HomeGrid extends StatefulWidget {
  const HomeGrid({
    super.key,
    required this.now,
    this.weather,
    this.system,
    this.onNeedCity,
    this.agenda,
    this.expanded = false,
    this.onToggle,
    this.expandedHeight,
  });

  final DateTime now;

  /// El clima. Sin esto el panel dice que no hay.
  final WeatherController? weather;

  /// El estado del teléfono. Sin esto el panel del sistema y los accesos dicen que no hay.
  final SystemController? system;

  /// Se toca el clima cuando falta la ciudad (abre la configuración).
  final VoidCallback? onNeedCity;

  /// Lo que se ve dentro de la hora expandida (la agenda). Sin esto la hora no se puede expandir.
  final Widget? agenda;

  /// Si la hora está expandida.
  final bool expanded;

  /// Se toca la hora para expandirla (o el botón de contraerla).
  final VoidCallback? onToggle;

  /// El alto del tablero expandido (el de la pantalla visible). Nunca baja de [minExpandedHeight].
  final double? expandedHeight;

  /// El alto de cada fila y el hueco entre paneles.
  static const rowHeight = 176.0;
  static const gap = 10.0;

  /// El alto de la franja de las teselas pequeñas cuando la hora está expandida, y lo mínimo que mide el tablero entonces.
  static const stripHeight = 104.0;
  static const minExpandedHeight = 500.0;

  /// El tablero normal mide dos filas y el hueco.
  static const collapsedHeight = rowHeight * 2 + gap;

  @override
  State<HomeGrid> createState() => _HomeGridState();
}

class _HomeGridState extends State<HomeGrid> with SingleTickerProviderStateMixin {
  late final AnimationController _open = AnimationController(vsync: this, duration: const Duration(milliseconds: 420), value: widget.expanded ? 1 : 0);
  late final Animation<double> _t = CurvedAnimation(parent: _open, curve: Curves.easeInOutCubic);

  @override
  void didUpdateWidget(covariant HomeGrid old) {
    super.didUpdateWidget(old);
    if (widget.expanded != old.expanded) {
      if (widget.expanded) {
        unawaited(_open.forward());
      } else {
        unawaited(_open.reverse());
      }
    }
  }

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canExpand = widget.agenda != null;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final cw = (w - HomeGrid.gap) / 2; // ancho de una celda de la cuadrícula normal
        final sw = (w - HomeGrid.gap * 2) / 3; // ancho de una tesela de la franja
        final expandedH = math.max(widget.expandedHeight ?? HomeGrid.minExpandedHeight, HomeGrid.minExpandedHeight);
        final stripY = expandedH - HomeGrid.stripHeight;

        final cTime = Rect.fromLTWH(0, 0, cw, HomeGrid.rowHeight);
        final cWeather = Rect.fromLTWH(cw + HomeGrid.gap, 0, cw, HomeGrid.rowHeight);
        final cSystem = Rect.fromLTWH(0, HomeGrid.rowHeight + HomeGrid.gap, cw, HomeGrid.rowHeight);
        final cQuick = Rect.fromLTWH(cw + HomeGrid.gap, HomeGrid.rowHeight + HomeGrid.gap, cw, HomeGrid.rowHeight);

        final eTime = Rect.fromLTWH(0, 0, w, stripY - HomeGrid.gap);
        final eWeather = Rect.fromLTWH(0, stripY, sw, HomeGrid.stripHeight);
        final eSystem = Rect.fromLTWH(sw + HomeGrid.gap, stripY, sw, HomeGrid.stripHeight);
        final eQuick = Rect.fromLTWH((sw + HomeGrid.gap) * 2, stripY, sw, HomeGrid.stripHeight);

        return AnimatedBuilder(
          animation: _t,
          builder: (context, _) {
            final t = _t.value;
            Rect at(Rect a, Rect b) => Rect.lerp(a, b, t)!;

            /// Una tesela pequeña: a medio camino la tesela entera se encoge hasta caber; al final enseña su versión compacta.
            Widget small(Rect from, Widget full, Widget compact) {
              if (t == 0) return full;
              if (t >= 0.5) return ClipRect(child: compact);
              return ClipRect(
                child: FittedBox(
                  alignment: Alignment.topLeft,
                  child: SizedBox(width: from.width, height: from.height, child: full),
                ),
              );
            }

            Widget panel(Rect rect, int order, MotionEdge edge, Widget child, {double active = 0}) => Positioned.fromRect(
              rect: rect,
              child: FlyIn(edge: edge, order: order, child: CyberPanel(active: active, child: child)),
            );

            final time = t < 0.5
                ? _TimeTile(now: widget.now, onTap: canExpand ? widget.onToggle : null, fade: 1 - t * 2)
                : const SizedBox.shrink();
            final agendaShown = canExpand && t > 0.15;
            return SizedBox(
              key: const Key('home-grid'),
              height: lerpDouble(HomeGrid.collapsedHeight, expandedH, t),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  panel(
                    at(cTime, eTime),
                    0,
                    MotionEdge.left,
                    Stack(
                      fit: StackFit.expand,
                      children: [
                        time,
                        if (agendaShown)
                          // la agenda se maqueta ya con su tamaño final y la tesela solo la va descubriendo (así no se desborda ni se recoloca a mitad)
                          Opacity(
                            opacity: ((t - 0.15) * 1.8).clamp(0.0, 1.0),
                            child: ClipRect(
                              child: OverflowBox(
                                alignment: Alignment.topLeft,
                                minWidth: eTime.width,
                                maxWidth: eTime.width,
                                minHeight: eTime.height,
                                maxHeight: eTime.height,
                                child: _AgendaTile(now: widget.now, onClose: widget.onToggle, child: widget.agenda!),
                              ),
                            ),
                          ),
                      ],
                    ),
                    active: t,
                  ),
                  panel(at(cWeather, eWeather), 1, MotionEdge.right, small(cWeather, _WeatherTile(controller: widget.weather, onNeedCity: widget.onNeedCity), _WeatherCompact(controller: widget.weather, onNeedCity: widget.onNeedCity))),
                  panel(at(cSystem, eSystem), 2, MotionEdge.left, small(cSystem, _SystemTile(controller: widget.system), _SystemCompact(controller: widget.system))),
                  panel(at(cQuick, eQuick), 3, MotionEdge.right, small(cQuick, _QuickTile(controller: widget.system), _QuickCompact(controller: widget.system))),
                ],
              ),
            );
          },
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

/// La hora (con su fecha). Con [onTap] se puede tocar para expandirla: ahí se abre la agenda.
class _TimeTile extends StatelessWidget {
  const _TimeTile({required this.now, this.onTap, this.fade = 1});

  final DateTime now;
  final VoidCallback? onTap;

  /// De 1 (visible) a 0 (invisible), mientras la tesela se expande.
  final double fade;

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
    final shown = fade >= 1 ? body : Opacity(opacity: fade.clamp(0.0, 1.0), child: body);
    if (onTap == null) return shown;
    return Semantics(
      button: true,
      label: 'Abrir la agenda: tareas, hábitos y recordatorios',
      child: GestureDetector(key: const Key('home-time-tile'), behavior: HitTestBehavior.opaque, onTap: onTap, child: shown),
    );
  }
}

/// La hora expandida: arriba una cabecera con la hora pequeña y el botón de contraer; debajo, la agenda.
class _AgendaTile extends StatelessWidget {
  const _AgendaTile({required this.now, required this.onClose, required this.child});

  final DateTime now;
  final VoidCallback? onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 40,
            child: Row(
              children: [
                const SizedBox(width: 4),
                Expanded(child: Text('SYS::TIME', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 1.2, color: c.accent))),
                const SizedBox(width: 8),
                Text(clockText(now), key: const Key('home-time-small'), style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.ink)),
                IconButton(
                  key: const Key('home-time-close'),
                  tooltip: 'Contraer',
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                  icon: Icon(Icons.expand_less_rounded, color: c.ink),
                ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _WeatherTile extends StatelessWidget {
  const _WeatherTile({required this.controller, this.onNeedCity});

  final WeatherController? controller;
  final VoidCallback? onNeedCity;

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
          onTap: needsCity ? onNeedCity : null,
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
          ),
          const SizedBox(height: 8),
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

/// Un acceso rápido: el icono, el nombre y si está encendido; tocarlo abre su panel del sistema.
class _QuickButton extends StatelessWidget {
  const _QuickButton({super.key, required this.icon, required this.label, required this.on, required this.onTap});

  final IconData icon;
  final String label;
  final bool? on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lit = on == true;
    return Semantics(
      button: true,
      label: '$label ${lit ? 'encendido' : 'apagado'}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 40,
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

// ---- las versiones compactas de las teselas pequeñas: lo esencial, para la franja de abajo con la hora expandida ----

class _WeatherCompact extends StatelessWidget {
  const _WeatherCompact({required this.controller, this.onNeedCity});

  final WeatherController? controller;
  final VoidCallback? onNeedCity;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final controller = this.controller;
    Widget body(String big, String small, PixelGlyph glyph, {VoidCallback? onTap}) => GestureDetector(
      key: const Key('home-weather-compact'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PixelIcon(glyph, size: 20, color: c.accent),
            const SizedBox(height: 4),
            Text(big, maxLines: 1, overflow: TextOverflow.clip, style: display(size: 26, color: c.ink, weight: FontWeight.w500).copyWith(height: 1)),
            Text(small, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: monoFont, fontSize: 15, height: 1.2, color: c.dim)),
          ],
        ),
      ),
    );
    if (controller == null) return body('--', 'CLIMA', PixelGlyphs.cloud);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final weather = controller.weather;
        final status = controller.status;
        final needsCity = status == WeatherStatus.noCity || status == WeatherStatus.unknownCity;
        if (weather == null) return body('--', needsCity ? 'CIUDAD' : 'CLIMA', PixelGlyphs.cloud, onTap: needsCity ? onNeedCity : null);
        return body('${weather.temperature.round()}°', weather.city, pixelWeatherGlyph(weather.code));
      },
    );
  }
}

class _SystemCompact extends StatelessWidget {
  const _SystemCompact({required this.controller});

  final SystemController? controller;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final controller = this.controller;
    Widget body(SystemStats? s) {
      final mono = TextStyle(fontFamily: monoFont, fontSize: 15, height: 1.3, color: c.dim);
      Widget line(String label, String value) => Row(
        children: [
          Text(label, style: mono),
          const SizedBox(width: 6),
          Expanded(child: Text(value, maxLines: 1, overflow: TextOverflow.clip, textAlign: TextAlign.right, style: mono.copyWith(color: c.ink))),
        ],
      );
      return Padding(
        key: const Key('home-system-compact'),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            line('BAT', s?.battery == null ? '--' : '${s!.battery}%${s.charging ? '+' : ''}'),
            line('RAM', s?.ramUsed == null ? '--' : '${(s!.ramUsed! * 100).round()}%'),
            line('ALM', s?.storageFree == null ? '--' : humanSize(s!.storageFree!)),
          ],
        ),
      );
    }

    if (controller == null) return body(null);
    return _Watching(controller: controller, builder: (context, s) => body(s));
  }
}

class _QuickCompact extends StatelessWidget {
  const _QuickCompact({required this.controller});

  final SystemController? controller;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    Widget body(SystemStats? s) => Padding(
      key: const Key('home-quick-compact'),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _QuickChip(icon: Icons.wifi_rounded, label: 'WI-FI', on: s?.wifi, onTap: controller == null ? null : () => unawaited(controller.openWifi()))),
          const SizedBox(height: 6),
          Expanded(child: _QuickChip(icon: Icons.bluetooth_rounded, label: 'BT', on: s?.bluetooth, onTap: controller == null ? null : () => unawaited(controller.openBluetooth()))),
        ],
      ),
    );
    if (controller == null) return body(null);
    return _Watching(controller: controller, builder: (context, s) => body(s));
  }
}

/// Un acceso rápido pequeño (para la franja): el icono y si está encendido; tocarlo abre su panel del sistema.
class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.icon, required this.label, required this.on, required this.onTap});

  final IconData icon;
  final String label;
  final bool? on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lit = on == true;
    return Semantics(
      button: true,
      label: '$label ${lit ? 'encendido' : 'apagado'}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: cutDecoration(color: lit ? c.accent.withValues(alpha: 0.22) : Colors.black.withValues(alpha: 0.3), edge: lit ? c.accent : c.edge, cut: 6),
          child: Row(
            children: [
              LcdIcon(icon, size: 18, color: lit ? c.accent : c.dim),
              const SizedBox(width: 6),
              Expanded(child: Text(on == null ? '--' : (lit ? 'ON' : 'OFF'), maxLines: 1, style: TextStyle(fontFamily: monoFont, fontSize: 15, fontWeight: FontWeight.w700, color: lit ? c.accent : c.dim))),
            ],
          ),
        ),
      ),
    );
  }
}
