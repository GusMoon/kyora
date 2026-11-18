import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/ui/widgets/flat_form.dart';
import 'package:kyora_chat/ui/widgets/cyber_panel.dart';
import 'package:kyora_chat/data/finance_store.dart';
import 'package:kyora_chat/models/finance.dart';
import 'package:kyora_chat/state/finance_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/finance_page.dart';

import 'calendar_sync_test.dart' show FakeRowBackend;

FinanceEntry _stampEntry(FinanceEntry e, String at) => FinanceEntry(
  id: e.id,
  kind: e.kind,
  amountCents: e.amountCents,
  currency: e.currency,
  categoryId: e.categoryId,
  description: e.description,
  occurredOn: e.occurredOn,
  createdAt: e.createdAt,
  updatedAt: e.updatedAt,
  deletedAt: e.deletedAt,
  syncedAt: at,
);

FinanceCategory _stampCategory(FinanceCategory c, String at) =>
    FinanceCategory(id: c.id, name: c.name, kind: c.kind, color: c.color, createdAt: c.createdAt, updatedAt: c.updatedAt, deletedAt: c.deletedAt, syncedAt: at);

/// La pantalla de Finanzas con un reloj fijo (14 de noviembre de 2026) y Supabase de mentira.
void main() {
  late FinanceController finance;
  late FakeRowBackend<FinanceEntry> entryServer;
  late FakeRowBackend<FinanceCategory> categoryServer;
  var n = 0;
  final now = DateTime.utc(2026, 11, 14, 12);

  setUp(() async {
    n = 0;
    entryServer = FakeRowBackend<FinanceEntry>(_stampEntry);
    categoryServer = FakeRowBackend<FinanceCategory>(_stampCategory);
    finance = FinanceController(
      FinanceCategories(MemoryFinanceCategoryStore(), categoryServer, now: () => now, retry: const Duration(hours: 1)),
      FinanceEntries(MemoryFinanceEntryStore(), entryServer, now: () => now, retry: const Duration(hours: 1)),
      newId: () => 'id${++n}',
      now: () => now,
    );
    await finance.start();
  });

  tearDown(() => finance.dispose());

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: FinancePage(controller: finance, now: () => now)));
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
  }

  String text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

  testWidgets('la pantalla es plana: cabecera con línea fina y sin paneles', (tester) async {
    await open(tester);
    // el estilo plano de la ficha de una tarea y del clima: cabecera «> TÍTULO» con una línea fina, sin paneles ni cajas
    expect(find.byType(FlatHeader), findsOneWidget);
    expect(find.byKey(const Key('flat-backdrop')), findsOneWidget); // el fondo va un poco oscurecido
    expect(find.byType(CyberPanel), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(SegmentedButton<Object>), findsNothing);
  });

  testWidgets('el mes vacío lo dice, con todo en cero, y se puede cambiar de mes', (tester) async {
    await open(tester);
    expect(text(tester, 'fin-month'), 'noviembre de 2026');
    expect(find.byKey(const Key('fin-empty')), findsOneWidget);
    expect(text(tester, 'fin-income-value'), '\$0.00');
    expect(find.byKey(const Key('fin-today')), findsNothing); // ya es el mes de hoy
    await tester.tap(find.byKey(const Key('fin-prev')));
    await tester.pumpAndSettle();
    expect(text(tester, 'fin-month'), 'octubre de 2026');
    expect(find.byKey(const Key('fin-today')), findsOneWidget);
    await tester.tap(find.byKey(const Key('fin-today')));
    await tester.pumpAndSettle();
    expect(text(tester, 'fin-month'), 'noviembre de 2026');
    await tester.tap(find.byKey(const Key('fin-next')));
    await tester.pumpAndSettle();
    expect(text(tester, 'fin-month'), 'diciembre de 2026');
  });

  testWidgets('«+» anota un gasto: aparece en la lista, entra en el resumen y sube a Supabase', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('fin-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fin-save'))); // sin importe
    await tester.pumpAndSettle();
    expect(find.text('Escribe un importe mayor que cero.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('fin-amount')), '1,250.50');
    await tester.enterText(find.byKey(const Key('fin-description')), 'Tacos');
    await tester.tap(find.byKey(const Key('fin-save')));
    await settle(tester);
    expect(find.byKey(const Key('fin-entry-id1')), findsOneWidget);
    expect(find.text('Tacos'), findsOneWidget);
    expect(find.text('-\$1,250.50'), findsWidgets);
    expect(text(tester, 'fin-expense-value'), '\$1,250.50');
    expect(text(tester, 'fin-balance-value'), '-\$1,250.50');
    expect(entryServer.server.keys, ['id1']);
    expect(finance.entries.byId('id1')!.occurredOn, '2026-11-14'); // hoy
  });

  testWidgets('un ingreso suma, el balance resta y el desglose reparte por categoría', (tester) async {
    final sueldo = (await finance.addCategory('Sueldo', FinanceKind.income, '#c8f73a'))!;
    final comida = (await finance.addCategory('Comida', FinanceKind.expense, '#ff5a1f'))!;
    await finance.addEntry(kind: FinanceKind.income, amountCents: 100000, categoryId: sueldo.id, occurredOn: '2026-11-01');
    await finance.addEntry(kind: FinanceKind.expense, amountCents: 30000, categoryId: comida.id, occurredOn: '2026-11-02');
    await finance.addEntry(kind: FinanceKind.expense, amountCents: 5000, occurredOn: '2026-11-03');
    await open(tester);
    expect(text(tester, 'fin-income-value'), '\$1,000.00');
    expect(text(tester, 'fin-expense-value'), '\$350.00');
    expect(text(tester, 'fin-balance-value'), '\$650.00');
    expect(find.byKey(Key('fin-cat-expense-${comida.id}')), findsOneWidget);
    expect(find.byKey(Key('fin-cat-income-${sueldo.id}')), findsOneWidget);
    expect(find.byKey(const Key('fin-cat-expense-none')), findsOneWidget); // «Sin categoría»
    // los movimientos de otro mes no cuentan
    await finance.addEntry(kind: FinanceKind.expense, amountCents: 99900, occurredOn: '2026-10-30');
    await tester.pumpAndSettle();
    expect(text(tester, 'fin-expense-value'), '\$350.00');
  });

  testWidgets('los filtros y el buscador acotan la lista', (tester) async {
    final comida = (await finance.addCategory('Comida', FinanceKind.expense, '#ff5a1f'))!;
    await finance.addEntry(kind: FinanceKind.income, amountCents: 100000, description: 'Quincena', occurredOn: '2026-11-01');
    await finance.addEntry(kind: FinanceKind.expense, amountCents: 3000, categoryId: comida.id, description: 'Tacos', occurredOn: '2026-11-02');
    await finance.addEntry(kind: FinanceKind.expense, amountCents: 8000, description: 'Taxi', occurredOn: '2026-11-03');
    await open(tester);
    expect(find.byKey(const Key('fin-entry-id3')), findsOneWidget);
    expect(find.byKey(const Key('fin-entry-id4')), findsOneWidget);
    await tester.tap(find.byKey(const Key('fin-filter-income')));
    await tester.pumpAndSettle();
    expect(find.text('Quincena'), findsOneWidget);
    expect(find.text('Tacos'), findsNothing);
    await tester.tap(find.byKey(const Key('fin-filter-expense')));
    await tester.pumpAndSettle();
    expect(find.text('Quincena'), findsNothing);
    expect(find.text('Taxi'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('fin-search')), 'comida'); // por la categoría
    await tester.pumpAndSettle();
    expect(find.text('Tacos'), findsOneWidget);
    expect(find.text('Taxi'), findsNothing);
    await tester.enterText(find.byKey(const Key('fin-search')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fin-empty')), findsOneWidget);
    expect(find.text('Ningún movimiento coincide.'), findsOneWidget);
  });

  testWidgets('tocar un movimiento lo edita y el editor también lo borra', (tester) async {
    await finance.addEntry(kind: FinanceKind.expense, amountCents: 3000, description: 'Tacos', occurredOn: '2026-11-02');
    await open(tester);
    await tester.tap(find.byKey(const Key('fin-entry-id1')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('fin-amount'))).controller!.text, '30.00');
    await tester.enterText(find.byKey(const Key('fin-amount')), '45');
    await tester.enterText(find.byKey(const Key('fin-description')), 'Cena');
    await tester.tap(find.byKey(const Key('fin-save')));
    await settle(tester);
    expect(find.text('Cena'), findsOneWidget);
    expect(text(tester, 'fin-expense-value'), '\$45.00');
    await tester.tap(find.byKey(const Key('fin-entry-id1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fin-delete')));
    await settle(tester);
    expect(find.byKey(const Key('fin-entry-id1')), findsNothing);
    expect(find.byKey(const Key('fin-empty')), findsOneWidget);
    expect(entryServer.server['id1']!.isDeleted, isTrue);
  });

  testWidgets('el editor ofrece las categorías del tipo elegido', (tester) async {
    await finance.addCategory('Comida', FinanceKind.expense, '#ff5a1f');
    await finance.addCategory('Sueldo', FinanceKind.income, '#c8f73a');
    await open(tester);
    await tester.tap(find.byKey(const Key('fin-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fin-category')));
    await tester.pumpAndSettle();
    expect(find.text('Comida'), findsWidgets);
    expect(find.text('Sueldo'), findsNothing); // es de ingresos y se está anotando un gasto
  });

  testWidgets('la moneda se elige arriba y los movimientos de otra moneda se avisan aparte', (tester) async {
    await finance.addEntry(kind: FinanceKind.expense, amountCents: 3000, occurredOn: '2026-11-02');
    await open(tester);
    await tester.tap(find.byKey(const Key('fin-currency')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fin-currency-USD')));
    await tester.pumpAndSettle();
    expect(finance.currency, 'USD');
    expect(text(tester, 'fin-expense-value'), '\$0.00 USD');
    expect(find.byKey(const Key('fin-other-currency')), findsOneWidget);
  });

  testWidgets('las categorías: crear las básicas, añadir una propia y borrarla (los movimientos quedan sin categoría)', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('fin-categories')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fin-no-categories')), findsOneWidget);
    await tester.tap(find.byKey(const Key('fin-seed')));
    await settle(tester);
    expect(finance.categories.items, hasLength(9));
    expect(find.byKey(const Key('fin-no-categories')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('fin-cat-name'))); // el panel se desplaza: con nueve categorías el formulario queda abajo
    await tester.enterText(find.byKey(const Key('fin-cat-name')), 'Mascotas');
    await tester.ensureVisible(find.byKey(const Key('fin-color-#35d4ff')));
    await tester.tap(find.byKey(const Key('fin-color-#35d4ff')));
    await tester.ensureVisible(find.byKey(const Key('fin-cat-add')));
    await tester.tap(find.byKey(const Key('fin-cat-add')));
    await settle(tester);
    final mascotas = finance.categoriesOf(FinanceKind.expense).firstWhere((c) => c.name == 'Mascotas');
    expect(mascotas.color, '#35d4ff');
    await finance.addEntry(kind: FinanceKind.expense, amountCents: 700, categoryId: mascotas.id);
    await tester.ensureVisible(find.byKey(Key('fin-cat-del-${mascotas.id}')));
    await tester.tap(find.byKey(Key('fin-cat-del-${mascotas.id}')));
    await settle(tester);
    expect(finance.categoriesOf(FinanceKind.expense).any((c) => c.name == 'Mascotas'), isFalse);
    expect(finance.entries.items.single.categoryId, isNull);
  });
}
