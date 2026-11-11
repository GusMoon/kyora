import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import 'cover.dart';
import 'cut_border.dart';
import 'deck_math.dart';
import 'pixel_glyph.dart';
import 'hack_text.dart';

/// Un álbum de la pila: su portada (la que le pusiste, o la de su primera canción, o un recuadro con un icono) y su nombre.
class DeckCard {
  const DeckCard({required this.id, required this.title, required this.icon, required this.onTap, this.coverFile, this.coverUrl});

  /// Con esta clave se encuentra la tarjeta (`card-root`, `card-folder-Rock`…).
  final String id;
  final String title;
  final IconData icon;

  /// Se llama con el rectángulo que ocupa la portada en la pantalla: de ahí «sale» el disco al abrir el álbum.
  final void Function(Rect origin) onTap;

  final String? coverFile;
  final String? coverUrl;
}

/// Lo que ocupa en la pantalla el widget de `context` (para que el disco del álbum salga de ahí).
Rect rectOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize || !box.attached) return Rect.zero;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Para saber (y cambiar) desde fuera qué álbum está enfocado en la pila.
class DeckController {
  _AlbumStackState? _state;

  /// El número del álbum enfocado (el del centro).
  int get current => _state?._front ?? 0;

  /// Lo deja enfocado, sin animación.
  void jumpTo(int index) => _state?._jumpTo(index);
}

/// Dónde va una portada de la pila.
typedef StackPlace = ({Offset center, double scale, double turn, double shade});

/// Los álbumes como una **pila vertical de portadas** que se desplaza con el dedo: la del centro, grande y delante; las demás, más pequeñas,
/// detrás y asomando por arriba y por abajo, un poco hacia un lado y otro (en cascada, como fotos sueltas apiladas). Al soltar sigue un poco por
/// la inercia y se detiene en una portada. Tocar la del centro abre el álbum; tocar otra la trae al centro.
class AlbumStack extends StatefulWidget {
  const AlbumStack({super.key, required this.cards, this.controller, this.hiddenId, this.cardKeys, this.speed = 1});

  final List<DeckCard> cards;
  final DeckController? controller;

  /// La tarjeta cuya portada no se pinta (porque en ese momento la está pintando el disco que sale de ella).
  final String? hiddenId;

  /// La clave de la portada de cada tarjeta, por `id` (para saber dónde está en la pantalla).
  final Map<String, GlobalKey>? cardKeys;

  /// La sensibilidad: 1 es lo normal, menos es más lenta (se elige en Configuración).
  final double speed;

  /// El lado de la portada del centro, del ancho disponible.
  static const fraction = 0.8;

  /// Lo que separa (en vertical) dos portadas seguidas, del lado de la portada.
  static const spacing = 0.44;

  /// Hasta dónde se dibujan portadas por arriba y por abajo del centro.
  static const reach = 3.5;

  /// Lo que hay que arrastrar el dedo para pasar a la portada siguiente.
  static double pixelsFor(double side, double speed) => side * spacing / speed;

  /// El lado de la portada del centro en un área.
  static double sideFor(Size area) => math.min(area.width * fraction, area.height * 0.66);

  /// Dónde va la portada `index` cuando el centro está en `pos`: su centro, su escala, su giro y lo oscurecida que va.
  static StackPlace placeOf(int index, double pos, Size area, double side) {
    final d = index - pos;
    final away = d.abs().clamp(0.0, reach);
    final lean = index.isEven ? -1.0 : 1.0; // una hacia un lado y la siguiente hacia el otro
    final side1 = away.clamp(0.0, 1.0);
    return (
      center: Offset(area.width / 2 + lean * area.width * 0.09 * side1, area.height / 2 + d * side * spacing),
      scale: 1 - 0.14 * away.clamp(0.0, 3.0),
      turn: lean * 0.06 * away.clamp(0.0, 1.5),
      shade: (0.22 * away).clamp(0.0, 0.7),
    );
  }

  @override
  State<AlbumStack> createState() => _AlbumStackState();
}

class _AlbumStackState extends State<AlbumStack> with SingleTickerProviderStateMixin {
  late final AnimationController _pos = AnimationController.unbounded(vsync: this)..addListener(_onMove);
  int _lastFront = 0;
  double _pixels = DeckMath.basePixels;

  int get _n => widget.cards.length;
  int get _front => _n == 0 ? 0 : _pos.value.round().clamp(0, _n - 1);

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
  }

  @override
  void didUpdateWidget(AlbumStack old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (old.controller?._state == this) old.controller?._state = null;
      widget.controller?._state = this;
    }
    // si cambian los álbumes, se sigue en el mismo
    if (old.cards.length != _n && old.cards.isNotEmpty && _n > 0) {
      final id = old.cards[_pos.value.round().clamp(0, old.cards.length - 1)].id;
      final at = widget.cards.indexWhere((card) => card.id == id);
      _pos.stop();
      _pos.value = (at < 0 ? 0 : at).toDouble();
    }
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    _pos.dispose();
    super.dispose();
  }

  void _jumpTo(int index) {
    _pos.stop();
    _pos.value = index.clamp(0, math.max(0, _n - 1)).toDouble();
  }

  void _onMove() {
    final front = _front;
    if (front == _lastFront) return;
    _lastFront = front;
    unawaited(HapticFeedback.selectionClick().catchError((Object _) {}));
  }

  void _dragStart(DragStartDetails _) => _pos.stop();

  void _dragUpdate(DragUpdateDetails d) {
    if (_n < 2) return;
    _pos.value = (_pos.value - d.delta.dy / _pixels).clamp(-0.4, _n - 0.6);
  }

  void _settle(double velocity) {
    if (_n == 0) return;
    final target = DeckMath.settleAt(_pos.value, velocity, pixels: _pixels).clamp(0.0, (_n - 1).toDouble());
    _goTo(target);
  }

  void _goTo(double target) {
    final distance = (target - _pos.value).abs();
    final time = Duration(milliseconds: (300 + distance * 110).round().clamp(260, 900));
    unawaited(_pos.animateTo(target, duration: time, curve: Curves.easeOutCubic));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      key: const Key('album-deck'),
      builder: (context, box) {
        final area = box.biggest;
        final side = AlbumStack.sideFor(area);
        _pixels = AlbumStack.pixelsFor(side, widget.speed);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: _dragStart,
          onVerticalDragUpdate: _dragUpdate,
          onVerticalDragEnd: (d) => _settle(d.primaryVelocity ?? 0),
          onVerticalDragCancel: () => _settle(0),
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _pos,
              builder: (context, _) {
                if (_n == 0) return const SizedBox.expand();
                final pos = _pos.value;
                final front = _front;
                final shown = [
                  for (var i = 0; i < _n; i++)
                    if ((i - pos).abs() <= AlbumStack.reach) i,
                ]..sort((a, b) => (b - pos).abs().compareTo((a - pos).abs())); // las lejanas primero: las cercanas las tapan
                final card = widget.cards[front];
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    for (final i in shown) _card(i, pos, area, side, i == front),
                    // la etiqueta del centro: su nombre y en qué número va, como un HUD
                    Positioned(
                      left: 16,
                      right: 16,
                      top: 6,
                      child: Row(
                        children: [
                          Text('> ', style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.accent)),
                          Expanded(
                            child: HackText(
                              card.title,
                              textKey: Key('deck-title-${card.id}'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: monoFont, fontSize: 15, fontWeight: FontWeight.w600, color: c.ink),
                            ),
                          ),
                          Text(
                            '${(front + 1).toString().padLeft(2, '0')}/${_n.toString().padLeft(2, '0')}',
                            key: const Key('deck-index'),
                            style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _card(int index, double pos, Size area, double side, bool isFront) {
    final card = widget.cards[index];
    final place = AlbumStack.placeOf(index, pos, area, side);
    final size = side * place.scale;
    return Positioned(
      key: ValueKey('slot-${card.id}'),
      left: place.center.dx - size / 2,
      top: place.center.dy - size / 2,
      width: size,
      height: size,
      child: Transform.rotate(
        angle: place.turn,
        child: _Card(
          card: card,
          side: size,
          shade: place.shade,
          focused: isFront,
          hidden: widget.hiddenId == card.id,
          coverKey: widget.cardKeys?[card.id],
          onBring: () => _goTo(index.toDouble()),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.card, required this.side, required this.shade, required this.focused, required this.hidden, required this.onBring, this.coverKey});

  final DeckCard card;
  final double side;

  /// Lo oscurecida que va (de 0 a 1): más cuanto más lejos del centro.
  final double shade;
  final bool focused;
  final bool hidden;
  final VoidCallback onBring;
  final GlobalKey? coverKey;

  /// Lo que se corta cada esquina de la portada (la misma que la del disco al salir).
  static const radius = 18.0;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: card.title,
      button: true,
      child: GestureDetector(
        key: ValueKey(card.id),
        behavior: HitTestBehavior.opaque,
        onTap: focused ? () => card.onTap(rectOf(coverKey?.currentContext ?? context)) : onBring,
        child: SizedBox(
          key: coverKey,
          width: side,
          height: side,
          child: hidden
              ? const SizedBox.shrink(key: Key('deck-hidden'))
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    DeckArt(card: card, side: side, focused: focused),
                    // las de atrás, más oscuras cuanto más lejos
                    if (shade > 0.02)
                      ClipPath(
                        clipper: const ShapeBorderClipper(shape: CutBorder(cut: radius)),
                        child: ColoredBox(color: Colors.black.withValues(alpha: shade)),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// La cara de la tarjeta: la portada entera dentro del marco de esquinas cortadas, o un recuadro con el icono.
class DeckArt extends StatelessWidget {
  const DeckArt({super.key, required this.card, required this.side, this.focused = false});

  final DeckCard card;
  final double side;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (card.coverFile != null || card.coverUrl != null) {
      return Cover(url: card.coverUrl, file: card.coverFile, size: side, radius: _Card.radius, focused: focused);
    }
    return CoverFrame(
      cut: _Card.radius,
      focused: focused,
      child: ColoredBox(key: const Key('plate-blank'), color: c.surface, child: Center(child: LcdIcon(card.icon, size: side * 0.32, color: c.dim))),
    );
  }
}
