import '../models/habit.dart';

/// Lo que los hábitos necesitan de Supabase: subir lo que cambió aquí y bajar lo que cambió en otros sitios.
abstract class HabitBackend {
  /// Sube lo que cambió aquí (hábitos y luego marcas). Subir lo mismo otra vez no duplica nada, y Supabase se queda con la versión más
  /// reciente de cada fila. Lanza `ChatException`.
  Future<void> pushHabits(HabitData changes);

  /// Lo que cambió en Supabase después de cada punto de partida (`synced_at` de la última fila leída de esa tabla; `null` = todo).
  /// Lanza `ChatException`.
  Future<HabitData> pullHabits({String? habitsSince, String? checksSince});
}
