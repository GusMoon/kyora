/// Cuánto falta para algo, en palabras cortas: «en 7 h 20 min», «en 2 d 3 h», «en menos de 1 min».
String untilText(Duration d) {
  final minutes = d.inMinutes;
  if (minutes < 1) return 'en menos de 1 min';
  if (minutes < 60) return 'en $minutes min';
  final hours = minutes ~/ 60;
  if (hours < 24) {
    final rest = minutes % 60;
    return rest == 0 ? 'en $hours h' : 'en $hours h $rest min';
  }
  final days = hours ~/ 24;
  final restHours = hours % 24;
  return restHours == 0 ? 'en $days d' : 'en $days d $restHours h';
}

/// El tiempo del cronómetro partido para dibujarlo: lo principal («05:07», o «1:05:07» si pasó una hora) y las centésimas («.42»).
(String, String) stopwatchParts(Duration d) {
  final total = d.isNegative ? Duration.zero : d;
  final hours = total.inHours;
  final minutes = total.inMinutes % 60;
  final seconds = total.inSeconds % 60;
  final hundredths = (total.inMilliseconds % 1000) ~/ 10;
  String two(int n) => n.toString().padLeft(2, '0');
  final main = hours > 0 ? '$hours:${two(minutes)}:${two(seconds)}' : '${two(minutes)}:${two(seconds)}';
  return (main, '.${two(hundredths)}');
}

/// El tiempo del cronómetro en una sola línea: «05:07.42».
String stopwatchText(Duration d) {
  final (main, fraction) = stopwatchParts(d);
  return '$main$fraction';
}
