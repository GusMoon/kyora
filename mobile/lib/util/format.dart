/// Textos y reglas pequeñas que comparten la app y la PC (el mismo nombre seguro de archivo, las mismas horas y tamaños).
library;

const _months = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre',
  'diciembre',
];

/// Las letras de los días de la semana, de lunes a domingo (el índice es `DateTime.weekday - 1`).
const weekdayLetters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

/// La fecha corta de Inicio: mes (con mayúscula), día y año: «Noviembre 3, 2026».
String shortDate(DateTime moment) {
  final local = moment.toLocal();
  final month = _months[local.month - 1];
  return '${month[0].toUpperCase()}${month.substring(1)} ${local.day}, ${local.year}';
}

/// El saludo según la hora local: de 05:00 a 11:59 «Buenos días», hasta las 18:59 «Buenas tardes» y el resto «Buenas noches».
String greetingFor(DateTime moment) {
  final hour = moment.toLocal().hour;
  if (hour >= 5 && hour < 12) return 'Buenos días';
  if (hour >= 12 && hour < 19) return 'Buenas tardes';
  return 'Buenas noches';
}

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

/// «0:07», «3:42» o «1:02:10».
String clock(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final two = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$two' : '$m:$two';
}

/// Parte «Artista - Título» (como se llaman los videos de YouTube) por el primer « - » (también con raya larga). Sin ese
/// separador, o si un lado queda vacío, todo es el título y no hay artista.
({String? artist, String title}) splitArtistTitle(String name) {
  final text = name.trim();
  final match = RegExp(r'\s[-–—]\s').firstMatch(text);
  if (match == null) return (artist: null, title: text);
  final artist = text.substring(0, match.start).trim();
  final title = text.substring(match.end).trim();
  if (artist.isEmpty || title.isEmpty) return (artist: null, title: text);
  return (artist: artist, title: title);
}

/// La línea de abajo de una canción en la lista: «Artista • 4:21». Lo que no se sepa se omite.
String songLine({String? artist, Duration? duration}) {
  final a = artist?.trim() ?? '';
  return [if (a.isNotEmpty) a, if (duration != null && duration > Duration.zero) clock(duration)].join(' • ');
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
