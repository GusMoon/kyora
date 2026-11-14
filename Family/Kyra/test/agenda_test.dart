import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/models/event.dart';
import 'package:kyora_chat/models/habit.dart';
import 'package:kyora_chat/models/reminder.dart';
import 'package:kyora_chat/models/task.dart';
import 'package:kyora_chat/util/agenda.dart';

/// La lógica del calendario sin pantalla (la misma que `agenda.ts` de Merida).
void main() {
  final stamp = DateTime.utc(2026, 11, 1);

  CalendarEvent event(String id, String title, DateTime start, {DateTime? end, bool allDay = false, String color = '#35d4ff'}) =>
      CalendarEvent(id: id, title: title, startsAt: start.toUtc(), endsAt: end?.toUtc(), allDay: allDay, color: color, createdAt: stamp, updatedAt: stamp);

  Reminder reminder(String id, String title, DateTime at, {bool done = false}) => Reminder(id: id, notifId: 1, title: title, at: at.toUtc(), createdAt: stamp, done: done);

  TaskItem task(String id, String name, DateTime due, {TaskStatus status = TaskStatus.pending}) => TaskItem(id: id, name: name, due: due.toUtc(), status: status, createdAt: stamp, updatedAt: stamp);

  final habit = Habit(id: 'h1', name: 'Leer', weekdays: Habit.maskOf([4]), remindAt: 8 * 60 + 30, createdAt: stamp, updatedAt: stamp); // jueves
  final habitAllDay = Habit(id: 'h2', name: 'Agua', createdAt: stamp, updatedAt: stamp);

  final thursday = DateTime(2026, 11, 5);

  AgendaData data({List<CalendarEvent> events = const [], List<TaskItem> tasks = const [], List<Reminder> reminders = const [], Set<String> done = const {}}) => AgendaData(
        events: events,
        tasks: tasks,
        reminders: reminders,
        habitsOn: (day) => [for (final h in [habit, habitAllDay]) if (h.on(day.weekday)) h],
        habitDone: (h, day) => done.contains('${h.id}|${dayKey(day)}'),
      );

  group('agendaForDay', () {
    test('mezcla las cuatro clases de un día, con su hora, y las de todo el día primero', () {
      final d = data(
        events: [event('e1', 'Reunión', DateTime(2026, 11, 5, 10), end: DateTime(2026, 11, 5, 11)), event('e2', 'Cumple', DateTime(2026, 11, 5), allDay: true)],
        tasks: [task('t1', 'Informe', DateTime(2026, 11, 5, 18))],
        reminders: [reminder('r1', 'Llamar', DateTime(2026, 11, 5, 9))],
      );
      final items = agendaForDay(d, thursday);
      expect(items.map((i) => i.title), ['Cumple', 'Agua', 'Leer', 'Llamar', 'Reunión', 'Informe']);
      final meeting = items.firstWhere((i) => i.id == 'e1');
      expect((meeting.kind, meeting.start, meeting.end, meeting.time), (AgendaKind.event, 600, 660, '10:00–11:00'));
      expect(items.firstWhere((i) => i.id == 'e2').allDay, isTrue);
      expect(items.firstWhere((i) => i.id == 'h1').time, '08:30');
      expect(items.firstWhere((i) => i.id == 'h2').time, 'todo el día'); // sin aviso, un hábito va en la franja de todo el día
    });

    test('no mezcla días ni enseña lo borrado', () {
      final gone = CalendarEvent(id: 'e3', title: 'Borrado', startsAt: DateTime(2026, 11, 5, 9).toUtc(), createdAt: stamp, updatedAt: stamp, deletedAt: stamp);
      final d = data(events: [gone, event('e4', 'Mañana', DateTime(2026, 11, 6, 9))], reminders: [reminder('r2', 'Otro día', DateTime(2026, 11, 7, 9))]);
      final titles = agendaForDay(d, thursday).map((i) => i.title);
      expect(titles, isNot(contains('Borrado')));
      expect(titles, isNot(contains('Mañana')));
      expect(titles, isNot(contains('Otro día')));
    });

    test('el filtro deja solo las clases pedidas y la búsqueda ignora tildes y mayúsculas', () {
      final d = data(events: [event('e1', 'Reunión', DateTime(2026, 11, 5, 10))], reminders: [reminder('r1', 'Llamar', DateTime(2026, 11, 5, 9))]);
      expect(agendaForDay(d, thursday, kinds: {AgendaKind.reminder}).map((i) => i.id), ['r1']);
      expect(agendaForDay(d, thursday, kinds: {}).isEmpty, isTrue);
      expect(agendaForDay(d, thursday, query: 'REUNION').map((i) => i.id), ['e1']);
    });

    test('un evento de varios días sale unido: inicio, medio y fin, en la franja de todo el día', () {
      final d = data(events: [event('e1', 'Viaje', DateTime(2026, 11, 4, 9), end: DateTime(2026, 11, 6, 18))]);
      Span spanOn(int day) => agendaForDay(d, DateTime(2026, 11, day), kinds: {AgendaKind.event}).single.span;
      expect([spanOn(4), spanOn(5), spanOn(6)], [Span.start, Span.mid, Span.end]);
      expect(agendaForDay(d, DateTime(2026, 11, 5), kinds: {AgendaKind.event}).single.allDay, isTrue);
      expect(agendaForDay(d, DateTime(2026, 11, 3), kinds: {AgendaKind.event}), isEmpty);
      expect(agendaForDay(d, DateTime(2026, 11, 7), kinds: {AgendaKind.event}), isEmpty);
    });

    test('lo hecho lo dice: tareas finalizadas, recordatorios hechos y hábitos marcados', () {
      final d = data(
        tasks: [task('t1', 'Hecha', DateTime(2026, 11, 5, 9), status: TaskStatus.done)],
        reminders: [reminder('r1', 'Hecho', DateTime(2026, 11, 5, 9, 5), done: true)],
        done: {'h1|2026-11-05'},
      );
      final items = {for (final i in agendaForDay(d, thursday)) i.id: i.done};
      expect(items['t1'], isTrue);
      expect(items['r1'], isTrue);
      expect(items['h1'], isTrue);
      expect(items['h2'], isFalse);
    });

    test('un hábito solo sale los días que toca', () {
      final d = data();
      expect(agendaForDay(d, DateTime(2026, 11, 6)).map((i) => i.id), ['h2']); // viernes
    });
  });

  group('layoutDay', () {
    AgendaItem at(String id, int start, {int? end, AgendaKind kind = AgendaKind.event}) =>
        AgendaItem(kind: kind, id: id, title: id, day: thursday, start: start, end: end, allDay: false, done: false, span: Span.single, time: '');

    test('lo que no se solapa va cada uno en su carril único', () {
      final placed = layoutDay([at('a', 540, end: 600), at('b', 660, end: 720)]);
      expect(placed.map((p) => (p.lane, p.lanes)), [(0, 1), (0, 1)]);
    });

    test('lo que se solapa va en carriles uno junto a otro', () {
      final placed = layoutDay([at('a', 540, end: 660), at('b', 600, end: 720), at('c', 610, end: 630)]);
      expect(placed.every((p) => p.lanes == 3), isTrue);
      expect(placed.map((p) => p.lane).toSet(), {0, 1, 2});
    });

    test('lo de todo el día o sin hora no entra en la columna, y el alto mínimo es media hora', () {
      final allDay = AgendaItem(kind: AgendaKind.event, id: 'z', title: 'z', day: thursday, start: null, end: null, allDay: true, done: false, span: Span.single, time: '');
      final placed = layoutDay([allDay, at('r', 600, kind: AgendaKind.reminder), at('e', 700)]);
      expect(placed.map((p) => p.item.id), ['r', 'e']);
      expect(placed[0].len, 30); // un recordatorio sin fin
      expect(placed[1].len, 60); // un evento sin fin
    });

    test('al final del día no se sale de las 24 h', () {
      final placed = layoutDay([at('n', 23 * 60 + 50, end: 23 * 60 + 59)]);
      expect(placed.single.top + placed.single.len, lessThanOrEqualTo(dayMinutes));
    });
  });

  group('el rango que se ve', () {
    test('minutesAtY da el cuarto de hora más cercano y no se sale del día', () {
      expect(minutesAtY(0, 1440), 0);
      expect(minutesAtY(720, 1440), 720);
      expect(minutesAtY(728, 1440), 735); // 12:08 → 12:15
      expect(minutesAtY(5000, 1440), 1425);
      expect(minutesAtY(10, 0), isNull);
    });

    test('el mes son 42 días de lunes a domingo; la semana, 7; el día, 1', () {
      final month = daysFor(CalendarMode.month, DateTime(2026, 11, 5));
      expect(month.length, 42);
      expect(month.first, DateTime(2026, 10, 26)); // el 1 de noviembre de 2026 es domingo: la rejilla empieza el lunes anterior
      expect(month.first.weekday, DateTime.monday);
      expect(month.last, DateTime(2026, 12, 6));
      final week = daysFor(CalendarMode.week, DateTime(2026, 11, 5));
      expect((week.first, week.last), (DateTime(2026, 11, 2), DateTime(2026, 11, 8)));
      expect(daysFor(CalendarMode.day, DateTime(2026, 11, 5, 18)), [DateTime(2026, 11, 5)]);
    });

    test('los títulos', () {
      expect(titleFor(CalendarMode.month, thursday), 'Noviembre 2026');
      expect(titleFor(CalendarMode.week, thursday), '2 – 8 nov 2026');
      expect(titleFor(CalendarMode.week, DateTime(2026, 11, 30)), '30 nov – 6 dic 2026');
      expect(titleFor(CalendarMode.day, thursday), 'Jueves 5 nov 2026');
    });

    test('ir adelante y atrás: un mes (sin pasarse de los días que tiene), una semana o un día', () {
      expect(stepSelected(CalendarMode.month, DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(stepSelected(CalendarMode.month, thursday, -1), DateTime(2026, 10, 5));
      expect(stepSelected(CalendarMode.week, thursday, 1), DateTime(2026, 11, 12));
      expect(stepSelected(CalendarMode.day, DateTime(2026, 12, 31), 1), DateTime(2027, 1, 1));
    });

    test('la semana ISO', () {
      expect(isoWeek(DateTime(2026, 11, 5)), 45);
      expect(isoWeek(DateTime(2026, 1, 1)), 1);
      expect(isoWeek(DateTime(2027, 1, 1)), 53); // el viernes 1 de enero de 2027 aún es de la última semana de 2026
    });
  });

  test('un color `#rrggbb` se lee, y uno raro cae en el primero de los eventos', () {
    expect(colorValue('#ff5a1f'), 0xFFFF5A1F);
    expect(colorValue('nada'), 0xFF35D4FF);
    expect(colorValue(null), 0xFF35D4FF);
  });

  test('atMinutes pone la hora local del día y la devuelve en UTC', () {
    final t = atMinutes(DateTime(2026, 11, 5), 14 * 60 + 15);
    expect(t.isUtc, isTrue);
    expect(t.toLocal(), DateTime(2026, 11, 5, 14, 15));
  });
}
