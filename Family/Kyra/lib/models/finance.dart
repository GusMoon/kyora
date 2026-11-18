import '../data/sync_rows.dart';

const _keep = Object();

/// Si un movimiento suma o resta.
enum FinanceKind {
  income('income', 'Ingreso'),
  expense('expense', 'Gasto');

  const FinanceKind(this.wire, this.label);

  /// Como va en Supabase (`kind`).
  final String wire;
  final String label;

  static FinanceKind fromWire(Object? value) => value == 'income' ? FinanceKind.income : FinanceKind.expense;
}

/// Una categoría de movimientos (tabla `finance_categories`, la misma que usa la web). Mismo esquema de sincronización que las demás filas: ids
/// uuid del dispositivo, horas en UTC, gana el `updatedAt` más reciente y el borrado es suave.
class FinanceCategory implements SyncRow {
  const FinanceCategory({
    required this.id,
    required this.name,
    required this.kind,
    required this.createdAt,
    required this.updatedAt,
    this.color = '#9aa1ac',
    this.deletedAt,
    this.syncedAt,
    this.dirty = false,
  });

  @override
  final String id;
  final String name;
  final FinanceKind kind;

  /// `#rrggbb`.
  final String color;
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;
  @override
  final String? syncedAt;
  @override
  final bool dirty;

  @override
  bool get isDeleted => deletedAt != null;

  FinanceCategory copyWith({String? name, String? color, DateTime? updatedAt, Object? deletedAt = _keep, bool? dirty}) => FinanceCategory(
    id: id,
    name: name ?? this.name,
    kind: kind,
    color: color ?? this.color,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: identical(deletedAt, _keep) ? this.deletedAt : deletedAt as DateTime?,
    syncedAt: syncedAt,
    dirty: dirty ?? this.dirty,
  );

  @override
  FinanceCategory withDirty(bool value) => copyWith(dirty: value);

  @override
  FinanceCategory get fromServer => FinanceCategory(
    id: id,
    name: name,
    kind: kind,
    color: color,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
    syncedAt: syncedAt,
  );

  /// Las columnas, tal cual van a Supabase.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.wire,
    'color': color,
    'created_at': isoOf(createdAt),
    'updated_at': isoOf(updatedAt),
    'deleted_at': isoOf(deletedAt),
  };

  /// Lo que se guarda en el teléfono: las columnas más lo que solo vale aquí.
  Map<String, Object?> toLocalJson() => {...toJson(), 'synced_at': syncedAt, 'dirty': dirty};

  factory FinanceCategory.fromJson(Map<String, Object?> json) => FinanceCategory(
    id: json['id']! as String,
    name: json['name']! as String,
    kind: FinanceKind.fromWire(json['kind']),
    color: (json['color'] as String?) ?? '#9aa1ac',
    createdAt: parseTime(json['created_at'])!,
    updatedAt: parseTime(json['updated_at'])!,
    deletedAt: parseTime(json['deleted_at']),
    syncedAt: json['synced_at'] as String?,
    dirty: json['dirty'] == true || json['dirty'] == 1,
  );
}

/// Un movimiento: un ingreso o un gasto (tabla `finance_entries`). El importe va en **centavos** (entero) para no arrastrar errores de redondeo;
/// el tipo dice si suma o resta, así que siempre es mayor que 0.
class FinanceEntry implements SyncRow {
  const FinanceEntry({
    required this.id,
    required this.kind,
    required this.amountCents,
    required this.occurredOn,
    required this.createdAt,
    required this.updatedAt,
    this.currency = 'MXN',
    this.categoryId,
    this.description = '',
    this.deletedAt,
    this.syncedAt,
    this.dirty = false,
  });

  @override
  final String id;
  final FinanceKind kind;
  final int amountCents;
  final String currency;
  final String? categoryId;
  final String description;

  /// El día, como «aaaa-mm-dd».
  final String occurredOn;
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;
  @override
  final String? syncedAt;
  @override
  final bool dirty;

  @override
  bool get isDeleted => deletedAt != null;

  FinanceEntry copyWith({
    FinanceKind? kind,
    int? amountCents,
    String? currency,
    Object? categoryId = _keep,
    String? description,
    String? occurredOn,
    DateTime? updatedAt,
    Object? deletedAt = _keep,
    bool? dirty,
  }) => FinanceEntry(
    id: id,
    kind: kind ?? this.kind,
    amountCents: amountCents ?? this.amountCents,
    currency: currency ?? this.currency,
    categoryId: identical(categoryId, _keep) ? this.categoryId : categoryId as String?,
    description: description ?? this.description,
    occurredOn: occurredOn ?? this.occurredOn,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: identical(deletedAt, _keep) ? this.deletedAt : deletedAt as DateTime?,
    syncedAt: syncedAt,
    dirty: dirty ?? this.dirty,
  );

  @override
  FinanceEntry withDirty(bool value) => copyWith(dirty: value);

  @override
  FinanceEntry get fromServer => FinanceEntry(
    id: id,
    kind: kind,
    amountCents: amountCents,
    currency: currency,
    categoryId: categoryId,
    description: description,
    occurredOn: occurredOn,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
    syncedAt: syncedAt,
  );

  /// Las columnas, tal cual van a Supabase.
  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.wire,
    'amount_cents': amountCents,
    'currency': currency,
    'category_id': categoryId,
    'description': description,
    'occurred_on': occurredOn,
    'created_at': isoOf(createdAt),
    'updated_at': isoOf(updatedAt),
    'deleted_at': isoOf(deletedAt),
  };

  /// Lo que se guarda en el teléfono: las columnas más lo que solo vale aquí.
  Map<String, Object?> toLocalJson() => {...toJson(), 'synced_at': syncedAt, 'dirty': dirty};

  factory FinanceEntry.fromJson(Map<String, Object?> json) => FinanceEntry(
    id: json['id']! as String,
    kind: FinanceKind.fromWire(json['kind']),
    amountCents: (json['amount_cents']! as num).toInt(),
    currency: (json['currency'] as String?) ?? 'MXN',
    categoryId: json['category_id'] as String?,
    description: (json['description'] as String?) ?? '',
    occurredOn: (json['occurred_on']! as String).substring(0, 10),
    createdAt: parseTime(json['created_at'])!,
    updatedAt: parseTime(json['updated_at'])!,
    deletedAt: parseTime(json['deleted_at']),
    syncedAt: json['synced_at'] as String?,
    dirty: json['dirty'] == true || json['dirty'] == 1,
  );
}
