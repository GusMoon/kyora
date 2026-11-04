import 'dart:async';

import 'package:flutter/material.dart';

import 'widgets/section_rail.dart';

/// Las secciones de la app una al lado de la otra: se cambia de una a otra **deslizando de lado**, sin iconos en las esquinas.
/// Al deslizar de lado (solo con un deslizamiento horizontal de verdad, no con uno vertical o diagonal) sale del borde derecho la barra
/// con los iconos de las secciones, con el de destino resaltado; se esconde en cuanto se vuelve a tocar la pantalla y, si no, sola a
/// los 2 s.
/// Cada sección conserva su estado (lo escrito, el scroll…) al ir y volver, y sus avisos salen solo en su pantalla.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.sections, this.initial = 0, this.hintOnStart = false, this.hideAfter = const Duration(seconds: 2)});

  final List<AppSection> sections;

  /// La sección con la que se arranca (y a la que vuelve «atrás»).
  final int initial;

  /// Enseñar la barra un momento al entrar (por defecto no: solo sale al deslizar).
  final bool hintOnStart;

  /// Cuánto tarda la barra en esconderse después de dejar de deslizar.
  final Duration hideAfter;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final PageController _controller = PageController(initialPage: widget.initial);
  late int _index = widget.initial;
  bool _visible = false;
  Timer? _hide;

  /// Lo que se ha movido el dedo desde que tocó la pantalla (px). La barra solo sale si el movimiento es de verdad de lado: así un
  /// deslizamiento vertical o en diagonal —aunque el `PageView` llegue a ganar el gesto— no la saca.
  double _dx = 0;
  double _dy = 0;

  /// Lo que hay que moverse de lado (px) y cuánto más de lado que vertical.
  static const _showAfter = 32.0;
  static const _sideness = 1.6;

  @override
  void initState() {
    super.initState();
    if (widget.hintOnStart && widget.sections.length > 1) {
      _visible = true;
      _hide = Timer(widget.hideAfter + const Duration(milliseconds: 800), _hideNow);
    }
  }

  @override
  void dispose() {
    _hide?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _show() {
    _hide?.cancel();
    if (!_visible) setState(() => _visible = true);
  }

  void _hideLater() {
    _hide?.cancel();
    _hide = Timer(widget.hideAfter, _hideNow);
  }

  void _hideNow() {
    _hide?.cancel();
    if (mounted && _visible) setState(() => _visible = false);
  }

  bool _onScroll(ScrollNotification n) {
    // solo el deslizamiento de las secciones (el del propio PageView), no el de las listas que hay dentro de cada una
    if (n.depth != 0 || n.metrics.axis != Axis.horizontal) return false;
    if (n is ScrollUpdateNotification) {
      // con el dedo (no una animación) y habiéndose movido de lado de verdad
      if (n.dragDetails != null && _dx.abs() > _showAfter && _dx.abs() > _sideness * _dy.abs()) _show();
    } else if (n is ScrollEndNotification) {
      if (_visible) _hideLater();
    }
    return false;
  }

  Future<void> _go(int i) {
    _show();
    return _controller.animateToPage(i, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // «atrás» vuelve a la sección de inicio antes de salir de la app
      canPop: _index == widget.initial,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_go(widget.initial));
      },
      child: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            // volver a tocar la pantalla esconde la barra al instante (sin entrar en la pelea de gestos: es `translucent`)
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) {
                _dx = 0;
                _dy = 0;
                _hideNow();
              },
              onPointerMove: (e) {
                _dx += e.delta.dx;
                _dy += e.delta.dy;
              },
              child: PageView.builder(
                key: const Key('sections-pager'),
                controller: _controller,
                itemCount: widget.sections.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _SectionPage(key: ValueKey(widget.sections[i].id), child: Builder(builder: widget.sections[i].builder)),
              ),
            ),
          ),
          // la barra sale del borde derecho, centrada a lo alto, como los paneles del escritorio
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !_visible,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                offset: _visible ? Offset.zero : const Offset(1.25, 0),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: _visible ? 1 : 0,
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) => SectionRail(
                        sections: widget.sections,
                        page: _controller.hasClients && _controller.position.haveDimensions ? (_controller.page ?? _index.toDouble()) : _index.toDouble(),
                        onSelect: (i) => unawaited(_go(i)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Una sección: se mantiene viva al deslizar (no pierde su estado) y tiene su propio `ScaffoldMessenger`, para que sus avisos no
/// salgan también en las otras secciones.
class _SectionPage extends StatefulWidget {
  const _SectionPage({super.key, required this.child});

  final Widget child;

  @override
  State<_SectionPage> createState() => _SectionPageState();
}

class _SectionPageState extends State<_SectionPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ScaffoldMessenger(child: widget.child);
  }
}
