/// Una mejora pendiente del proyecto (tabla `feature_requests`, la misma que usa Merida): qué sección se quiere agregar o mejorar, las funciones
/// que se quieren (una por línea) y una descripción. Al terminarla se pulsa «Hecho» y se **borra** de la base de datos.
class Improvement {
  const Improvement({required this.id, required this.section, required this.createdAt, this.functions = '', this.description = ''});

  final String id;
  final String section;

  /// Una función por línea.
  final String functions;
  final String description;
  final DateTime createdAt;

  /// Lo más largo que admite el nombre de la sección y cada texto (los mismos topes que la base de datos y Merida).
  static const maxSection = 80;
  static const maxText = 4000;

  /// Las funciones como lista: una por línea, sin las viñetas («-», «*», «•») ni los números con que se hayan escrito.
  List<String> get functionLines => linesOf(functions);

  static List<String> linesOf(String text) => [
    for (final line in text.split(RegExp(r'\r?\n')))
      if (line.replaceFirst(RegExp(r'^\s*(?:[-*•·]\s+|\d+[.)]\s+)'), '').trim().isNotEmpty) line.replaceFirst(RegExp(r'^\s*(?:[-*•·]\s+|\d+[.)]\s+)'), '').trim(),
  ];

  /// Lo que falta o sobra en lo escrito, con el aviso ya explicado; `null` si está bien.
  static String? validate({required String section, String functions = '', String description = ''}) {
    final name = section.trim();
    if (name.isEmpty) return 'Escribe qué sección quieres agregar o mejorar.';
    if (name.length > maxSection) return 'El nombre de la sección admite hasta $maxSection caracteres.';
    if (functions.trim().isEmpty && description.trim().isEmpty) return 'Anota al menos una función o una descripción.';
    if (functions.length > maxText || description.length > maxText) return 'Cada texto admite hasta $maxText caracteres.';
    return null;
  }

  /// Las columnas, tal cual van a Supabase (`owner_id` lo pone la base de datos).
  Map<String, Object?> toJson() => {
    'id': id,
    'section': section,
    'functions': functions,
    'description': description,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  factory Improvement.fromJson(Map<String, Object?> json) => Improvement(
    id: json['id']! as String,
    section: json['section']! as String,
    functions: (json['functions'] as String?) ?? '',
    description: (json['description'] as String?) ?? '',
    createdAt: DateTime.parse(json['created_at']! as String).toUtc(),
  );
}
