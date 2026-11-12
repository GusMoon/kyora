import 'package:flutter/painting.dart';

const _days = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

String _two(int n) => n.toString().padLeft(2, '0');

/// La entrega en la hora del teléfono: «Hoy 18:00», «Mañana 09:30», «Ayer 17:00» o «vie 24 oct 18:00» (como en el escritorio).
String dueLabel(DateTime due, DateTime now) {
  final d = due.toLocal();
  final today = DateTime(now.toLocal().year, now.toLocal().month, now.toLocal().day);
  final day = DateTime(d.year, d.month, d.day);
  final clock = '${_two(d.hour)}:${_two(d.minute)}';
  switch (day.difference(today).inDays) {
    case 0:
      return 'Hoy $clock';
    case 1:
      return 'Mañana $clock';
    case -1:
      return 'Ayer $clock';
  }
  return '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]} $clock';
}

/// «1 h 30 min», «45 min», «2 h»; vacío si no hay.
String minutesLabel(int? minutes) {
  if (minutes == null) return '';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h > 0 && m > 0) return '$h h $m min';
  return h > 0 ? '$h h' : '$m min';
}

/// Los minutos de un texto libre: «90», «1:30», «1h30», «1 h 30 min», «45 min», «1,5 h». `null` si está vacío; lanza
/// `FormatException` si no se entiende.
int? parseMinutes(String? text) {
  final t = (text ?? '').trim().toLowerCase();
  if (t.isEmpty) return null;
  final clock = RegExp(r'^(\d+):(\d{1,2})$').firstMatch(t);
  if (clock != null) return int.parse(clock.group(1)!) * 60 + int.parse(clock.group(2)!);
  if (RegExp(r'^\d+$').hasMatch(t)) return int.parse(t);
  var total = 0.0;
  var found = false;
  String? before;
  final unit = RegExp(r'(\d+(?:[.,]\d+)?)\s*(horas|hora|h|minutos|minuto|mins|min|m)?(?![a-z])');
  for (final match in unit.allMatches(t)) {
    final value = double.parse(match.group(1)!.replaceAll(',', '.'));
    final u = match.group(2);
    if (u != null && u.startsWith('h')) {
      total += value * 60;
      before = 'h';
    } else if (u != null || before == 'h') {
      total += value;
      before = 'm';
    } else {
      throw FormatException('No entiendo «$text»');
    }
    found = true;
  }
  if (!found || t.replaceAll(RegExp(r'[\d.,\s]|horas?|h|minutos?|mins?|m'), '').isNotEmpty) {
    throw FormatException('No entiendo «$text»: escribe por ejemplo 1 h 30 min');
  }
  return total.round();
}

/// Un color «#RRGGBB» (si no se entiende, gris).
Color colorFromHex(String hex) {
  final clean = hex.replaceAll('#', '');
  final value = int.tryParse(clean.length == 6 ? 'FF$clean' : clean, radix: 16);
  return Color(value ?? 0xFF888888);
}
