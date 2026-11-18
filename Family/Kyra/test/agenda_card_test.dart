import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/widgets/agenda_card.dart';
import 'package:kyora_chat/util/agenda.dart';

/// La tarjeta de la agenda: bloque de color con la hora a la izquierda y, a la derecha, título, subtítulo, línea y pie.
void main() {
  AgendaItem item({int? start = 10 * 60, bool allDay = false, bool done = false, String subtitle = '', String footer = '', AgendaKind kind = AgendaKind.event, String title = 'Reunión de desarrollo'}) => AgendaItem(
        kind: kind,
        id: 'x',
        title: title,
        day: DateTime(2026, 12, 9),
        start: start,
        end: null,
        allDay: allDay,
        done: done,
        span: Span.single,
        time: '',
        subtitle: subtitle,
        footer: footer,
      );

  Future<void> show(WidgetTester tester, AgendaCard card, {double width = 380}) async {
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: Center(child: SizedBox(width: width, child: card)))));
    await tester.pump();
  }

  Finder inBlock(String text, {String kind = 'event'}) => find.descendant(of: find.byKey(Key('card-time-$kind-x')), matching: find.text(text));

  testWidgets('el bloque de la izquierda lleva la hora en 12 h y, debajo, la fecha', (tester) async {
    await show(tester, AgendaCard(item: item(), color: const Color(0xFFFF5A1F)));
    expect(inBlock('10'), findsOneWidget);
    expect(inBlock('AM'), findsOneWidget);
    expect(find.text('9 DIC'), findsOneWidget);
    final block = tester.widget<ColoredBox>(find.byKey(const Key('card-time-event-x')));
    expect(block.color, const Color(0xFFFF5A1F)); // el color de su clase
    // el bloque va a la izquierda de lo demás
    expect(tester.getRect(find.byKey(const Key('card-time-event-x'))).right, lessThan(tester.getRect(find.text('Reunión de desarrollo')).left));
    expect(tester.getSize(find.byKey(const Key('card-time-event-x'))).width, AgendaCard.blockWidth);
  });

  testWidgets('la tarde sale en PM, y el mediodía y la medianoche en 12', (tester) async {
    await show(tester, AgendaCard(item: item(start: 18 * 60 + 30), color: Colors.blue));
    expect(inBlock('6'), findsOneWidget);
    expect(inBlock('PM'), findsOneWidget);
    await show(tester, AgendaCard(item: item(start: 0), color: Colors.blue));
    expect(inBlock('12'), findsOneWidget);
    expect(inBlock('AM'), findsOneWidget);
  });

  testWidgets('lo de todo el día o sin hora dice TODO DÍA en el bloque', (tester) async {
    await show(tester, AgendaCard(item: item(start: null, allDay: true), color: Colors.blue));
    expect(inBlock('TODO'), findsOneWidget);
    expect(inBlock('DÍA'), findsOneWidget);
    expect(inBlock('AM'), findsNothing);
  });

  testWidgets('título, subtítulo y pie con su icono; la flecha ›; y sin subtítulo no queda hueco', (tester) async {
    await show(tester, AgendaCard(item: item(subtitle: 'Fecha de lanzamiento de la app', footer: '2 de 3 subtareas', kind: AgendaKind.task), color: Colors.blue));
    expect(find.text('Reunión de desarrollo'), findsOneWidget);
    expect(find.text('Fecha de lanzamiento de la app'), findsOneWidget);
    expect(find.text('2 de 3 subtareas'), findsOneWidget);
    expect(find.byIcon(Icons.check_box_outlined), findsOneWidget); // el icono de la tarea
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    // título arriba, subtítulo debajo y el pie al final
    final title = tester.getRect(find.text('Reunión de desarrollo')).top;
    final sub = tester.getRect(find.text('Fecha de lanzamiento de la app')).top;
    final foot = tester.getRect(find.text('2 de 3 subtareas')).top;
    expect(title, lessThan(sub));
    expect(sub, lessThan(foot));
    await show(tester, AgendaCard(item: item(footer: 'Evento'), color: Colors.blue));
    expect(find.byKey(const Key('card-subtitle-event-x')), findsNothing);
  });

  testWidgets('sin pie, dice la clase (Evento, Tarea, Recordatorio, Hábito)', (tester) async {
    for (final k in AgendaKind.values) {
      await show(tester, AgendaCard(item: item(kind: k), color: Colors.blue));
      expect(find.text(agendaKindLabel[k]!), findsOneWidget, reason: k.name);
      expect(find.byIcon(agendaKindIcon(k)), findsOneWidget, reason: k.name);
    }
  });

  testWidgets('lo hecho va tachado y atenuado', (tester) async {
    await show(tester, AgendaCard(item: item(done: true), color: Colors.blue));
    final style = tester.widget<Text>(find.text('Reunión de desarrollo')).style!;
    expect(style.decoration, TextDecoration.lineThrough);
    final c = tester.element(find.byType(AgendaCard)).colors;
    expect(style.color, c.dim);
  });

  testWidgets('lo vencido lleva el bloque en el color de aviso', (tester) async {
    await show(tester, AgendaCard(item: item(), color: Colors.blue, overdue: true));
    final c = tester.element(find.byType(AgendaCard)).colors;
    expect(tester.widget<ColoredBox>(find.byKey(const Key('card-time-event-x'))).color, c.warn);
  });

  testWidgets('la casilla se puede tocar sin abrir la tarjeta; tocar la tarjeta la abre; los eventos no llevan casilla', (tester) async {
    var opened = 0;
    var toggled = 0;
    await show(tester, AgendaCard(item: item(kind: AgendaKind.task), color: Colors.blue, onTap: () => opened++, check: SquareCheck(done: false, onTap: () => toggled++)));
    await tester.tap(find.byType(SquareCheck));
    expect((toggled, opened), (1, 0));
    await tester.tap(find.text('Reunión de desarrollo'));
    expect((toggled, opened), (1, 1));
    await show(tester, AgendaCard(item: item(), color: Colors.blue));
    expect(find.byType(SquareCheck), findsNothing);
  });

  testWidgets('el título largo se corta y no desborda; sin esquinas redondeadas', (tester) async {
    await show(tester, AgendaCard(item: item(title: 'Un título larguísimo ' * 12, subtitle: 'Y un subtítulo también muy largo ' * 8, footer: 'Todo el día'), color: Colors.blue), width: 320);
    expect(tester.takeException(), isNull);
    expect(find.byWidgetPredicate((w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).borderRadius != null), findsNothing);
    expect(find.byType(ClipRRect), findsNothing);
  });
}
