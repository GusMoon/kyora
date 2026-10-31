/// Textos y reglas pequeñas que comparten la app y la PC (el mismo nombre seguro de archivo, las mismas horas y tamaños).
library;

const _months = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre',
  'diciembre',
];

/// La hora local de un instante: `09:05`.
String clockText(DateTime moment) {
  final local = moment.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

/// Una fecha en palabras: «Hoy», «Ayer», «30 de octubre» (con el año si no es el actual).
String dayLabel(DateTime moment, {DateTime? now}) {
  final local = moment.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  final a = DateTime(local.year, local.month, local.day);
  final b = DateTime(today.year, today.month, today.day);
  final gap = b.difference(a).inDays;
  if (gap == 0) return 'Hoy';
  if (gap == 1) return 'Ayer';
  final text = '${local.day} de ${_months[local.month - 1]}';
  return local.year == today.year ? text : '$text de ${local.year}';
}

/// ¿Es el mismo día (en la hora local)?
bool sameDay(DateTime a, DateTime b) {
  final x = a.toLocal(), y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

/// Un tamaño legible, como en la PC (`kyora/search/folders.py::human_size`): base 1024, un decimal y coma: `23,5 MB`.
String humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024.0;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(1).replaceAll('.', ',')} ${units[unit]}';
}

/// El nombre de un archivo apto para la ruta de Storage: solo letras, números, punto, guion y guion bajo (igual que la
/// PC, en `kyora/chat/service.py::safe_name`).
String safeName(String name) {
  var cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_').replaceAll(RegExp(r'^[._]+|[._]+$'), '');
  if (cleaned.isEmpty) cleaned = 'archivo';
  return cleaned.length > 120 ? cleaned.substring(cleaned.length - 120) : cleaned;
}

/// La clase de mensaje según el tipo del primer adjunto (la misma regla que `send_message` en el SQL).
String kindOfMime(String? mime) {
  final value = (mime ?? '').toLowerCase();
  if (value.isEmpty) return 'other';
  if (value.startsWith('image/')) return 'image';
  if (value.startsWith('audio/')) return 'audio';
  if (value.startsWith('video/')) return 'video';
  return 'file';
}
