import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/finance.dart';
import '../util/finance.dart';
import 'row_controller.dart';
import 'task_controller.dart' show SyncState;

/// Los movimientos (ingresos y gastos): se guardan en el teléfono y se sincronizan con Supabase (ver [RowController]).
class FinanceEntries extends RowController<FinanceEntry> {
  FinanceEntries(super.store, super.backend, {super.now, super.retry});

  List<FinanceEntry> get items => rows;

  FinanceEntry? byId(String id) => rowById(id);

  Future<void> save(List<FinanceEntry> changes) => put(changes);

  /// Una hora de cambio siempre mayor que la anterior de esa fila.
  DateTime nextStampOf(DateTime? previous) => stamp(previous);
}

/// Las categorías de los movimientos.
class FinanceCategories extends RowController<FinanceCategory> {
  FinanceCategories(super.store, super.backend, {super.now, super.retry});

  List<FinanceCategory> get items => rows;

  FinanceCategory? byId(String id) => rowById(id);

  Future<void> save(List<FinanceCategory> changes) => put(changes);

  DateTime nextStampOf(DateTime? previous) => stamp(previous);
}

/// Las finanzas, como en Merida: **categorías** y **movimientos** (ingresos y gastos) por mes. Va por encima de dos [RowController]: los dos se
/// guardan en el teléfono y se sincronizan con Supabase (tablas `finance_categories` y `finance_entries`). Las categorías suben antes que los
/// movimientos, que dependen de ellas.
class FinanceController extends ChangeNotifier {
  FinanceController(this.categories, this.entries, {String Function()? newId, DateTime Function()? now, String currency = 'MXN', this.persistCurrency})
    : _newId = newId ?? (() => const Uuid().v4()),
      _now = now ?? (() => DateTime.now().toUtc()),
      _currency = currency {  // ignore: prefer_initializing_formals
    categories.addListener(_changed);
    entries.addListener(_changed);
  }

  final FinanceCategories categories;
  final FinanceEntries entries;

  /// Recuerda la moneda elegida en el teléfono (sin esto, solo vale mientras la pantalla siga abierta).
  final Future<void> Function(String currency)? persistCurrency;
  final String Function() _newId;
  final DateTime Function() _now;
  String _currency;

  /// La moneda con la que se suma (cada movimiento guarda la suya; los de otra moneda no se suman, se cuentan aparte).
  String get currency => _currency;

  bool get loaded => categories.loaded && entries.loaded;
  SyncState get syncState => categories.syncState != SyncState.idle ? categories.syncState : entries.syncState;
  String? get syncError => categories.syncError ?? entries.syncError;
  int get pending => categories.pending + entries.pending;

  void _changed() => notifyListeners();

  Future<void> start() async {
    await categories.start();
    await entries.start();
  }

  /// Sube lo pendiente y baja las novedades: primero las categorías y después los movimientos.
  Future<void> sync() async {
    await categories.sync();
    await entries.sync();
  }

  Future<void> setCurrency(String value) async {
    if (!financeCurrencies.contains(value) || value == _currency) return;
    _currency = value;
    notifyListeners();
    await persistCurrency?.call(value);
  }

  // ---------- lo que se ve ----------

  /// Las categorías de un tipo, por nombre.
  List<FinanceCategory> categoriesOf(FinanceKind kind) =>
      categories.items.where((c) => c.kind == kind).toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  FinanceCategory? categoryById(String? id) => id == null ? null : categories.byId(id);

  /// Los movimientos de un mes (de todas las monedas), del más reciente al más antiguo.
  List<FinanceEntry> monthEntries(String month) => entriesInMonth(entries.items, month);

  /// Los movimientos de un mes en la moneda activa y el resumen de ellos.
  MonthSummary summaryOf(String month) => summarize(monthEntries(month).where((e) => e.currency == _currency), categories.items);

  /// Cuántos movimientos de ese mes están en otra moneda (no se suman).
  int otherCurrencyCount(String month) => monthEntries(month).where((e) => e.currency != _currency).length;

  // ---------- movimientos ----------

  /// Un movimiento nuevo. Un importe inválido (o 0) no crea nada.
  Future<FinanceEntry?> addEntry({
    required FinanceKind kind,
    required int amountCents,
    String? categoryId,
    String description = '',
    String? occurredOn,
  }) async {
    if (amountCents <= 0) return null;
    final t = _now();
    final entry = FinanceEntry(
      id: _newId(),
      kind: kind,
      amountCents: amountCents,
      currency: _currency,
      categoryId: categoryId,
      description: description.trim(),
      occurredOn: occurredOn ?? todayKey(t.toLocal()),
      createdAt: t,
      updatedAt: t,
    );
    await entries.save([entry]);
    return entry;
  }

  Future<void> updateEntry(
    FinanceEntry entry, {
    FinanceKind? kind,
    int? amountCents,
    Object? categoryId = _unchanged,
    String? description,
    String? occurredOn,
  }) async {
    final current = entries.byId(entry.id) ?? entry;
    if (amountCents != null && amountCents <= 0) return;
    final next = current.copyWith(
      kind: kind,
      amountCents: amountCents,
      categoryId: identical(categoryId, _unchanged) ? current.categoryId : categoryId as String?,
      description: description?.trim(),
      occurredOn: occurredOn,
      updatedAt: entries.nextStampOf(current.updatedAt),
    );
    await entries.save([next]);
  }

  /// Borra el movimiento (borrado suave: llega también a Supabase y a los demás dispositivos).
  Future<void> deleteEntry(FinanceEntry entry) async {
    final current = entries.byId(entry.id) ?? entry;
    await entries.save([current.copyWith(deletedAt: _now(), updatedAt: entries.nextStampOf(current.updatedAt))]);
  }

  // ---------- categorías ----------

  /// Una categoría nueva. Un nombre vacío, o uno que ya existe en ese tipo, no crea nada.
  Future<FinanceCategory?> addCategory(String name, FinanceKind kind, String color) async {
    final clean = name.trim();
    if (clean.isEmpty) return null;
    if (categoriesOf(kind).any((c) => c.name.toLowerCase() == clean.toLowerCase())) return null;
    final t = _now();
    final category = FinanceCategory(id: _newId(), name: clean, kind: kind, color: color, createdAt: t, updatedAt: t);
    await categories.save([category]);
    return category;
  }

  /// Pone las categorías de siempre (las que aún no existan). Devuelve cuántas creó.
  Future<int> addDefaultCategories() async {
    final t = _now();
    final fresh = <FinanceCategory>[
      for (final d in defaultFinanceCategories)
        if (!categoriesOf(d.kind).any((c) => c.name.toLowerCase() == d.name.toLowerCase()))
          FinanceCategory(id: _newId(), name: d.name, kind: d.kind, color: d.color, createdAt: t, updatedAt: t),
    ];
    if (fresh.isNotEmpty) await categories.save(fresh);
    return fresh.length;
  }

  /// Borra una categoría: sus movimientos se quedan «sin categoría».
  Future<void> deleteCategory(FinanceCategory category) async {
    final current = categories.byId(category.id) ?? category;
    final orphans = [
      for (final e in entries.items)
        if (e.categoryId == category.id) e.copyWith(categoryId: null, updatedAt: entries.nextStampOf(e.updatedAt)),
    ];
    // primero se sueltan los movimientos (así nunca apuntan a una categoría que ya no está) y después se borra la categoría
    if (orphans.isNotEmpty) await entries.save(orphans);
    await categories.save([current.copyWith(deletedAt: _now(), updatedAt: categories.nextStampOf(current.updatedAt))]);
  }

  @override
  void dispose() {
    categories.removeListener(_changed);
    entries.removeListener(_changed);
    categories.dispose();
    entries.dispose();
    super.dispose();
  }
}

const _unchanged = Object();
