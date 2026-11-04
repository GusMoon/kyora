import '../models/task.dart';

/// Lo que la app necesita de Supabase para las tareas. La implementación real es `ChatRepository`; los tests usan una falsa.
abstract class TaskBackend {
  /// Sube lo que cambió aquí (etiquetas, tareas y marcas, por ese orden). Subir lo mismo otra vez no duplica nada, y Supabase
  /// se queda con la versión más reciente de cada fila. Lanza `ChatException`.
  Future<void> push(TaskData changes);

  /// Lo que cambió en Supabase después de cada punto de partida (`synced_at` de la última fila leída de esa tabla; `null` = todo).
  /// Lanza `ChatException`.
  Future<TaskData> pull({String? tasksSince, String? tagsSince, String? linksSince});
}
