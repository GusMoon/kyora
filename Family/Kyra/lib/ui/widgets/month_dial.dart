import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import '../../util/calendar_marks.dart';
import 'cyber_core.dart';
import 'dot_matrix.dart';

/// Los meses en tres letras, para el anillo de los meses.
const dialMonths = ['ENE', 'FEB', 'MAR', 'ABR', 'MAY', 'JUN', 'JUL', 'AGO', 'SEP', 'OCT', 'NOV', 'DIC'];

/// La clave de un día: `yyyy-MM-dd`.
String dialDayKey(DateTime day) => '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

/// El **mini calendario sci-fi**: un dial anclado al borde izquierdo, a media altura (como el de la referencia: un temporizador de anillos).
/// En el centro, el núcleo ciberpunk con la fecha en **matriz de puntos**; alrededor, un anillo con los meses y, más afuera, un anillo con los
/// días del mes. Arrastrar en vertical gira el anillo que se toca (el de los meses, cerca del núcleo; el de los días, más afuera), con inercia
/// y ajuste; el día del centro se ilumina. Junto a cada día, **marcadores** de colores: tareas, recordatorios y hábitos.
///
/// Tocar un día lo elige; tocar el núcleo elige el día del centro. Tocar fuera cierra sin elegir.
class MonthDial extends StatefulWidget {
  const MonthDial({super.key, required this.selected, required this.today, required this.marksOf, required this.onPick, required this.onClose});

  final DateTime selected;
  final DateTime today;

  /// Lo que hay cada día (para los marcadores).
  final DayMarks Function(DateTime day) marksOf;

  final ValueChanged<DateTime> onPick;
  final VoidCallback onClose;

  /// El ángulo entre dos días seguidos y entre dos meses seguidos (rad).
  static const dayStep = 0.19;
  static const monthStep = 0.42;

  /// Lo que dura la entrada del dial.
  static const enter = Duration(milliseconds: 320);

  /// El radio del núcleo, del anillo de los meses y del de los días, del ancho.
  static double hubRadius(double width) => width * 0.27;
  static double monthRadius(double width) => width * 0.40;
  static double dayRadius(double width) => width * 0.66;

  @override
  State<MonthDial> createState() => _MonthDialState();
}

class _MonthDialState extends State<MonthDial> with TickerProviderStateMixin {
  late final AnimationController _in = AnimationController(vsync: this, duration: MonthDial.enter)..forward();

  /// El mes que se ve (como número absoluto: año·12 + mes-1) y el día del centro (0 = el día 1).
  late final AnimationController _month = AnimationController.unbounded(vsync: this, value: (widget.selected.year * 12 + widget.selected.month - 1).toDouble());
  late final AnimationController _day = AnimationController.unbounded(vsync: this, value: (widget.selected.day - 1).toDouble());

  /// Qué anillo se está girando.
  bool _draggingMonth = false;
  int _lastDay = -1;

  @override
  void initState() {
    super.initState();
    _day.addListener(_onDay);
    _month.addListener(_clampDay);
  }

  @override
  void dispose() {
    _in.dispose();
    _month.dispose();
    _day.dispose();
    super.dispose();
  }

  int get _monthIndex => _month.value.round();
  DateTime get _monthDate => DateTime(_monthIndex ~/ 12, _monthIndex % 12 + 1);
  int get _daysInMonth => DateTime(_monthDate.year, _monthDate.month + 1, 0).day;
  int get _focusDay => _day.value.round().clamp(0, _daysInMonth - 1) + 1;
  DateTime get _focus => DateTime(_monthDate.year, _monthDate.month, _focusDay);

  void _onDay() {
    final d = _focusDay;
    if (_lastDay != -1 && d != _lastDay) unawaited(HapticFeedback.selectionClick().catchError((Object _) {}));
    _lastDay = d;
  }

  /// Un mes más corto no deja el día del centro fuera.
  void _clampDay() {
    final last = (_daysInMonth - 1).toDouble();
    if (_day.value > last && !_day.isAnimating) _day.value = last;
  }

  void _dragStart(DragStartDetails d, Offset hub, double width) {
    final distance = (d.localPosition - hub).distance;
    _draggingMonth = distance < (MonthDial.monthRadius(width) + MonthDial.dayRadius(width)) / 2;
    _month.stop();
    _day.stop();
  }

  void _dragUpdate(DragUpdateDetails d, double width) {
    if (_draggingMonth) {
      _month.value -= d.delta.dy / (MonthDial.monthRadius(width) * MonthDial.monthStep);
    } else {
      _day.value = (_day.value - d.delta.dy / (MonthDial.dayRadius(width) * MonthDial.dayStep)).clamp(-0.5, _daysInMonth - 0.5);
    }
  }

  void _dragEnd(DragEndDetails d, double width) {
    final v = -(d.primaryVelocity ?? 0);
    final spring = SpringDescription.withDampingRatio(mass: 1, stiffness: 150, ratio: 1);
    if (_draggingMonth) {
      final perItem = MonthDial.monthRadius(width) * MonthDial.monthStep;
      final target = (_month.value + v / perItem * 0.25).roundToDouble();
      unawaited(_month.animateWith(SpringSimulation(spring, _month.value, target, v / perItem)));
    } else {
      final perItem = MonthDial.dayRadius(width) * MonthDial.dayStep;
      final target = (_day.value + v / perItem * 0.3).round().clamp(0, _daysInMonth - 1).toDouble();
      unawaited(_day.animateWith(SpringSimulation(spring, _day.value, target, v / perItem)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedBuilder(
      animation: Listenable.merge([_in, _month, _day]),
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          final size = box.biggest;
          final t = Curves.easeOutCubic.transform(_in.value);
          final width = size.width;
          final hub = Offset(lerpDouble(-MonthDial.hubRadius(width), 0, t)!, size.height / 2);
          final hubR = MonthDial.hubRadius(width);
          final monthR = MonthDial.monthRadius(width);
          final dayR = MonthDial.dayRadius(width);
          final month = _monthDate;
          final days = _daysInMonth;
          final dayPos = _day.value;
          final focus = _focus;
          return GestureDetector(
            key: const Key('month-dial'),
            behavior: HitTestBehavior.opaque,
            onTap: widget.onClose,
            onVerticalDragStart: (d) => _dragStart(d, hub, width),
            onVerticalDragUpdate: (d) => _dragUpdate(d, width),
            onVerticalDragEnd: (d) => _dragEnd(d, width),
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                IgnorePointer(child: ColoredBox(color: Colors.black.withValues(alpha: 0.72 * t))),
                IgnorePointer(
                  child: CustomPaint(
                    painter: _DialPainter(t: t, hub: hub, hubR: hubR, monthR: monthR, dayR: dayR, accent: c.accent, dayPos: dayPos, monthPos: _month.value),
                  ),
                ),
                // el anillo de los meses
                for (var m = _monthIndex - 3; m <= _monthIndex + 3; m++) _monthLabel(m, hub, monthR, t, c),
                // el anillo de los días, con sus marcadores
                for (var d = math.max(0, dayPos.floor() - 8); d < math.min(days, dayPos.ceil() + 9); d++) _dayLabel(DateTime(month.year, month.month, d + 1), d - dayPos, hub, dayR, t, c),
                // el núcleo: la fecha del centro en matriz de puntos; tocarlo elige ese día
                Positioned(
                  left: 0,
                  top: hub.dy - hubR,
                  width: hubR,
                  height: hubR * 2,
                  child: Opacity(
                    opacity: t,
                    child: GestureDetector(
                      key: const Key('dial-hub'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.onPick(focus),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          DotMatrixText(focus.day.toString().padLeft(2, '0'), key: const Key('dial-focus-day'), height: hubR * 0.34, color: Colors.white),
                          SizedBox(height: hubR * 0.08),
                          DotMatrixText(dialMonths[focus.month - 1], key: const Key('dial-focus-month'), height: hubR * 0.16, color: c.accent),
                          SizedBox(height: hubR * 0.05),
                          DotMatrixText('${focus.year}', height: hubR * 0.12, color: Colors.white.withValues(alpha: 0.6), glow: false),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _monthLabel(int m, Offset hub, double radius, double t, KyoraColors c) {
    final angle = (m - _month.value) * MonthDial.monthStep;
    if (angle.abs() > 1.3) return const SizedBox.shrink();
    final focus = (m - _month.value).abs() < 0.5;
    final at = hub + Offset(math.cos(angle), math.sin(angle)) * radius;
    final label = dialMonths[m % 12];
    return Positioned(
      left: at.dx - 24,
      top: at.dy - 12,
      width: 48,
      height: 24,
      child: IgnorePointer(
        child: Opacity(
          opacity: t * (1 - (angle.abs() / 1.3)).clamp(0.25, 1.0),
          child: Center(
            child: Transform.rotate(
              angle: angle,
              child: Text(
                label,
                key: focus ? const Key('dial-month') : null,
                style: TextStyle(fontFamily: monoFont, fontSize: 15, fontWeight: focus ? FontWeight.w700 : FontWeight.w400, color: focus ? c.accent : c.dim, letterSpacing: 1),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dayLabel(DateTime day, double away, Offset hub, double radius, double t, KyoraColors c) {
    final angle = away * MonthDial.dayStep;
    if (angle.abs() > 1.45) return const SizedBox.shrink();
    final focus = away.abs() < 0.5;
    final today = dialDayKey(day) == dialDayKey(widget.today);
    final at = hub + Offset(math.cos(angle), math.sin(angle)) * radius + Offset((1 - t) * 120, 0);
    final marks = widget.marksOf(day);
    final size = focus ? 30.0 : 18.0;
    final fade = t * (1 - ((angle.abs() - 0.9) / 0.55).clamp(0.0, 0.85));
    return Positioned(
      left: at.dx - 22,
      top: at.dy - 22,
      width: 96,
      height: 44,
      child: Opacity(
        opacity: fade,
        child: GestureDetector(
          key: Key('dial-day-${dialDayKey(day)}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onPick(day),
          child: Transform.rotate(
            angle: angle,
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Center(
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        fontFamily: monoFont,
                        fontSize: size,
                        fontWeight: focus ? FontWeight.w700 : FontWeight.w500,
                        color: focus ? Colors.white : (today ? c.accent : c.dim),
                        shadows: focus ? [Shadow(color: c.accent, blurRadius: 14)] : null,
                      ),
                    ),
                  ),
                ),
                // los marcadores: tareas, recordatorios y hábitos
                if (marks.tasks > 0) _mark('tasks', day, c.tasks),
                if (marks.reminders > 0) _mark('reminders', day, c.reminders),
                if (marks.habits > 0) _mark('habits', day, c.habits),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _mark(String kind, DateTime day, Color color) => Container(
    key: Key('dial-mark-$kind-${dialDayKey(day)}'),
    width: 7,
    height: 7,
    margin: const EdgeInsets.only(right: 4),
    color: color,
  );
}

/// El dibujo del dial: el núcleo, el anillo de los meses, el de los días con sus marcas y la línea que señala el día del centro.
class _DialPainter extends CustomPainter {
  _DialPainter({required this.t, required this.hub, required this.hubR, required this.monthR, required this.dayR, required this.accent, required this.dayPos, required this.monthPos});

  final double t;
  final Offset hub;
  final double hubR;
  final double monthR;
  final double dayR;
  final Color accent;
  final double dayPos;
  final double monthPos;

  @override
  void paint(Canvas canvas, Size size) {
    paintCyberCore(canvas, hub, hubR, accent: accent, angle: dayPos * 0.4, menu: true);
    if (t == 0) return;
    final faint = Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = Colors.white.withValues(alpha: 0.18 * t);
    final band = Paint()..style = PaintingStyle.stroke..strokeWidth = monthR * 0.22..color = Colors.white.withValues(alpha: 0.05 * t);
    // el anillo de los meses: una banda tenue con sus filos
    canvas.drawArc(Rect.fromCircle(center: hub, radius: monthR), -1.5, 3.0, false, band);
    canvas.drawArc(Rect.fromCircle(center: hub, radius: monthR * 0.88), -1.5, 3.0, false, faint);
    canvas.drawArc(Rect.fromCircle(center: hub, radius: monthR * 1.12), -1.5, 3.0, false, faint);
    // el anillo de los días: una banda, sus marcas (que corren al girar) y los tramos del acento
    final dayBand = Paint()..style = PaintingStyle.stroke..strokeWidth = 46..color = Colors.white.withValues(alpha: 0.05 * t);
    canvas.drawArc(Rect.fromCircle(center: hub, radius: dayR + 22), -1.45, 2.9, false, dayBand);
    canvas.drawArc(Rect.fromCircle(center: hub, radius: dayR - 4), -1.45, 2.9, false, faint);
    final tick = Paint()..strokeWidth = 1..color = Colors.white.withValues(alpha: 0.35 * t);
    final offset = (dayPos * MonthDial.dayStep) % (MonthDial.dayStep / 2);
    for (var a = -1.4 - offset; a <= 1.4; a += MonthDial.dayStep / 2) {
      if (a < -1.4) continue;
      canvas.drawLine(hub + Offset(math.cos(a), math.sin(a)) * (dayR - 12), hub + Offset(math.cos(a), math.sin(a)) * (dayR - 6), tick);
    }
    final arc = Paint()..style = PaintingStyle.stroke..strokeWidth = 2.2..color = accent.withValues(alpha: 0.9 * t);
    canvas.drawArc(Rect.fromCircle(center: hub, radius: dayR + 52), -1.3, 2.6, false, arc);
    // la línea que señala el día del centro
    canvas.drawLine(hub + Offset(hubR * 1.05, 0), hub + Offset(dayR - 16, 0), Paint()..strokeWidth = 1..color = accent.withValues(alpha: 0.6 * t));
  }

  @override
  bool shouldRepaint(covariant _DialPainter old) => old.t != t || old.hub != hub || old.dayPos != dayPos || old.monthPos != monthPos || old.accent != accent;
}
