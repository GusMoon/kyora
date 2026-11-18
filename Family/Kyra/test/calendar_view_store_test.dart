import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/calendar_view_store.dart';
import 'package:kyora_chat/util/agenda.dart' show CalendarMode;
import 'package:shared_preferences/shared_preferences.dart';

/// La vista con la que se abre el calendario (semana o mes), elegida en Configuración.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('en memoria', () {
    test('empieza en la semana y avisa al cambiar (y solo si cambia)', () async {
      final store = MemoryCalendarViewStore();
      var calls = 0;
      store.addListener(() => calls++);
      expect(store.mode, CalendarMode.week);
      await store.setMode(CalendarMode.week);
      expect(calls, 0);
      await store.setMode(CalendarMode.month);
      expect(store.mode, CalendarMode.month);
      expect(calls, 1);
    });
  });

  group('guardada en el teléfono', () {
    test('sin nada guardado es la semana', () async {
      final store = await PrefsCalendarViewStore.open();
      expect(store.mode, CalendarMode.week);
    });

    test('lo elegido se recuerda al volver a abrir', () async {
      final store = await PrefsCalendarViewStore.open();
      await store.setMode(CalendarMode.month);
      expect((await PrefsCalendarViewStore.open()).mode, CalendarMode.month);
      await store.setMode(CalendarMode.week);
      expect((await PrefsCalendarViewStore.open()).mode, CalendarMode.week);
    });

    test('se guarda con su clave y avisa a quien escucha', () async {
      final store = await PrefsCalendarViewStore.open();
      var calls = 0;
      store.addListener(() => calls++);
      await store.setMode(CalendarMode.month);
      expect((await SharedPreferences.getInstance()).getString('calendar.defaultView'), 'month');
      expect(calls, 1);
      await store.setMode(CalendarMode.month); // lo mismo: no avisa otra vez
      expect(calls, 1);
    });

    test('un valor raro guardado cae en la semana', () async {
      SharedPreferences.setMockInitialValues({'calendar.defaultView': 'day'}); // la vista Día ya no existe
      expect((await PrefsCalendarViewStore.open()).mode, CalendarMode.week);
      expect(PrefsCalendarViewStore.parse(null), CalendarMode.week);
      expect(PrefsCalendarViewStore.parse('basura'), CalendarMode.week);
      expect(PrefsCalendarViewStore.parse('month'), CalendarMode.month);
    });

    test('elegir la semana cuando nada estaba guardado también la guarda', () async {
      final store = await PrefsCalendarViewStore.open();
      await store.setMode(CalendarMode.week);
      expect((await SharedPreferences.getInstance()).getString('calendar.defaultView'), 'week');
    });
  });
}
