import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Cuánto ocupa tu proyecto de Supabase (la función `server_stats()` de Server/supabase/schema.sql §15) frente a los límites del plan
/// gratuito. El aviso salta al llegar al 80 %. Solo se pueden medir la base de datos y los archivos: el tráfico del mes (egress) y los
/// usuarios activos no salen por ninguna API que la app pueda leer. Es lo mismo que hace Merida (`src/data/server.ts`).

/// Un megabyte, en bytes.
const mb = 1024 * 1024;

/// Los límites del plan gratuito de Supabase, en MB (se pueden cambiar en Configuración si cambias de plan).
const freeDbMb = 500;
const freeFilesMb = 1024;

/// A partir de aquí hay advertencia, y a partir de [criticalAt] está casi lleno.
const warnAt = 0.8;
const criticalAt = 0.95;

/// Los límites que más se pueden poner (10 millones de MB): evita escribir una cifra imposible.
const maxLimitMb = 10000000;

class BucketStat {
  const BucketStat({required this.bucket, required this.objects, required this.bytes});

  final String bucket;
  final int objects;
  final int bytes;
}

class TableStat {
  const TableStat({required this.name, required this.bytes, required this.rows});

  final String name;
  final int bytes;
  final int rows;
}

/// Lo que mide el servidor.
class ServerStats {
  const ServerStats({required this.dbBytes, required this.storageBytes, this.storageObjects = 0, this.buckets = const [], this.tables = const [], this.at});

  final int dbBytes;
  final int storageBytes;
  final int storageObjects;
  final List<BucketStat> buckets;
  final List<TableStat> tables;

  /// Cuándo se midió (la hora del servidor).
  final DateTime? at;
}

/// Los límites con los que se compara (en MB).
class QuotaLimits {
  const QuotaLimits({this.dbMb = freeDbMb, this.filesMb = freeFilesMb});

  final int dbMb;
  final int filesMb;

  QuotaLimits copyWith({int? dbMb, int? filesMb}) => QuotaLimits(dbMb: dbMb ?? this.dbMb, filesMb: filesMb ?? this.filesMb);

  @override
  bool operator ==(Object other) => other is QuotaLimits && other.dbMb == dbMb && other.filesMb == filesMb;

  @override
  int get hashCode => Object.hash(dbMb, filesMb);
}

enum QuotaLevel { ok, warn, critical }

enum QuotaId { db, files }

class Quota {
  const Quota({required this.id, required this.label, required this.used, required this.limit, required this.ratio, required this.level});

  final QuotaId id;
  final String label;

  /// Bytes usados y bytes que permite el plan.
  final int used;
  final int limit;

  /// De 0 en adelante (puede pasar de 1).
  final double ratio;
  final QuotaLevel level;
}

QuotaLevel levelOf(double ratio) => ratio >= criticalAt ? QuotaLevel.critical : (ratio >= warnAt ? QuotaLevel.warn : QuotaLevel.ok);

/// Un límite válido en MB: un entero de 1 a [maxLimitMb]. Cualquier otra cosa da [fallback].
int validMb(Object? value, int fallback) => value is int && value >= 1 && value <= maxLimitMb ? value : fallback;

List<Quota> quotas(ServerStats stats, QuotaLimits limits) {
  Quota make(QuotaId id, String label, int used, int limitMb) {
    final limit = (limitMb < 1 ? 1 : limitMb) * mb;
    final ratio = used / limit;
    return Quota(id: id, label: label, used: used, limit: limit, ratio: ratio, level: levelOf(ratio));
  }

  return [
    make(QuotaId.db, 'Base de datos', stats.dbBytes, limits.dbMb),
    make(QuotaId.files, 'Archivos (Storage)', stats.storageBytes, limits.filesMb),
  ];
}

/// Los que están en el 80 % o más.
List<Quota> overQuota(ServerStats stats, QuotaLimits limits) => [for (final q in quotas(stats, limits)) if (q.level != QuotaLevel.ok) q];

/// El porcentaje, redondeado hacia abajo: «80 %» solo si de verdad llegó.
String percent(double ratio) => '${(ratio * 100).floor()} %';

/// «412,3 MB» o «1,24 GB».
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < mb) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * mb) return '${(bytes / mb).toStringAsFixed(1).replaceAll('.', ',')} MB';
  return '${(bytes / (1024 * mb)).toStringAsFixed(2).replaceAll('.', ',')} GB';
}

/// El mensaje de la advertencia (para el aviso de la Nube y la notificación).
String warningText(Quota q) {
  final left = q.limit > q.used ? q.limit - q.used : 0;
  return q.level == QuotaLevel.critical && q.ratio >= 1
      ? '${q.label}: superaste el límite del plan gratuito (${formatBytes(q.used)} de ${formatBytes(q.limit)}).'
      : '${q.label}: llevas ${percent(q.ratio)} del plan gratuito (${formatBytes(q.used)} de ${formatBytes(q.limit)}; quedan ${formatBytes(left)}).';
}

/// Solo se vuelve a notificar lo mismo pasado un día (la advertencia dentro de la app no se esconde).
const renotifyAfter = Duration(hours: 24);

bool shouldRenotify(DateTime? lastWarnedAt, DateTime now) => lastWarnedAt == null || now.difference(lastWarnedAt) >= renotifyAfter;

int _num(Object? v) {
  if (v is num && v.isFinite) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? double.tryParse('${v ?? ''}')?.toInt() ?? 0;
}

/// Lo que devuelve la función, saneado (los `bigint` de Postgres a veces llegan como texto).
ServerStats parseStats(Object? raw) {
  final o = raw is Map ? Map<String, Object?>.from(raw) : <String, Object?>{};
  List<Map<String, Object?>> list(Object? v) => v is List ? [for (final e in v) if (e is Map) Map<String, Object?>.from(e)] : const [];
  return ServerStats(
    dbBytes: _num(o['db_bytes']),
    storageBytes: _num(o['storage_bytes']),
    storageObjects: _num(o['storage_objects']),
    buckets: [for (final b in list(o['buckets'])) BucketStat(bucket: '${b['bucket'] ?? '?'}', objects: _num(b['objects']), bytes: _num(b['bytes']))],
    tables: [for (final t in list(o['tables'])) TableStat(name: '${t['name'] ?? '?'}', bytes: _num(t['bytes']), rows: _num(t['rows']))],
    at: o['at'] is String ? DateTime.tryParse(o['at']! as String) : null,
  );
}

/// Lo que se necesita de Supabase para medir el servidor. Lanza `ChatException` (con un mensaje claro si falta la función).
abstract class ServerBackend {
  Future<ServerStats> serverStats();
}

/// Lo que se recuerda de esto en el teléfono: los límites y cuándo se avisó de cada uno (para no repetir el aviso más de una vez al día).
abstract class ServerStore {
  Future<QuotaLimits> loadLimits();
  Future<void> saveLimits(QuotaLimits limits);

  /// Cuándo se notificó cada límite por última vez.
  Future<Map<QuotaId, DateTime>> loadWarned();
  Future<void> saveWarned(Map<QuotaId, DateTime> warned);
}

class MemoryServerStore implements ServerStore {
  QuotaLimits limits = const QuotaLimits();
  Map<QuotaId, DateTime> warned = {};

  @override
  Future<QuotaLimits> loadLimits() async => limits;

  @override
  Future<void> saveLimits(QuotaLimits value) async => limits = value;

  @override
  Future<Map<QuotaId, DateTime>> loadWarned() async => Map.of(warned);

  @override
  Future<void> saveWarned(Map<QuotaId, DateTime> value) async => warned = Map.of(value);
}

class PrefsServerStore implements ServerStore {
  PrefsServerStore._(this._prefs);

  final SharedPreferences _prefs;

  static const _dbKey = 'server.limit.db';
  static const _filesKey = 'server.limit.files';
  static const _warnedKey = 'server.warned';

  static Future<PrefsServerStore> open() async => PrefsServerStore._(await SharedPreferences.getInstance());

  @override
  Future<QuotaLimits> loadLimits() async => QuotaLimits(dbMb: validMb(_prefs.getInt(_dbKey), freeDbMb), filesMb: validMb(_prefs.getInt(_filesKey), freeFilesMb));

  @override
  Future<void> saveLimits(QuotaLimits limits) async {
    await _prefs.setInt(_dbKey, validMb(limits.dbMb, freeDbMb));
    await _prefs.setInt(_filesKey, validMb(limits.filesMb, freeFilesMb));
  }

  @override
  Future<Map<QuotaId, DateTime>> loadWarned() async {
    try {
      final raw = jsonDecode(_prefs.getString(_warnedKey) ?? '{}') as Map<String, dynamic>;
      return {
        for (final id in QuotaId.values)
          if (raw[id.name] is int) id: DateTime.fromMillisecondsSinceEpoch(raw[id.name] as int, isUtc: true),
      };
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> saveWarned(Map<QuotaId, DateTime> warned) async {
    await _prefs.setString(_warnedKey, jsonEncode({for (final e in warned.entries) e.key.name: e.value.millisecondsSinceEpoch}));
  }
}
