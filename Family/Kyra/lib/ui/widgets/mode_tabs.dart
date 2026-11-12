import 'package:flutter/material.dart';

import '../../theme.dart';
import 'cut_border.dart';
import 'pixel_glyph.dart';

/// Una pestaña de la barra de pestañas.
@immutable
class ModeTab {
  const ModeTab({required this.id, required this.label, required this.glyph, required this.active, required this.onPressed});

  /// También es la clave de la pestaña (`Key(id)`), para encontrarla.
  final String id;
  final String label;
  final PixelGlyph glyph;
  final bool active;
  final VoidCallback onPressed;
}

/// La barra de pestañas: una **píldora oscura** flotante con las pestañas repartidas; la elegida es una píldora de acento con su icono y su
/// nombre, las demás solo el icono.
class ModeTabs extends StatelessWidget {
  const ModeTabs({super.key, required this.tabs});

  final List<ModeTab> tabs;

  static const height = 76.0;

  @override
  Widget build(BuildContext context) {
    if (tabs.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 6, 16, 10 + MediaQuery.paddingOf(context).bottom),
      child: RepaintBoundary(
        child: Container(
          height: 60,
          padding: const EdgeInsets.all(6),
          decoration: ShapeDecoration(color: c.surface, shape: CutBorder(cut: 14, side: BorderSide(color: c.edge))),
          child: Row(
            children: [
              for (final t in tabs)
                Expanded(
                  flex: t.active ? 3 : 1,
                  child: Semantics(
                    button: true,
                    selected: t.active,
                    label: t.label,
                    child: GestureDetector(
                      key: Key(t.id),
                      behavior: HitTestBehavior.opaque,
                      onTap: t.onPressed,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: ShapeDecoration(color: t.active ? c.accent : null, shape: const CutBorder(cut: 10)),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            PixelIcon(t.glyph, size: 22, color: t.active ? c.onAccent : c.dim),
                            if (t.active) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  t.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.clip,
                                  softWrap: false,
                                  style: lcdLabel(color: c.onAccent),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Las pestañas de una pantalla, arriba: un selector de píldoras a lo ancho; la elegida lleva el acento.
class SegmentTabs extends StatelessWidget {
  const SegmentTabs({super.key, required this.tabs});

  final List<ModeTab> tabs;

  @override
  Widget build(BuildContext context) {
    if (tabs.length < 2) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Container(
        height: 48,
        padding: const EdgeInsets.all(4),
        decoration: ShapeDecoration(color: c.surface, shape: CutBorder(cut: 14, side: BorderSide(color: c.edge))),
        child: Row(
          children: [
            for (final t in tabs)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: t.active,
                  label: t.label,
                  child: GestureDetector(
                    key: Key(t.id),
                    behavior: HitTestBehavior.opaque,
                    onTap: t.onPressed,
                    child: Container(
                      decoration: ShapeDecoration(color: t.active ? c.accent : null, shape: const CutBorder(cut: 10)),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PixelIcon(t.glyph, size: 20, color: t.active ? c.onAccent : c.dim),
                          const SizedBox(width: 6),
                          Flexible(child: Text(t.label, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: lcdLabel(color: t.active ? c.onAccent : c.dim))),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
