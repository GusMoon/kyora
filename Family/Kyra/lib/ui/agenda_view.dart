import 'dart:async';

import 'package:flutter/material.dart';

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
import '../util/format.dart';
import 'calendar_views.dart';
import 'event_editor.dart';
import 'reminder_editor.dart';
import 'task_detail_page.dart';
import 'widgets/agenda_card.dart';
import 'widgets/app_backdrop.dart';
import 'widgets/pixel_glyph.dart';
import 'widgets/cut_border.dart';
import 'widgets/focus_space.dart';
import 'widgets/section_motion.dart';

export '../util/agenda.dart' show addDays, dateOnly, mondayOf, monthNames, minutesLabel, habitDaysLabel;
export 'widgets/agenda_card.dart' show SquareCheck;

/// Un día corto: «Ayer», «Mañana» o «3 nov».
String shortDayLabel(DateTime moment, DateTime today) {
  final d = dateOnly(moment);
  final t = dateOnly(today);
  if (d == addDays(t, -1)) return 'Ayer';
  if (d == addDays(t, 1)) return 'Mañana';
  return '${d.day} ${monthNames[d.month - 1].substring(0, 3).toLowerCase()}';
}

/// El calendario (eventos, tareas con entrega, recordatorios y hábitos). Arriba, en una sola fila, el rango que se ve (‹ título ›, «Hoy») y, en la
/// esquina, **Actualizar** y «+». Las dos vistas **Semana · Mes** (por defecto la que se elige en Configuración, y si no, la semana) se
/// cambian **pellizcando**: juntar los dedos pasa a Mes; separarlos, a Semana. Siempre se ve todo —no hay filtros— y
/// todo se enseña en **tarjetas** (`AgendaCard`).
///
/// - **Mes**: a pantalla completa. El número grande del día elegido (con lo que falta para él), el mes y el año, la cuadrícula de cuadros
///   (que se estira hasta llenar la pantalla, con puntos de color y acabado sci-fi) y, debajo, las tarjetas del día elegido.
/// - **Semana**: los siete días apilados en bandas; el día elegido se abre con su fecha, sus tarjetas y un campo para añadir una tarea.
///
/// Se pone al día con Supabase solo (Realtime, al volver a la app y tras cada cambio) y con el botón «Actualizar». Lo que no esté disponible
/// (sin eventos, sin tareas, sin avisos…) no se ofrece.
///
/// Vive dentro de la tesela de la hora de Inicio. Con [embedded] va sin el marco propio y «atrás» llama a [onClose].
class AgendaView extends StatefulWidget {
  const AgendaView({super.key, this.tasks, this.reminders, this.habits, this.events, this.now, this.embedded = false, this.onClose, this.initialMode = CalendarMode.week});

  final Future<TaskController>? tasks;
  final Future<ReminderController>? reminders;
  final Future<HabitController>? habits;
  final Future<EventController>? events;

  /// El reloj (en las pruebas, uno fijo).
  final DateTime Function()? now;

  /// Dentro de la tesela de Inicio: sin el panel propio.
  final bool embedded;

  /// Cerrar la agenda (contraer la tesela). Si no es nulo, «atrás» lo llama.
  final VoidCallback? onClose;

  /// La vista con la que se abre (la elegida en Configuración; por defecto, la semana). Con el pellizco se cambia mientras está abierto.
  final CalendarMode initialMode;

  /// Cuánto hay que juntar los dedos (sobre lo que estaban separados) para pasar al mes, y cuánto separarlos para volver a la semana.
  static const pinchIn = 0.82;
  static const pinchOut = 1.2;

  @override
  State<AgendaView> createState() => _AgendaViewState();
}

class _AgendaViewState extends State<AgendaView> with SingleTickerProviderStateMixin {
  TaskController? _tasks;
  ReminderController? _reminders;
  HabitController? _habits;
  EventController? _events;

  late CalendarMode _mode = widget.initialMode;
  late DateTime _selected = _today;
  bool _refreshing = false;

  /// El cambio de vista (semana ↔ mes): el cuerpo se materializa con el efecto de holograma (0 oculto → 1 nítido).
  late final AnimationController _swap = AnimationController(vsync: this, duration: const Duration(milliseconds: 420), value: 1);

  /// Los dedos que tocan la pantalla (para el pellizco: minimizar pasa de la semana al mes; separar, del mes a la semana).
  final Map<int, Offset> _pointers = {};
  double? _pinchStart;

  /// El campo de «añadir una tarea» del día abierto de la semana.
  final TextEditingController _quickTask = TextEditingController();

  /// Para llevar la lista de la semana al día elegido.
  final Map<String, GlobalKey> _dayKeys = {};

  @override
  void dispose() {
    _swap.dispose();
    _quickTask.dispose();
    super.dispose();
  }

  DateTime get _clock => (widget.now ?? DateTime.now)();
  DateTime get _today => dateOnly(_clock);

  @override
  void initState() {
    super.initState();
    _attach<TaskController>(widget.tasks, (c) => _tasks = c);
    _attach<ReminderController>(widget.reminders, (c) => _reminders = c);
    _attach<HabitController>(widget.habits, (c) => _habits = c);
    _attach<EventController>(widget.events, (c) => _events = c);
    _revealDay();
  }

  /// En la semana, lleva el día abierto hasta arriba (si no, con varios días cerrados encima, sus tarjetas quedarían fuera de la pantalla).
  void _revealDay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _mode != CalendarMode.week) return;
      final ctx = _dayKeys[dayKey(_selected)]?.currentContext;
      if (ctx != null && ctx.mounted) unawaited(Scrollable.ensureVisible(ctx, alignment: 0, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic));
    });
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

  /// Siempre se ve todo: eventos, tareas, recordatorios y hábitos.
  Set<AgendaKind> get _visible => {..._kinds};

  AgendaData get _data {
    final habits = _habits;
    return AgendaData(
      events: _events?.items ?? const [],
      tasks: _tasks?.roots() ?? const [],
      reminders: _reminders?.items ?? const [],
      habitsOn: habits?.habitsFor,
      habitDone: habits?.isDone,
      taskProgress: _tasks?.progress,
    );
  }

  List<AgendaItem> _itemsFor(DateTime day, {Set<AgendaKind>? kinds}) => agendaForDay(_data, day, kinds: kinds ?? _visible);

  /// Lo de antes de hoy que sigue sin hacerse (recordatorios y tareas), para enseñarlo en hoy.
  List<AgendaItem> _overdue() {
    final today = _today;
    final out = <AgendaItem>[];
    if (_visible.contains(AgendaKind.reminder)) {
      for (final r in _reminders?.items ?? const <Reminder>[]) {
        if (!r.done && dateOnly(r.at).isBefore(today)) {
          out.add(AgendaItem(kind: AgendaKind.reminder, id: r.id, title: r.title, day: dateOnly(r.at), start: r.at.toLocal().hour * 60 + r.at.toLocal().minute, end: null, allDay: false, done: false, span: Span.single, time: '${shortDayLabel(r.at, today)} ${clockText(r.at)}', subtitle: r.notes.trim(), footer: 'Recordatorio'));
        }
      }
    }
    if (_visible.contains(AgendaKind.task)) {
      for (final t in _tasks?.roots() ?? const <TaskItem>[]) {
        final due = t.due;
        if (!t.isDone && due != null && dateOnly(due).isBefore(today)) {
          out.add(AgendaItem(kind: AgendaKind.task, id: t.id, title: t.name, day: dateOnly(due), start: due.toLocal().hour * 60 + due.toLocal().minute, end: null, allDay: false, done: false, span: Span.single, time: '${shortDayLabel(due, today)} ${clockText(due)}', subtitle: t.description.trim(), footer: taskFooter(_tasks?.progress(t))));
        }
      }
    }
    out.sort((a, b) => a.day.compareTo(b.day));
    return out;
  }

  // ---- moverse ----

  void _select(DateTime day) => setState(() => _selected = dateOnly(day));

  void _setMode(CalendarMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
    unawaited(_swap.forward(from: 0));
    _revealDay();
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
    if (_mode == CalendarMode.week && ratio < AgendaView.pinchIn) {
      _pinchStart = null;
      _setMode(CalendarMode.month);
    } else if (_mode == CalendarMode.month && ratio > AgendaView.pinchOut) {
      _pinchStart = null;
      _setMode(CalendarMode.week);
    }
  }

  void _pointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) _pinchStart = null;
  }

  void _step(int delta) {
    setState(() => _selected = stepSelected(_mode, _selected, delta));
    _revealDay();
  }

  void _goToday() {
    setState(() => _selected = _today);
    _revealDay();
  }

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

  // ---- acciones ----

  Future<void> _add({DateTime? day}) async {
    final c = context.colors;
    final at = day ?? _selected;
    final choice = await showFocusPanel<String>(context, title: 'Añadir', builder: (sheet) => SafeArea(
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
        if (events != null && mounted) await showEventEditor(context, events, day: at);
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

  /// Una tarjeta de la agenda. Claves: `cal-<clase>-<id>` (la tarjeta) y `cal-<clase>-check-<id>` (su casilla; los eventos no la llevan).
  Widget _card(BuildContext context, AgendaItem item, {bool overdue = false}) {
    final color = itemColor(context, item);
    final name = item.kind.name;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: AgendaCard(
        key: Key('cal-$name-${item.id}'),
        item: item,
        color: color,
        overdue: overdue,
        check: item.kind == AgendaKind.event
            ? null
            : SquareCheck(
                key: Key('cal-$name-check-${item.id}'),
                color: overdue ? context.colors.warn : color,
                done: item.done,
                label: item.title,
                onTap: _canToggle(item) ? () => _toggle(item) : null,
              ),
        onTap: () => _open(item),
      ),
    );
  }

  /// Un aviso con un margen a los lados (la agenda va de borde a borde).
  Widget? _sidePadded(Widget? child) => child == null ? null : Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: child);

  /// El aviso de notificaciones desactivadas (solo si lo están).
  Widget? _blockedNote(BuildContext context, {double top = 4}) {
    if (!(_reminders?.notificationsBlocked ?? false)) return null;
    return _Note(
      'Las notificaciones están desactivadas: los recordatorios y los hábitos se guardan pero no avisarán. Actívalas para esta app en los ajustes del teléfono.',
      key: const Key('reminders-blocked'),
      color: context.colors.warn,
      top: top,
    );
  }

  /// Lo de un día en tarjetas: lo vencido (si es hoy) y todo lo suyo, o «Nada para este día».
  List<Widget> _dayCards(BuildContext context, DateTime day) {
    final c = context.colors;
    final items = _itemsFor(day);
    final overdue = day == _today ? _overdue() : const <AgendaItem>[];
    return [
      if (overdue.isNotEmpty) _Block('Vencido', color: c.warn, count: overdue.length, children: [for (final i in overdue) _card(context, i, overdue: true)]),
      for (final i in items) _card(context, i),
      if (items.isEmpty && overdue.isEmpty) _Note('Nada para este día.', key: const Key('cal-day-empty'), color: c.dim, top: 8),
    ];
  }

  /// El mes, a pantalla completa: el número grande del día elegido, la cuadrícula —que se estira hasta llenar lo que queda de pantalla, con un
  /// mínimo por fila— y, debajo, las tarjetas de ese día. Si no caben, todo se desliza junto.
  Widget _monthBody(BuildContext context) {
    final bottom = 24 + MediaQuery.paddingOf(context).bottom;
    return LayoutBuilder(
      builder: (context, box) {
        final blocked = _reminders?.notificationsBlocked ?? false;
        final room = box.maxHeight - MonthHeader.height - MonthGrid.cardsReserve - bottom - (blocked ? 96 : 0);
        final gridHeight = room < MonthGrid.minHeight ? MonthGrid.minHeight : room;
        return ListView(
          key: const Key('cal-day'),
          padding: EdgeInsets.only(bottom: bottom),
          children: [
            ?_sidePadded(_blockedNote(context)),
            MonthHeader(day: _selected, today: _today),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: SizedBox(
                height: gridHeight,
                child: MonthGrid(days: daysFor(CalendarMode.month, _selected), selected: _selected, today: _today, month: _selected.month, itemsOf: _itemsFor, onTap: _select),
              ),
            ),
            const SizedBox(height: 6),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _dayCards(context, _selected))),
          ],
        );
      },
    );
  }

  /// «Noviembre 5, 2026» (y la hora de ahora si es hoy).
  String _dateLine(DateTime day) => '${monthNames[day.month - 1]} ${day.day}, ${day.year}${day == _today ? ' · ${clockText(_clock)}' : ''}';

  /// La hora de entrega de una tarea que se añade desde la semana: las 18:00 de ese día (o las 23:59 si hoy ya pasaron).
  DateTime _quickDue(DateTime day) {
    final late = day == _today && _clock.hour >= 18;
    return atMinutes(day, late ? 23 * 60 + 59 : 18 * 60);
  }

  /// Añade la tarea escrita en el campo del día abierto, con entrega ese día.
  Future<void> _addQuick(DateTime day) async {
    final name = _quickTask.text.trim();
    if (name.isEmpty) return;
    final tasks = _tasks ?? await widget.tasks;
    if (tasks == null || !mounted) return;
    _quickTask.clear();
    await tasks.add(name, due: _quickDue(day));
  }

  /// El campo de «Añadir una tarea…» del día abierto.
  Widget _quickAdd(BuildContext context, DateTime day) {
    final c = context.colors;
    final k = dayKey(day);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: TextField(
        key: Key('cal-week-add-$k'),
        controller: _quickTask,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => unawaited(_addQuick(day)),
        decoration: InputDecoration(
          hintText: 'Añadir una tarea…',
          prefixIcon: LcdIcon(Icons.add_rounded, color: c.tasks),
          suffixIcon: IconButton(key: Key('cal-week-add-send-$k'), tooltip: 'Añadir', onPressed: () => unawaited(_addQuick(day)), icon: LcdIcon(Icons.keyboard_return_rounded, color: c.accent)),
        ),
      ),
    );
  }

  Widget _weekDay(BuildContext context, DateTime day, int index) {
    final open = day == _selected;
    final items = _itemsFor(day);
    final overdue = day == _today ? _overdue() : const <AgendaItem>[];
    return KeyedSubtree(
      key: _dayKeys.putIfAbsent(dayKey(day), GlobalKey.new),
      child: WeekDayBand(
        day: day,
        index: index,
        today: _today,
        open: open,
        count: items.length + overdue.length,
        dateLine: _dateLine(day),
        onTap: () {
          if (day != _selected) _quickTask.clear();
          _select(day);
          _revealDay();
        },
        children: open ? [..._dayCards(context, day), if (widget.tasks != null) _quickAdd(context, day)] : const [],
      ),
    );
  }

  /// La semana: los siete días apilados, el elegido abierto. La columna **llega hasta abajo de la pantalla**: si los días no llenan el alto,
  /// las bandas cerradas se estiran (con el nombre centrado) para ocupar el resto; si no caben, se desliza.
  Widget _weekBody(BuildContext context) {
    final days = daysFor(CalendarMode.week, _selected);
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        key: const Key('cal-week'),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ?_sidePadded(_blockedNote(context)),
                for (var i = 0; i < days.length; i++)
                  days[i] == _selected ? _weekDay(context, days[i], i) : Expanded(child: _weekDay(context, days[i], i)),
              ],
            ),
          ),
        ),
      ),
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
          // dentro de Inicio, «atrás» contrae la agenda
          canPop: widget.onClose == null,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) widget.onClose?.call();
          },
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Listener(
              onPointerDown: _pointerDown,
              onPointerMove: _pointerMove,
              onPointerUp: _pointerUp,
              onPointerCancel: _pointerUp,
              child: Padding(
              // a todo el ancho: las bandas de la semana y el mes llegan de borde a borde
              padding: EdgeInsets.only(top: widget.embedded ? 0 : MediaQuery.paddingOf(context).top + 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FlyIn(edge: MotionEdge.top, child: _header(context, canAdd)),
                  if (problem != null) _SyncLine(problem),
                  const SizedBox(height: 4),
                  Expanded(
                    child: FlyIn(
                      edge: MotionEdge.bottom,
                      order: 3,
                      child: HologramReveal(
                        animation: _swap,
                        child: switch (_mode) {
                          CalendarMode.month => _monthBody(context),
                          CalendarMode.week => _weekBody(context),
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ),
          ),
        );
      },
    );
  }

  /// ‹ título ›, «Hoy» y, en la esquina, **Actualizar** y «+».
  Widget _header(BuildContext context, bool canAdd) {
    final c = context.colors;
    final isToday = _selected == _today;
    final button = IconButton.styleFrom(fixedSize: const Size(36, 40), padding: EdgeInsets.zero);
    final square = IconButton.styleFrom(fixedSize: const Size(40, 40), padding: EdgeInsets.zero, shape: CutBorder(side: BorderSide(color: c.accent.withValues(alpha: 0.45))));
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 8, 6),
      child: Row(
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
          Semantics(
            button: true,
            label: 'Hoy',
            child: GestureDetector(
              key: const Key('cal-today'),
              behavior: HitTestBehavior.opaque,
              onTap: _goToday,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(border: Border.all(color: isToday ? c.edge : c.accent.withValues(alpha: 0.7))),
                child: Text('Hoy', style: TextStyle(fontFamily: monoFont, fontSize: 15, color: isToday ? c.dim : c.accent)),
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

/// Un bloque de la agenda (lo vencido): un marcador y el título en el color que se diga, cuántas hay y debajo sus tarjetas.
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
          ...children,
        ],
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
