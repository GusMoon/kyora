import 'package:flutter/material.dart';

/// El estilo de un tema (para agruparlos en Ajustes).
enum NeoThemeGroup {
  classic('Clásicos'),
  wild('Extravagantes'),
  cute('Tiernos'),
  tough('Rudos');

  const NeoThemeGroup(this.label);

  final String label;
}

/// Un tema de colores de KyraFamily: el acento (lo activo, los números, las flechas) y el «pop» (lo resaltado: etiquetas, lo elegido, los
/// mensajes propios). Las superficies las pone el modo claro u oscuro; los colores se ajustan solos para que siempre se lean.
@immutable
class NeoThemeSpec {
  const NeoThemeSpec({required this.id, required this.name, required this.group, required this.accent, required this.pop});

  /// Lo que se guarda en el teléfono (no cambiarlo).
  final String id;
  final String name;
  final NeoThemeGroup group;
  final Color accent;
  final Color pop;
}

/// Los 10 temas: unos clásicos, otros extravagantes, otros tiernos y otros rudos. Todos con la misma estética.
abstract final class NeoThemes {
  static const cyber = NeoThemeSpec(id: 'cyber', name: 'Cyber', group: NeoThemeGroup.classic, accent: Color(0xFF6A3DFA), pop: Color(0xFFDDFF3C));

  static const all = <NeoThemeSpec>[
    // clásicos
    cyber,
    NeoThemeSpec(id: 'mono', name: 'Monocromo', group: NeoThemeGroup.classic, accent: Color(0xFF2A2A30), pop: Color(0xFFFF3B30)),
    NeoThemeSpec(id: 'navy', name: 'Marino', group: NeoThemeGroup.classic, accent: Color(0xFF1F4FD8), pop: Color(0xFFFFB000)),
    // extravagantes
    NeoThemeSpec(id: 'acid', name: 'Ácido', group: NeoThemeGroup.wild, accent: Color(0xFFD1127E), pop: Color(0xFFB6FF00)),
    NeoThemeSpec(id: 'synth', name: 'Synthwave', group: NeoThemeGroup.wild, accent: Color(0xFFFF2E93), pop: Color(0xFF00E5FF)),
    NeoThemeSpec(id: 'volcano', name: 'Volcán', group: NeoThemeGroup.wild, accent: Color(0xFFFF4D00), pop: Color(0xFF00D1BE)),
    // tiernos
    NeoThemeSpec(id: 'sakura', name: 'Sakura', group: NeoThemeGroup.cute, accent: Color(0xFFE8579A), pop: Color(0xFFA8F0D1)),
    NeoThemeSpec(id: 'lavender', name: 'Lavanda', group: NeoThemeGroup.cute, accent: Color(0xFF9B7BFF), pop: Color(0xFFFFC7A6)),
    // rudos
    NeoThemeSpec(id: 'military', name: 'Militar', group: NeoThemeGroup.tough, accent: Color(0xFF5B6B2E), pop: Color(0xFFFF7A00)),
    NeoThemeSpec(id: 'steel', name: 'Acero', group: NeoThemeGroup.tough, accent: Color(0xFF4A5568), pop: Color(0xFFE11D2E)),
  ];

  /// El de siempre.
  static const standard = cyber;

  /// El tema con ese id (o el de siempre si no existe).
  static NeoThemeSpec byId(String? id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return standard;
  }
}
