import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../theme.dart';
import 'cover.dart';

/// Para mover el anillo desde fuera (por ejemplo, llevar una canción al frente).
class RingController {
  void Function(int index)? _centerOn;

  /// Gira el anillo hasta dejar esa canción al frente.
  void centerOn(int index) => _centerOn?.call(index);
}

/// Las canciones de un álbum como un anillo 3D de portadas, visto algo desde arriba, que se **gira arrastrando de lado**. La de enfrente es la
/// elegida. Con entre 6 y 11 canciones el anillo se cierra y se puede girar sin fin; con menos o con más es un arco, con tope en la
/// primera y la última. Al abrir el álbum las portadas salen de la placa tocada y se abren en anillo.
class SongRing extends StatefulWidget {
  const SongRing({
    super.key,
    required this.tracks,
    required this.animation,
    required this.origin,
    required this.artOf,
    required this.onSelect,
    required this.onTap,
    this.onLongPress,
    this.checked,
    this.cardKey,
    this.controller,
    this.initialIndex = 0,
    this.playingId,
    this.accent,
  });

  final List<Track> tracks;

  /// 0 → 1 al abrir el álbum.
  final Animation<double> animation;

  /// Lo que ocupa en la pantalla la placa de la que salen las portadas.
  final Rect origin;

  /// La imagen de cada canción (un archivo del teléfono), si la tiene.
  final String? Function(Track track) artOf;

  /// La canción de enfrente cambió (al girar).
  final ValueChanged<int> onSelect;

  /// Se tocó la portada de una canción.
  final void Function(Track track, int index) onTap;
  final ValueChanged<Track>? onLongPress;

  /// En el modo de marcar varias: ¿está marcada? (`null` fuera de ese modo).
  final bool Function(Track track)? checked;
  final Key? Function(Track track)? cardKey;
  final RingController? controller;
  final int initialIndex;

  /// La canción que suena ahora (lleva una marca).
  final String? playingId;
  final Color? accent;

  /// Cuánto hay que arrastrar el dedo (px) para pasar de una canción a la siguiente.
  static const pxPerStep = 90.0;

  /// Cuánto se ve el anillo desde arriba (radianes): así se ven también las canciones de atrás, por encima de las de enfrente.
  static const tilt = 0.5;

  /// ¿Se cierra el anillo? Con 6 a 11 canciones sí; con otras cantidades es un arco.
  static bool isClosed(int n) => n >= 6 && n < 12;

  /// El ángulo entre dos canciones seguidas (radianes).
  static double stepFor(int n) => isClosed(n) ? 2 * math.pi / n : math.pi / 6;

  /// El ángulo de la canción `index` cuando la de enfrente es la posición `pos` (0 = justo de frente; positivo = a la derecha).
  static double angleOf(int index, double pos, int n) {
    final raw = (index - pos) * stepFor(n);
    if (!isClosed(n)) return raw;
    final turn = 2 * math.pi;
    var a = raw % turn;
    if (a > math.pi) a -= turn;
    return a;
  }

  @override
  State<SongRing> createState() => _SongRingState();
}

class _SongRingState extends State<SongRing> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController.unbounded(vsync: this, value: widget.initialIndex.toDouble());
  final _box = GlobalKey();
  int _last = 0;

  int get _n => widget.tracks.length;

  int get _selected {
    final n = _n;
    if (n == 0) return 0;
    final i = _ctrl.value.round();
    return SongRing.isClosed(n) ? ((i % n) + n) % n : i.clamp(0, n - 1);
  }

  @override
  void initState() {
    super.initState();
    _last = _selected;
    _ctrl.addListener(() {
      final i = _selected;
      if (i != _last) {
        _last = i;
        widget.onSelect(i);
      }
    });
    widget.controller?._centerOn = _centerOn;
  }

  @override
  void didUpdateWidget(SongRing old) {
    super.didUpdateWidget(old);
    widget.controller?._centerOn = _centerOn;
    final n = _n;
    if (n > 0 && !SongRing.isClosed(n) && _ctrl.value > n - 1) _ctrl.value = (n - 1).toDouble(); // la lista se acortó
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _centerOn(int index) {
    final n = _n;
    if (n == 0) return;
    var target = index.toDouble();
    if (SongRing.isClosed(n)) {
      // por el lado más corto
      var delta = (index - _ctrl.value) % n;
      if (delta > n / 2) delta -= n;
      target = _ctrl.value + delta;
    }
    _go(target);
  }

  void _go(double target) {
    final n = _n;
    if (!SongRing.isClosed(n)) target = target.clamp(0.0, math.max(n - 1, 0).toDouble());
    _ctrl.animateTo(target, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
  }

  void _drag(DragUpdateDetails d) {
    final n = _n;
    if (n < 2) return;
    _ctrl.stop();
    var v = _ctrl.value - d.delta.dx / SongRing.pxPerStep;
    if (!SongRing.isClosed(n)) v = v.clamp(-0.45, n - 1 + 0.45);
    _ctrl.value = v;
  }

  void _end(DragEndDetails d) {
    if (_n < 2) return;
    final v = d.primaryVelocity ?? 0;
    _go((_ctrl.value - v / 1000).roundToDouble());
  }

  @override
  Widget build(BuildContext context) {
    final n = _n;
    return LayoutBuilder(
      builder: (context, box) {
        final card = math.min(math.min(box.maxWidth * 0.32, box.maxHeight * 0.36), 150.0);
        return GestureDetector(
          key: _box,
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: _drag,
          onHorizontalDragEnd: _end,
          child: AnimatedBuilder(
            animation: Listenable.merge([_ctrl, widget.animation]),
            builder: (context, _) => n == 0 ? const SizedBox.expand() : _stage(context, box, card),
          ),
        );
      },
    );
  }

  Widget _stage(BuildContext context, BoxConstraints box, double card) {
    final n = _n;
    final pos = _ctrl.value;
    final open = Curves.easeOutCubic.transform(const Interval(0.0, 0.85).transform(widget.animation.value));
    final radius = card * 1.55 * open;
    final spread = 0.35 + 0.65 * open;

    // de dónde salen las portadas: el centro de la placa tocada, respecto al centro del anillo
    var from = Offset.zero;
    final render = _box.currentContext?.findRenderObject();
    if (render is RenderBox && render.hasSize && widget.origin != Rect.zero) {
      from = (widget.origin.center - render.localToGlobal(render.size.center(Offset.zero))) * (1 - open);
    }

    final cards = <({int index, double angle})>[];
    for (var i = 0; i < n; i++) {
      final angle = SongRing.angleOf(i, pos, n) * spread;
      if (!SongRing.isClosed(n) && angle.abs() > 1.75) continue; // en un arco, solo lo que se ve
      cards.add((index: i, angle: angle));
    }
    // las de atrás primero: así las de delante las tapan
    cards.sort((a, b) => math.cos(a.angle).compareTo(math.cos(b.angle)));

    return Transform.translate(
      offset: from,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0009)
          ..rotateX(SongRing.tilt),
        // Con el tamaño de todo el espacio del anillo (no solo el de una carta): un toque solo llega a las cartas si cae dentro de la caja del
        // `Stack`, y las de los lados quedan fuera de la caja de la de enfrente.
        child: SizedBox(
          width: box.maxWidth,
          height: box.maxHeight,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none, // las cartas de los lados y de atrás sobresalen de su sitio
            children: [for (final c in cards) _card(context, c.index, c.angle, card, radius, open)],
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, int index, double angle, double size, double radius, double open) {
    final track = widget.tracks[index];
    final facing = math.cos(angle); // 1 = de frente, -1 = de espaldas
    final front = widget.checked == null && index == _selected && angle.abs() < 0.2;
    final checked = widget.checked?.call(track);
    final scale = (0.35 + 0.65 * open) * (front ? 1.06 : 1);
    final c = context.colors;
    final art = widget.artOf(track);
    final face = SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: front ? Border.all(color: widget.accent ?? c.accent, width: 2) : null,
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 10, offset: Offset(0, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Cover(url: track.coverUrl, file: art, size: size, radius: 0),
              // el título abajo, sobre un velo para que se lea sobre cualquier portada
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xCC000000)]),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 18, 8, 7),
                    child: Text(
                      _title(track),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.1),
                    ),
                  ),
                ),
              ),
              // de espaldas, más oscuras
              if (facing < 0)
                Positioned.fill(
                  child: ColoredBox(color: Colors.black.withValues(alpha: 0.35 + 0.25 * -facing)),
                ),
              if (widget.playingId == track.id)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(Icons.graphic_eq_rounded, key: const Key('ring-playing'), size: 20, color: Colors.white),
                ),
              if (checked != null)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Icon(
                    checked ? Icons.check_circle : Icons.radio_button_unchecked,
                    key: Key(checked ? 'row-selected' : 'row-unselected'),
                    size: 22,
                    color: checked ? (widget.accent ?? c.accent) : Colors.white70,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    // La transformación va la primera, directamente bajo el `Stack`, y la opacidad por dentro: un `Transform` no comprueba si el toque cae en
    // su caja sin mover (deja que lo decida su hijo ya movido), así los toques aciertan también en las cartas de los lados; y la capa de
    // opacidad no recorta lo que sobresale por la perspectiva. Con `IgnorePointer` por fuera no llegarían: miraría la caja sin mover.
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        // el eje del anillo está detrás de la de enfrente (en Flutter, +z se aleja): las de los lados quedan más atrás y más pequeñas
        ..translateByDouble(0.0, 0.0, radius, 1.0)
        ..rotateY(-angle)
        ..translateByDouble(0.0, 0.0, -radius, 1.0)
        ..scaleByDouble(scale, scale, scale, 1.0),
      child: IgnorePointer(
        ignoring: facing < 0, // las de espaldas no se tocan
        child: GestureDetector(
          key: widget.cardKey?.call(track) ?? ValueKey('ring-${track.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onTap(track, index),
          onLongPress: widget.onLongPress == null ? null : () => widget.onLongPress!(track),
          child: Opacity(opacity: open * (0.6 + 0.4 * ((facing + 1) / 2)), child: face),
        ),
      ),
    );
  }

  String _title(Track track) {
    final i = track.title.indexOf(' - ');
    return i > 0 ? track.title.substring(i + 3) : track.title;
  }
}
