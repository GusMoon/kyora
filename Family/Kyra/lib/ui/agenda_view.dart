import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/event.dart';
import '../models/habit.dart';
import '../models/reminder.dart';
import '../models/task.dart';
import '../state/event_controller.dart';
import '../state/habit_controller.dart';
import '../state/reminder_controller.dart';
import '../state/task_controller.dart';
import '../theme.dart';
import '../util/agenda.dart';
import '../util/calendar_marks.dart';
import '../util/format.dart';
import 'calendar_views.dart';
import 'event_editor.dart';
import 'reminder_editor.dart';
import 'task_detail_page.dart';
import 'tasks_page.dart';
import 'widgets/app_backdrop.dart';
import 'widgets/month_dial.dart';
import 'widgets/pixel_glyph.dart';
import 'widgets/cut_border.dart';
import 'widgets/focus_space.dart';
import 'widgets/section_motion.dart';
import 'widgets/cyber_panel.dart';

export '../util/agenda.dart' show addDays, dateOnly, mondayOf, monthNames, minutesLabel;

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

/// El calendario (eventos, tareas con entrega, recordatorios y hábitos), con la organización de Merida pero compacto. Arriba, el rango que se ve
/// (‹ título ›, «Hoy»), las tres vistas **Día · Semana · Mes** (la semana es la de siempre al abrir), las clases que se muestran (cada una con su
/// color y cuántas hay) y los botones de **Actualizar**, mini calendario y «+».
///
/// - **Mes**: seis semanas con un pequeño margen entre días y puntos de color; el día elegido enseña debajo todo lo suyo.
/// - **Semana**: la tira de siete días y, debajo, lo de cada día de la semana.
/// - **Día**: la columna de 24 h con cada cosa en su hora, la de todo el día arriba y la línea de «ahora». Mantener el dedo en un hueco crea un
///   evento a esa hora.
///
/// Se pone al día con Supabase solo (Realtime, al volver a la app y tras cada cambio) y con el botón «Actualizar». **Pellizcando** con dos dedos
/// (o con el botón) se abre el mini calendario del mes. Lo que no esté disponible (sin eventos, sin tareas, sin avisos…) no se ofrece.
///
/// Vive dentro de la tesela de la hora de Inicio, que se **expande** al tocarla (`HomeGrid`). Con [embedded] va sin el marco propio y «atrás»
/// llama a [onClose] cuando no hay mini calendario abierto.
class AgendaView extends StatefulWidget {
  const AgendaView({super.key, this.tasks, this.reminders, this.habits, this.events, this.now, this.embedded = false, this.onClose});

  final Future<TaskController>? tasks;
  final Future<ReminderController>? reminders;
  final Future<HabitController>? habits;
  final Future<EventController>? events;

  /// El reloj (en las pruebas, uno fijo).
  final DateTime Function()? now;

  /// Dentro de la tesela de Inicio: sin el panel propio.
  final bool embedded;

  /// Cerrar la agenda (contraer la tesela). Si no es nulo, «atrás» cierra primero el mini calendario y después llama a esto.
  final VoidCallback? onClose;

  /// Cuánto hay que juntar los dedos (de la distancia inicial) para que se abra el mini calendario, y separarlos para cerrarlo.
  static const pinchIn = 0.82;
  static const pinchOut = 1.2;

  /// La vista que se usó la última vez en esta sesión (la semana, al abrir por primera vez).
  static CalendarMode lastMode = CalendarMode.week;

  @override
  State<AgendaView> createState() => _AgendaViewState();
}

class _AgendaViewState extends State<AgendaView> {
  TaskController? _tasks;
  ReminderController? _reminders;
  HabitController? _habits;
  EventController? _events;

  late CalendarMode _mode = AgendaView.lastMode;
  late DateTime _selected = _today;
  final Set<AgendaKind> _hidden = {};
  bool _dialOpen = false;
  bool _refreshing = false;

  /// Para llevar la lista de la semana al día elegido.
  final Map<String, GlobalKey> _dayKeys = {};

  /// Los dedos que hay en la pantalla (para el pellizco), y la distancia entre los dos primeros al empezar.
  final Map<int, Offset> _pointers = {};
  double? _pinchStart;

  DateTime get _clock => (widget.now ?? DateTime.now)();
  DateTime get _today => dateOnly(_clock);

  @override
  void initState() {
    super.initState();
    _attach<TaskController>(widget.tasks, (c) => _tasks = c);
    _attach<ReminderController>(widget.reminders, (c) => _reminders = c);
    _attach<HabitController>(widget.habits, (c) => _habits = c);
    _attach<EventController>(widget.events, (c) => _events = c);
  }

  void _attach<T>(Future<T>? future, void Function(T controller) set) {
    future?.then((c) {
      if (mounted) setState(() => set(c));
    });
  }

  @override
  void didUpdateWidget(covariant AgendaView old) {
    super.didUpdateWidget(old);
    // si se cerró sesión (o entró otra cuenta) los controladores son otros: se vuelven a pedir
    if (old.tasks != widget.tasks) {
      _tasks = null;
      _attach<TaskController>(widget.tasks, (c) => _tasks = c);
    }
    if (old.reminders != widget.reminders) {
      _reminders = null;
      _attach<ReminderController>(widget.reminders, (c) => _reminders = c);
    }
    if (old.habits != widget.habits) {
      _habits = null;
      _attach<HabitController>(widget.habits, (c) => _habits = c);
    }
    if (old.events != widget.events) {
      _events = null;
      _attach<EventController>(widget.events, (c) => _events = c);
    }
  }

  // ---- lo que hay ----

  List<AgendaKind> get _kinds => [
    if (widget.events != null) AgendaKind.event,
    if (widget.tasks != null) AgendaKind.task,
    if (widget.reminders != null) AgendaKind.reminder,
    if (widget.habits != null) AgendaKind.habit,
  ];

  Set<AgendaKind> get _visible => {for (final k in _kinds) if (!_hidden.contains(k)) k};

  AgendaData get _data {
    final habits = _habits;
    return AgendaData(
      events: _events?.items ?? const [],
      tasks: _tasks?.roots() ?? const [],
      reminders: _reminders?.items ?? const [],
      habitsOn: habits?.habitsFor,
      habitDone: habits?.isDone,
    );
  }

  List<AgendaItem> _itemsFor(DateTime day, {Set<AgendaKind>? kinds}) => agendaForDay(_data, day, kinds: kinds ?? _visible);

  /// Cuántas cosas de esa clase hay en lo que se ve.
  int _count(AgendaKind kind) {
    final data = _data;
    var total = 0;
    for (final d in daysFor(_mode, _selected)) {
      total += agendaForDay(data, d, kinds: {kind}).length;
    }
    return total;
  }

  /// Lo de antes de hoy que sigue sin hacerse (recordatorios y tareas), para enseñarlo en hoy.
  List<AgendaItem> _overdue() {
    final today = _today;
    final out = <AgendaItem>[];
    if (_visible.contains(AgendaKind.reminder)) {
      for (final r in _reminders?.items ?? const <Reminder>[]) {
        if (!r.done && dateOnly(r.at).isBefore(today)) {
          out.add(AgendaItem(kind: AgendaKind.reminder, id: r.id, title: r.title, day: dateOnly(r.at), start: null, end: null, allDay: false, done: false, span: Span.single, time: '${shortDayLabel(r.at, today)} ${clockText(r.at)}'));
        }
      }
    }
    if (_visible.contains(AgendaKind.task)) {
      for (final t in _tasks?.roots() ?? const <TaskItem>[]) {
        final due = t.due;
        if (!t.isDone && due != null && dateOnly(due).isBefore(today)) {
          out.add(AgendaItem(kind: AgendaKind.task, id: t.id, title: t.name, day: dateOnly(due), start: null, end: null, allDay: false, done: false, span: Span.single, time: '${shortDayLabel(due, today)} ${clockText(due)}'));
        }
      }
    }
    out.sort((a, b) => a.day.compareTo(b.day));
    return out;
  }

  // ---- moverse ----

  void _select(DateTime day) => setState(() => _selected = dateOnly(day));

  void _setMode(CalendarMode mode) {
    AgendaView.lastMode = mode;
    setState(() => _mode = mode);
  }

  void _step(int delta) => setState(() => _selected = stepSelected(_mode, _selected, delta));

  void _goToday() => setState(() => _selected = _today);

  void _toggleKind(AgendaKind kind) => setState(() {
        if (!_hidden.remove(kind)) _hidden.add(kind);
      });

  /// Pone al día todo con Supabase a mano.
  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await Future.wait([
        if (_tasks != null) _tasks!.sync(),
        if (_habits != null) _habits!.sync(),
        if (_reminders != null) _reminders!.sync(),
        if (_events != null) _events!.sync(),
      ]);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  /// El estado de la sincronización de lo que se ve: `null` si todo va bien.
  String? get _syncProblem {
    final list = <(SyncState, String?)>[
      if (_tasks != null) (_tasks!.syncState, _tasks!.syncError),
      if (_habits != null) (_habits!.syncState, _habits!.syncError),
      if (_reminders != null) (_reminders!.syncState, _reminders!.syncError),
      if (_events != null) (_events!.syncState, _events!.syncError),
    ];
    for (final (state, error) in list) {
      if (state == SyncState.offline) return 'Sin conexión: se actualizará al volver.';
      if (state == SyncState.error) return error ?? 'No se pudo actualizar.';
    }
    return null;
  }

  void _openDial() {
    if (_dialOpen) return;
    unawaited(HapticFeedback.lightImpact().catchError((Object _) {}));
    setState(() => _dialOpen = true);
  }

  void _closeDial() {
    if (_dialOpen) setState(() => _dialOpen = false);
  }

  // ---- el pellizco: se mira a mano (con un Listener), para no quitarle el deslizamiento a la lista ----

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

  DayMarks _marksOf(DateTime day) => marksFor(day, tasks: _tasks, reminders: _reminders, habits: _habits);

  // ---- acciones ----

  Future<void> _add({int? minutes, DateTime? day}) async {
    final c = context.colors;
    final at = day ?? _selected;
    // desde un hueco de la columna de horas solo tiene sentido crear un evento
    final choice = minutes != null && widget.events != null
        ? 'event'
        : await showFocusPanel<String>(context, title: 'Añadir', builder: (sheet) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.events != null)
                  _AddOption(key: const Key('cal-add-event'), icon: Icons.event_outlined, label: 'Evento', color: Color(colorValue(eventColors.first)), onTap: () => Navigator.of(sheet).pop('event')),
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
      case 'event':
        final events = _events ?? await widget.events;
        if (events != null && mounted) await showEventEditor(context, events, day: at, minutes: minutes);
      case 'task':
        final tasks = _tasks ?? await widget.tasks;
        if (tasks != null && mounted) await showQuickTaskEditor(context, tasks, at);
      case 'reminder':
        final reminders = _reminders ?? await widget.reminders;
        if (reminders != null && mounted) await showReminderEditor(context, reminders, day: at);
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

  /// Tocar una cosa abre su editor.
  void _open(AgendaItem item) {
    switch (item.kind) {
      case AgendaKind.event:
        final e = _events?.byId(item.id);
        if (e != null) unawaited(showEventEditor(context, _events!, existing: e));
      case AgendaKind.reminder:
        final r = _reminders?.rowById(item.id);
        if (r != null) unawaited(showReminderEditor(context, _reminders!, existing: r));
      case AgendaKind.task:
        final tasks = _tasks;
        if (tasks != null) unawaited(Navigator.of(context).push(QuickPageRoute<void>(builder: (_) => TaskDetailPage(controller: tasks, taskId: item.id))));
      case AgendaKind.habit:
        final h = _habits?.byId(item.id);
        if (h != null) unawaited(showHabitEditor(context, _habits!, existing: h));
    }
  }

  /// La casilla de una cosa: la marca o la desmarca. Un hábito de un día que todavía no llega no se marca.
  void _toggle(AgendaItem item) {
    switch (item.kind) {
      case AgendaKind.event:
        break;
      case AgendaKind.reminder:
        final r = _reminders?.rowById(item.id);
        if (r != null) unawaited(_reminders!.toggleDone(r));
      case AgendaKind.task:
        final t = _tasks?.byId(item.id);
        if (t != null) unawaited(_tasks!.toggleDone(t));
      case AgendaKind.habit:
        final h = _habits?.byId(item.id);
        if (h != null) unawaited(_habits!.toggle(h, item.day));
    }
  }

  bool _canToggle(AgendaItem item) => switch (item.kind) {
        AgendaKind.event => false,
        AgendaKind.habit => !(_habits?.isFuture(item.day) ?? item.day.isAfter(_today)),
        _ => true,
      };

  // ---- dibujo ----

  Widget _row(BuildContext context, AgendaItem item, {bool overdue = false}) {
    final color = itemColor(context, item);
    final name = item.kind.name;
    final Widget check = item.kind == AgendaKind.event
        ? SizedBox(
            width: 44,
            height: 44,
            child: Align(alignment: Alignment.centerLeft, child: Container(key: Key('cal-event-mark-${item.id}'), width: 14, height: 14, color: color)),
          )
        : SquareCheck(
            key: Key('cal-$name-check-${item.id}'),
            color: color,
            done: item.done,
            label: item.title,
            onTap: _canToggle(item) ? () => _toggle(item) : null,
          );
    return _AgendaRow(
      key: Key('cal-$name-${item.id}'),
      check: check,
      when: item.time,
      whenWarn: overdue,
      tone: color,
      title: item.title,
      done: item.done,
      onTap: () => _open(item),
    );
  }

  Widget _rows(BuildContext context, List<AgendaItem> items, {bool overdue = false}) {
    final c = context.colors;
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) ColoredBox(color: c.edge, child: const SizedBox(height: 1)),
          _row(context, items[i], overdue: overdue),
        ],
      ],
    );
  }

  /// Lo del día: el aviso de notificaciones, lo vencido (si es hoy) y todo lo suyo.
  List<Widget> _dayChildren(BuildContext context, DateTime day, {bool withAll = true}) {
    final c = context.colors;
    final items = _itemsFor(day);
    final overdue = day == _today ? _overdue() : const <AgendaItem>[];
    return [
      if (_reminders?.notificationsBlocked ?? false)
        _Note(
          'Las notificaciones están desactivadas: los recordatorios y los hábitos se guardan pero no avisarán. Actívalas para esta app en los ajustes del teléfono.',
          key: const Key('reminders-blocked'),
          color: c.warn,
          top: 4,
        ),
      if (overdue.isNotEmpty) _Block('Vencido', color: c.warn, count: overdue.length, children: [for (final i in overdue) _row(context, i, overdue: true)]),
      if (items.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: CyberPanel(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: _rows(context, items))),
        ),
      if (items.isEmpty && overdue.isEmpty) _Note('Nada para este día.', key: const Key('cal-day-empty'), color: c.dim, top: 8),
      if (withAll && widget.tasks != null)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: OutlinedButton(
            key: const Key('cal-all-tasks'),
            onPressed: _openAllTasks,
            style: OutlinedButton.styleFrom(foregroundColor: c.accent, minimumSize: const Size.fromHeight(48), side: BorderSide(color: c.accent.withValues(alpha: 0.6)), shape: const CutBorder()),
            child: Text('TODAS LAS TAREAS ›', style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 0.5, color: c.accent)),
          ),
        ),
    ];
  }

  Widget _monthBody(BuildContext context) {
    final bottom = 24 + MediaQuery.paddingOf(context).bottom;
    return LayoutBuilder(
      builder: (context, box) {
        final grid = (box.maxHeight * 0.5).clamp(250.0, 340.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: grid,
              child: MonthGrid(days: daysFor(CalendarMode.month, _selected), selected: _selected, today: _today, month: _selected.month, itemsOf: _itemsFor, onTap: _select),
            ),
            const SizedBox(height: 6),
            Expanded(child: ListView(key: const Key('cal-day'), padding: EdgeInsets.only(bottom: bottom), children: _dayChildren(context, _selected))),
          ],
        );
      },
    );
  }

  Widget _weekBody(BuildContext context) {
    final c = context.colors;
    final days = daysFor(CalendarMode.week, _selected);
    final bottom = 24 + MediaQuery.paddingOf(context).bottom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WeekStrip(
          days: days,
          selected: _selected,
          today: _today,
          itemsOf: _itemsFor,
          onTap: (day) {
            _select(day);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final ctx = _dayKeys[dayKey(day)]?.currentContext;
              if (ctx != null && ctx.mounted) unawaited(Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic));
            });
          },
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ListView(
            key: const Key('cal-week'),
            padding: EdgeInsets.only(bottom: bottom),
            children: [
              if (_reminders?.notificationsBlocked ?? false)
                _Note(
                  'Las notificaciones están desactivadas: los recordatorios y los hábitos se guardan pero no avisarán. Actívalas para esta app en los ajustes del teléfono.',
                  key: const Key('reminders-blocked'),
                  color: c.warn,
                  top: 4,
                ),
              for (final day in days) ...[
                Builder(
                  builder: (context) {
                    final items = _itemsFor(day);
                    final overdue = day == _today ? _overdue() : const <AgendaItem>[];
                    return Column(
                      key: _dayKeys.putIfAbsent(dayKey(day), GlobalKey.new),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(2, 12, 2, 4),
                          child: GestureDetector(
                            key: Key('cal-week-day-${dayKey(day)}'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _select(day),
                            child: Text(
                              '${weekdayNames[day.weekday - 1]} ${day.day} ${monthNames[day.month - 1].substring(0, 3).toLowerCase()}${day == _today ? ' · HOY' : ''}',
                              style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 0.4, fontWeight: day == _selected ? FontWeight.w700 : FontWeight.w500, color: day == _selected ? c.accent : (day == _today ? c.ink : c.dim)),
                            ),
                          ),
                        ),
                        if (overdue.isNotEmpty) _Block('Vencido', color: c.warn, count: overdue.length, children: [for (final i in overdue) _row(context, i, overdue: true)]),
                        if (items.isNotEmpty)
                          CyberPanel(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: _rows(context, items)))
                        else if (overdue.isEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(2, 0, 2, 2),
                            child: Text('Nada', key: day == _selected ? const Key('cal-day-empty') : null, style: TextStyle(color: c.dim.withValues(alpha: 0.7), fontSize: 15)),
                          ),
                      ],
                    );
                  },
                ),
              ],
              if (widget.tasks != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: OutlinedButton(
                    key: const Key('cal-all-tasks'),
                    onPressed: _openAllTasks,
                    style: OutlinedButton.styleFrom(foregroundColor: c.accent, minimumSize: const Size.fromHeight(48), side: BorderSide(color: c.accent.withValues(alpha: 0.6)), shape: const CutBorder()),
                    child: Text('TODAS LAS TAREAS ›', style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 0.5, color: c.accent)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dayBody(BuildContext context) {
    final c = context.colors;
    final items = _itemsFor(_selected);
    final overdue = _selected == _today ? _overdue() : const <AgendaItem>[];
    final allDay = [
      if (_reminders?.notificationsBlocked ?? false)
        _Note(
          'Las notificaciones están desactivadas: los recordatorios y los hábitos se guardan pero no avisarán. Actívalas para esta app en los ajustes del teléfono.',
          key: const Key('reminders-blocked'),
          color: c.warn,
          top: 0,
        ),
      for (final i in overdue) _row(context, i, overdue: true),
      for (final i in items)
        if (i.allDay) _row(context, i),
    ];
    return DayTimeline(
      key: ValueKey('cal-timeline-${dayKey(_selected)}'),
      day: _selected,
      items: items,
      now: _clock,
      allDay: allDay,
      onOpen: _open,
      onToggle: _toggle,
      canToggle: _canToggle,
      onCreateAt: (m) => unawaited(_add(minutes: m)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listen = Listenable.merge([_tasks, _reminders, _habits, _events]);
    return ListenableBuilder(
      listenable: listen,
      builder: (context, _) {
        final canAdd = _kinds.isNotEmpty;
        final problem = _syncProblem;
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
                  Padding(
                    padding: EdgeInsets.fromLTRB(2, widget.embedded ? 0 : MediaQuery.paddingOf(context).top + 8, 2, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FlyIn(edge: MotionEdge.top, child: _header(context)),
                        FlyIn(edge: MotionEdge.top, order: 1, child: _toolbar(context, canAdd)),
                        if (_kinds.length > 1) FlyIn(edge: MotionEdge.top, order: 2, child: _filters(context)),
                        if (problem != null) _SyncLine(problem),
                        const SizedBox(height: 4),
                        Expanded(
                          child: FlyIn(
                            edge: MotionEdge.bottom,
                            order: 3,
                            child: switch (_mode) {
                              CalendarMode.month => _monthBody(context),
                              CalendarMode.week => _weekBody(context),
                              CalendarMode.day => _dayBody(context),
                            },
                          ),
                        ),
                      ],
                    ),
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

  /// ‹ título › y «Hoy».
  Widget _header(BuildContext context) {
    final c = context.colors;
    final isToday = _selected == _today;
    final button = IconButton.styleFrom(fixedSize: const Size(40, 40), padding: EdgeInsets.zero);
    return Row(
      children: [
        IconButton(key: const Key('cal-prev'), tooltip: 'Anterior', onPressed: () => _step(-1), style: button, icon: Icon(Icons.chevron_left_rounded, color: c.ink)),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _goToday,
            child: Text(
              titleFor(_mode, _selected),
              key: const Key('cal-title'),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: monoFont, fontSize: 16, fontWeight: FontWeight.w700, color: c.ink, letterSpacing: 0.3),
            ),
          ),
        ),
        IconButton(key: const Key('cal-next'), tooltip: 'Siguiente', onPressed: () => _step(1), style: button, icon: Icon(Icons.chevron_right_rounded, color: c.ink)),
        const SizedBox(width: 2),
        Semantics(
          button: true,
          label: 'Hoy',
          child: GestureDetector(
            key: const Key('cal-today'),
            behavior: HitTestBehavior.opaque,
            onTap: _goToday,
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(border: Border.all(color: isToday ? c.edge : c.accent.withValues(alpha: 0.7))),
              child: Text('Hoy', style: TextStyle(fontFamily: monoFont, fontSize: 15, color: isToday ? c.dim : c.accent)),
            ),
          ),
        ),
      ],
    );
  }

  /// Las tres vistas y los botones de actualizar, mini calendario y «+».
  Widget _toolbar(BuildContext context, bool canAdd) {
    final c = context.colors;
    final square = IconButton.styleFrom(fixedSize: const Size(40, 40), padding: EdgeInsets.zero, shape: CutBorder(side: BorderSide(color: c.accent.withValues(alpha: 0.45))));
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
      child: Row(
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: cutDecoration(color: c.field, edge: c.edge),
              child: Row(
                children: [
                  for (final m in CalendarMode.values)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: m == _mode,
                        label: calendarModeLabel[m],
                        child: GestureDetector(
                          key: Key('cal-mode-${m.name}'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _setMode(m),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 40,
                            alignment: Alignment.center,
                            color: m == _mode ? c.accent.withValues(alpha: 0.16) : Colors.transparent,
                            child: Text(
                              calendarModeLabel[m]!,
                              style: TextStyle(fontFamily: monoFont, fontSize: 15, fontWeight: m == _mode ? FontWeight.w700 : FontWeight.w400, color: m == _mode ? c.accent : c.dim),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            key: const Key('cal-refresh'),
            tooltip: 'Actualizar',
            onPressed: _refreshing ? null : () => unawaited(_refresh()),
            style: square,
            icon: _refreshing ? SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: c.accent)) : Icon(Icons.refresh_rounded, color: c.ink, size: 24),
          ),
          const SizedBox(width: 4),
          IconButton(key: const Key('cal-open-month'), tooltip: 'Calendario', onPressed: _openDial, style: square, icon: Icon(Icons.blur_circular_rounded, color: c.ink, size: 24)),
          if (canAdd) ...[
            const SizedBox(width: 4),
            Semantics(
              button: true,
              label: 'Añadir',
              child: GestureDetector(
                key: const Key('cal-add'),
                onTap: () => unawaited(_add()),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: cutDecoration(color: c.accent, edge: c.ink.withValues(alpha: 0.6), width: 1.5),
                  child: Icon(Icons.add_rounded, color: c.onAccent, size: 26),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Qué clases se ven: un recuadro por cada una, con su color y cuántas hay.
  Widget _filters(BuildContext context) {
    final c = context.colors;
    Color colorOf(AgendaKind k) => switch (k) {
          AgendaKind.event => Color(colorValue(eventColors.first)),
          AgendaKind.task => c.tasks,
          AgendaKind.reminder => c.reminders,
          AgendaKind.habit => c.habits,
        };
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      child: Wrap(
        key: const Key('cal-show'),
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final k in _kinds) KindChip(kind: k, label: agendaKindPlural[k]!, count: _count(k), on: !_hidden.contains(k), color: colorOf(k), onTap: () => _toggleKind(k)),
        ],
      ),
    );
  }
}

/// Una línea con lo que falla al actualizar (sin conexión, o un error de Supabase).
class _SyncLine extends StatelessWidget {
  const _SyncLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 0, 6, 2),
    child: Text(text, key: const Key('cal-sync-problem'), style: TextStyle(fontSize: 15, color: context.colors.warn)),
  );
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

/// Un bloque de la agenda como **ficha HUD**: un marcador y el título en el color de su tipo, cuántas hay y debajo las filas separadas por líneas
/// finas.
class _Block extends StatelessWidget {
  const _Block(this.title, {required this.color, required this.children, required this.count});

  final String title;
  final Color color;
  final List<Widget> children;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
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
                  Text(count.toString().padLeft(2, '0'), style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim)),
                ],
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
