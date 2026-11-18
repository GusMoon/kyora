import 'package:shared_preferences/shared_preferences.dart';

import '../models/finance.dart';
import 'sync_rows.dart';

/// Dónde se recuerdan en el teléfono las categorías y los movimientos de las finanzas (con los borrados y lo que falta por subir).
typedef FinanceEntryStore = RowStore<FinanceEntry>;
typedef FinanceCategoryStore = RowStore<FinanceCategory>;

class MemoryFinanceEntryStore extends MemoryRowStore<FinanceEntry> {}

class MemoryFinanceCategoryStore extends MemoryRowStore<FinanceCategory> {}

class PrefsFinanceEntryStore extends PrefsRowStore<FinanceEntry> {
  PrefsFinanceEntryStore._(SharedPreferences prefs, String key) : super(prefs, key, FinanceEntry.fromJson, (e) => e.toLocalJson());

  /// Uno por cuenta.
  static Future<PrefsFinanceEntryStore> open(String userId) async => PrefsFinanceEntryStore._(await SharedPreferences.getInstance(), 'finance_entries.$userId');
}

class PrefsFinanceCategoryStore extends PrefsRowStore<FinanceCategory> {
  PrefsFinanceCategoryStore._(SharedPreferences prefs, String key) : super(prefs, key, FinanceCategory.fromJson, (c) => c.toLocalJson());

  /// Uno por cuenta.
  static Future<PrefsFinanceCategoryStore> open(String userId) async =>
      PrefsFinanceCategoryStore._(await SharedPreferences.getInstance(), 'finance_categories.$userId');
}

/// La moneda con la que se suman los movimientos (cada movimiento guarda la suya; aquí se elige cuál se ve). Una por teléfono.
class FinanceSettings {
  FinanceSettings(this._prefs);

  static const _key = 'finance.currency';

  final SharedPreferences _prefs;

  static Future<FinanceSettings> open() async => FinanceSettings(await SharedPreferences.getInstance());

  String get currency => _prefs.getString(_key) ?? 'MXN';

  Future<void> setCurrency(String value) => _prefs.setString(_key, value);
}
