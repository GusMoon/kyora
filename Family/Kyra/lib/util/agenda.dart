import 'dart:math' as math;

import '../models/event.dart';
import '../models/habit.dart';
import '../models/reminder.dart';
import '../models/task.dart';
import 'format.dart' show weekdayLetters;

/// La lógica del calendario, sin pantalla (lo mismo que `agenda.ts` de Merida): mezcla eventos, entregas de tareas, recordatorios y hábitos por
/// día y calcula el rango que se ve. La pantalla solo lo dibuja.

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

/// La hora en 12 h, partida para la tarjeta: `(10, AM)`, `(12, PM)`, `(12, AM)`.
(String, String) hourParts(int minutes) {
  final h = (minutes ~/ 60) % 24;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return ('$h12', h < 12 ? 'AM' : 'PM');
}

/// La hora en 12 h con minutos: «6:05 PM».
String hourLabel12(int minutes) {
  final (h, ampm) = hourParts(minutes);
  return '$h:${(minutes % 60).toString().padLeft(2, '0')} $ampm';
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

/// Cómo se ve el calendario: la semana (los días apilados) o el mes (la cuadrícula de cuadros).
enum CalendarMode { week, month }

const calendarModeLabel = {CalendarMode.week: 'Semana', CalendarMode.month: 'Mes'};

/// Un evento de varios días se pinta unido de un día al siguiente.
enum Span { single, start, mid, end }

/// Todo lo que el calendario puede enseñar.
class AgendaData {
  const AgendaData({this.events = const [], this.tasks = const [], this.reminders = const [], this.habitsOn, this.habitDone, this.taskProgress});

  final List<CalendarEvent> events;

  /// Las tareas con entrega (las raíces, sin las subtareas).
  final List<TaskItem> tasks;
  final List<Reminder> reminders;

  /// Los hábitos que tocan ese día y si se cumplió uno ese día (lo sabe el controlador de hábitos).
  final List<Habit> Function(DateTime day)? habitsOn;
  final bool Function(Habit habit, DateTime day)? habitDone;

  /// Cuántas subtareas de una tarea están hechas (lo sabe el controlador de tareas); para el pie de su tarjeta.
  final ({int done, int total}) Function(TaskItem task)? taskProgress;
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
    this.subtitle = '',
    this.footer = '',
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

  /// La segunda línea de su tarjeta (la descripción del evento, las notas del recordatorio, lo que dice la tarea); vacía si no hay.
  final String subtitle;

  /// El pie de su tarjeta: «Todo el día», «2 de 3 subtareas», «L M V»…
  final String footer;
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

/// El pie de la tarjeta de una tarea: lo que lleva de sus subtareas, o solo «Tarea».
String taskFooter(({int done, int total})? progress) {
  if (progress == null || progress.total == 0) return 'Tarea';
  return '${progress.done} de ${progress.total} ${progress.total == 1 ? 'subtarea' : 'subtareas'}';
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
        subtitle: e.description.trim(),
        footer: span != Span.single ? 'Varios días' : (allDay ? 'Todo el día' : (end != null ? '${hourLabel12(start!)} – ${hourLabel12(end)}' : 'Evento')),
      ));
    }
  }
  if (want(AgendaKind.task)) {
    for (final t in data.tasks) {
      final due = t.due;
      if (due == null || t.isDeleted || dateOnly(due) != d) continue;
      final start = _minutesOf(due);
      out.add(AgendaItem(
        kind: AgendaKind.task,
        id: t.id,
        title: t.name,
        day: d,
        start: start,
        end: null,
        allDay: false,
        done: t.isDone,
        span: Span.single,
        time: minutesLabel(start),
        subtitle: t.description.trim(),
        footer: taskFooter(data.taskProgress?.call(t)),
      ));
    }
  }
  if (want(AgendaKind.reminder)) {
    for (final r in data.reminders) {
      if (r.isDeleted || dateOnly(r.at) != d) continue;
      final start = _minutesOf(r.at);
      out.add(AgendaItem(kind: AgendaKind.reminder, id: r.id, title: r.title, day: d, start: start, end: null, allDay: false, done: r.done, span: Span.single, time: minutesLabel(start), subtitle: r.notes.trim(), footer: 'Recordatorio'));
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
        footer: habitDaysLabel(h.weekdays),
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

// ---------- el rango que se ve ----------

/// Los 42 días (6 semanas, de lunes a domingo) que pinta el mes de [day].
List<DateTime> monthGridDays(DateTime day) {
  final first = DateTime(day.year, day.month, 1);
  final start = mondayOf(first);
  return [for (var i = 0; i < 42; i++) addDays(start, i)];
}

/// Los días que se pintan: 42 en el mes y 7 en la semana.
List<DateTime> daysFor(CalendarMode mode, DateTime selected) => switch (mode) {
      CalendarMode.month => monthGridDays(selected),
      CalendarMode.week => [for (var i = 0; i < 7; i++) addDays(mondayOf(selected), i)],
    };

String _abbr(int month) => monthNames[month - 1].substring(0, 3).toLowerCase();

/// El título de lo que se ve: «Noviembre 2026» o «2 – 8 nov 2026».
String titleFor(CalendarMode mode, DateTime selected) {
  final d = dateOnly(selected);
  switch (mode) {
    case CalendarMode.month:
      return '${monthNames[d.month - 1]} ${d.year}';
    case CalendarMode.week:
      final a = mondayOf(d);
      final b = addDays(a, 6);
      return a.month == b.month ? '${a.day} – ${b.day} ${_abbr(b.month)} ${b.year}' : '${a.day} ${_abbr(a.month)} – ${b.day} ${_abbr(b.month)} ${b.year}';
  }
}

/// El día elegido tras ir [delta] pasos hacia delante o atrás: un mes o una semana.
DateTime stepSelected(CalendarMode mode, DateTime selected, int delta) {
  final d = dateOnly(selected);
  switch (mode) {
    case CalendarMode.month:
      final month = DateTime(d.year, d.month + delta, 1);
      final last = DateTime(month.year, month.month + 1, 0).day;
      return DateTime(month.year, month.month, math.min(d.day, last));
    case CalendarMode.week:
      return addDays(d, 7 * delta);
  }
}

/// La hora del día [day] a [minutes] desde medianoche, en la hora local (devuelta en UTC, como se guarda).
DateTime atMinutes(DateTime day, int minutes) => DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60).toUtc();
