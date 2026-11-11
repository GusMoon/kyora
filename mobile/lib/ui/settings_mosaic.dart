import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'widgets/cyber_panel.dart';
import 'widgets/hack_text.dart';

export 'widgets/cyber_panel.dart' show CyberPanel;

/// Cuántas columnas tiene el mosaico.
const mosaicColumns = 4;

/// Una ficha del mosaico: cuánto ocupa (en celdas) cuando se ve el mosaico entero.
@immutable
class MosaicTile {
  const MosaicTile(this.id, this.colSpan, this.rowSpan);

  final String id;
  final int colSpan;
  final int rowSpan;
}

/// Dónde cae cada ficha en la rejilla (columna y fila de su celda de arriba a la izquierda) y cuántas filas hacen falta. Las coloca una a una
/// en el primer hueco libre (de izquierda a derecha y de arriba abajo): si falta una ficha, las demás se reacomodan sin dejar agujeros.
({Map<String, ({int col, int row})> cells, int rows}) packMosaic(List<MosaicTile> tiles) {
  final used = <List<bool>>[];
  List<bool> rowAt(int r) {
    while (used.length <= r) {
      used.add(List<bool>.filled(mosaicColumns, false));
    }
    return used[r];
  }

  bool fits(int col, int row, MosaicTile t) {
    if (col + t.colSpan > mosaicColumns) return false;
    for (var r = row; r < row + t.rowSpan; r++) {
      for (var c = col; c < col + t.colSpan; c++) {
        if (rowAt(r)[c]) return false;
      }
    }
    return true;
  }

  final cells = <String, ({int col, int row})>{};
  for (final t in tiles) {
    var placed = false;
    for (var row = 0; !placed; row++) {
      for (var col = 0; col < mosaicColumns && !placed; col++) {
        if (!fits(col, row, t)) continue;
        for (var r = row; r < row + t.rowSpan; r++) {
          for (var c = col; c < col + t.colSpan; c++) {
            rowAt(r)[c] = true;
          }
        }
        cells[t.id] = (col: col, row: row);
        placed = true;
      }
    }
  }
  return (cells: cells, rows: used.length);
}

/// Cuánto mide de alto, como mucho, una celda respecto a su ancho (para que con pocas fichas no salgan celdas altísimas).
const _maxCellRatio = 1.2;

/// Los rectángulos de cada ficha dentro de [area]. Con [expanded] `null`, el mosaico entero; con una ficha elegida, esa ocupa casi todo el
/// área y las demás se encogen en una **franja de iconos** de [strip] de alto abajo del todo.
Map<String, Rect> mosaicRects(Size area, List<MosaicTile> tiles, String? expanded, {double gap = 10, double strip = 62}) {
  if (tiles.isEmpty) return const {};
  if (expanded != null && tiles.any((t) => t.id == expanded)) {
    final others = [for (final t in tiles) if (t.id != expanded) t];
    final big = Rect.fromLTWH(0, 0, area.width, math.max(0, area.height - strip - gap));
    final result = <String, Rect>{expanded: big};
    if (others.isNotEmpty) {
      final w = (area.width - gap * (others.length - 1)) / others.length;
      for (var i = 0; i < others.length; i++) {
        result[others[i].id] = Rect.fromLTWH(i * (w + gap), area.height - strip, w, strip);
      }
    }
    return result;
  }
  final packed = packMosaic(tiles);
  final cellW = (area.width - gap * (mosaicColumns - 1)) / mosaicColumns;
  final cellH = math.min((area.height - gap * (packed.rows - 1)) / packed.rows, cellW * _maxCellRatio);
  return {
    for (final t in tiles)
      t.id: Rect.fromLTWH(
        packed.cells[t.id]!.col * (cellW + gap),
        packed.cells[t.id]!.row * (cellH + gap),
        t.colSpan * cellW + (t.colSpan - 1) * gap,
        t.rowSpan * cellH + (t.rowSpan - 1) * gap,
      ),
  };
}

/// Una ficha de Configuración: su sitio en el mosaico, cómo se ve cerrada (resumen) y qué hay dentro cuando se expande (detalle).
class MosaicEntry {
  const MosaicEntry({required this.id, required this.title, required this.code, required this.icon, required this.colSpan, required this.rowSpan, required this.summary, required this.detail});

  final String id;
  final String title;

  /// La etiqueta técnica de la esquina, tipo «CFG·01».
  final String code;
  final IconData icon;
  final int colSpan;
  final int rowSpan;

  /// Lo que se ve con la ficha cerrada, además del icono y el título: una vista previa en vivo. Recibe el alto disponible.
  final Widget Function(BuildContext context, double height) summary;

  /// Lo que hay dentro con la ficha expandida (las filas de ajustes).
  final WidgetBuilder detail;

  MosaicTile get tile => MosaicTile(id, colSpan, rowSpan);
}

enum _Role { summary, detail, strip }

/// El mosaico de fichas: se ve entero con fichas de distintos tamaños y, al tocar una, **se expande** y las demás se reacomodan en una franja
/// de iconos; tocar otra de la franja cambia de ficha. Todo se mueve con una sola animación (cada ficha va de donde está a donde le toca) y el
/// contenido se cambia con un fundido: el resumen se desvanece y entra el detalle.
class MosaicView extends StatefulWidget {
  const MosaicView({super.key, required this.entries, required this.expandedId, required this.onExpand});

  final List<MosaicEntry> entries;

  /// La ficha expandida, o `null` para ver el mosaico entero.
  final String? expandedId;

  /// Se pide expandir una ficha (`id`) o volver al mosaico (`null`).
  final ValueChanged<String?> onExpand;

  /// Lo que dura el reacomodo de las fichas.
  static const transition = Duration(milliseconds: 440);

  @override
  State<MosaicView> createState() => _MosaicViewState();
}

class _MosaicViewState extends State<MosaicView> with TickerProviderStateMixin {
  late final AnimationController _move = AnimationController(vsync: this, duration: MosaicView.transition, value: 1);
  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();

  /// De dónde viene cada ficha en este movimiento y qué ficha estaba expandida antes.
  Map<String, Rect> _fromRects = const {};
  String? _fromState;

  /// Lo último que se dibujó (para arrancar desde ahí si llega otro movimiento a mitad).
  Map<String, Rect> _shown = const {};
  Size? _lastSize;

  @override
  void didUpdateWidget(MosaicView old) {
    super.didUpdateWidget(old);
    if (old.expandedId != widget.expandedId) {
      _fromRects = _shown;
      _fromState = old.expandedId;
      _move.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _move.dispose();
    _enter.dispose();
    super.dispose();
  }

  _Role _roleIn(String id, String? state) => state == null ? _Role.summary : (state == id ? _Role.detail : _Role.strip);

  @override
  Widget build(BuildContext context) {
    final tiles = [for (final e in widget.entries) e.tile];
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final target = mosaicRects(size, tiles, widget.expandedId);
        if (_lastSize != size) {
          // el área cambió (el teclado, girar el teléfono): se sigue sin animar para no ir por detrás de ella
          _lastSize = size;
          _fromRects = target;
          _fromState = widget.expandedId;
          _move.value = 1;
        }
        return AnimatedBuilder(
          animation: Listenable.merge([_move, _enter]),
          builder: (context, _) {
            final t = Curves.easeInOutCubic.transform(_move.value);
            final fromLayout = mosaicRects(size, tiles, _fromState);
            final shown = <String, Rect>{
              for (final e in widget.entries) e.id: Rect.lerp(_fromRects[e.id] ?? target[e.id], target[e.id], t)!,
            };
            _shown = shown;
            final ordered = [...widget.entries]..sort((a, b) => (a.id == widget.expandedId ? 1 : 0).compareTo(b.id == widget.expandedId ? 1 : 0)); // la expandida, encima
            return Stack(
              clipBehavior: Clip.none,
              children: [
                for (final e in ordered)
                  Positioned.fromRect(
                    key: ValueKey('mosaic-pos-${e.id}'),
                    rect: shown[e.id]!,
                    child: _tile(context, e, widget.entries.indexOf(e), t, fromLayout[e.id]!.size, target[e.id]!.size),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _tile(BuildContext context, MosaicEntry e, int index, double t, Size fromRest, Size toRest) {
    final fromRole = _roleIn(e.id, _fromState);
    final toRole = _roleIn(e.id, widget.expandedId);
    final expanded = widget.expandedId == e.id;
    // el fundido del contenido: el de antes se va en la primera mitad y el nuevo entra en la segunda
    final out = 1 - Interval(0, 0.5, curve: Curves.easeIn).transform(t);
    final inn = const Interval(0.45, 1, curve: Curves.easeOut).transform(t);
    final animating = _move.isAnimating && fromRole != toRole;
    // mientras las fichas aparecen escalonadas, el título espera a que la suya asome
    final enterWait = _enter.isCompleted ? Duration.zero : Duration(milliseconds: index * 81 + 150);
    Widget content;
    if (!animating) {
      content = _reveal(e, toRole, toRest, enterWait);
    } else {
      content = Stack(
        fit: StackFit.expand,
        children: [
          Opacity(opacity: out, child: _reveal(e, fromRole, fromRest)),
          Opacity(opacity: inn, child: _reveal(e, toRole, toRest)),
        ],
      );
    }

    // la entrada: cada ficha aparece un poco después de la anterior, subiendo y creciendo
    final start = (index * 0.09).clamp(0.0, 0.6);
    final appear = Interval(start, math.min(1, start + 0.4), curve: Curves.easeOutCubic).transform(_enter.value);

    final panel = CyberPanel(
      key: Key('mosaic-tile-${e.id}'),
      active: expanded ? 1 : 0,
      child: content,
    );
    return Opacity(
      opacity: appear,
      child: Transform.translate(
        offset: Offset(0, (1 - appear) * 24),
        child: Transform.scale(
          scale: 0.94 + 0.06 * appear,
          child: expanded
              ? panel
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onExpand(e.id),
                  child: Semantics(button: true, label: e.title, child: panel),
                ),
        ),
      ),
    );
  }

  /// El contenido de un papel (resumen, detalle o icono) puesto a su tamaño de reposo y recortado por la ficha: así, mientras la ficha crece o se
  /// encoge, el contenido no se reacomoda (ni se desborda), solo se va descubriendo.
  Widget _reveal(MosaicEntry e, _Role role, Size rest, [Duration delay = Duration.zero]) {
    final child = switch (role) {
      _Role.summary => _Summary(entry: e, delay: delay),
      _Role.detail => _Detail(entry: e, onClose: () => widget.onExpand(null)),
      _Role.strip => _StripIcon(entry: e),
    };
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: rest.width,
        maxWidth: rest.width,
        minHeight: rest.height,
        maxHeight: rest.height,
        child: child,
      ),
    );
  }
}

/// La ficha cerrada: icono y etiqueta técnica arriba, una vista previa en vivo, y el título.
class _Summary extends StatelessWidget {
  const _Summary({required this.entry, this.delay = Duration.zero});

  final MosaicEntry entry;

  /// Lo que espera el título para escribirse (la ficha aparece escalonada).
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      key: Key('mosaic-summary-${entry.id}'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: LayoutBuilder(
        builder: (context, box) {
          // una ficha muy baja (una fila en una pantalla pequeña): solo el icono y el título, en una línea
          if (box.maxHeight < 70) {
            return Row(
              children: [
                Icon(entry.icon, size: 20, color: c.accent),
                const SizedBox(width: 8),
                Expanded(child: HackText(entry.title, delay: delay, maxLines: 1, overflow: TextOverflow.ellipsis, style: display(size: 15, color: c.ink))),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(entry.icon, size: 20, color: c.accent),
                  const Spacer(),
                  // en una ficha estrecha (una columna) no cabe la etiqueta técnica
                  if (box.maxWidth >= 110) Text(entry.code, style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 0.5, color: c.dim)),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(child: entry.summary(context, box.maxHeight)),
              const SizedBox(height: 6),
              HackText(entry.title, delay: delay, maxLines: 2, overflow: TextOverflow.ellipsis, style: display(size: 15, color: c.ink).copyWith(height: 1.1)),
            ],
          );
        },
      ),
    );
  }
}

/// La ficha expandida: su cabecera (icono, título, etiqueta y la X para volver) y debajo el detalle, que se desplaza.
class _Detail extends StatelessWidget {
  const _Detail({required this.entry, required this.onClose});

  final MosaicEntry entry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      key: Key('mosaic-detail-${entry.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 6, 0),
          child: Row(
            children: [
              Icon(entry.icon, size: 22, color: c.accent),
              const SizedBox(width: 10),
              Expanded(child: HackText(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: display(size: 20, color: c.ink))),
              Text(entry.code, style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 0.5, color: c.dim)),
              IconButton(
                key: const Key('mosaic-close'),
                tooltip: 'Volver',
                onPressed: onClose,
                icon: Icon(Icons.close_rounded, color: c.ink),
              ),
            ],
          ),
        ),
        Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 16), color: c.accent.withValues(alpha: 0.35)),
        Expanded(child: Material(type: MaterialType.transparency, child: entry.detail(context))),
      ],
    );
  }
}

/// Una ficha en la franja de abajo (con otra expandida): solo su icono.
class _StripIcon extends StatelessWidget {
  const _StripIcon({required this.entry});

  final MosaicEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(key: Key('mosaic-strip-${entry.id}'), child: Icon(entry.icon, size: 24, color: c.accent));
  }
}
