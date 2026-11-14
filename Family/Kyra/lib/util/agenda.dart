import 'dart:math' as math;

import '../models/event.dart';
import '../models/habit.dart';
import '../models/reminder.dart';
import '../models/task.dart';

/// La lógica del calendario, sin pantalla (lo mismo que `agenda.ts` de Merida): mezcla eventos, entregas de tareas, recordatorios y hábitos por
/// día, coloca lo que tiene hora en carriles y calcula el rango que se ve. La pantalla solo lo dibuja.

/// Los meses, con mayúscula: «Noviembre».
const monthNames = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];

/// Los días de la semana, con mayúscula, del lunes al domingo.
const weekdayNames = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];

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

/// Minutos desde medianoche → «07:30».
String minutesLabel(int minutes) => '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// El número de semana ISO.
int isoWeek(DateTime day) {
  final d = DateTime.utc(day.year, day.month, day.day);
  final thursday = d.add(Duration(days: 4 - d.weekday));
  final firstDay = DateTime.utc(thursday.year, 1, 1);
  return ((thursday.difference(firstDay).inDays) ~/ 7) + 1;
}

/// Las clases de cosas del calendario.
enum AgendaKind { event, task, reminder, habit }

const agendaKindLabel = {
  AgendaKind.event: 'Evento',
  AgendaKind.task: 'Tarea',
  AgendaKind.reminder: 'Recordatorio',
  AgendaKind.habit: 'Hábito',
};

const agendaKindPlural = {
  AgendaKind.event: 'Eventos',
  AgendaKind.task: 'Tareas',
  AgendaKind.reminder: 'Recordatorios',
  AgendaKind.habit: 'Hábitos',
};

/// Cómo se ve el calendario.
enum CalendarMode { day, week, month }

const calendarModeLabel = {CalendarMode.day: 'Día', CalendarMode.week: 'Semana', CalendarMode.month: 'Mes'};

/// Un evento de varios días se pinta unido de un día al siguiente.
enum Span { single, start, mid, end }

/// Todo lo que el calendario puede enseñar.
class AgendaData {
  const AgendaData({this.events = const [], this.tasks = const [], this.reminders = const [], this.habitsOn, this.habitDone});

  final List<CalendarEvent> events;

  /// Las tareas con entrega (las raíces, sin las subtareas).
  final List<TaskItem> tasks;
  final List<Reminder> reminders;

  /// Los hábitos que tocan ese día y si se cumplió uno ese día (lo sabe el controlador de hábitos).
  final List<Habit> Function(DateTime day)? habitsOn;
  final bool Function(Habit habit, DateTime day)? habitDone;
}

/// Una cosa en un día.
class AgendaItem {
  const AgendaItem({
    required this.kind,
    required this.id,
    required this.title,
    required this.day,
    required this.start,
    required this.end,
    required this.allDay,
    required this.done,
    required this.span,
    required this.time,
    this.colorHex,
  });

  final AgendaKind kind;
  final String id;
  final String title;
  final DateTime day;

  /// Minutos desde medianoche; `null` = sin hora.
  final int? start;

  /// Minutos; `null` = la duración de siempre.
  final int? end;

  /// Va en la franja de «todo el día» (sin hora, de todo el día o de varios días).
  final bool allDay;
  final bool done;
  final Span span;

  /// «18:00», «18:00–19:00» o «todo el día».
  final String time;

  /// El color propio (solo los eventos lo traen, `#rrggbb`); lo demás usa el color de su clase.
  final String? colorHex;
}

int _minutesOf(DateTime moment) {
  final local = moment.toLocal();
  return local.hour * 60 + local.minute;
}

/// Un `#rrggbb` como color (opaco). Lo que no se entienda cae en el primer color de los eventos.
int colorValue(String? hex) {
  final clean = (hex ?? '').replaceFirst('#', '');
  final parsed = clean.length == 6 ? int.tryParse(clean, radix: 16) : null;
  return 0xFF000000 | (parsed ?? 0x35D4FF);
}

/// Los eventos que ocupan ese día (de su día de inicio al de su fin, los dos incluidos).
List<CalendarEvent> eventsOnDay(List<CalendarEvent> events, DateTime day) {
  final d = dateOnly(day);
  return [
    for (final e in events)
      if (!e.isDeleted && !d.isBefore(dateOnly(e.startsAt)) && !d.isAfter(_lastDay(e))) e,
  ];
}

DateTime _lastDay(CalendarEvent e) {
  final first = dateOnly(e.startsAt);
  final end = e.endsAt;
  if (end == null) return first;
  final last = dateOnly(end);
  return last.isBefore(first) ? first : last;
}

int _kindOrder(AgendaKind k) => switch (k) { AgendaKind.event => 0, AgendaKind.reminder => 1, AgendaKind.task => 2, AgendaKind.habit => 3 };

/// Sin tildes ni mayúsculas, para buscar.
String normalizeText(String text) {
  const from = 'áàäâéèëêíìïîóòöôúùüûñ';
  const to = 'aaaaeeeeiiiioooouuuun';
  final lower = text.toLowerCase();
  final out = StringBuffer();
  for (final unit in lower.runes) {
    final ch = String.fromCharCode(unit);
    final i = from.indexOf(ch);
    out.write(i < 0 ? ch : to[i]);
  }
  return out.toString().trim();
}

/// Lo que hay ese día, solo de las clases que se quieren ver, ordenado: primero lo de todo el día, luego por hora y clase.
List<AgendaItem> agendaForDay(AgendaData data, DateTime day, {Set<AgendaKind>? kinds, String query = ''}) {
  final d = dateOnly(day);
  bool want(AgendaKind k) => kinds == null || kinds.contains(k);
  final out = <AgendaItem>[];
  if (want(AgendaKind.event)) {
    for (final e in eventsOnDay(data.events, d)) {
      final first = dateOnly(e.startsAt);
      final last = _lastDay(e);
      final span = first == last ? Span.single : (d == first ? Span.start : (d == last ? Span.end : Span.mid));
      final allDay = e.allDay || span != Span.single;
      final start = allDay ? null : _minutesOf(e.startsAt);
      final end = !allDay && e.endsAt != null ? _minutesOf(e.endsAt!) : null;
      out.add(AgendaItem(
        kind: AgendaKind.event,
        id: e.id,
        title: e.title,
        day: d,
        start: start,
        end: end,
        allDay: allDay,
        done: false,
        span: span,
        time: allDay ? 'todo el día' : '${minutesLabel(start!)}${end != null ? '–${minutesLabel(end)}' : ''}',
        colorHex: e.color,
      ));
    }
  }
  if (want(AgendaKind.task)) {
    for (final t in data.tasks) {
      final due = t.due;
      if (due == null || t.isDeleted || dateOnly(due) != d) continue;
      final start = _minutesOf(due);
      out.add(AgendaItem(kind: AgendaKind.task, id: t.id, title: t.name, day: d, start: start, end: null, allDay: false, done: t.isDone, span: Span.single, time: minutesLabel(start)));
    }
  }
  if (want(AgendaKind.reminder)) {
    for (final r in data.reminders) {
      if (r.isDeleted || dateOnly(r.at) != d) continue;
      final start = _minutesOf(r.at);
      out.add(AgendaItem(kind: AgendaKind.reminder, id: r.id, title: r.title, day: d, start: start, end: null, allDay: false, done: r.done, span: Span.single, time: minutesLabel(start)));
    }
  }
  if (want(AgendaKind.habit)) {
    for (final h in data.habitsOn?.call(d) ?? const <Habit>[]) {
      final timed = h.remindAt != null;
      out.add(AgendaItem(
        kind: AgendaKind.habit,
        id: h.id,
        title: h.name,
        day: d,
        start: h.remindAt,
        end: null,
        allDay: !timed,
        done: data.habitDone?.call(h, d) ?? false,
        span: Span.single,
        time: timed ? minutesLabel(h.remindAt!) : 'todo el día',
      ));
    }
  }
  final q = normalizeText(query);
  final list = q.isEmpty ? out : [for (final i in out) if (normalizeText(i.title).contains(q)) i];
  list.sort((a, b) {
    final byAllDay = (b.allDay ? 1 : 0) - (a.allDay ? 1 : 0);
    if (byAllDay != 0) return byAllDay;
    final byStart = (a.start ?? -1) - (b.start ?? -1);
    if (byStart != 0) return byStart;
    final byKind = _kindOrder(a.kind) - _kindOrder(b.kind);
    return byKind != 0 ? byKind : a.title.compareTo(b.title);
  });
  return list;
}

// ---------- la columna de horas (semana y día) ----------

const _defaultLen = 30; // minutos que ocupa en la columna lo que no tiene fin
const _eventLen = 60;
const dayMinutes = 1440;

/// Algo con hora colocado en la columna.
class Placed {
  Placed(this.item, this.top, this.len);

  final AgendaItem item;

  /// Minutos desde medianoche.
  final int top;

  /// Minutos de alto.
  final int len;

  /// En qué carril va si se solapa con otros, y cuántos carriles tiene su grupo.
  int lane = 0;
  int lanes = 1;
}

/// Coloca lo que tiene hora: cada uno con su alto, y lo que se solapa, uno junto a otro en carriles.
List<Placed> layoutDay(List<AgendaItem> items) {
  final timed = <Placed>[
    for (final item in items)
      if (!item.allDay && item.start != null)
        Placed(
          item,
          item.start!,
          math.min(math.max(_defaultLen, item.end != null ? item.end! - item.start! : (item.kind == AgendaKind.event ? _eventLen : _defaultLen)), dayMinutes - item.start!),
        ),
  ]..sort((a, b) => a.top != b.top ? a.top - b.top : b.len - a.len);
  var group = <Placed>[];
  var groupEnd = -1;
  void close() {
    final lanes = group.fold<int>(1, (m, p) => math.max(m, p.lane + 1));
    for (final p in group) {
      p.lanes = lanes;
    }
    group = [];
  }

  final laneEnds = <int>[];
  for (final p in timed) {
    if (p.top >= groupEnd) {
      close();
      laneEnds.clear();
    }
    var lane = laneEnds.indexWhere((end) => end <= p.top);
    if (lane < 0) lane = laneEnds.length;
    if (lane == laneEnds.length) {
      laneEnds.add(p.top + p.len);
    } else {
      laneEnds[lane] = p.top + p.len;
    }
    p.lane = lane;
    group.add(p);
    groupEnd = math.max(groupEnd, p.top + p.len);
  }
  close();
  return timed;
}

/// De un toque o suelta en una columna de horas a minutos desde medianoche, al cuarto de hora.
int? minutesAtY(double offsetY, double columnHeight) {
  if (!(columnHeight > 0)) return null;
  final raw = (offsetY.clamp(0, columnHeight)) / columnHeight * dayMinutes;
  return math.min((raw / 15).round() * 15, dayMinutes - 15);
}

// ---------- el rango que se ve ----------

/// Los 42 días (6 semanas, de lunes a domingo) que pinta el mes de [day].
List<DateTime> monthGridDays(DateTime day) {
  final first = DateTime(day.year, day.month, 1);
  final start = mondayOf(first);
  return [for (var i = 0; i < 42; i++) addDays(start, i)];
}

/// Los días que se pintan: 42 en el mes, 7 en la semana, 1 en el día.
List<DateTime> daysFor(CalendarMode mode, DateTime selected) => switch (mode) {
      CalendarMode.month => monthGridDays(selected),
      CalendarMode.week => [for (var i = 0; i < 7; i++) addDays(mondayOf(selected), i)],
      CalendarMode.day => [dateOnly(selected)],
    };

String _abbr(int month) => monthNames[month - 1].substring(0, 3).toLowerCase();

/// El título de lo que se ve: «Noviembre 2026», «2 – 8 nov 2026» o «Jueves 5 nov 2026».
String titleFor(CalendarMode mode, DateTime selected) {
  final d = dateOnly(selected);
  switch (mode) {
    case CalendarMode.month:
      return '${monthNames[d.month - 1]} ${d.year}';
    case CalendarMode.week:
      final a = mondayOf(d);
      final b = addDays(a, 6);
      return a.month == b.month ? '${a.day} – ${b.day} ${_abbr(b.month)} ${b.year}' : '${a.day} ${_abbr(a.month)} – ${b.day} ${_abbr(b.month)} ${b.year}';
    case CalendarMode.day:
      return '${weekdayNames[d.weekday - 1]} ${d.day} ${_abbr(d.month)} ${d.year}';
  }
}

/// El día elegido tras ir [delta] pasos hacia delante o atrás: un mes, una semana o un día.
DateTime stepSelected(CalendarMode mode, DateTime selected, int delta) {
  final d = dateOnly(selected);
  switch (mode) {
    case CalendarMode.month:
      final month = DateTime(d.year, d.month + delta, 1);
      final last = DateTime(month.year, month.month + 1, 0).day;
      return DateTime(month.year, month.month, math.min(d.day, last));
    case CalendarMode.week:
      return addDays(d, 7 * delta);
    case CalendarMode.day:
      return addDays(d, delta);
  }
}

/// La hora del día [day] a [minutes] desde medianoche, en la hora local (devuelta en UTC, como se guarda).
DateTime atMinutes(DateTime day, int minutes) => DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60).toUtc();
