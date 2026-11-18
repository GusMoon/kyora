import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';
import 'focus_space.dart';
import 'radial_menu.dart' show ReactorSpin;
import 'section_motion.dart';

/// Un ajuste que se hace **girando el dedo** por el aro del reactor (la velocidad, el tono…): va de [min] a [max] de paso en paso.
class ReactorDial {
  const ReactorDial({required this.id, required this.icon, required this.label, required this.min, required this.max, required this.step, required this.value, required this.onChanged, required this.format, this.neutral});

  /// Con ella se forman las claves `reactor-dial-<id>`.
  final String id;
  final IconData icon;

  /// Solo para accesibilidad (el reactor no enseña textos en las opciones).
  final String label;
  final double min;
  final double max;
  final double step;

  /// El valor de ahora (se vuelve a leer cuando [OptionsReactor.listenable] avisa).
  final double Function() value;
  final ValueChanged<double> onChanged;
  final String Function(double value) format;

  /// A lo que vuelve «restablecer» (normalmente 1×). Sin él no sale el botón.
  final double? neutral;
}

/// Una opción del reactor: solo un icono. Tocarla ejecuta [onTap]; si trae [dials], en vez de eso el propio reactor pasa a ser un dial para
/// ajustarlos girando.
class DiscOption {
  const DiscOption({required this.id, required this.icon, required this.label, this.onTap, this.warn = false, this.dials});

  /// Con ella se forma la clave `disc-option-<id>`.
  final String id;
  final IconData icon;

  /// Solo para accesibilidad: el reactor no enseña el texto.
  final String label;
  final VoidCallback? onTap;

  /// Una acción peligrosa (borrar): va en el color de aviso.
  final bool warn;

  /// Los ajustes que se hacen girando el dedo (velocidad y tono).
  final List<ReactorDial>? dials;
}

/// Abre el **reactor de opciones** centrado en [center] (en la pantalla), con el resto de la pantalla oscurecido para que sea él quien mande.
/// Tocar una opción la ejecuta (y cierra el reactor); tocar fuera, o el centro, lo cierra. [listenable] avisa de que cambió algo que se ve
/// dentro (el valor de un dial).
Future<void> showOptionsReactor(BuildContext context, {required Offset center, required List<DiscOption> options, Listenable? listenable, double size = 320}) =>
    Navigator.of(context, rootNavigator: true).push<void>(OptionsReactorRoute(center: center, options: options, listenable: listenable, size: size));

/// La ruta del reactor: velo oscuro con un hueco redondo, el reactor que se materializa con el holograma al abrir y se apaga rápido y sin
/// parpadeo al cerrar.
class OptionsReactorRoute extends PopupRoute<void> {
  OptionsReactorRoute({required this.center, required this.options, this.listenable, this.size = 320});

  final Offset center;
  final List<DiscOption> options;
  final Listenable? listenable;
  final double size;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => 'Cerrar';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 240);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 150);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final media = MediaQuery.of(context);
    final insets = EdgeInsets.fromLTRB(media.padding.left, media.padding.top, media.padding.right, media.padding.bottom);
    final side = math.min(size, math.min(media.size.width, media.size.height) - FocusSpace.margin * 2);
    final rect = FocusSpace.place(Size.square(side), media.size, insets, around: center);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final raw = animation.value;
        final t = Curves.easeOutCubic.transform(raw);
        final leaving = animation.status == AnimationStatus.reverse;
        return Stack(
          fit: StackFit.expand,
          children: [
            FocusVeil(hole: FocusVeil.circle(rect.center, side / 2), amount: t, onTapOutside: () => Navigator.of(context).maybePop()),
            Positioned.fromRect(
              rect: rect,
              child: Opacity(
                opacity: leaving ? SectionMotion.quietOpacity(raw) : SectionMotion.glitchOpacity(t, 9),
                child: Transform.translate(
                  offset: leaving ? SectionMotion.quietShift(raw, 9) : SectionMotion.glitchShift(t, 9, MotionEdge.bottom),
                  child: Transform.scale(
                    scale: leaving ? 0.985 + 0.015 * raw : 0.92 + 0.08 * t,
                    child: Material(
                      type: MaterialType.transparency,
                      child: OptionsReactor(
                        size: side,
                        options: options,
                        listenable: listenable,
                        onClose: () => Navigator.of(context).maybePop(),
                        // al elegir una opción el reactor se apaga y, ya cerrado, se hace lo que toque
                        onPick: (o) {
                          Navigator.of(context).pop();
                          o.onTap?.call();
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// El **reactor de opciones**: el aro del menú circular de Inicio (cristal oscuro con filos de neón, anillos que giran y un núcleo de aspas)
/// con las acciones de la canción repartidas alrededor **solo con su icono**, y el botón de cerrar en el núcleo. Si se elige una opción de ajuste
/// (velocidad y tono) el aro pasa a ser un **dial**: se gira el dedo por él para cambiar el valor y el núcleo enseña cuánto vale.
///
/// Gira solo con [ReactorSpin.enabled] (en las pruebas se queda quieto).
class OptionsReactor extends StatefulWidget {
  const OptionsReactor({super.key, required this.size, required this.options, required this.onClose, this.onPick, this.listenable});

  /// El lado del reactor.
  final double size;
  final List<DiscOption> options;
  final VoidCallback onClose;

  /// Se llama al tocar una opción (que no sea de ajuste). Sin él se ejecuta su [DiscOption.onTap] directamente.
  final ValueChanged<DiscOption>? onPick;

  /// Avisa de que cambió un valor que se ve (el de un dial).
  final Listenable? listenable;

  /// Lo que tarda el aro en dar una vuelta entera.
  static const period = Duration(seconds: 14);

  /// El dial recorre 270° (de abajo a la izquierda, por arriba, a abajo a la derecha): empieza aquí.
  static const gaugeStart = 3 * math.pi / 4;
  static const gaugeSweep = 3 * math.pi / 2;

  /// Qué parte del dial (0 a 1) es el ángulo `angle` (rad, de `atan2`): lo que cae en el hueco de abajo se pega al extremo más cercano.
  static double fractionAt(double angle) {
    var rel = (angle - gaugeStart) % (2 * math.pi);
    if (rel < 0) rel += 2 * math.pi;
    if (rel > gaugeSweep) rel = rel - gaugeSweep < (2 * math.pi - gaugeSweep) / 2 ? gaugeSweep : 0;
    return rel / gaugeSweep;
  }

  @override
  State<OptionsReactor> createState() => _OptionsReactorState();
}

class _OptionsReactorState extends State<OptionsReactor> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: OptionsReactor.period);

  /// Los ajustes que se están haciendo girar (si es que se eligió una opción de ajuste) y cuál de ellos.
  List<ReactorDial>? _dials;
  int _active = 0;

  @override
  void initState() {
    super.initState();
    if (ReactorSpin.enabled) _spin.repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  void _pick(DiscOption option) {
    final dials = option.dials;
    if (dials != null && dials.isNotEmpty) {
      setState(() {
        _dials = dials;
        _active = 0;
      });
      return;
    }
    final pick = widget.onPick;
    if (pick != null) {
      pick(option);
    } else {
      option.onTap?.call();
    }
  }

  ReactorDial? get _dial => _dials == null ? null : _dials![_active];

  /// Pone el valor del dial según dónde está el dedo (`local`, en el reactor).
  void _setFromTouch(Offset local) {
    final dial = _dial;
    if (dial == null) return;
    final v = local - Offset(widget.size / 2, widget.size / 2);
    if (v.distance < widget.size * 0.2) return; // junto al centro el ángulo da saltos
    final f = OptionsReactor.fractionAt(v.direction);
    final raw = dial.min + f * (dial.max - dial.min);
    final snapped = (dial.min + ((raw - dial.min) / dial.step).round() * dial.step).clamp(dial.min, dial.max).toDouble();
    final next = double.parse(snapped.toStringAsFixed(2));
    if (next != dial.value()) dial.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = widget.size;
    return ListenableBuilder(
      listenable: widget.listenable ?? const AlwaysStoppedAnimation<double>(0),
      builder: (context, _) {
        final dial = _dial;
        final value = dial?.value();
        final fraction = dial == null ? null : ((value! - dial.min) / (dial.max - dial.min)).clamp(0.0, 1.0);
        final n = dial == null ? widget.options.length : _dials!.length + (dial.neutral == null ? 0 : 1);
        return SizedBox.square(
          key: const Key('options-disc'),
          dimension: size,
          child: GestureDetector(
            key: const Key('options-disc-back'),
            behavior: HitTestBehavior.opaque,
            onTap: widget.onClose,
            onPanStart: dial == null ? null : (d) => _setFromTouch(d.localPosition),
            onPanUpdate: dial == null ? null : (d) => _setFromTouch(d.localPosition),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      key: const Key('options-dial'),
                      painter: ReactorPainter(accent: c.accent, ink: c.edge, count: n, spin: _spin, gauge: fraction),
                    ),
                  ),
                ),
                if (dial == null)
                  for (var i = 0; i < widget.options.length; i++) _slot(widget.options[i], i, n, size, c)
                else ...[
                  for (var i = 0; i < _dials!.length; i++) _dialSlot(i, size, c),
                  if (dial.neutral != null) _resetSlot(dial, size, c),
                ],
                _hub(size, c, dial, value),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _at(double angle, double radius, double size, Widget child) => Align(alignment: Alignment(math.cos(angle) * radius, math.sin(angle) * radius), child: child);

  Widget _slot(DiscOption option, int i, int n, double size, KyoraColors c) {
    final color = option.warn ? c.warn : c.accent;
    return _at(
      -math.pi / 2 + i * 2 * math.pi / n,
      0.6,
      size,
      Semantics(
        button: true,
        label: option.label,
        child: GestureDetector(
          key: Key('disc-option-${option.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _pick(option),
          child: SizedBox.square(dimension: size * 0.2, child: Icon(option.icon, size: size * 0.105, color: color)),
        ),
      ),
    );
  }

  /// En el modo dial: los ajustes arriba (a izquierda y derecha) para elegir cuál se gira.
  Widget _dialSlot(int i, double size, KyoraColors c) {
    final d = _dials![i];
    final on = i == _active;
    final angle = _dials!.length == 1 ? -math.pi / 2 : -math.pi / 2 + (i == 0 ? -1 : 1) * math.pi / 4;
    return _at(
      angle,
      0.64,
      size,
      Semantics(
        button: true,
        selected: on,
        label: d.label,
        child: GestureDetector(
          key: Key('reactor-dial-${d.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _active = i),
          child: Container(
            width: size * 0.2,
            height: size * 0.2,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: on ? c.accent : null, border: Border.all(color: on ? c.accent : c.accent.withValues(alpha: 0.35))),
            child: Icon(d.icon, size: size * 0.095, color: on ? c.onAccent : c.accent),
          ),
        ),
      ),
    );
  }

  Widget _resetSlot(ReactorDial dial, double size, KyoraColors c) => _at(
    math.pi / 2,
    0.6,
    size,
    Semantics(
      button: true,
      label: 'Restablecer',
      child: GestureDetector(
        key: const Key('reactor-reset'),
        behavior: HitTestBehavior.opaque,
        onTap: () => dial.onChanged(dial.neutral!),
        child: SizedBox.square(dimension: size * 0.2, child: Icon(Icons.restart_alt_rounded, size: size * 0.1, color: c.accent)),
      ),
    ),
  );

  /// El núcleo: el botón de cerrar o, en el modo dial, lo que vale el ajuste (tocarlo vuelve a las opciones).
  Widget _hub(double size, KyoraColors c, ReactorDial? dial, double? value) {
    final hub = size * 0.3;
    if (dial == null) {
      return GestureDetector(
        key: const Key('disc-options-close'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onClose,
        child: SizedBox.square(dimension: hub, child: Icon(Icons.close_rounded, size: size * 0.11, color: c.accent)),
      );
    }
    return GestureDetector(
      key: const Key('reactor-back'),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _dials = null),
      child: SizedBox.square(
        dimension: hub,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(dial.icon, size: size * 0.07, color: c.dim),
            Text(dial.format(value!), key: const Key('reactor-value'), maxLines: 1, style: display(size: size * 0.075, color: c.ink, weight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// El cuerpo del reactor, a la escala que le toque: cristal oscuro con filos de neón, anillos que giran (arcos de energía, marcas y un aro de
/// puntos) y el núcleo de aspas con un latido de luz. Con [gauge] (0 a 1) dibuja además el dial: una pista de 270° con lo recorrido y una
/// perilla. [spin] (0 a 1 por vuelta) lo hace girar; sin él queda quieto.
class ReactorPainter extends CustomPainter {
  ReactorPainter({required this.accent, required this.ink, required this.count, this.spin, this.gauge}) : super(repaint: spin);

  final Color accent;
  final Color ink;
  final int count;
  final Animation<double>? spin;
  final double? gauge;

  static const _full = 2 * math.pi;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final s = (spin?.value ?? 0) * _full;
    final outer = r * 0.84, inner = r * 0.36, hub = r * 0.3;
    Offset polar(double radius, double a) => c + Offset.fromDirection(a, radius);

    // el resplandor de detrás del aro
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(colors: [accent.withValues(alpha: 0), accent.withValues(alpha: 0.18), accent.withValues(alpha: 0)], stops: const [0.66, 0.84, 1]).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // el cuerpo: cristal oscuro con un toque del acento
    final body = Path()
      ..addOval(Rect.fromCircle(center: c, radius: outer))
      ..addOval(Rect.fromCircle(center: c, radius: inner))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(body, Paint()..color = Color.alphaBlend(accent.withValues(alpha: 0.08), Colors.black.withValues(alpha: 0.86)));

    // los radios que separan una opción de la siguiente (en el dial no hay)
    if (gauge == null && count > 1) {
      final line = Paint()..strokeWidth = 1..color = ink;
      for (var i = 0; i < count; i++) {
        final a = -math.pi / 2 + (i + 0.5) * _full / count;
        canvas.drawLine(polar(inner, a), polar(outer, a), line);
      }
    }
    // los filos de neón del cuerpo
    for (final radius in [outer - 0.5, inner]) {
      canvas.drawCircle(c, radius, Paint()..style = PaintingStyle.stroke..strokeWidth = 7..color = accent.withValues(alpha: 0.1));
      canvas.drawCircle(c, radius, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.6..color = accent.withValues(alpha: 0.85));
    }
    // por dentro: un anillo punteado que gira al revés
    final dash = Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = accent.withValues(alpha: 0.55);
    final innerRing = Rect.fromCircle(center: c, radius: inner - r * 0.04);
    for (var i = 0; i < 24; i++) {
      canvas.drawArc(innerRing, -s + i * _full / 24, _full / 48, false, dash);
    }
    // por fuera: arcos de energía, marcas (al revés) y un anillo fino
    final arcs = Paint()..style = PaintingStyle.stroke..strokeWidth = 3.5..strokeCap = StrokeCap.butt..color = accent.withValues(alpha: 0.9);
    final arcRing = Rect.fromCircle(center: c, radius: r * 0.89);
    for (var i = 0; i < 6; i++) {
      canvas.drawArc(arcRing, s + i * _full / 6, _full / 6 * 0.58, false, arcs);
    }
    final tick = Paint()..strokeWidth = 1.2..color = accent.withValues(alpha: 0.6);
    for (var i = 0; i < 72; i++) {
      final a = -s + i * _full / 72;
      final long = i % 6 == 0;
      canvas.drawLine(polar(r * (0.945 - (long ? 0.015 : 0)), a), polar(r * (0.975 + (long ? 0.015 : 0)), a), tick);
    }
    canvas.drawCircle(c, r - 1.5, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = accent.withValues(alpha: 0.35));

    // el dial: la pista de 270°, lo recorrido y la perilla
    final f = gauge;
    if (f != null) {
      final trackR = r * 0.7;
      final rect = Rect.fromCircle(center: c, radius: trackR);
      canvas.drawArc(rect, OptionsReactor.gaugeStart, OptionsReactor.gaugeSweep, false, Paint()..style = PaintingStyle.stroke..strokeWidth = 6..strokeCap = StrokeCap.butt..color = accent.withValues(alpha: 0.18));
      if (f > 0) canvas.drawArc(rect, OptionsReactor.gaugeStart, OptionsReactor.gaugeSweep * f, false, Paint()..style = PaintingStyle.stroke..strokeWidth = 6..strokeCap = StrokeCap.butt..color = accent);
      final end = polar(trackR, OptionsReactor.gaugeStart + OptionsReactor.gaugeSweep * f);
      canvas.drawCircle(end, r * 0.055, Paint()..color = accent);
      canvas.drawCircle(end, r * 0.095, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2..color = accent.withValues(alpha: 0.6));
    }

    // el núcleo: disco oscuro, aspas que giran y un latido de luz
    canvas.drawCircle(c, hub, Paint()..color = Colors.black.withValues(alpha: 0.88));
    final pulse = 0.5 + 0.5 * math.sin(s * 3);
    canvas.drawCircle(c, hub - 2, Paint()..shader = RadialGradient(colors: [accent.withValues(alpha: 0.05 + 0.2 * pulse), accent.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: hub)));
    final blade = Paint()..strokeWidth = 3..strokeCap = StrokeCap.butt..color = accent.withValues(alpha: 0.5);
    for (var i = 0; i < 6; i++) {
      final a = s * 2 + i * _full / 6;
      canvas.drawLine(polar(hub * 0.74, a), polar(hub - 4, a), blade);
    }
    canvas.drawCircle(c, hub, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.8..color = accent);
    canvas.drawCircle(c, hub - 7, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = accent.withValues(alpha: 0.4));
  }

  @override
  bool shouldRepaint(covariant ReactorPainter old) => old.accent != accent || old.ink != ink || old.count != count || old.spin != spin || old.gauge != gauge;
}
