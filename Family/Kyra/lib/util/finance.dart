import '../models/finance.dart';

/// La lógica de las finanzas, la misma que la de Merida (`Family/Merida/src/data/finance.ts`).

/// Las monedas que se pueden elegir (las mismas que en Merida).
const financeCurrencies = ['MXN', 'USD', 'EUR', 'COP', 'ARS', 'CLP', 'PEN', 'GBP', 'CAD'];

/// Las categorías con las que se empieza (las mismas que en Merida): nombre, tipo y color.
const defaultFinanceCategories = <({String name, FinanceKind kind, String color})>[
  (name: 'Sueldo', kind: FinanceKind.income, color: '#c8f73a'),
  (name: 'Otros ingresos', kind: FinanceKind.income, color: '#35d4ff'),
  (name: 'Comida', kind: FinanceKind.expense, color: '#ff5a1f'),
  (name: 'Transporte', kind: FinanceKind.expense, color: '#ffd23f'),
  (name: 'Casa', kind: FinanceKind.expense, color: '#ff4fd8'),
  (name: 'Servicios', kind: FinanceKind.expense, color: '#35d4ff'),
  (name: 'Salud', kind: FinanceKind.expense, color: '#c9cebc'),
  (name: 'Ocio', kind: FinanceKind.expense, color: '#c8f73a'),
  (name: 'Otros gastos', kind: FinanceKind.expense, color: '#9aa1ac'),
];

/// Los colores para una categoría nueva.
const financeColors = ['#c8f73a', '#ff5a1f', '#35d4ff', '#ff4fd8', '#ffd23f', '#c9cebc', '#9aa1ac'];

/// «1,234.50», «1.234,50», «120,5», «\$ 80», «80» → centavos. `null` si no es un importe válido (o es 0 o negativo).
int? parseAmount(String text) {
  if (RegExp(r'^\s*[-−–]').hasMatch(text)) return null; // un importe negativo no vale: el tipo (ingreso o gasto) ya dice si suma o resta
  var t = text.replaceAll(RegExp(r'[^\d.,]'), '');
  if (t.isEmpty || !RegExp(r'\d').hasMatch(t)) return null;
  final lastDot = t.lastIndexOf('.');
  final lastComma = t.lastIndexOf(',');
  final sep = lastDot > lastComma ? lastDot : lastComma;
  var whole = t;
  var frac = '';
  if (sep >= 0) {
    final after = t.length - sep - 1;
    final other = lastDot > lastComma ? ',' : '.';
    final onlyOne = t.split(t[sep]).length == 2; // un solo separador de ese tipo
    // decimal si es el único de su tipo y detrás hay 1 o 2 cifras, o si el otro tipo ya aparece antes (1.234,50)
    if (after > 0 && after <= 2 && (onlyOne || t.contains(other))) {
      whole = t.substring(0, sep);
      frac = t.substring(sep + 1);
    }
  }
  t = whole.replaceAll(RegExp(r'[.,]'), '');
  if (t.isEmpty && frac.isEmpty) return null;
  final units = int.tryParse(t.isEmpty ? '0' : t);
  if (units == null) return null;
  final cents = units * 100 + int.parse(('${frac}00').substring(0, 2));
  return cents > 0 && cents < 9007199254740991 ? cents : null;
}

/// 123450 → «\$1,234.50» (o «1,234.50 EUR» con otra moneda). Sin `intl`: se arma a mano.
String formatMoney(int cents, [String currency = 'MXN']) {
  final negative = cents < 0;
  final abs = cents.abs();
  final whole = (abs ~/ 100).toString();
  final grouped = whole.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  final text = '$grouped.${(abs % 100).toString().padLeft(2, '0')}';
  final sign = negative ? '-' : '';
  return switch (currency) {
    'MXN' || 'USD' || 'COP' || 'ARS' || 'CLP' || 'CAD' => '$sign\$$text${currency == 'MXN' ? '' : ' $currency'}',
    'EUR' => '$sign$text €',
    'GBP' => '$sign£$text',
    _ => '$sign$text $currency',
  };
}

/// «aaaa-mm» del día «aaaa-mm-dd».
String monthOf(String day) => day.substring(0, 7);

/// El día de `now` como «aaaa-mm-dd».
String todayKey(DateTime now) => '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

/// El mes `delta` meses después (o antes) de «aaaa-mm».
String shiftMonthKey(String month, int delta) {
  final parts = month.split('-');
  final t = int.parse(parts[0]) * 12 + (int.parse(parts[1]) - 1) + delta;
  return '${(t ~/ 12).toString().padLeft(4, '0')}-${((t % 12) + 1).toString().padLeft(2, '0')}';
}

/// «noviembre de 2026» de «2026-11».
String monthLabel(String month) {
  const names = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
  final parts = month.split('-');
  return '${names[int.parse(parts[1]) - 1]} de ${parts[0]}';
}

/// Los movimientos de un mes, del más reciente al más antiguo.
List<FinanceEntry> entriesInMonth(Iterable<FinanceEntry> entries, String month) {
  final list = [
    for (final e in entries)
      if (!e.isDeleted && monthOf(e.occurredOn) == month) e,
  ];
  list.sort((a, b) {
    final byDay = b.occurredOn.compareTo(a.occurredOn);
    return byDay != 0 ? byDay : b.createdAt.compareTo(a.createdAt);
  });
  return list;
}

/// Lo que suma un tipo de movimiento en una categoría.
class CategoryTotal {
  CategoryTotal({required this.categoryId, required this.name, required this.color, required this.kind, this.total = 0, this.share = 0});

  final String? categoryId;
  final String name;
  final String color;
  final FinanceKind kind;
  int total;

  /// De 0 a 1 dentro de su tipo (ingresos o gastos).
  double share;
}

/// Ingresos, gastos, balance y desglose por categoría.
class MonthSummary {
  const MonthSummary({required this.income, required this.expense, required this.count, required this.byCategory});

  final int income;
  final int expense;
  final int count;
  final List<CategoryTotal> byCategory;

  int get balance => income - expense;
}

/// El resumen de los movimientos que se le pasen (ya filtrados por mes y moneda): primero los gastos, de más a menos, y luego los ingresos.
MonthSummary summarize(Iterable<FinanceEntry> entries, Iterable<FinanceCategory> categories) {
  final live = [
    for (final e in entries)
      if (!e.isDeleted) e,
  ];
  final byId = {for (final c in categories) c.id: c};
  var income = 0;
  var expense = 0;
  final totals = <String, CategoryTotal>{};
  for (final e in live) {
    if (e.kind == FinanceKind.income) {
      income += e.amountCents;
    } else {
      expense += e.amountCents;
    }
    final category = e.categoryId == null ? null : byId[e.categoryId];
    final key = '${e.kind.wire}:${e.categoryId ?? ''}';
    final row = totals.putIfAbsent(
      key,
      () => CategoryTotal(categoryId: category?.id, name: category?.name ?? 'Sin categoría', color: category?.color ?? '#9aa1ac', kind: e.kind),
    );
    row.total += e.amountCents;
  }
  final list = totals.values.toList()
    ..sort((a, b) {
      if (a.kind != b.kind) return a.kind == FinanceKind.expense ? -1 : 1;
      return b.total.compareTo(a.total);
    });
  for (final row in list) {
    final whole = row.kind == FinanceKind.income ? income : expense;
    row.share = whole == 0 ? 0 : row.total / whole;
  }
  return MonthSummary(income: income, expense: expense, count: live.length, byCategory: list);
}

/// «\$1,200 de ingresos y \$300 de gastos»: lo que se dice del mes.
String financeStatement(MonthSummary s, String currency) =>
    'Este mes: ${formatMoney(s.income, currency)} de ingresos, ${formatMoney(s.expense, currency)} de gastos; balance ${formatMoney(s.balance, currency)}.';

/// `#rrggbb` → un color de Flutter (`0xAARRGGBB`).
int colorValueOf(String hex) {
  final clean = hex.replaceFirst('#', '');
  return 0xFF000000 | (int.tryParse(clean.length == 6 ? clean : '9aa1ac', radix: 16) ?? 0x9aa1ac);
}
