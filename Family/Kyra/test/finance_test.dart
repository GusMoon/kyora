import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/chat_backend.dart';
import 'package:kyora_chat/data/finance_store.dart';
import 'package:kyora_chat/models/finance.dart';
import 'package:kyora_chat/state/finance_controller.dart';
import 'package:kyora_chat/state/task_controller.dart' show SyncState;
import 'package:kyora_chat/util/finance.dart';

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

final _t0 = DateTime.utc(2026, 11, 13, 10);

FinanceCategory _cat(String id, String name, FinanceKind kind, [String color = '#9aa1ac']) =>
    FinanceCategory(id: id, name: name, kind: kind, color: color, createdAt: _t0, updatedAt: _t0);

FinanceEntry _entry(String id, FinanceKind kind, int cents, String? category, String day, {String currency = 'MXN', DateTime? at, DateTime? deleted}) => FinanceEntry(
  id: id,
  kind: kind,
  amountCents: cents,
  currency: currency,
  categoryId: category,
  occurredOn: day,
  createdAt: at ?? _t0,
  updatedAt: at ?? _t0,
  deletedAt: deleted,
);

void main() {
  group('importes (los mismos casos que en Merida)', () {
    test('lee lo que se escribe como centavos', () {
      expect(parseAmount('250'), 25000);
      expect(parseAmount('1,250.50'), 125050);
      expect(parseAmount('1.250,50'), 125050);
      expect(parseAmount('120,5'), 12050);
      expect(parseAmount('\$ 80'), 8000);
      expect(parseAmount('0.99'), 99);
      expect(parseAmount('1,250'), 125000); // coma de miles: no es decimal
      expect(parseAmount('12.345'), 1234500);
    });

    test('rechaza lo que no es un importe positivo', () {
      for (final bad in ['', 'abc', '0', '0.00', '-5', '−5', ',', '.']) {
        expect(parseAmount(bad), isNull, reason: '«$bad»');
      }
    });

    test('da formato de moneda con miles y dos decimales', () {
      expect(formatMoney(125050), '\$1,250.50');
      expect(formatMoney(125050, 'USD'), '\$1,250.50 USD');
      expect(formatMoney(100, 'EUR'), '1.00 €');
      expect(formatMoney(5, 'XXX'), '0.05 XXX'); // una moneda rara no rompe nada
      expect(formatMoney(123456789), '\$1,234,567.89');
      expect(formatMoney(-2500), '-\$25.00');
    });
  });

  group('meses y resumen', () {
    final sueldo = _cat('c-sueldo', 'Sueldo', FinanceKind.income);
    final comida = _cat('c-comida', 'Comida', FinanceKind.expense);
    final casa = _cat('c-casa', 'Casa', FinanceKind.expense);

    test('cambia de mes por clave', () {
      expect(monthOf('2026-11-13'), '2026-11');
      expect(shiftMonthKey('2026-11', 1), '2026-12');
      expect(shiftMonthKey('2026-12', 1), '2027-01');
      expect(shiftMonthKey('2026-01', -1), '2025-12');
      expect(monthLabel('2026-11'), 'noviembre de 2026');
      expect(todayKey(DateTime(2026, 3, 5)), '2026-03-05');
    });

    test('filtra por mes, sin los borrados, de lo más nuevo a lo más viejo', () {
      final all = [
        _entry('a', FinanceKind.expense, 100, null, '2026-11-02'),
        _entry('b', FinanceKind.expense, 100, null, '2026-11-20'),
        _entry('c', FinanceKind.expense, 100, null, '2026-10-30'),
        _entry('d', FinanceKind.income, 100, null, '2026-11-05', deleted: _t0),
      ];
      expect(entriesInMonth(all, '2026-11').map((e) => e.id), ['b', 'a']);
    });

    test('suma ingresos, gastos y balance, y reparte por categoría dentro de su tipo', () {
      final entries = [
        _entry('1', FinanceKind.income, 100000, sueldo.id, '2026-11-01'),
        _entry('2', FinanceKind.expense, 30000, comida.id, '2026-11-02'),
        _entry('3', FinanceKind.expense, 10000, comida.id, '2026-11-03'),
        _entry('4', FinanceKind.expense, 60000, casa.id, '2026-11-04'),
        _entry('5', FinanceKind.expense, 5000, null, '2026-11-05'),
      ];
      final s = summarize(entries, [sueldo, comida, casa]);
      expect((s.income, s.expense, s.balance, s.count), (100000, 105000, -5000, 5));
      // primero los gastos (de mayor a menor), luego los ingresos
      expect([for (final c in s.byCategory) (c.name, c.total)], [('Casa', 60000), ('Comida', 40000), ('Sin categoría', 5000), ('Sueldo', 100000)]);
      expect(s.byCategory[0].share, closeTo(60000 / 105000, 1e-9));
      expect(s.byCategory[3].share, 1);
    });

    test('sin movimientos todo es cero', () {
      final s = summarize(const [], const []);
      expect((s.income, s.expense, s.balance, s.count), (0, 0, 0, 0));
      expect(s.byCategory, isEmpty);
    });
  });

  group('el modelo', () {
    test('se guarda y se lee igual (con la fecha en «aaaa-mm-dd» y los centavos enteros)', () {
      final e = _entry('x', FinanceKind.expense, 12345, 'c1', '2026-11-13');
      final back = FinanceEntry.fromJson(e.toLocalJson());
      expect((back.id, back.kind, back.amountCents, back.currency, back.categoryId, back.occurredOn), ('x', FinanceKind.expense, 12345, 'MXN', 'c1', '2026-11-13'));
      expect(e.toJson().containsKey('dirty'), isFalse); // lo local no sube a Supabase
      // Supabase manda la fecha como «aaaa-mm-dd» y los centavos como número
      final fromServer = FinanceEntry.fromJson({
        'id': 'y',
        'kind': 'income',
        'amount_cents': 500,
        'currency': 'USD',
        'category_id': null,
        'description': 'Café',
        'occurred_on': '2026-11-13',
        'created_at': '2026-11-13T10:00:00+00:00',
        'updated_at': '2026-11-13T10:00:00+00:00',
        'deleted_at': null,
        'synced_at': '2026-11-13T10:00:01+00:00',
      });
      expect((fromServer.kind, fromServer.currency, fromServer.description), (FinanceKind.income, 'USD', 'Café'));
      expect(fromServer.syncedAt, isNotNull);
    });
  });

  group('el controlador', () {
    late FinanceController finance;
    late FakeRowBackend<FinanceEntry> entryServer;
    late FakeRowBackend<FinanceCategory> categoryServer;
    late MemoryFinanceEntryStore entryStore;
    late MemoryFinanceCategoryStore categoryStore;
    var now = DateTime.utc(2026, 11, 13, 10);
    var n = 0;

    FinanceController build() => FinanceController(
      FinanceCategories(categoryStore, categoryServer, now: () => now, retry: const Duration(hours: 1)),
      FinanceEntries(entryStore, entryServer, now: () => now, retry: const Duration(hours: 1)),
      newId: () => 'id${++n}',
      now: () => now,
    );

    setUp(() async {
      now = DateTime.utc(2026, 11, 13, 10);
      n = 0;
      entryServer = FakeRowBackend<FinanceEntry>(_stampEntry);
      categoryServer = FakeRowBackend<FinanceCategory>(_stampCategory);
      entryStore = MemoryFinanceEntryStore();
      categoryStore = MemoryFinanceCategoryStore();
      finance = build();
      await finance.start();
    });

    tearDown(() => finance.dispose());

    test('un movimiento nuevo lleva el día de hoy, la moneda activa y sube a Supabase', () async {
      final e = await finance.addEntry(kind: FinanceKind.expense, amountCents: 500, description: '  Café ');
      expect((e!.id, e.description, e.occurredOn, e.currency), ('id1', 'Café', '2026-11-13', 'MXN'));
      await Future<void>.delayed(Duration.zero);
      expect(entryServer.server.keys, ['id1']);
      expect(finance.entries.pending, 0);
      expect(finance.summaryOf('2026-11').expense, 500);
    });

    test('un importe en cero no crea nada', () async {
      expect(await finance.addEntry(kind: FinanceKind.expense, amountCents: 0), isNull);
      expect(finance.entries.items, isEmpty);
    });

    test('editar y borrar suben la hora de cambio aunque el reloj no se mueva, y el borrado llega a Supabase', () async {
      final e = (await finance.addEntry(kind: FinanceKind.expense, amountCents: 500))!;
      await finance.updateEntry(e, amountCents: 700, description: 'Nuevo');
      final edited = finance.entries.byId(e.id)!;
      expect(edited.amountCents, 700);
      expect(edited.updatedAt.isAfter(e.updatedAt), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(entryServer.server[e.id]!.amountCents, 700);
      await finance.deleteEntry(edited);
      expect(finance.entries.items, isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(entryServer.server[e.id]!.isDeleted, isTrue);
    });

    test('los movimientos de otra moneda no se suman: se cuentan aparte', () async {
      await finance.addEntry(kind: FinanceKind.income, amountCents: 10000);
      await finance.setCurrency('USD');
      await finance.addEntry(kind: FinanceKind.expense, amountCents: 300);
      expect(finance.summaryOf('2026-11').income, 0);
      expect(finance.summaryOf('2026-11').expense, 300);
      expect(finance.otherCurrencyCount('2026-11'), 1);
      await finance.setCurrency('XXX'); // una moneda que no está en la lista no vale
      expect(finance.currency, 'USD');
    });

    test('las categorías de siempre se crean una sola vez y no se repite un nombre dentro del mismo tipo', () async {
      expect(await finance.addDefaultCategories(), defaultFinanceCategories.length);
      expect(await finance.addDefaultCategories(), 0);
      expect(await finance.addCategory(' sueldo ', FinanceKind.income, '#c8f73a'), isNull); // ya existe (sin importar mayúsculas)
      expect(await finance.addCategory('Sueldo', FinanceKind.expense, '#c8f73a'), isNotNull); // en el otro tipo sí
      expect(await finance.addCategory('  ', FinanceKind.expense, '#c8f73a'), isNull);
      expect(finance.categoriesOf(FinanceKind.income).map((c) => c.name), ['Otros ingresos', 'Sueldo']);
    });

    test('borrar una categoría deja sus movimientos «sin categoría»', () async {
      final comida = (await finance.addCategory('Comida', FinanceKind.expense, '#ff5a1f'))!;
      final e = (await finance.addEntry(kind: FinanceKind.expense, amountCents: 900, categoryId: comida.id))!;
      await finance.deleteCategory(comida);
      expect(finance.categoriesOf(FinanceKind.expense), isEmpty);
      expect(finance.entries.byId(e.id)!.categoryId, isNull);
      expect(finance.summaryOf('2026-11').byCategory.single.name, 'Sin categoría');
      await Future<void>.delayed(Duration.zero);
      expect(categoryServer.server[comida.id]!.isDeleted, isTrue);
      expect(entryServer.server[e.id]!.categoryId, isNull);
    });

    test('sin conexión se queda guardado y sube al volver; lo que cambió en otro dispositivo se baja', () async {
      entryServer.failWith = const ChatException('Sin conexión con Supabase', retryable: true, code: 'offline');
      await finance.addEntry(kind: FinanceKind.expense, amountCents: 500);
      await Future<void>.delayed(Duration.zero);
      expect(finance.syncState, SyncState.offline);
      expect(finance.pending, 1);
      expect(entryStore.rows, hasLength(1)); // en el teléfono ya está
      entryServer.failWith = null;
      entryServer.remote(_entry('otro', FinanceKind.income, 9000, null, '2026-11-12', at: DateTime.utc(2026, 11, 13, 11)));
      await finance.sync();
      expect(finance.pending, 0);
      expect(finance.entries.items.map((e) => e.id).toSet(), {'id1', 'otro'});
      expect(finance.summaryOf('2026-11').income, 9000);
    });

    test('al reabrir (otra sesión sobre el mismo teléfono) todo sigue ahí', () async {
      final comida = (await finance.addCategory('Comida', FinanceKind.expense, '#ff5a1f'))!;
      await finance.addEntry(kind: FinanceKind.expense, amountCents: 900, categoryId: comida.id);
      final again = build();
      addTearDown(again.dispose);
      await again.start();
      expect(again.categories.items.single.name, 'Comida');
      expect(again.summaryOf('2026-11').expense, 900);
      expect(again.categoryById(comida.id)!.name, 'Comida');
    });
  });
}
