import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/clock_alarm.dart';
import '../../state/clock_controller.dart';
import '../../theme.dart';
import '../../util/agenda.dart' show hourParts;
import '../../util/clock_format.dart';
import 'cyber_panel.dart';
import 'dot_matrix.dart';
import 'hack_text.dart';
import 'pixel_glyph.dart';
import 'section_motion.dart';

/// El componente del reloj en Inicio: **solo sale si hay algo que enseñar** — un cronómetro en marcha (o con tiempo contado) y/o una alarma
/// próxima — y desaparece si no. Si hay las dos cosas van lado a lado, cada una en su panel; si hay una, ocupa todo el ancho. Tocar un panel
/// lleva a la sección Reloj ([onOpen]).
class HomeClockPanel extends StatefulWidget {
  const HomeClockPanel({super.key, required this.alarms, required this.stopwatch, this.now, this.onOpen});

  final AlarmController alarms;
  final StopwatchController stopwatch;

  /// El reloj (en las pruebas, uno fijo).
  final DateTime Function()? now;

  /// Se toca un panel: abre la sección Reloj.
  final VoidCallback? onOpen;

  /// El alto del panel.
  static const height = 104.0;

  @override
  State<HomeClockPanel> createState() => _HomeClockPanelState();
}

class _HomeClockPanelState extends State<HomeClockPanel> {
  Timer? _timer;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    widget.stopwatch.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    widget.stopwatch.removeListener(_sync);
    _timer?.cancel();
    super.dispose();
  }

  /// Corre un reloj propio (que repinta) mientras el cronómetro cuenta, para ver las décimas; si no, uno lento para «en 20 min».
  void _sync() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.stopwatch.running ? const Duration(milliseconds: 100) : const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.alarms, widget.stopwatch]),
      builder: (context, _) {
        final sw = widget.stopwatch;
        final next = widget.alarms.next();
        final showSw = sw.running || sw.hasTime;
        if (!showSw && next == null) return const SizedBox.shrink();
        final tiles = [
          if (showSw) _StopwatchTile(controller: sw),
          if (next != null) _AlarmTile(alarm: next.$1, at: next.$2, now: _now),
        ];
        return Padding(
          key: const Key('home-clock'),
          padding: const EdgeInsets.only(top: 10),
          child: FlyIn(
            edge: MotionEdge.bottom,
            order: 4,
            child: SizedBox(
              height: HomeClockPanel.height,
              child: Row(
                children: [
                  for (var i = 0; i < tiles.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: 'Abrir el reloj',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.onOpen,
                          child: CyberPanel(active: i == 0 && showSw && sw.running ? 0.6 : 0, child: tiles[i]),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StopwatchTile extends StatelessWidget {
  const _StopwatchTile({required this.controller});

  final StopwatchController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (main, fraction) = stopwatchParts(controller.elapsed);
    return Padding(
      key: const Key('home-clock-stopwatch'),
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: HackText('SYS::STOPW', maxLines: 1, overflow: TextOverflow.clip, style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 1.2, color: c.accent))),
              Container(width: 9, height: 9, color: controller.running ? c.accent : c.dim),
            ],
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                DotMatrixText(main, key: const Key('home-clock-sw-main'), height: 32, color: controller.running ? c.accent : c.dim, glow: false, dimOff: false, square: true),
                const SizedBox(width: 6),
                DotMatrixText(fraction, height: 16, color: c.dim, glow: false, dimOff: false, square: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlarmTile extends StatelessWidget {
  const _AlarmTile({required this.alarm, required this.at, required this.now});

  final ClockAlarm alarm;
  final DateTime at;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (h, ampm) = hourParts(alarm.minutes);
    final label = alarm.label.isEmpty ? 'Alarma' : alarm.label;
    return Padding(
      key: const Key('home-clock-alarm'),
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: HackText('SYS::ALARM', maxLines: 1, overflow: TextOverflow.clip, style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 1.2, color: c.accent))),
              PixelIcon(PixelGlyphs.alarm, size: 18, color: c.accent),
            ],
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$h:${alarm.minute.toString().padLeft(2, '0')}', key: const Key('home-clock-alarm-time'), style: display(size: 30, color: c.ink, weight: FontWeight.w700)),
                const SizedBox(width: 6),
                Text(ampm, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim)),
              ],
            ),
          ),
          Text('$label · ${untilText(at.difference(now))}', key: const Key('home-clock-alarm-until'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim)),
        ],
      ),
    );
  }
}
