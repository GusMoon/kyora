import '../models/improvement.dart';

/// Dónde viven las mejoras pendientes: la tabla `feature_requests` de Supabase (la misma que usa Merida). Lanza `ChatException`.
abstract class ImprovementBackend {
  /// Las pendientes, de la más nueva a la más antigua.
  Future<List<Improvement>> list();

  /// Anota una (repetirla con el mismo id no la duplica).
  Future<void> add(Improvement item);

  /// «Hecho»: la borra de verdad de la base de datos.
  Future<void> finish(String id);
}
