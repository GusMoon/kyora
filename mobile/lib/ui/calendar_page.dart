import 'dart:async';

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
import 'widgets/home_clock.dart' show softFade, softStops;
import 'widgets/lcd_box.dart';
import 'widgets/month_dial.dart';
import 'widgets/pixel_glyph.dart';
import 'widgets/section_motion.dart';
import 'widgets/cut_border.dart';
import 'widgets/hack_text.dart';
import 'widgets/focus_space.dart';

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

/// El Calendario, como una **consola**: arriba el día elegido en grande (matriz de puntos), su fecha y un resumen (`> 3 tareas · 2 hábitos`);
/// debajo, tres paneles que se pasan **deslizando a los lados**: **Hoy** (lo del día elegido: recordatorios, tareas que vencen y hábitos que
/// tocan, con su casilla, y el acceso a todas las tareas), **Hábitos** y **Recordatorios**. **Pellizcando** con dos dedos (o con el botón del
/// calendario) se abre el **mini calendario**: un dial sci-fi con los días del mes y sus marcadores. El «+» crea una tarea, un recordatorio o un
/// hábito con el día elegido ya puesto. Lo que no esté disponible (sin Supabase de tareas, sin avisos…) no se ofrece.
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, this.tasks, this.reminders, this.habits, this.now});

  final Future<TaskController>? tasks;
  final Future<ReminderController>? reminders;
  final Future<HabitController>? habits;

  /// El reloj (en las pruebas, uno fijo).
  final DateTime Function()? now;

  /// Cuánto hay que juntar los dedos (de la distancia inicial) para que se abra el mini calendario, y separarlos para cerrarlo.
  static const pinchIn = 0.82;
  static const pinchOut = 1.2;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
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
    if (!_dialOpen && ratio < CalendarPage.pinchIn) {
      _pinchStart = null;
      _openDial();
    } else if (_dialOpen && ratio > CalendarPage.pinchOut) {
      _pinchStart = null;
      _closeDial();
    }
  }

  void _pointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) _pinchStart = null;
  }

  DayMarks _marksOf(DateTime day) => marksFor(day, tasks: _tasks, reminders: _reminders, habits: _habits);

  Future<void> _add() async {
    final choice = await showFocusPanel<String>(context, builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.tasks != null)
              ListTile(
                key: const Key('cal-add-task'),
                leading: const LcdIcon(Icons.check_box_outlined),
                title: const Text('Tarea'),
                onTap: () => Navigator.of(sheet).pop('task'),
              ),
            if (widget.reminders != null)
              ListTile(
                key: const Key('cal-add-reminder'),
                leading: const LcdIcon(Icons.notifications_none_rounded),
                title: const Text('Recordatorio'),
                onTap: () => Navigator.of(sheet).pop('reminder'),
              ),
            if (widget.habits != null)
              ListTile(
                key: const Key('cal-add-habit'),
                leading: const LcdIcon(Icons.repeat_rounded),
                title: const Text('Hábito'),
                onTap: () => Navigator.of(sheet).pop('habit'),
              ),
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
          // «atrás» cierra primero el mini calendario
          canPop: !_dialOpen,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _closeDial();
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

/// La consola de arriba: el día elegido en grande en matriz de puntos, la fecha y una línea con lo que hay ese día, sobre un degradado negro
/// suave (como la hora de Inicio). A la derecha, abrir el mini calendario y el «+».
class _Console extends StatelessWidget {
  const _Console({required this.selected, required this.today, required this.summary, required this.onOpenDial, required this.onAdd});

  final DateTime selected;
  final DateTime today;
  final String summary;
  final VoidCallback onOpenDial;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final top = MediaQuery.paddingOf(context).top;
    final isToday = selected == today;
    final mono = TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim);
    return DecoratedBox(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: softFade(0.85), stops: softStops())),
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, top + 18, 12, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      DotMatrixText(selected.day.toString().padLeft(2, '0'), key: const Key('cal-day-number'), height: 44, color: c.accent),
                      const SizedBox(width: 12),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: DotMatrixText(dialMonths[selected.month - 1], height: 18, color: Colors.white.withValues(alpha: 0.85)),
                      ),
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
            IconButton(
              key: const Key('cal-open-month'),
              tooltip: 'Calendario',
              onPressed: onOpenDial,
              icon: Icon(Icons.blur_circular_rounded, color: c.ink, size: 28),
            ),
            if (onAdd != null)
              Semantics(
                button: true,
                label: 'Añadir',
                child: GestureDetector(
                  key: const Key('cal-add'),
                  onTap: onAdd,
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: cutDecoration(color: c.accent, edge: c.ink.withValues(alpha: 0.6), width: 1.5, cut: 12),
                    child: Icon(Icons.add_rounded, color: c.onAccent, size: 28),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Las etiquetas de los paneles, como un HUD: la del que se ve, encendida; tocar una lleva a ella. Debajo, un punto por panel.
class _PanelTabs extends StatelessWidget {
  const _PanelTabs({required this.panels, required this.active, required this.onTap});

  final List<CalendarPanel> panels;
  final int active;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Row(
        children: [
          for (var i = 0; i < panels.length; i++)
            Expanded(
              child: GestureDetector(
                key: Key('cal-tab-${panels[i].name}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
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
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        height: 2,
                        width: i == active ? 36 : 10,
                        color: i == active ? c.accent : c.edge,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Una casilla cuadrada: vacía, o rellena con ✓. Sin `onTap` queda apagada (un día que todavía no llega).
class SquareCheck extends StatelessWidget {
  const SquareCheck({super.key, required this.done, required this.onTap, this.label});

  final bool done;
  final VoidCallback? onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onTap != null;
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
                color: done ? c.accent : null,
                border: Border.all(color: done ? c.accent : (enabled ? c.dim : c.edge), width: 1.5),
              ),
              child: done ? LcdIcon(Icons.check_rounded, size: 18, color: c.onAccent) : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Una fila de la agenda: casilla, la hora o el día (si lo hay) y el título; lo hecho, tachado.
class _AgendaRow extends StatelessWidget {
  const _AgendaRow({super.key, required this.check, required this.title, required this.done, this.when, this.whenWarn = false, this.onTap});

  final Widget check;
  final String title;
  final bool done;
  final String? when;
  final bool whenWarn;
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
              width: 74,
              child: Align(
                alignment: Alignment.centerLeft,
                // lo vencido, en vídeo inverso
                child: LcdTag(when!, inverse: whenWarn, bold: true),
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

/// El título de un bloque de la agenda.
class _BlockTitle extends StatelessWidget {
  const _BlockTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 2),
    child: Text(text.toUpperCase(), style: hudLabel(color: context.colors.accent)),
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
        Container(
          key: const Key('reminders-blocked'),
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(14),
          // un aviso del sistema: una tarjeta con el color de aviso
          decoration: cutDecoration(color: c.warn.withValues(alpha: 0.14), edge: c.warn.withValues(alpha: 0.5), cut: 12),
          child: Text(
            'Las notificaciones están desactivadas: los recordatorios y los hábitos se guardan pero no avisarán. Actívalas para esta app en los ajustes del teléfono.',
            style: lcdStatus(color: c.warn),
          ),
        ),
      if (dayReminders.isNotEmpty) ...[
        const _BlockTitle('Recordatorios'),
        for (final r in dayReminders)
          _AgendaRow(
            key: Key('cal-reminder-${r.id}'),
            check: SquareCheck(key: Key('cal-reminder-check-${r.id}'), done: r.done, label: r.title, onTap: () => unawaited(reminders!.toggleDone(r))),
            when: sameDay(r.at, day) ? clockText(r.at) : shortDayLabel(r.at, today),
            whenWarn: reminders!.isOverdue(r),
            title: r.title,
            done: r.done,
            onTap: () => unawaited(showReminderEditor(context, reminders!, existing: r)),
          ),
      ],
      if (dayTasks.isNotEmpty) ...[
        const _BlockTitle('Tareas'),
        for (final t in dayTasks)
          _AgendaRow(
            key: Key('cal-task-${t.id}'),
            check: SquareCheck(key: Key('cal-task-check-${t.id}'), done: t.isDone, label: t.name, onTap: () => unawaited(tasks!.toggleDone(t))),
            when: sameDay(t.due!, day) ? clockText(t.due!) : shortDayLabel(t.due!, today),
            whenWarn: !t.isDone && t.due!.isBefore(now.toUtc()),
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
      if (dayHabits.isNotEmpty) ...[
        const _BlockTitle('Hábitos'),
        for (final h in dayHabits)
          _AgendaRow(
            key: Key('cal-habit-${h.id}'),
            check: SquareCheck(
              key: Key('cal-habit-check-${h.id}'),
              done: habits!.isDone(h, day),
              label: h.name,
              onTap: future ? null : () => unawaited(habits!.toggle(h, day)),
            ),
            when: h.remindAt == null ? null : minutesLabel(h.remindAt!),
            title: h.name,
            done: habits!.isDone(h, day),
          ),
      ],
      if (dayReminders.isEmpty && dayTasks.isEmpty && dayHabits.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 28),
          child: Text(
            'Nada para este día.',
            key: const Key('cal-day-empty'),
            style: TextStyle(color: c.dim, fontSize: 16),
          ),
        ),
      if (onAllTasks != null)
        Padding(
          padding: const EdgeInsets.only(top: 22),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: const Key('cal-all-tasks'),
              onPressed: onAllTasks,
              style: OutlinedButton.styleFrom(
                foregroundColor: c.accent,
                side: BorderSide(color: c.accent.withValues(alpha: 0.6)),
                shape: const CutBorder(cut: 8),
              ),
              child: Text('TODAS LAS TAREAS ›', style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 0.5, color: c.accent)),
            ),
          ),
        ),
    ];
    return ListView(key: const Key('cal-day'), padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.paddingOf(context).bottom), children: children);
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
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
        child: Text(
          'Aún no tienes hábitos. Crea uno con «+».',
          key: const Key('habits-empty'),
          style: TextStyle(color: c.dim, fontSize: 16),
        ),
      );
    }
    return ListView(
      key: const Key('habit-list'),
      padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        // las letras de la semana, sobre las casillas
        Row(
          children: [
            const Spacer(),
            for (var i = 0; i < 7; i++)
              SizedBox(
                width: 26,
                child: Center(
                  child: Text(weekdayLetters[i], style: TextStyle(color: c.dim, fontSize: 15)),
                ),
              ),
          ],
        ),
        for (final h in habits)
          GestureDetector(
            key: Key('habit-${h.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(showHabitEditor(context, controller, existing: h)),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.edge)),
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
                          style: TextStyle(color: c.dim, fontSize: 15),
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
                                  color: done ? c.accent : null,
                                  border: due && !done ? Border.all(color: c.dim, width: 1.5) : null,
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
        Container(
          key: const Key('reminders-blocked-list'),
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(14),
          decoration: cutDecoration(color: c.warn.withValues(alpha: 0.14), edge: c.warn.withValues(alpha: 0.5), cut: 12),
          child: Text('Las notificaciones están desactivadas: los recordatorios se guardan pero no avisarán.', style: lcdStatus(color: c.warn)),
        ),
      if (all.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 28),
          child: Text('Aún no tienes recordatorios. Crea uno con «+».', key: const Key('reminders-empty'), style: TextStyle(color: c.dim, fontSize: 16)),
        ),
      if (all.any((r) => !r.done)) const _BlockTitle('Pendientes'),
      for (final r in all.where((r) => !r.done)) _row(context, r),
      if (all.any((r) => r.done)) const _BlockTitle('Hechos'),
      for (final r in all.where((r) => r.done)) _row(context, r),
    ];
    return ListView(key: const Key('cal-reminders'), padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.paddingOf(context).bottom), children: children);
  }

  Widget _row(BuildContext context, Reminder r) => _AgendaRow(
    key: Key('rem-${r.id}'),
    check: SquareCheck(key: Key('rem-check-${r.id}'), done: r.done, label: r.title, onTap: () => unawaited(controller.toggleDone(r))),
    when: sameDay(r.at, today) ? clockText(r.at) : '${shortDayLabel(r.at, today)} ${clockText(r.at)}',
    whenWarn: controller.isOverdue(r),
    title: r.title,
    done: r.done,
    onTap: () => unawaited(showReminderEditor(context, controller, existing: r)),
  );
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
            const Text('Nueva tarea', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
            Text(widget.existing == null ? 'Nuevo hábito' : 'Editar hábito', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
