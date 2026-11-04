import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../theme.dart';
import '../../util/format.dart';
import 'album_art.dart';

/// La lista de canciones de un álbum: discos pequeños a lo largo de una **curva**, con la fila del centro en una píldora con el botón de
/// reproducir. La curva se abomba hacia la izquierda: la fila del centro es la que más se acerca al borde y las demás se apartan al alejarse.
/// Se desplaza con imán a la fila del centro. Tocar otra fila la trae al centro; con canciones marcadas, tocar marca o desmarca.
///
/// Sin `BackdropFilter`: va bajo el difuminado de arriba y de abajo, que se lo quitaría.
class SongArcList extends StatefulWidget {
  const SongArcList({
    super.key,
    required this.tracks,
    required this.focus,
    required this.opening,
    required this.file,
    required this.url,
    required this.icon,
    required this.keyOf,
    required this.lineOf,
    required this.isCurrent,
    required this.isPlaying,
    required this.onPlay,
    required this.onFocus,
    required this.onDoubleTap,
    this.warnOf,
    this.savedOf,
    this.selectedOf,
    this.onHold,
    this.onToggle,
    this.actionsOf,
    this.extraOf,
  });

  final List<Track> tracks;

  /// La fila que va en el centro. Si cambia desde fuera (porque pasó a sonar otra canción), la lista va hasta ella.
  final int focus;

  /// 0 → 1 al abrirse: las filas llegan por la derecha, una tras otra.
  final Animation<double> opening;

  /// La portada del álbum.
  final String? file;
  final String? url;
  final IconData icon;

  final Key Function(Track track) keyOf;

  /// El texto de debajo del nombre.
  final String Function(Track track) lineOf;

  /// Ese texto es un aviso de error.
  final bool Function(Track track)? warnOf;

  /// Ya está guardada en el teléfono: una marquita junto a ese texto.
  final bool Function(Track track)? savedOf;

  /// ¿Es la canción puesta (aunque esté en pausa)? ¿Está sonando?
  final bool Function(Track track) isCurrent;
  final bool Function(Track track) isPlaying;
  final ValueChanged<Track> onPlay;

  /// Otra fila ha quedado en el centro.
  final ValueChanged<int> onFocus;

  /// Doble toque en cualquier parte menos en la píldora, donde están los botones.
  final VoidCallback onDoubleTap;

  /// `null` fuera del modo de marcar; si no, si está marcada.
  final bool? Function(Track track)? selectedOf;
  final ValueChanged<Track>? onHold;
  final ValueChanged<Track>? onToggle;

  /// Los botones junto al de reproducir (el corazón).
  final List<Widget> Function(Track track)? actionsOf;

  /// Lo que va en una segunda línea de la píldora («Recibido» y el menú ⋯ de las enviadas).
  final List<Widget> Function(Track track)? extraOf;

  /// El alto de cada fila, el lado de cada disco y el radio de la curva (del alto de la lista).
  static const extent = 112.0;
  static const thumb = 74.0;
  static const curve = 0.95;

  /// A qué distancia del borde izquierdo va la fila del centro.
  static const edge = 14.0;

  /// Cuánto se aparta de la izquierda una fila que está a `rows` filas del centro, en una curva de radio `radius`.
  static double offsetOf(double rows, double radius) {
    final y = math.min((rows * extent).abs(), radius);
    return radius - math.sqrt(radius * radius - y * y);
  }

  @override
  State<SongArcList> createState() => _SongArcListState();
}

class _SongArcListState extends State<SongArcList> {
  late final FixedExtentScrollController _scroll = FixedExtentScrollController(initialItem: widget.focus);
  late int _focus = widget.focus;

  // el doble toque se cuenta a mano: un detector por encima haría esperar a cada toque de las filas y de sus botones por si llega un segundo
  Offset? _downAt;
  Duration _downTime = Duration.zero;
  Offset? _lastUpAt;
  Duration _lastUpTime = Duration.zero;
  bool _inPill = false;

  @override
  void didUpdateWidget(SongArcList old) {
    super.didUpdateWidget(old);
    if (widget.focus != old.focus && widget.focus != _focus && _scroll.hasClients) {
      unawaited(_scroll.animateToItem(widget.focus, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic));
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onSelected(int i) {
    setState(() => _focus = i);
    widget.onFocus(i);
  }

  void _tapRow(int i, Track track) {
    final selected = widget.selectedOf?.call(track);
    if (selected != null) {
      widget.onToggle?.call(track);
    } else if (i != _focus) {
      unawaited(_scroll.animateToItem(i, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic));
    }
  }

  void _pointerDown(PointerDownEvent e) {
    _downAt = e.position;
    _downTime = e.timeStamp;
  }

  void _pointerUp(PointerUpEvent e) {
    final down = _downAt;
    final wasPill = _inPill;
    _inPill = false;
    _downAt = null;
    if (wasPill || down == null || (e.position - down).distance > kTouchSlop || e.timeStamp - _downTime > kLongPressTimeout) {
      _lastUpAt = null;
      return;
    }
    final last = _lastUpAt;
    if (last != null && e.timeStamp - _lastUpTime <= kDoubleTapTimeout && (e.position - last).distance <= kDoubleTapSlop) {
      _lastUpAt = null;
      widget.onDoubleTap();
    } else {
      _lastUpAt = e.position;
      _lastUpTime = e.timeStamp;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _pointerDown,
      onPointerUp: _pointerUp,
      child: ShaderMask(
        key: const Key('arc-fade'),
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00FFFFFF), Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
          stops: [0.05, 0.24, 0.80, 0.97],
        ).createShader(rect),
        child: LayoutBuilder(
          builder: (context, box) {
            final radius = box.maxHeight * SongArcList.curve;
            return ListWheelScrollView.useDelegate(
              key: const Key('arc-list'),
              controller: _scroll,
              itemExtent: SongArcList.extent,
              physics: const FixedExtentScrollPhysics(),
              perspective: 0.0012,
              diameterRatio: 3.4,
              onSelectedItemChanged: _onSelected,
              childDelegate: ListWheelChildBuilderDelegate(
                childCount: widget.tracks.length,
                builder: (context, i) => AnimatedBuilder(
                  animation: Listenable.merge([_scroll, widget.opening]),
                  builder: (context, _) {
                    final at = _scroll.hasClients && _scroll.position.haveDimensions ? _scroll.offset / SongArcList.extent : widget.focus.toDouble();
                    final rows = i - at;
                    final delay = math.min(rows.abs() * 0.12, 0.5);
                    final enter = Curves.easeOutCubic.transform(((widget.opening.value - delay) / (1 - delay)).clamp(0.0, 1.0));
                    return Transform.translate(
                      offset: Offset((1 - enter) * box.maxWidth * 0.7, 0),
                      child: Padding(
                        padding: EdgeInsets.only(left: SongArcList.edge + SongArcList.offsetOf(rows, radius), right: 12),
                        child: _row(context, i),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _row(BuildContext context, int i) {
    final c = context.colors;
    final track = widget.tracks[i];
    final named = splitArtistTitle(track.title);
    final selected = widget.selectedOf?.call(track);
    final focused = i == _focus;
    final warn = widget.warnOf?.call(track) ?? false;
    final extra = focused && selected == null ? (widget.extraOf?.call(track) ?? const <Widget>[]) : const <Widget>[];
    final playing = widget.isPlaying(track);

    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(named.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: const Color(0xFFF4F4F6), fontSize: focused ? 17 : 16, fontWeight: focused ? FontWeight.w600 : FontWeight.w500, fontStyle: FontStyle.italic)),
        const SizedBox(height: 2),
        Row(
          children: [
            if (widget.savedOf?.call(track) ?? false) ...[
              Icon(Icons.check_circle, key: const Key('saved'), size: 13, color: c.accent),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(widget.lineOf(track), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: warn ? c.warn : const Color(0x99F4F4F6), fontSize: 13, fontStyle: FontStyle.italic)),
            ),
          ],
        ),
      ],
    );

    final Widget pill = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(16, focused ? 8 : 0, focused ? 8 : 0, focused ? 8 : 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: focused ? const Color(0x2EFFFFFF) : const Color(0x00FFFFFF)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: focused ? const [Color(0x33FFFFFF), Color(0x12FFFFFF)] : const [Color(0x00FFFFFF), Color(0x00FFFFFF)],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: words),
              if (focused && selected == null) ...[
                ...?widget.actionsOf?.call(track),
                IconButton(
                  key: Key('arc-play-${track.id}'),
                  tooltip: playing ? 'Pausar' : 'Reproducir',
                  constraints: const BoxConstraints.tightFor(width: 56, height: 40),
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(backgroundColor: const Color(0xFF2B2B2F), foregroundColor: const Color(0xFFF4F4F6)),
                  icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 24),
                  onPressed: () => widget.onPlay(track),
                ),
              ],
            ],
          ),
          if (extra.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: extra),
            ),
        ],
      ),
    );

    return Semantics(
      label: named.title,
      button: true,
      child: GestureDetector(
        key: widget.keyOf(track),
        behavior: HitTestBehavior.opaque,
        onTap: () => _tapRow(i, track),
        onLongPress: widget.onHold == null ? null : () => widget.onHold!(track),
        child: Row(
          children: [
            _Thumb(file: widget.file, url: widget.url, icon: widget.icon, selected: selected, current: widget.isCurrent(track), playing: playing),
            const SizedBox(width: 10),
            Expanded(
              child: focused && selected == null
                  ? Listener(onPointerDown: (_) => _inPill = true, child: pill)
                  : pill,
            ),
          ],
        ),
      ),
    );
  }
}

/// El disco pequeño de una fila: la portada en círculo, con su aro; la que suena lleva un ecualizador y, si se está marcando, su casilla.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.file, required this.url, required this.icon, required this.selected, required this.current, required this.playing});

  final String? file;
  final String? url;
  final IconData icon;
  final bool? selected;

  /// Es la canción puesta: un ecualizador si suena, una pausa si no.
  final bool current;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const size = SongArcList.thumb;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AlbumArt(file: file, url: url, icon: icon, size: size, radius: size / 2),
          const DecoratedBox(
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.fromBorderSide(BorderSide(color: Color(0x40FFFFFF), width: 1.2))),
            child: SizedBox.square(dimension: size),
          ),
          if (current && selected == null)
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
              child: Icon(playing ? Icons.graphic_eq_rounded : Icons.pause_rounded, key: const Key('now-playing'), size: 22, color: Colors.white),
            ),
          if (selected == true) ...[
            Container(width: size, height: size, decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.85), shape: BoxShape.circle)),
            const Icon(Icons.check_rounded, key: Key('row-selected'), size: 30, color: Colors.white),
          ],
          if (selected == false) Container(key: const Key('row-unselected'), width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.dim, width: 2))),
        ],
      ),
    );
  }
}
