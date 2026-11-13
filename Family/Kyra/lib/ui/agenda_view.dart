import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/habit.dart';
import '../models/reminder.dart';
import '../models/task.dart';
import '../state/habit_controller.dart';
import '../state/reminder_controller.dart';
import '../state/task_controller.dart';
import '../theme.dart';
import '../util/calendar_marks.dart';
import '../util/format.dart';
import 'reminder_editor.dart';
import 'task_detail_page.dart';
import 'tasks_page.dart';
import 'widgets/app_backdrop.dart';
import 'widgets/dot_matrix.dart';
import 'widgets/month_dial.dart';
import 'widgets/pixel_glyph.dart';
import 'widgets/section_motion.dart';
import 'widgets/cut_border.dart';
import 'widgets/hack_text.dart';
import 'widgets/focus_space.dart';
import 'widgets/cyber_panel.dart';
import 'widgets/tech_shapes.dart' show HudBars;

/// Los meses, con mayúscula: «Noviembre».
const monthNames = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];

/// El día (sin hora) de un instante, en la hora local.
DateTime dateOnly(DateTime moment) {
  final local = moment.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// `n` días después (con el constructor, así un cambio de horario no mueve el día).
DateTime addDays(DateTime day, int n) => DateTime(day.year, day.month, day.day + n);

/// El lunes de la semana de ese día.
DateTime mondayOf(DateTime day) {
  final d = dateOnly(day);
  return addDays(d, -(d.weekday - 1));
}

/// Los días de un hábito, en palabras: «Todos los días», «Entre semana», «Fines de semana» o las letras («L M V»).
String habitDaysLabel(int mask) {
  if (mask & Habit.everyDay == Habit.everyDay) return 'Todos los días';
  if (mask == Habit.maskOf([1, 2, 3, 4, 5])) return 'Entre semana';
  if (mask == Habit.maskOf([6, 7])) return 'Fines de semana';
  return [
    for (var d = 1; d <= 7; d++)
      if (mask & (1 << (d - 1)) != 0) weekdayLetters[d - 1],
  ].join(' ');
}

/// Un día corto, para la columna de la hora en la agenda: «Ayer», «Mañana» o «3 nov».
String shortDayLabel(DateTime moment, DateTime today) {
  final d = dateOnly(moment);
  final t = dateOnly(today);
  if (d == addDays(t, -1)) return 'Ayer';
  if (d == addDays(t, 1)) return 'Mañana';
  return '${d.day} ${monthNames[d.month - 1].substring(0, 3).toLowerCase()}';
}

/// Minutos desde medianoche → «07:30».
String minutesLabel(int minutes) => '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// Los paneles del Calendario, que se pasan deslizando a los lados: **Hoy** (la agenda del día elegido), **Hábitos** y **Recordatorios**.
enum CalendarPanel { day, habits, reminders }

const _panelLabels = {CalendarPanel.day: 'HOY', CalendarPanel.habits: 'HÁBITOS', CalendarPanel.reminders: 'RECORDATORIOS'};

/// La agenda (tareas, hábitos, recordatorios y calendario), como una **consola**: arriba el día elegido en grande (matriz de puntos), su fecha y un resumen (`> 3 tareas · 2 hábitos`);
/// debajo, tres paneles que se pasan **deslizando a los lados**: **Hoy** (lo del día elegido: recordatorios, tareas que vencen y hábitos que
/// tocan, con su casilla, y el acceso a todas las tareas), **Hábitos** y **Recordatorios**. **Pellizcando** con dos dedos (o con el botón del
/// calendario) se abre el **mini calendario**: un dial sci-fi con los días del mes y sus marcadores. El «+» crea una tarea, un recordatorio o un
/// hábito con el día elegido ya puesto. Lo que no esté disponible (sin Supabase de tareas, sin avisos…) no se ofrece.
///
/// Vive dentro de la tesela de la hora de Inicio, que se **expande** al tocarla (`HomeGrid`): ya no es una sección aparte. Con [embedded] va sin
/// el marco ni la cabecera propios (los pone la tesela) y «atrás» llama a [onClose] cuando no hay mini calendario abierto.
class AgendaView extends StatefulWidget {
  const AgendaView({super.key, this.tasks, this.reminders, this.habits, this.now, this.embedded = false, this.onClose});

  final Future<TaskController>? tasks;
  final Future<ReminderController>? reminders;
  final Future<HabitController>? habits;

  /// El reloj (en las pruebas, uno fijo).
  final DateTime Function()? now;

  /// Dentro de la tesela de Inicio: sin el panel ni la línea técnica de la consola.
  final bool embedded;

  /// Cerrar la agenda (contraer la tesela). Si no es nulo, «atrás» cierra primero el mini calendario y después llama a esto.
  final VoidCallback? onClose;

  /// Cuánto hay que juntar los dedos (de la distancia inicial) para que se abra el mini calendario, y separarlos para cerrarlo.
  static const pinchIn = 0.82;
  static const pinchOut = 1.2;

  @override
  State<AgendaView> createState() => _AgendaViewState();
}

class _AgendaViewState extends State<AgendaView> {
  TaskController? _tasks;
  ReminderController? _reminders;
  HabitController? _habits;

  late final DateTime _today = dateOnly((widget.now ?? DateTime.now)());
  late DateTime _selected = _today;
  final PageController _pages = PageController();
  int _panel = 0;
  bool _dialOpen = false;

  /// Los dedos que hay en la pantalla (para el pellizco), y la distancia entre los dos primeros al empezar.
  final Map<int, Offset> _pointers = {};
  double? _pinchStart;

  @override
  void initState() {
    super.initState();
    widget.tasks?.then((c) {
      if (mounted) setState(() => _tasks = c);
    });
    widget.reminders?.then((c) {
      if (mounted) setState(() => _reminders = c);
    });
    widget.habits?.then((c) {
      if (mounted) setState(() => _habits = c);
    });
  }

  @override
  void didUpdateWidget(covariant AgendaView old) {
    super.didUpdateWidget(old);
    // si se cerró sesión (o entró otra cuenta) los controladores son otros: se vuelven a pedir
    if (old.tasks != widget.tasks) {
      _tasks = null;
      widget.tasks?.then((c) {
        if (mounted) setState(() => _tasks = c);
      });
    }
    if (old.reminders != widget.reminders) {
      _reminders = null;
      widget.reminders?.then((c) {
        if (mounted) setState(() => _reminders = c);
      });
    }
    if (old.habits != widget.habits) {
      _habits = null;
      widget.habits?.then((c) {
        if (mounted) setState(() => _habits = c);
      });
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  List<CalendarPanel> get _panels => [
    CalendarPanel.day,
    if (widget.habits != null) CalendarPanel.habits,
    if (widget.reminders != null) CalendarPanel.reminders,
  ];

  void _select(DateTime day) => setState(() => _selected = dateOnly(day));

  void _goToPanel(int i) {
    if (!_pages.hasClients) return;
    unawaited(_pages.animateToPage(i, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic));
  }

  void _openDial() {
    if (_dialOpen) return;
    unawaited(HapticFeedback.lightImpact().catchError((Object _) {}));
    setState(() => _dialOpen = true);
  }

  void _closeDial() {
    if (_dialOpen) setState(() => _dialOpen = false);
  }

  // ---- el pellizco: se mira a mano (con un Listener), para no quitarle el deslizamiento a los paneles ----

  double? _spread() {
    if (_pointers.length < 2) return null;
    final points = _pointers.values.take(2).toList();
    return (points[0] - points[1]).distance;
  }

  void _pointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) _pinchStart = _spread();
  }

  void _pointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    final start = _pinchStart;
    final now = _spread();
    if (start == null || now == null || start < 1) return;
    final ratio = now / start;
    if (!_dialOpen && ratio < AgendaView.pinchIn) {
      _pinchStart = null;
      _openDial();
    } else if (_dialOpen && ratio > AgendaView.pinchOut) {
      _pinchStart = null;
      _closeDial();
    }
  }

  void _pointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) _pinchStart = null;
  }

  /// Lo hecho y el total de lo que hay ese día (recordatorios, tareas que vencen y hábitos que tocan), para el anillo de la consola.
  (int, int) _progressOf(DateTime day) {
    var done = 0, total = 0;
    for (final r in _reminders?.items ?? const <Reminder>[]) {
      if (!sameDay(r.at, day)) continue;
      total++;
      if (r.done) done++;
    }
    for (final t in _tasks?.roots() ?? const <TaskItem>[]) {
      if (t.due == null || !sameDay(t.due!, day)) continue;
      total++;
      if (t.isDone) done++;
    }
    final habits = _habits;
    if (habits != null) {
      for (final h in habits.habitsFor(day)) {
        total++;
        if (habits.isDone(h, day)) done++;
      }
    }
    return (done, total);
  }

  DayMarks _marksOf(DateTime day) => marksFor(day, tasks: _tasks, reminders: _reminders, habits: _habits);

  Future<void> _add() async {
    final c = context.colors;
    final choice = await showFocusPanel<String>(context, title: 'Añadir', builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.tasks != null)
              _AddOption(key: const Key('cal-add-task'), icon: Icons.check_box_outlined, label: 'Tarea', color: c.tasks, onTap: () => Navigator.of(sheet).pop('task')),
            if (widget.reminders != null)
              _AddOption(key: const Key('cal-add-reminder'), icon: Icons.notifications_none_rounded, label: 'Recordatorio', color: c.reminders, onTap: () => Navigator.of(sheet).pop('reminder')),
            if (widget.habits != null)
              _AddOption(key: const Key('cal-add-habit'), icon: Icons.repeat_rounded, label: 'Hábito', color: c.habits, onTap: () => Navigator.of(sheet).pop('habit')),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'task':
        final tasks = _tasks ?? await widget.tasks;
        if (tasks != null && mounted) await showQuickTaskEditor(context, tasks, _selected);
      case 'reminder':
        final reminders = _reminders ?? await widget.reminders;
        if (reminders != null && mounted) await showReminderEditor(context, reminders, day: _selected);
      case 'habit':
        final habits = _habits ?? await widget.habits;
        if (habits != null && mounted) await showHabitEditor(context, habits);
    }
  }

  /// «Todas las tareas»: la lista completa con sus filtros, en su propia página.
  void _openAllTasks() {
    final tasks = _tasks;
    if (tasks == null) return;
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TasksPage(controller: tasks))));
  }

  @override
  Widget build(BuildContext context) {
    final listen = Listenable.merge([_tasks, _reminders, _habits]);
    return ListenableBuilder(
      listenable: listen,
      builder: (context, _) {
        final panels = _panels;
        final panel = _panel.clamp(0, panels.length - 1);
        final canAdd = widget.tasks != null || widget.reminders != null || widget.habits != null;
        return PopScope(
          // «atrás» cierra primero el mini calendario y, dentro de Inicio, después contrae la agenda
          canPop: !_dialOpen && widget.onClose == null,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_dialOpen) {
              _closeDial();
            } else {
              widget.onClose?.call();
            }
          },
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Listener(
              onPointerDown: _pointerDown,
              onPointerMove: _pointerMove,
              onPointerUp: _pointerUp,
              onPointerCancel: _pointerUp,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FlyIn(
                        edge: MotionEdge.top,
                        child: _Console(
                          selected: _selected,
                          today: _today,
                          summary: marksSummary(
                            _marksOf(_selected),
                            withTasks: widget.tasks != null,
                            withHabits: widget.habits != null,
                            withReminders: widget.reminders != null,
                          ),
                          progress: _progressOf(_selected),
                          embedded: widget.embedded,
                          onOpenDial: _openDial,
                          onAdd: canAdd ? _add : null,
                        ),
                      ),
                      if (panels.length > 1)
                        FlyIn(
                          edge: MotionEdge.top,
                          order: 1,
                          child: _PanelTabs(panels: panels, active: panel, onTap: _goToPanel),
                        ),
                      Expanded(
                        child: FlyIn(
                          edge: MotionEdge.bottom,
                          order: 3,
                          child: PageView(
                            key: const Key('cal-panels'),
                            controller: _pages,
                            onPageChanged: (i) => setState(() => _panel = i),
                            children: [
                              for (final p in panels)
                                switch (p) {
                                  CalendarPanel.day => _DayView(
                                    day: _selected,
                                    today: _today,
                                    tasks: _tasks,
                                    reminders: _reminders,
                                    habits: _habits,
                                    onAllTasks: widget.tasks == null ? null : _openAllTasks,
                                  ),
                                  CalendarPanel.habits => _habits == null
                                      ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
                                      : _HabitsView(controller: _habits!, week: mondayOf(_selected)),
                                  CalendarPanel.reminders => _reminders == null
                                      ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
                                      : _RemindersView(controller: _reminders!, today: _today),
                                },
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_dialOpen)
                    Positioned.fill(
                      child: MonthDial(
                        selected: _selected,
                        today: _today,
                        marksOf: _marksOf,
                        onPick: (day) {
                          _select(day);
                          _closeDial();
                        },
                        onClose: _closeDial,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// La consola de arriba, en un **panel HUD** (filo del acento y marcas en las esquinas): una línea técnica, el día elegido en grande en matriz de
/// puntos con el **anillo de avance** del día (hechos / total), la fecha y una línea con lo que hay ese día. A la derecha, abrir el mini
/// calendario y el «+».
class _Console extends StatelessWidget {
  const _Console({required this.selected, required this.today, required this.summary, required this.progress, required this.onOpenDial, required this.onAdd, this.embedded = false});

  /// Dentro de la tesela de Inicio: sin el panel propio ni la línea «KYRA // AGENDA» (la tesela ya es el panel).
  final bool embedded;

  final DateTime selected;
  final DateTime today;
  final String summary;

  /// Lo hecho y el total de ese día (para el anillo).
  final (int, int) progress;
  final VoidCallback onOpenDial;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final top = embedded ? 0.0 : MediaQuery.paddingOf(context).top;
    final isToday = selected == today;
    final mono = TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim);
    final square = IconButton.styleFrom(
      fixedSize: const Size(44, 44),
      padding: EdgeInsets.zero,
      shape: CutBorder(side: BorderSide(color: c.accent.withValues(alpha: 0.55))),
    );
    Widget framed(Widget content) => embedded
        ? Padding(padding: const EdgeInsets.fromLTRB(2, 0, 2, 4), child: content)
        : Padding(padding: EdgeInsets.fromLTRB(12, top + 10, 12, 8), child: CyberPanel(child: content));
    return framed(
        Padding(
          padding: embedded ? const EdgeInsets.fromLTRB(10, 4, 4, 6) : const EdgeInsets.fromLTRB(18, 14, 10, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!embedded) ...[
                      Row(
                        children: [
                          Text('KYRA // AGENDA', style: hudLabel(color: c.dim)),
                          const SizedBox(width: 10),
                          HudBars(values: const [0.4, 0.8, 0.55, 1, 0.3, 0.7], height: 12, barWidth: 3, gap: 3, color: c.accent.withValues(alpha: 0.7)),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        DotMatrixText(selected.day.toString().padLeft(2, '0'), key: const Key('cal-day-number'), height: 44, color: c.accent),
                        const SizedBox(width: 12),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: DotMatrixText(dialMonths[selected.month - 1], height: 18, color: Colors.white.withValues(alpha: 0.85)),
                        ),
                        const Spacer(),
                        _DayRing(key: const Key('cal-ring'), done: progress.$1, total: progress.$2),
                      ],
                    ),
                    const SizedBox(height: 10),
                    HackText(
                      '${isToday ? 'HOY · ' : ''}${longDate(selected)} ${selected.year}',
                      textKey: const Key('cal-title'),
                      style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.ink, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 4),
                    HackText('> $summary', textKey: const Key('cal-summary'), order: 1, style: mono.copyWith(color: c.accent)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  IconButton(
                    key: const Key('cal-open-month'),
                    tooltip: 'Calendario',
                    onPressed: onOpenDial,
                    style: square,
                    icon: Icon(Icons.blur_circular_rounded, color: c.ink, size: 26),
                  ),
                  if (onAdd != null) ...[
                    const SizedBox(height: 8),
                    Semantics(
                      button: true,
                      label: 'Añadir',
                      child: GestureDetector(
                        key: const Key('cal-add'),
                        onTap: onAdd,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: cutDecoration(color: c.accent, edge: c.ink.withValues(alpha: 0.6), width: 1.5),
                          child: Icon(Icons.add_rounded, color: c.onAccent, size: 28),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
    );
  }
}

/// El anillo del día: un aro con marcas que se rellena con el acento según lo hecho; en el centro, «hechos/total» (o «–» sin nada).
class _DayRing extends StatelessWidget {
  const _DayRing({super.key, required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final complete = total > 0 && done >= total;
    return Semantics(
      label: total == 0 ? 'Sin pendientes' : '$done de $total hechos',
      child: SizedBox.square(
        dimension: 58,
        child: CustomPaint(
          painter: _RingPainter(fraction: total == 0 ? 0 : done / total, accent: complete ? c.ok : c.accent, track: c.edge),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: FittedBox(
                child: Text(total == 0 ? '–' : '$done/$total', style: TextStyle(fontFamily: monoFont, fontSize: 15, fontWeight: FontWeight.w600, color: complete ? c.ok : c.ink)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.fraction, required this.accent, required this.track});

  final double fraction;
  final Color accent;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 3;
    // las marcas de fuera, como las de un dial
    final tick = Paint()
      ..strokeWidth = 1
      ..color = track;
    for (var i = 0; i < 24; i++) {
      final angle = i * math.pi / 12;
      final d = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(center + d * (radius + 1), center + d * (radius + (i % 6 == 0 ? 4.0 : 2.5)), tick);
    }
    final ring = Rect.fromCircle(center: center, radius: radius - 2);
    canvas.drawArc(
      ring,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = track,
    );
    if (fraction > 0) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.butt
        ..color = accent;
      canvas.drawArc(ring, -math.pi / 2, 2 * math.pi * fraction.clamp(0.0, 1.0), false, arc);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.fraction != fraction || old.accent != accent || old.track != track;
}

/// Las etiquetas de los paneles, como un **selector HUD** en una sola barra con filo: la del panel que se ve, encendida y entre corchetes;
/// tocar una lleva a ella.
class _PanelTabs extends StatelessWidget {
  const _PanelTabs({required this.panels, required this.active, required this.onTap});

  final List<CalendarPanel> panels;
  final int active;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: DecoratedBox(
        decoration: cutDecoration(color: c.field, edge: c.edge),
        child: Row(
          children: [
            for (var i = 0; i < panels.length; i++)
              Expanded(
                child: GestureDetector(
                  key: Key('cal-tab-${panels[i].name}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    padding: const EdgeInsets.only(top: 9),
                    color: i == active ? c.accent.withValues(alpha: 0.12) : Colors.transparent,
                    child: Column(
                      children: [
                        HackText(
                          i == active ? '[${_panelLabels[panels[i]]}]' : _panelLabels[panels[i]]!,
                          order: 1,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 0.5, fontWeight: i == active ? FontWeight.w700 : FontWeight.w400, color: i == active ? c.accent : c.dim),
                        ),
                        const SizedBox(height: 7),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          height: 2,
                          color: i == active ? c.accent : Colors.transparent,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Una casilla cuadrada: vacía, o rellena con ✓. Sin `onTap` queda apagada (un día que todavía no llega). Con [color] va del color de su tipo
/// (recordatorio, tarea, hábito); sin él, del acento.
class SquareCheck extends StatelessWidget {
  const SquareCheck({super.key, required this.done, required this.onTap, this.label, this.color});

  final bool done;
  final VoidCallback? onTap;
  final String? label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onTap != null;
    final tone = color ?? c.accent;
    final on = tone.computeLuminance() > 0.18 ? const Color(0xFF0A0B0D) : const Color(0xFFFFFFFF);
    return Semantics(
      button: true,
      checked: done,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: done ? tone : tone.withValues(alpha: enabled ? 0.08 : 0),
                border: Border.all(color: done ? tone : (enabled ? tone.withValues(alpha: 0.75) : c.edge), width: 1.5),
              ),
              child: done ? LcdIcon(Icons.check_rounded, size: 18, color: on) : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// La hora (o el día) de una fila, en una etiqueta técnica con filo del color de su tipo; lo vencido, rellena en el color de aviso.
class _TimeChip extends StatelessWidget {
  const _TimeChip(this.text, {required this.color, required this.warn});

  final String text;
  final Color color;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      key: warn ? const Key('lcd-tag-inverse') : null,
      decoration: ShapeDecoration(
        color: warn ? c.warn : null,
        shape: CutBorder(side: warn ? BorderSide.none : BorderSide(color: color.withValues(alpha: 0.55))),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontFamily: monoFont, fontSize: 15, fontWeight: FontWeight.w600, color: warn ? const Color(0xFF0A0B0D) : c.ink),
        ),
      ),
    );
  }
}

/// Una fila de la agenda: casilla, la hora o el día (si lo hay) y el título; lo hecho, tachado.
class _AgendaRow extends StatelessWidget {
  const _AgendaRow({super.key, required this.check, required this.title, required this.done, this.when, this.whenWarn = false, this.tone, this.onTap});

  final Widget check;
  final String title;
  final bool done;
  final String? when;
  final bool whenWarn;

  /// El color de su tipo (para la etiqueta de la hora).
  final Color? tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        children: [
          check,
          if (when != null) ...[
            SizedBox(
              width: 82,
              child: Align(
                alignment: Alignment.centerLeft,
                // lo vencido, relleno en el color de aviso
                child: _TimeChip(when!, color: tone ?? c.accent, warn: whenWarn),
              ),
            ),
          ],
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: done ? c.dim : c.ink, fontSize: 16, height: 1.25, decoration: done ? TextDecoration.lineThrough : null),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Un bloque de la agenda como **ficha HUD**: un marcador y el título en el color de su tipo, el avance («02/05») con una barra fina, y debajo
/// las filas separadas por líneas finas. Con [count] en lugar de [done]/[total] solo enseña cuántas hay.
class _Block extends StatelessWidget {
  const _Block(this.title, {required this.color, required this.children, this.done, this.total, this.count});

  final String title;
  final Color color;
  final List<Widget> children;
  final int? done;
  final int? total;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasProgress = done != null && total != null && total! > 0;
    final fraction = hasProgress ? (done! / total!).clamp(0.0, 1.0) : 0.0;
    String two(int n) => n.toString().padLeft(2, '0');
    final counter = hasProgress ? '${two(done!)}/${two(total!)}' : (count == null ? null : two(count!));
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: CyberPanel(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 14, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(width: 9, height: 9, color: color),
                  const SizedBox(width: 10),
                  Expanded(child: Text(title.toUpperCase(), style: hudLabel(color: color))),
                  if (counter != null) Text(counter, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim)),
                ],
              ),
              if (hasProgress)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SizedBox(
                    height: 2,
                    child: Stack(
                      children: [
                        Positioned.fill(child: ColoredBox(color: c.edge)),
                        FractionallySizedBox(widthFactor: fraction, child: ColoredBox(color: color)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 2),
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) ColoredBox(color: c.edge, child: const SizedBox(height: 1)),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Un recuadro de aviso o de «nada por aquí»: texto dentro de un filo fino del color que se diga.
class _Note extends StatelessWidget {
  const _Note(this.text, {super.key, required this.color, this.top = 14});

  final String text;
  final Color color;
  final double top;

  @override
  Widget build(BuildContext context) => Container(
    margin: EdgeInsets.only(top: top),
    padding: const EdgeInsets.all(14),
    decoration: cutDecoration(color: color.withValues(alpha: 0.10), edge: color.withValues(alpha: 0.5)),
    child: Text(text, style: lcdStatus(color: color)),
  );
}

/// Lo del día elegido: recordatorios por hora, tareas que vencen ese día y hábitos que tocan. Si es hoy, también lo que ya venció.
class _DayView extends StatelessWidget {
  const _DayView({required this.day, required this.today, required this.tasks, required this.reminders, required this.habits, this.onAllTasks});

  /// Abre la lista completa de tareas. Sin esto (sin tareas), no sale.
  final VoidCallback? onAllTasks;

  final DateTime day;
  final DateTime today;
  final TaskController? tasks;
  final ReminderController? reminders;
  final HabitController? habits;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now();
    final isToday = day == today;
    final allReminders = reminders?.items ?? const <Reminder>[];
    final dayReminders = [
      if (isToday) ...[
        for (final r in allReminders)
          if (!r.done && dateOnly(r.at).isBefore(today)) r,
      ],
      for (final r in allReminders)
        if (sameDay(r.at, day)) r,
    ]..sort((a, b) => a.at.compareTo(b.at));
    final roots = tasks?.roots() ?? const <TaskItem>[];
    final dayTasks = [
      if (isToday) ...[
        for (final t in roots)
          if (!t.isDone && t.due != null && dateOnly(t.due!).isBefore(today)) t,
      ],
      for (final t in roots)
        if (t.due != null && sameDay(t.due!, day)) t,
    ]..sort((a, b) => a.due!.compareTo(b.due!));
    final dayHabits = habits?.habitsFor(day) ?? const <Habit>[];
    final future = habits?.isFuture(day) ?? day.isAfter(today);
    final children = <Widget>[
      if (reminders?.notificationsBlocked ?? false)
        // un aviso del sistema: un recuadro con el color de aviso
        _Note(
          'Las notificaciones están desactivadas: los recordatorios y los hábitos se guardan pero no avisarán. Actívalas para esta app en los ajustes del teléfono.',
          key: const Key('reminders-blocked'),
          color: c.warn,
          top: 4,
        ),
      if (dayReminders.isNotEmpty)
        _Block(
          'Recordatorios',
          color: c.reminders,
          done: dayReminders.where((r) => r.done).length,
          total: dayReminders.length,
          children: [
            for (final r in dayReminders)
              _AgendaRow(
                key: Key('cal-reminder-${r.id}'),
                check: SquareCheck(key: Key('cal-reminder-check-${r.id}'), color: c.reminders, done: r.done, label: r.title, onTap: () => unawaited(reminders!.toggleDone(r))),
                when: sameDay(r.at, day) ? clockText(r.at) : shortDayLabel(r.at, today),
                whenWarn: reminders!.isOverdue(r),
                tone: c.reminders,
                title: r.title,
                done: r.done,
                onTap: () => unawaited(showReminderEditor(context, reminders!, existing: r)),
              ),
          ],
        ),
      if (dayTasks.isNotEmpty)
        _Block(
          'Tareas',
          color: c.tasks,
          done: dayTasks.where((t) => t.isDone).length,
          total: dayTasks.length,
          children: [
            for (final t in dayTasks)
              _AgendaRow(
                key: Key('cal-task-${t.id}'),
                check: SquareCheck(key: Key('cal-task-check-${t.id}'), color: c.tasks, done: t.isDone, label: t.name, onTap: () => unawaited(tasks!.toggleDone(t))),
                when: sameDay(t.due!, day) ? clockText(t.due!) : shortDayLabel(t.due!, today),
                whenWarn: !t.isDone && t.due!.isBefore(now.toUtc()),
                tone: c.tasks,
                title: t.name,
                done: t.isDone,
                onTap: () => unawaited(
                  Navigator.of(context).push(
                    QuickPageRoute<void>(
                      builder: (_) => TaskDetailPage(controller: tasks!, taskId: t.id),
                    ),
                  ),
                ),
              ),
          ],
        ),
      if (dayHabits.isNotEmpty)
        _Block(
          'Hábitos',
          color: c.habits,
          done: dayHabits.where((h) => habits!.isDone(h, day)).length,
          total: dayHabits.length,
          children: [
            for (final h in dayHabits)
              _AgendaRow(
                key: Key('cal-habit-${h.id}'),
                check: SquareCheck(
                  key: Key('cal-habit-check-${h.id}'),
                  color: c.habits,
                  done: habits!.isDone(h, day),
                  label: h.name,
                  onTap: future ? null : () => unawaited(habits!.toggle(h, day)),
                ),
                when: h.remindAt == null ? null : minutesLabel(h.remindAt!),
                tone: c.habits,
                title: h.name,
                done: habits!.isDone(h, day),
              ),
          ],
        ),
      if (dayReminders.isEmpty && dayTasks.isEmpty && dayHabits.isEmpty)
        _Note('Nada para este día.', key: const Key('cal-day-empty'), color: c.dim, top: 14),
      if (onAllTasks != null)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: OutlinedButton(
            key: const Key('cal-all-tasks'),
            onPressed: onAllTasks,
            style: OutlinedButton.styleFrom(
              foregroundColor: c.accent,
              minimumSize: const Size.fromHeight(48),
              side: BorderSide(color: c.accent.withValues(alpha: 0.6)),
              shape: const CutBorder(),
            ),
            child: Text('TODAS LAS TAREAS ›', style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 0.5, color: c.accent)),
          ),
        ),
    ];
    return ListView(key: const Key('cal-day'), padding: EdgeInsets.fromLTRB(12, 0, 12, 24 + MediaQuery.paddingOf(context).bottom), children: children);
  }
}

/// Los hábitos: nombre, días y aviso, con las casillas de la semana elegida (se puede marcar o desmarcar cualquier día que tocaba y ya pasó).
/// Tocar uno abre su editor.
class _HabitsView extends StatelessWidget {
  const _HabitsView({required this.controller, required this.week});

  final HabitController controller;

  /// El lunes de la semana que se enseña.
  final DateTime week;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final habits = controller.habits;
    if (habits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
        child: _Note('Aún no tienes hábitos. Crea uno con «+».', key: const Key('habits-empty'), color: c.dim),
      );
    }
    return ListView(
      key: const Key('habit-list'),
      padding: EdgeInsets.fromLTRB(12, 4, 12, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        // las letras de la semana, sobre las casillas
        Padding(
          padding: const EdgeInsets.only(right: 14),
          child: Row(
            children: [
              const Spacer(),
              for (var i = 0; i < 7; i++)
                SizedBox(
                  width: 26,
                  child: Center(
                    child: Text(weekdayLetters[i], style: TextStyle(fontFamily: monoFont, color: c.dim, fontSize: 15)),
                  ),
                ),
            ],
          ),
        ),
        for (final h in habits)
          GestureDetector(
            key: Key('habit-${h.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(showHabitEditor(context, controller, existing: h)),
            // cada hábito, una ficha con su marca en el color de los hábitos
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              // el mismo cristal oscuro y filo del acento que las demás fichas (`CyberPanel`)
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color.alphaBlend(c.accent.withValues(alpha: 0.10), Colors.black.withValues(alpha: 0.9)), Colors.black.withValues(alpha: 0.66)],
                ),
                border: Border.all(color: c.accent.withValues(alpha: 0.28)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          h.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: c.ink, fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [habitDaysLabel(h.weekdays), if (h.remindAt != null) minutesLabel(h.remindAt!)].join(' · '),
                          style: TextStyle(fontFamily: monoFont, color: c.habits, fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                  for (var i = 0; i < 7; i++)
                    Builder(
                      builder: (context) {
                        final day = addDays(week, i);
                        final due = h.on(day.weekday);
                        final done = controller.isDone(h, day);
                        final open = due && !controller.isFuture(day);
                        return GestureDetector(
                          key: Key('habit-cell-${h.id}-${dayKey(day)}'),
                          behavior: HitTestBehavior.opaque,
                          onTap: open ? () => unawaited(controller.toggle(h, day)) : null,
                          child: SizedBox(
                            width: 26,
                            height: 40,
                            child: Center(
                              child: Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: done ? c.habits : null,
                                  border: due && !done ? Border.all(color: c.habits.withValues(alpha: 0.7), width: 1.5) : null,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Todos los recordatorios: los pendientes por fecha y hora (lo vencido, en vídeo inverso) y después los hechos. La casilla los marca; tocar
/// uno abre su editor.
class _RemindersView extends StatelessWidget {
  const _RemindersView({required this.controller, required this.today});

  final ReminderController controller;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final all = controller.items;
    final children = <Widget>[
      if (controller.notificationsBlocked)
        _Note('Las notificaciones están desactivadas: los recordatorios se guardan pero no avisarán.', key: const Key('reminders-blocked-list'), color: c.warn, top: 4),
      if (all.isEmpty) _Note('Aún no tienes recordatorios. Crea uno con «+».', key: const Key('reminders-empty'), color: c.dim),
      if (all.any((r) => !r.done))
        _Block('Pendientes', color: c.reminders, count: all.where((r) => !r.done).length, children: [for (final r in all.where((r) => !r.done)) _row(context, r)]),
      if (all.any((r) => r.done))
        _Block('Hechos', color: c.ok, count: all.where((r) => r.done).length, children: [for (final r in all.where((r) => r.done)) _row(context, r)]),
    ];
    return ListView(key: const Key('cal-reminders'), padding: EdgeInsets.fromLTRB(12, 0, 12, 24 + MediaQuery.paddingOf(context).bottom), children: children);
  }

  Widget _row(BuildContext context, Reminder r) => _AgendaRow(
    key: Key('rem-${r.id}'),
    check: SquareCheck(key: Key('rem-check-${r.id}'), color: r.done ? context.colors.ok : context.colors.reminders, done: r.done, label: r.title, onTap: () => unawaited(controller.toggleDone(r))),
    when: sameDay(r.at, today) ? clockText(r.at) : '${shortDayLabel(r.at, today)} ${clockText(r.at)}',
    whenWarn: controller.isOverdue(r),
    tone: context.colors.reminders,
    title: r.title,
    done: r.done,
    onTap: () => unawaited(showReminderEditor(context, controller, existing: r)),
  );
}

/// Una opción del menú de «+»: un icono en un cuadro del color de su tipo y el nombre en mayúsculas técnicas.
class _AddOption extends StatelessWidget {
  const _AddOption({super.key, required this.icon, required this.label, required this.color, required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 56,
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: cutDecoration(color: c.field, edge: color.withValues(alpha: 0.5)),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), border: Border.all(color: color.withValues(alpha: 0.7))),
              child: LcdIcon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: lcdLabel(size: 16, color: c.ink))),
            Icon(Icons.chevron_right_rounded, color: color),
          ],
        ),
      ),
    );
  }
}

// ---------- editores ----------

/// Anota una tarea rápida, con entrega el día elegido (a una hora) o sin fecha.
Future<void> showQuickTaskEditor(BuildContext context, TaskController controller, DateTime day) {
  return showFocusPanel<void>(context, builder: (_) => _QuickTaskEditor(controller: controller, day: day),
  );
}

class _QuickTaskEditor extends StatefulWidget {
  const _QuickTaskEditor({required this.controller, required this.day});

  final TaskController controller;
  final DateTime day;

  @override
  State<_QuickTaskEditor> createState() => _QuickTaskEditorState();
}

class _QuickTaskEditorState extends State<_QuickTaskEditor> {
  final _name = TextEditingController();
  late DateTime _day = dateOnly(widget.day);
  TimeOfDay _time = const TimeOfDay(hour: 18, minute: 0);
  bool _dated = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (picked != null) setState(() => _day = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Escribe la tarea.');
      return;
    }
    final due = _dated ? DateTime(_day.year, _day.month, _day.day, _time.hour, _time.minute).toUtc() : null;
    await widget.controller.add(_name.text, due: due);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('NUEVA TAREA', style: hudLabel(color: context.colors.tasks)),
            const SizedBox(height: 12),
            TextField(
              key: const Key('quick-task-name'),
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: '¿Qué hay que hacer?', errorText: _error),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const Key('quick-task-dated'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Con fecha de entrega'),
              value: _dated,
              onChanged: (v) => setState(() => _dated = v),
            ),
            if (_dated)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('quick-task-day'),
                      onPressed: _pickDay,
                      icon: const LcdIcon(Icons.event_outlined),
                      label: Text(dayLabel(_day)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('quick-task-time'),
                      onPressed: _pickTime,
                      icon: const LcdIcon(Icons.schedule),
                      label: Text(minutesLabel(_time.hour * 60 + _time.minute)),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 14),
            FilledButton(key: const Key('quick-task-save'), onPressed: _save, child: const Text('Guardar')),
          ],
        ),
      ),
    );
  }
}

/// Crea un hábito, o edita `existing`: nombre, días que toca y aviso opcional a una hora.
Future<void> showHabitEditor(BuildContext context, HabitController controller, {Habit? existing}) {
  return showFocusPanel<void>(context, builder: (_) => _HabitEditor(controller: controller, existing: existing),
  );
}

class _HabitEditor extends StatefulWidget {
  const _HabitEditor({required this.controller, this.existing});

  final HabitController controller;
  final Habit? existing;

  @override
  State<_HabitEditor> createState() => _HabitEditorState();
}

class _HabitEditorState extends State<_HabitEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.existing?.name ?? '');
  late int _days = widget.existing?.weekdays ?? Habit.everyDay;
  late bool _remind = widget.existing?.remindAt != null;
  late int _at = widget.existing?.remindAt ?? 8 * 60;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _at ~/ 60, minute: _at % 60),
    );
    if (picked != null) setState(() => _at = picked.hour * 60 + picked.minute);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Escribe el hábito.');
      return;
    }
    if (_days == 0) {
      setState(() => _error = 'Elige al menos un día.');
      return;
    }
    final existing = widget.existing;
    if (existing == null) {
      await widget.controller.add(_name.text, weekdays: _days, remindAt: _remind ? _at : null);
    } else {
      await widget.controller.update(existing, name: _name.text, weekdays: _days, remindAt: _remind ? _at : null);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    await widget.controller.delete(widget.existing!);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? 'Nuevo hábito' : 'Editar hábito', style: display(size: 20, color: c.ink)),
            const SizedBox(height: 12),
            TextField(
              key: const Key('habit-name'),
              controller: _name,
              autofocus: widget.existing == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: 'Leer 20 minutos, beber agua…', errorText: _error),
            ),
            const SizedBox(height: 14),
            Text('Qué días', style: TextStyle(color: c.dim, fontSize: 15)),
            const SizedBox(height: 6),
            Row(
              children: [
                for (var d = 1; d <= 7; d++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: _days & (1 << (d - 1)) != 0,
                      child: GestureDetector(
                        key: Key('habit-day-$d'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _days ^= 1 << (d - 1)),
                        child: Container(
                          height: 44,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          alignment: Alignment.center,
                          decoration: cutDecoration(color: _days & (1 << (d - 1)) != 0 ? c.accent : null, edge: _days & (1 << (d - 1)) != 0 ? c.accent : c.edge, cut: 10),
                          child: Text(
                            weekdayLetters[d - 1],
                            style: TextStyle(fontFamily: appFont, color: _days & (1 << (d - 1)) != 0 ? c.onAccent : c.ink, fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const Key('habit-remind'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Avisarme'),
              subtitle: const Text('Una notificación los días que toca'),
              value: _remind,
              onChanged: (v) => setState(() => _remind = v),
            ),
            if (_remind)
              OutlinedButton.icon(key: const Key('habit-time'), onPressed: _pickTime, icon: const LcdIcon(Icons.schedule), label: Text(minutesLabel(_at))),
            const SizedBox(height: 14),
            FilledButton(key: const Key('habit-save'), onPressed: _save, child: const Text('Guardar')),
            if (widget.existing != null) ...[
              const SizedBox(height: 6),
              TextButton(
                key: const Key('habit-delete'),
                onPressed: _delete,
                child: Text('Borrar el hábito', style: TextStyle(color: c.warn)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
