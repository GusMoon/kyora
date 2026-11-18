import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import 'cover.dart';
import 'cut_border.dart';
import 'focus_space.dart';
import 'pixel_glyph.dart';

/// Una opción del menú de consola de una tarjeta (mantenerla presionada).
class CardAction {
  const CardAction({required this.id, required this.label, required this.icon, required this.onTap, this.warn = false});

  /// Con ella se forma la clave `deck-action-<id>`.
  final String id;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  /// Una acción peligrosa (borrar): va en el color de aviso.
  final bool warn;
}

/// Un álbum de la cuadrícula: su portada (la que le pusiste, o la de su primera canción, o un recuadro con un icono) y su nombre.
class DeckCard {
  const DeckCard({required this.id, required this.title, required this.icon, required this.onTap, this.coverFile, this.coverUrl, this.actions = const []});

  /// Con esta clave se encuentra la tarjeta (`card-root`, `card-folder-Rock`…).
  final String id;
  final String title;
  final IconData icon;

  /// Lo que pasa al tocar el álbum (abrirlo).
  final VoidCallback onTap;

  final String? coverFile;
  final String? coverUrl;

  /// Lo que sale, en forma de consola, al mantener presionada la portada. Sin opciones no sale nada.
  final List<CardAction> actions;
}

/// Para saber (y cambiar) desde fuera qué álbum se ve en la cuadrícula.
class DeckController {
  _AlbumGridState? _state;

  /// El número del primer álbum de la fila que se ve arriba.
  int get current => _state?._firstVisible ?? 0;

  /// Lleva la cuadrícula hasta ese álbum, sin animación.
  void jumpTo(int index) => _state?._jumpTo(index);
}

/// Los álbumes en **cuadrícula: tres por fila**, pegados (con un margen muy pequeño e igual entre uno y otro) y **sin nombre**: cada uno es su
/// portada (la que le pusiste, o la de su primera canción, o un recuadro con un icono) en un marco de esquinas cortadas. Tocar uno lo abre;
/// mantenerlo presionado abre el menú de consola con sus opciones. La cuadrícula se desplaza en vertical.
class AlbumGrid extends StatefulWidget {
  const AlbumGrid({super.key, required this.cards, this.controller});

  final List<DeckCard> cards;
  final DeckController? controller;

  /// Cuántos álbumes por fila.
  static const columns = 3;

  /// Lo que se separan los álbumes (en horizontal y en vertical) y el margen de la cuadrícula: el mismo, muy pequeño, para que queden pegados.
  static const gap = 4.0;
  static const margin = 4.0;

  /// Lo que se corta cada esquina de la portada.
  static const radius = 12.0;

  /// El lado de la portada para un ancho dado.
  static double sideFor(double width) => (width - 2 * margin - (columns - 1) * gap) / columns;

  @override
  State<AlbumGrid> createState() => _AlbumGridState();
}

class _AlbumGridState extends State<AlbumGrid> {
  final ScrollController _scroll = ScrollController();
  double _row = 1;

  int get _firstVisible => _scroll.hasClients && _row > 0 ? (_scroll.offset / _row).round() * AlbumGrid.columns : 0;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
  }

  @override
  void didUpdateWidget(AlbumGrid old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (old.controller?._state == this) old.controller?._state = null;
      widget.controller?._state = this;
    }
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    _scroll.dispose();
    super.dispose();
  }

  void _jumpTo(int index) {
    if (!_scroll.hasClients) return;
    final target = (index ~/ AlbumGrid.columns) * _row;
    _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
  }

  Future<void> _menu(DeckCard card) async {
    unawaited(HapticFeedback.mediumImpact().catchError((Object _) {}));
    await showFocusPanel<void>(
      context,
      title: card.title,
      builder: (panel) => AlbumConsole(key: Key('deck-menu-${card.id}'), card: card, onClose: () => Navigator.of(panel).pop()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cards = widget.cards;
    return LayoutBuilder(
      key: const Key('album-deck'),
      builder: (context, box) {
        final side = math.max(40.0, AlbumGrid.sideFor(box.maxWidth));
        _row = side + AlbumGrid.gap;
        return Stack(
          fit: StackFit.expand,
          children: [
            GridView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(AlbumGrid.margin, 44, AlbumGrid.margin, 28),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: AlbumGrid.columns,
                mainAxisSpacing: AlbumGrid.gap,
                crossAxisSpacing: AlbumGrid.gap,
                mainAxisExtent: side,
              ),
              itemCount: cards.length,
              itemBuilder: (context, i) => _Tile(card: cards[i], side: side, onMenu: cards[i].actions.isEmpty ? null : () => unawaited(_menu(cards[i]))),
            ),
            // la etiqueta de arriba: como un HUD
            Positioned(
              left: AlbumGrid.margin,
              top: 12,
              child: Row(
                children: [
                  Text('> ', style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.accent)),
                  Text('ÁLBUMES', style: TextStyle(fontFamily: monoFont, fontSize: 15, fontWeight: FontWeight.w600, color: c.ink, letterSpacing: 1)),
                  const SizedBox(width: 10),
                  Text(cards.length.toString().padLeft(2, '0'), key: const Key('deck-count'), style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.card, required this.side, required this.onMenu});

  final DeckCard card;
  final double side;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) => Semantics(
    label: card.title,
    button: true,
    child: GestureDetector(
      key: ValueKey(card.id),
      behavior: HitTestBehavior.opaque,
      onTap: card.onTap,
      onLongPress: onMenu,
      child: SizedBox(width: side, height: side, child: DeckArt(card: card, side: side)),
    ),
  );
}

/// La cara de un álbum: la portada entera dentro del marco de esquinas cortadas, o un recuadro con el icono.
class DeckArt extends StatelessWidget {
  const DeckArt({super.key, required this.card, required this.side, this.focused = false, this.radius = AlbumGrid.radius});

  final DeckCard card;
  final double side;
  final bool focused;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (card.coverFile != null || card.coverUrl != null) {
      return Cover(url: card.coverUrl, file: card.coverFile, size: side, radius: radius, focused: focused);
    }
    return CoverFrame(
      cut: radius,
      focused: focused,
      child: ColoredBox(key: const Key('plate-blank'), color: c.surface, child: Center(child: LcdIcon(card.icon, size: side * 0.32, color: c.dim))),
    );
  }
}

/// El menú de un álbum, dentro del panel focal y en forma de consola: una línea por opción (`[1] CAMBIAR NOMBRE`…) y una «x» para cerrar.
/// Tocar una opción la ejecuta y cierra el menú.
class AlbumConsole extends StatelessWidget {
  const AlbumConsole({super.key, required this.card, required this.onClose});

  final DeckCard card;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final line = TextStyle(fontFamily: monoFont, fontSize: 15, color: c.ink, letterSpacing: 0.6);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 10, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('─' * 40, maxLines: 1, overflow: TextOverflow.clip, style: line.copyWith(color: c.edge))),
              GestureDetector(
                key: const Key('deck-menu-close'),
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
                child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.close_rounded, size: 20, color: c.dim)),
              ),
            ],
          ),
          for (var i = 0; i < card.actions.length; i++)
            GestureDetector(
              key: Key('deck-action-${card.actions[i].id}'),
              behavior: HitTestBehavior.opaque,
              onTap: () {
                onClose();
                card.actions[i].onTap();
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    Text('[${i + 1}] ', style: line.copyWith(color: c.dim)),
                    Icon(card.actions[i].icon, size: 18, color: card.actions[i].warn ? c.warn : c.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        card.actions[i].label.toUpperCase(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: line.copyWith(color: card.actions[i].warn ? c.warn : c.ink),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
