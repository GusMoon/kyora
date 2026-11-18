import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/clock_alarm.dart';
import '../state/clock_controller.dart';
import '../theme.dart';
import '../util/agenda.dart' show hourParts;
import '../util/clock_format.dart';
import '../util/format.dart' show weekdayLetters;
import 'widgets/cut_border.dart';
import 'widgets/cyber_panel.dart';
import 'widgets/dot_matrix.dart';
import 'widgets/focus_space.dart';
import 'widgets/section_motion.dart';

/// El reloj: **Alarmas** y **Cronómetro**. Todo vive solo en el teléfono.
///
/// - **Alarmas**: la hora de ahora en puntos, cuánto falta para la próxima alarma y la lista (cada una con su hora, nombre, días y un
///   interruptor). «+» crea una; tocar una la edita. Suenan con la app cerrada (notificación de alarma de Android).
/// - **Cronómetro**: el tiempo en puntos, **Iniciar / Pausar / Continuar**, **Vuelta** y **Reiniciar**, y la lista de vueltas con la más rápida y
///   la más lenta marcadas.
class ClockPage extends StatefulWidget {
  const ClockPage({super.key, required this.alarms, required this.stopwatch, this.now});

  final AlarmController alarms;
  final StopwatchController stopwatch;

  /// El reloj (en las pruebas, uno fijo).
  final DateTime Function()? now;

  @override
  State<ClockPage> createState() => _ClockPageState();
}

enum _Tab { alarms, stopwatch }

class _ClockPageState extends State<ClockPage> with SingleTickerProviderStateMixin {
  _Tab _tab = _Tab.alarms;
  late final Ticker _ticker = createTicker((_) {
    if (mounted) setState(() {});
  });
  Timer? _second;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    widget.stopwatch.addListener(_syncTicker);
    _syncTicker();
    // la hora de ahora y lo que falta para la próxima alarma se ponen al día cada segundo
    _second = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_ticker.isActive) setState(() {});
    });
  }

  @override
  void dispose() {
    widget.stopwatch.removeListener(_syncTicker);
    _second?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  /// El cronómetro dibuja a cada fotograma solo mientras corre.
  void _syncTicker() {
    if (widget.stopwatch.running && !_ticker.isActive) {
      _ticker.start();
    } else if (!widget.stopwatch.running && _ticker.isActive) {
      _ticker.stop();
    }
  }

  Future<void> _edit([ClockAlarm? alarm]) async {
    await showFocusPanel<void>(context, title: alarm == null ? 'Nueva alarma' : 'Editar alarma', builder: (_) => _AlarmEditor(controller: widget.alarms, alarm: alarm, now: _now));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FlyIn(
              edge: MotionEdge.top,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      Text('> ', style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.accent)),
                      Text('RELOJ', style: TextStyle(fontFamily: monoFont, fontSize: 15, fontWeight: FontWeight.w600, color: c.ink, letterSpacing: 1.2)),
                      const Spacer(),
                      if (_tab == _Tab.alarms)
                        Semantics(
                          button: true,
                          label: 'Nueva alarma',
                          child: GestureDetector(
                            key: const Key('clock-add'),
                            onTap: () => unawaited(_edit()),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: cutDecoration(color: c.accent, edge: c.ink.withValues(alpha: 0.6), width: 1.5),
                              child: Icon(Icons.add_rounded, color: c.onAccent, size: 26),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            FlyIn(edge: MotionEdge.top, order: 1, child: _tabs(context)),
            const SizedBox(height: 8),
            Expanded(
              child: FlyIn(
                edge: MotionEdge.bottom,
                order: 2,
                child: ListenableBuilder(
                  listenable: Listenable.merge([widget.alarms, widget.stopwatch]),
                  builder: (context, _) => switch (_tab) {
                    _Tab.alarms => _alarmsBody(context),
                    _Tab.stopwatch => _stopwatchBody(context),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabs(BuildContext context) {
    final c = context.colors;
    Widget tab(_Tab t, String label, String key) => Expanded(
          child: Semantics(
            button: true,
            selected: _tab == t,
            label: label,
            child: GestureDetector(
              key: Key(key),
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _tab = t),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 44,
                alignment: Alignment.center,
                color: _tab == t ? c.accent.withValues(alpha: 0.16) : Colors.transparent,
                child: Text(label.toUpperCase(), style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 1, fontWeight: _tab == t ? FontWeight.w700 : FontWeight.w400, color: _tab == t ? c.accent : c.dim)),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DecoratedBox(
        decoration: cutDecoration(color: c.field, edge: c.edge),
        child: Row(children: [tab(_Tab.alarms, 'Alarmas', 'clock-tab-alarms'), tab(_Tab.stopwatch, 'Cronómetro', 'clock-tab-stopwatch')]),
      ),
    );
  }

  // ---------- alarmas ----------

  Widget _alarmsBody(BuildContext context) {
    final c = context.colors;
    final now = _now;
    final next = widget.alarms.next();
    final (h, ampm) = hourParts(now.hour * 60 + now.minute);
    final alarms = widget.alarms.alarms;
    return ListView(
      key: const Key('clock-alarms'),
      padding: EdgeInsets.fromLTRB(16, 4, 16, 28 + MediaQuery.paddingOf(context).bottom),
      children: [
        CyberPanel(
          active: 0.3,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    DotMatrixText('$h:${now.minute.toString().padLeft(2, '0')}', key: const Key('clock-now'), height: 56, color: c.accent, glow: false, dimOff: false, square: true),
                    const SizedBox(width: 10),
                    Padding(padding: const EdgeInsets.only(bottom: 2), child: Text(ampm, style: display(size: 24, color: c.dim, weight: FontWeight.w500))),
                    const Spacer(),
                    Padding(padding: const EdgeInsets.only(bottom: 2), child: Text(now.second.toString().padLeft(2, '0'), key: const Key('clock-seconds'), style: TextStyle(fontFamily: monoFont, fontSize: 20, color: c.dim))),
                  ],
                ),
                const SizedBox(height: 14),
                Container(height: 1, color: c.edge),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(width: 9, height: 9, color: next == null ? c.dim : c.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        next == null ? 'SIN ALARMAS ACTIVAS' : 'PRÓXIMA ${untilText(next.$2.difference(now)).toUpperCase()}',
                        key: const Key('clock-next'),
                        style: hudLabel(color: next == null ? c.dim : c.ink),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (widget.alarms.permissionDenied)
          Container(
            key: const Key('clock-denied'),
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(14),
            decoration: cutDecoration(color: c.warn.withValues(alpha: 0.10), edge: c.warn.withValues(alpha: 0.5)),
            child: Text('Las notificaciones están desactivadas: las alarmas se guardan pero no sonarán. Actívalas para esta app en los ajustes del teléfono.', style: lcdStatus(color: c.warn)),
          ),
        if (alarms.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 28),
            child: Center(child: Text('Aún no hay alarmas.\nToca + para crear la primera.', key: const Key('clock-empty'), textAlign: TextAlign.center, style: TextStyle(fontFamily: monoFont, fontSize: 15, height: 1.4, color: c.dim))),
          ),
        for (final a in alarms) _AlarmTile(alarm: a, onTap: () => unawaited(_edit(a)), onToggle: (on) => unawaited(widget.alarms.setEnabled(a.id, on))),
      ],
    );
  }

  // ---------- cronómetro ----------

  Widget _stopwatchBody(BuildContext context) {
    final c = context.colors;
    final sw = widget.stopwatch;
    final (main, fraction) = stopwatchParts(sw.elapsed);
    final laps = sw.laps;
    final times = sw.lapTimes;
    Duration? best, worst;
    if (times.length >= 3) {
      best = times.reduce((a, b) => a < b ? a : b);
      worst = times.reduce((a, b) => a > b ? a : b);
    }
    final label = sw.running ? 'PAUSAR' : (sw.hasTime ? 'CONTINUAR' : 'INICIAR');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: CyberPanel(
            active: sw.running ? 0.8 : 0.2,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 26, 18, 26),
              child: Semantics(
                label: 'Cronómetro ${stopwatchText(sw.elapsed)}',
                child: ExcludeSemantics(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        DotMatrixText(main, key: const Key('sw-main'), height: 64, color: c.accent, glow: false, dimOff: false, square: true),
                        const SizedBox(width: 10),
                        DotMatrixText(fraction, key: const Key('sw-fraction'), height: 32, color: c.dim, glow: false, dimOff: false, square: true),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: sw.running || !sw.hasTime
                    ? _SwButton(key: const Key('sw-lap'), label: 'VUELTA', onTap: sw.running ? () => unawaited(sw.lap()) : null)
                    : _SwButton(key: const Key('sw-reset'), label: 'REINICIAR', onTap: () => unawaited(sw.reset())),
              ),
              const SizedBox(width: 12),
              Expanded(child: _SwButton(key: const Key('sw-toggle'), label: label, primary: true, onTap: () => unawaited(sw.toggle()))),
            ],
          ),
        ),
        if (laps.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(
              children: [
                Expanded(flex: 2, child: Text('VUELTA', style: hudLabel(color: c.dim))),
                Expanded(flex: 3, child: Text('TIEMPO', style: hudLabel(color: c.dim))),
                Expanded(flex: 3, child: Text('TOTAL', textAlign: TextAlign.end, style: hudLabel(color: c.dim))),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            key: const Key('sw-laps'),
            padding: EdgeInsets.fromLTRB(16, 0, 16, 28 + MediaQuery.paddingOf(context).bottom),
            children: [
              for (var i = laps.length - 1; i >= 0; i--)
                Container(
                  key: Key('sw-lap-${i + 1}'),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: c.edge))),
                  child: Row(
                    children: [
                      Expanded(flex: 2, child: Text('${i + 1}'.padLeft(2, '0'), style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim))),
                      Expanded(
                        flex: 3,
                        child: Text(
                          stopwatchText(times[i]),
                          style: TextStyle(fontFamily: monoFont, fontSize: 16, fontWeight: FontWeight.w600, color: times[i] == best ? c.habits : (times[i] == worst ? c.warn : c.ink)),
                        ),
                      ),
                      Expanded(flex: 3, child: Text(stopwatchText(laps[i]), textAlign: TextAlign.end, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim))),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Un botón grande del cronómetro: de esquinas cortadas; el principal, relleno con el acento.
class _SwButton extends StatelessWidget {
  const _SwButton({super.key, required this.label, required this.onTap, this.primary = false});

  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: primary
              ? cutDecoration(color: c.accent, edge: c.ink.withValues(alpha: 0.6), width: 1.5)
              : cutDecoration(color: c.field, edge: enabled ? c.accent.withValues(alpha: 0.6) : c.edge),
          child: Text(label, style: TextStyle(fontFamily: monoFont, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: primary ? c.onAccent : (enabled ? c.accent : c.dim.withValues(alpha: 0.6)))),
        ),
      ),
    );
  }
}

/// Una alarma de la lista: la hora grande (con AM/PM), su nombre y días, y un interruptor.
class _AlarmTile extends StatelessWidget {
  const _AlarmTile({required this.alarm, required this.onTap, required this.onToggle});

  final ClockAlarm alarm;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (h, ampm) = hourParts(alarm.minutes);
    final on = alarm.enabled;
    final ink = on ? c.ink : c.dim;
    final sub = [if (alarm.label.isNotEmpty) alarm.label, alarm.daysLabel].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
        button: true,
        label: 'Alarma $h:${alarm.minute.toString().padLeft(2, '0')} $ampm, ${on ? 'activa' : 'apagada'}',
        child: GestureDetector(
          key: Key('alarm-${alarm.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: CyberPanel(
            active: on ? 0.25 : 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text('$h:${alarm.minute.toString().padLeft(2, '0')}', key: Key('alarm-time-${alarm.id}'), style: display(size: 40, color: ink, weight: FontWeight.w700)),
                            const SizedBox(width: 8),
                            Text(ampm, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(sub, key: Key('alarm-sub-${alarm.id}'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: on ? c.dim : c.dim.withValues(alpha: 0.6))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _SquareSwitch(key: Key('alarm-switch-${alarm.id}'), on: on, onChanged: onToggle),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Un interruptor cuadrado: una caja con un bloque que se mueve de un lado a otro; encendido va en el acento.
class _SquareSwitch extends StatelessWidget {
  const _SquareSwitch({super.key, required this.on, required this.onChanged});

  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      toggled: on,
      label: 'Activar alarma',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!on),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 56,
            height: 30,
            padding: const EdgeInsets.all(3),
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(color: on ? c.accent.withValues(alpha: 0.18) : c.field, border: Border.all(color: on ? c.accent : c.edge, width: 1.5)),
            child: Container(width: 22, height: 22, color: on ? c.accent : c.dim),
          ),
        ),
      ),
    );
  }
}

/// El panel para crear o editar una alarma: la hora en dos ruedas (hora y minutos) y AM/PM, los días que se repite, un nombre y Guardar (o Eliminar).
class _AlarmEditor extends StatefulWidget {
  const _AlarmEditor({required this.controller, required this.alarm, required this.now});

  final AlarmController controller;
  final ClockAlarm? alarm;
  final DateTime now;

  @override
  State<_AlarmEditor> createState() => _AlarmEditorState();
}

class _AlarmEditorState extends State<_AlarmEditor> {
  late int _hour12; // 1–12
  late int _minute;
  late bool _pm;
  late int _days;
  late final TextEditingController _label;
  late final FixedExtentScrollController _hourWheel;
  late final FixedExtentScrollController _minuteWheel;

  @override
  void initState() {
    super.initState();
    final a = widget.alarm;
    final hour = a?.hour ?? widget.now.hour;
    _minute = a?.minute ?? widget.now.minute;
    _pm = hour >= 12;
    _hour12 = hour % 12 == 0 ? 12 : hour % 12;
    _days = a?.days ?? 0;
    _label = TextEditingController(text: a?.label ?? '');
    _hourWheel = FixedExtentScrollController(initialItem: _hour12 - 1);
    _minuteWheel = FixedExtentScrollController(initialItem: _minute);
  }

  @override
  void dispose() {
    _label.dispose();
    _hourWheel.dispose();
    _minuteWheel.dispose();
    super.dispose();
  }

  int get _hour24 => (_hour12 % 12) + (_pm ? 12 : 0);

  Future<void> _save() async {
    final a = widget.alarm;
    if (a == null) {
      await widget.controller.add(hour: _hour24, minute: _minute, label: _label.text, days: _days);
    } else {
      await widget.controller.update(a.id, hour: _hour24, minute: _minute, label: _label.text, days: _days);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final a = widget.alarm;
    if (a != null) await widget.controller.remove(a.id);
    if (mounted) Navigator.of(context).pop();
  }

  Widget _wheel({required Key key, required FixedExtentScrollController controller, required int count, required int selected, required String Function(int index) text, required ValueChanged<int> onChanged}) {
    final c = context.colors;
    return SizedBox(
      key: key,
      width: 84,
      height: 150,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: 50,
        diameterRatio: 1.7,
        perspective: 0.003,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: (i) => onChanged(i % count),
        childDelegate: ListWheelChildLoopingListDelegate(
          children: [
            for (var i = 0; i < count; i++)
              Center(child: Text(text(i), style: display(size: i == selected ? 38 : 28, color: i == selected ? c.accent : c.dim, weight: i == selected ? FontWeight.w700 : FontWeight.w400))),
          ],
        ),
      ),
    );
  }

  Widget _ampm(String label, bool pm) {
    final c = context.colors;
    final on = _pm == pm;
    return GestureDetector(
      key: Key(pm ? 'alarm-pm' : 'alarm-am'),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _pm = pm),
      child: Container(
        width: 56,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: on ? c.accent.withValues(alpha: 0.18) : null, border: Border.all(color: on ? c.accent : c.edge)),
        child: Text(label, style: TextStyle(fontFamily: monoFont, fontSize: 15, fontWeight: on ? FontWeight.w700 : FontWeight.w400, color: on ? c.accent : c.dim)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _wheel(key: const Key('alarm-hour'), controller: _hourWheel, count: 12, selected: _hour12 - 1, text: (i) => '${i + 1}', onChanged: (i) => setState(() => _hour12 = i + 1)),
                Text(':', style: display(size: 38, color: c.dim)),
                _wheel(key: const Key('alarm-minute'), controller: _minuteWheel, count: 60, selected: _minute, text: (i) => i.toString().padLeft(2, '0'), onChanged: (i) => setState(() => _minute = i)),
                const SizedBox(width: 12),
                Column(mainAxisSize: MainAxisSize.min, children: [_ampm('AM', false), const SizedBox(height: 8), _ampm('PM', true)]),
              ],
            ),
            const SizedBox(height: 14),
            Text('REPETIR', style: hudLabel(color: c.dim)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var d = 1; d <= 7; d++)
                  GestureDetector(
                    key: Key('alarm-day-$d'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _days ^= 1 << (d - 1)),
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: _days & (1 << (d - 1)) != 0 ? c.accent : c.field, border: Border.all(color: _days & (1 << (d - 1)) != 0 ? c.accent : c.edge)),
                      child: Text(weekdayLetters[d - 1], style: TextStyle(fontFamily: monoFont, fontSize: 15, fontWeight: FontWeight.w700, color: _days & (1 << (d - 1)) != 0 ? c.onAccent : c.dim)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(_days == 0 ? 'Suena una sola vez.' : ClockAlarm(id: 0, hour: 0, minute: 0, days: _days).daysLabel, key: const Key('alarm-days-label'), style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim)),
            const SizedBox(height: 12),
            TextField(key: const Key('alarm-label'), controller: _label, maxLength: 40, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'Nombre (opcional)', counterText: '')),
            const SizedBox(height: 12),
            Row(
              children: [
                if (widget.alarm != null) ...[
                  Expanded(child: _SwButton(key: const Key('alarm-delete'), label: 'ELIMINAR', onTap: () => unawaited(_delete()))),
                  const SizedBox(width: 12),
                ],
                Expanded(child: _SwButton(key: const Key('alarm-save'), label: 'GUARDAR', primary: true, onTap: () => unawaited(_save()))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
