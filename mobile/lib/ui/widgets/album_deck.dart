import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import 'cover.dart';

/// Un álbum de la ruleta: su portada (la que le pusiste, o la de su primera canción, o un recuadro con un icono) y su nombre.
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

/// Para saber (y cambiar) desde fuera qué álbum tiene enfrente la ruleta.
class DeckController {
  _AlbumDeckState? _state;

  /// El número del álbum de enfrente.
  int get current => _state?._front ?? 0;

  /// Lo deja enfrente, sin animación.
  void jumpTo(int index) => _state?._jumpTo(index);
}

/// Los álbumes como una **ruleta**. En reposo solo se ve el de enfrente, en grande: los demás esperan escondidos detrás de él. Al tirar a un
/// lado o al otro el anillo se abre en perspectiva y gira, sin tope; al soltar sigue un poco por la inercia, se detiene en un álbum y los demás
/// vuelven suavemente detrás. Tocar el de enfrente lo abre.
///
/// Nada usa opacidad: lo que se esconde queda tapado, y lo de atrás se oscurece con un velo. Recorta en su propio rectángulo: al cambiar de
/// sección un bloque solo se desplaza un ancho de pantalla, y lo que sobresaliera seguiría a la vista.
class AlbumDeck extends StatefulWidget {
  const AlbumDeck({super.key, required this.cards, this.controller, this.hiddenId, this.cardKeys});

  final List<DeckCard> cards;

  final DeckController? controller;

  /// La tarjeta cuya portada no se pinta (porque en ese momento la está pintando el disco que sale de ella).
  final String? hiddenId;

  /// La clave de la portada de cada tarjeta, por `id` (para saber dónde está en la pantalla).
  final Map<String, GlobalKey>? cardKeys;

  /// Cuánto de la pantalla ocupa la tarjeta de enfrente en reposo.
  static const fraction = 0.74;

  /// Cuánto hay que arrastrar el dedo (px) para pasar de un álbum al siguiente.
  static const pxPerStep = 110.0;

  /// Cuánto se ve el anillo desde arriba al girar (rad): así asoman también los de atrás, por encima del de enfrente.
  static const tilt = 0.34;

  /// Lo que encoge cada tarjeta con el anillo abierto.
  static const openScale = 0.70;

  /// El espacio de más que hay encima de la tarjeta para los álbumes de atrás.
  static const rise = 64.0;

  /// Lo que tarda el anillo en abrirse y, al detenerse, en recogerse.
  static const openTime = Duration(milliseconds: 220);
  static const closeTime = Duration(milliseconds: 420);

  /// El ángulo entre dos álbumes seguidos (rad): la vuelta entera repartida entre todos, salvo si son muchos (entonces no da la vuelta entera
  /// a la vista, pero sigue sin tener tope).
  static double stepFor(int n) => n < 2 ? 0 : math.max(2 * math.pi / n, math.pi / 6);

  /// El ángulo del álbum `index` cuando enfrente está la posición `pos` (0 = de frente; positivo = a la derecha), por el lado más corto.
  static double angleOf(int index, double pos, int n) {
    if (n < 2) return 0;
    var away = (index - pos) % n;
    if (away > n / 2) away -= n;
    return away * stepFor(n);
  }

  /// El álbum de enfrente en la posición `pos`.
  static int frontOf(double pos, int n) => n == 0 ? 0 : pos.round() % n;

  /// A qué posición llega la ruleta si se suelta en `pos` con esta velocidad del dedo (px/s).
  static double settleAt(double pos, double velocity) => (pos - velocity / pxPerStep * 0.35).roundToDouble();

  @override
  State<AlbumDeck> createState() => _AlbumDeckState();
}

class _AlbumDeckState extends State<AlbumDeck> with TickerProviderStateMixin {
  late final AnimationController _pos;
  late final AnimationController _spread;
  bool _dragging = false;
  int _lastFront = 0;

  int get _n => widget.cards.length;
  int get _front => AlbumDeck.frontOf(_pos.value, _n);

  @override
  void initState() {
    super.initState();
    _pos = AnimationController.unbounded(vsync: this)..addListener(_onTurn);
    _spread = AnimationController(vsync: this, duration: AlbumDeck.openTime);
    widget.controller?._state = this;
  }

  @override
  void didUpdateWidget(AlbumDeck old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (old.controller?._state == this) old.controller?._state = null;
      widget.controller?._state = this;
    }
    // si cambian los álbumes, se sigue enfrente del mismo
    if (old.cards.length != _n && old.cards.isNotEmpty && _n > 0) {
      final id = old.cards[AlbumDeck.frontOf(_pos.value, old.cards.length)].id;
      final at = widget.cards.indexWhere((card) => card.id == id);
      _pos.stop();
      _pos.value = (at < 0 ? 0 : at).toDouble();
    }
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    _pos.dispose();
    _spread.dispose();
    super.dispose();
  }

  void _jumpTo(int index) {
    _pos.stop();
    _pos.value = index.toDouble();
  }

  void _onTurn() {
    final front = _front;
    if (front == _lastFront) return;
    _lastFront = front;
    if (_dragging || _spread.value > 0) unawaited(HapticFeedback.selectionClick().catchError((Object _) {}));
  }

  void _open() {
    unawaited(_spread.animateTo(1, duration: AlbumDeck.openTime, curve: Curves.easeOutCubic));
  }

  void _close() {
    unawaited(_spread.animateTo(0, duration: AlbumDeck.closeTime, curve: Curves.easeInOutCubic));
  }

  void _dragStart(DragStartDetails _) {
    _dragging = true;
    _pos.stop();
    _open();
  }

  void _dragUpdate(DragUpdateDetails d) => _pos.value -= d.delta.dx / AlbumDeck.pxPerStep;

  void _settle(double velocity) {
    _dragging = false;
    final target = AlbumDeck.settleAt(_pos.value, velocity);
    final distance = (target - _pos.value).abs();
    final time = Duration(milliseconds: (320 + distance * 130).round().clamp(320, 1100));
    // solo al completarse: si se vuelve a agarrar a mitad, esto no se cumple y el anillo sigue abierto
    unawaited(_pos.animateTo(target, duration: time, curve: Curves.easeOutCubic).then((_) {
      if (mounted && !_dragging) _close();
    }));
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final side = width * AlbumDeck.fraction - 24; // el cuadrado de la portada (con aire a los lados)
    final spins = _n > 1;
    return SizedBox(
      key: const Key('album-deck'),
      height: AlbumDeck.rise + side + 64,
      child: ClipRect(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: spins ? _dragStart : null,
          onHorizontalDragUpdate: spins ? _dragUpdate : null,
          onHorizontalDragEnd: spins ? (d) => _settle(d.primaryVelocity ?? 0) : null,
          onHorizontalDragCancel: spins ? () => _settle(0) : null,
          child: AnimatedBuilder(
            animation: Listenable.merge([_pos, _spread]),
            builder: (context, _) => _stage(context, width, side),
          ),
        ),
      ),
    );
  }

  Widget _stage(BuildContext context, double width, double side) {
    final n = _n;
    if (n == 0) return const SizedBox.expand();
    final c = context.colors;
    final s = _spread.value;
    final pos = _pos.value;
    final front = _front;
    final limit = n <= 12 ? math.pi + 0.01 : math.pi * 5 / 6;
    final shown = <({int index, double angle})>[
      for (var i = 0; i < n; i++)
        if (AlbumDeck.angleOf(i, pos, n).abs() <= limit) (index: i, angle: AlbumDeck.angleOf(i, pos, n)),
    ]
      // los de atrás primero: los de delante los tapan
      ..sort((a, b) => math.cos(a.angle).compareTo(math.cos(b.angle)));
    final card = widget.cards[front];
    return Stack(
      fit: StackFit.expand,
      children: [
        // el anillo, inclinado solo mientras está abierto
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: AlbumDeck.rise + side,
          child: Transform(
            alignment: Alignment(0, (AlbumDeck.rise) / (AlbumDeck.rise + side)),
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0009)
              ..rotateX(AlbumDeck.tilt * s),
            child: Stack(
              clipBehavior: Clip.none,
              children: [for (final item in shown) _card(item.index, item.angle, side, width, s, item.index == front)],
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          top: AlbumDeck.rise + side + 14,
          child: Text(card.title, key: Key('deck-title-${card.id}'), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(color: c.ink, fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _card(int index, double angle, double side, double width, double s, bool isFront) {
    final card = widget.cards[index];
    final facing = math.cos(angle); // 1 = de frente, -1 = de espaldas
    final open = angle * s; // cerrado, todos miran de frente y en el mismo sitio: tapados por el de enfrente
    final radius = side * 0.78 * s;
    final scale = 1 - (1 - AlbumDeck.openScale) * s;
    final shade = s * 0.62 * (1 - facing) / 2;
    return Positioned(
      key: ValueKey('slot-${card.id}'),
      left: (width - side) / 2,
      top: AlbumDeck.rise,
      width: side,
      height: side,
      // cerrado, los de detrás ni se pintan (siguen vivos, para no volver a leer su portada al girar)
      child: Offstage(
        offstage: s == 0 && !isFront,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            // el eje del anillo está detrás del de enfrente (en Flutter, +z se aleja): los de los lados quedan más atrás y más pequeños
            ..translateByDouble(0.0, 0.0, radius, 1.0)
            ..rotateY(-open)
            ..translateByDouble(0.0, 0.0, -radius, 1.0)
            ..scaleByDouble(scale, scale, scale, 1.0),
          child: IgnorePointer(
            ignoring: !isFront || s > 0.5,
            child: _Card(
              card: card,
              side: side,
              shade: shade,
              hidden: widget.hiddenId == card.id,
              coverKey: widget.cardKeys?[card.id],
            ),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.card, required this.side, required this.shade, required this.hidden, this.coverKey});

  final DeckCard card;
  final double side;

  /// Lo oscurecido que va (de 0 a 1): más cuanto más atrás.
  final double shade;
  final bool hidden;
  final GlobalKey? coverKey;

  /// Lo redondeadas que van las esquinas de la portada (la misma que la del disco al salir).
  static const radius = 28.0;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: card.title,
      button: true,
      child: GestureDetector(
        key: ValueKey(card.id),
        behavior: HitTestBehavior.opaque,
        onTap: () => card.onTap(rectOf(coverKey?.currentContext ?? context)),
        child: SizedBox(
          key: coverKey,
          width: side,
          height: side,
          child: hidden
              ? const SizedBox.shrink(key: Key('deck-hidden'))
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    DeckArt(card: card, side: side),
                    if (shade > 0.005) DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius), color: Colors.black.withValues(alpha: shade))),
                  ],
                ),
        ),
      ),
    );
  }
}

/// La cara de la tarjeta: la portada con las esquinas redondeadas, o un recuadro con el icono.
class DeckArt extends StatelessWidget {
  const DeckArt({super.key, required this.card, required this.side});

  final DeckCard card;
  final double side;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (card.coverFile != null || card.coverUrl != null) {
      return Cover(url: card.coverUrl, file: card.coverFile, size: side, radius: _Card.radius);
    }
    return DecoratedBox(
      key: const Key('plate-blank'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_Card.radius),
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c.pick, c.plate]),
      ),
      child: Center(child: Icon(card.icon, size: side * 0.32, color: c.dim)),
    );
  }
}
