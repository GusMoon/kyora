import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../data/installed_apps.dart';
import '../../theme.dart';
import '../../util/format.dart';
import 'app_icon_lines.dart';
import 'section_motion.dart';
import 'wave_sweep.dart';

/// El camino en forma de «n» que siguen las apps: **sube pegado al borde izquierdo del teléfono, dobla la esquina con el mismo redondeo del
/// marco, cruza por arriba en línea recta y baja por el borde derecho**: una «n» cuadrada de esquinas redondas, sin punta. Es solo geometría
/// (sin widgets) para poder probarla: se mide en «distancia recorrida» `s` por la curva, de 0 (abajo a la izquierda) a [length] (abajo a la
/// derecha); la cima (el centro del tramo de arriba) está en [apex].
class ArchPath {
  ArchPath({
    required Size size,
    required EdgeInsets insets,
    this.margin = 30,
    this.top = 44,
    this.radius = 66,
  }) {
    left = insets.left + margin;
    right = size.width - insets.right - margin;
    yTop = insets.top + top;
    yBottom = size.height - insets.bottom - 76;
    // la esquina nunca puede ser mayor que lo que cabe entre los dos lados ni entre la cima y el arranque
    final r = math.max(1.0, math.min(radius, math.min((right - left) / 2, (yBottom - yTop) / 2)));
    corner = r;
    final points = <Offset>[];
    void line(Offset a, Offset b) {
      final n = math.max(1, ((b - a).distance / step).ceil());
      for (var i = points.isEmpty ? 0 : 1; i <= n; i++) {
        points.add(Offset.lerp(a, b, i / n)!);
      }
    }

    void arc(Offset center, double from, double to) {
      final n = math.max(1, (r * (to - from).abs() / step).ceil());
      for (var i = 1; i <= n; i++) {
        final angle = from + (to - from) * i / n;
        points.add(center + Offset(math.cos(angle), math.sin(angle)) * r);
      }
    }

    line(Offset(left, yBottom), Offset(left, yTop + r));
    arc(Offset(left + r, yTop + r), math.pi, 1.5 * math.pi);
    line(Offset(left + r, yTop), Offset(right - r, yTop));
    arc(Offset(right - r, yTop + r), 1.5 * math.pi, 2 * math.pi);
    line(Offset(right, yTop + r), Offset(right, yBottom));
    _points = points;
    _lengths = List.filled(points.length, 0);
    for (var i = 1; i < points.length; i++) {
      _lengths[i] = _lengths[i - 1] + (points[i] - points[i - 1]).distance;
    }
    length = _lengths.last;
  }

  /// La separación entre dos puntos medidos de la curva (px).
  static const step = 1.0;

  /// El aire entre la curva y el borde de la pantalla, lo que baja la cima desde la barra de estado y el radio de las esquinas de la «n»
  /// (el del marco del teléfono).
  final double margin;
  final double top;
  final double radius;

  late final double left, right, yTop, yBottom, length, corner;
  late final List<Offset> _points;
  late final List<double> _lengths;

  /// La distancia de la cima.
  double get apex => length / 2;

  /// El punto de la curva a la distancia `s` (se recorta a `[0, length]`) y hacia dónde va (ángulo de la tangente, rad).
  (Offset, double) at(double s) {
    s = s.clamp(0.0, length);
    var lo = 0, hi = _points.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (_lengths[mid] <= s) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final span = _lengths[hi] - _lengths[lo];
    final t = span <= 0 ? 0.0 : (s - _lengths[lo]) / span;
    final v = _points[hi] - _points[lo];
    return (Offset.lerp(_points[lo], _points[hi], t)!, v.direction);
  }

  /// La distancia `s` del punto de la curva más cercano a `p`.
  double nearest(Offset p) {
    var best = 0, bestDistance = double.infinity;
    for (var i = 0; i < _points.length; i++) {
      final d = (_points[i] - p).distanceSquared;
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return _lengths[best];
  }

  /// La curva como línea, para dibujarla.
  Path get line {
    final path = Path()..moveTo(_points.first.dx, _points.first.dy);
    for (final p in _points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    return path;
  }
}

/// **Todas las apps** a pantalla completa, en lugar del contenido (sin oscurecer nada, sobre el fondo de la app): los iconos, sin nombre, se
/// reparten a lo largo de una curva en forma de «n» que sigue los bordes del teléfono y en el **centro, en columna, el abecedario**.
///
/// * Al abrirse, las apps **se materializan con el efecto de holograma al paso de una ola** que barre la pantalla desde el borde de arriba a
///   la izquierda hasta el de abajo a la derecha (`WaveSweep`); al cerrarse, la ola las deshace en el mismo sentido.
/// * Arrastrando por la curva se recorren las apps, que siguen al dedo; **la app que llega a la cima marca la letra** resaltada en la columna.
/// * Tocar o arrastrar por una letra lleva a la primera app con esa inicial hasta la cima.
///
/// Tocar una app la abre; la cruz de abajo cierra.
class AppsArch extends StatefulWidget {
  const AppsArch({
    super.key,
    required this.apps,
    required this.onOpen,
    required this.onClose,
    this.closing = false,
    this.onClosed,
  });

  /// Las apps, ya en orden alfabético.
  final List<InstalledApp> apps;
  final ValueChanged<InstalledApp> onOpen;
  final VoidCallback onClose;

  /// Pide que se cierre: las apps se van por donde entraron y, al terminar, avisa con [onClosed].
  final bool closing;
  final VoidCallback? onClosed;

  /// Las letras de la columna: de la A a la Z y «#» (lo que no empieza por letra).
  static const letters = [
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
    '#',
  ];

  /// La letra de una app para la columna («#» si no empieza por letra).
  static String letterFor(String label) {
    final l = letterOf(label);
    return letters.contains(l) && l != '#' ? l : '#';
  }

  /// Lo que se separan las apps a lo largo de la curva y el lado del icono.
  static const spacing = 64.0;
  static const icon = 46.0;

  /// Lo que dura la entrada y la salida (lo que tarda la ola en cruzar la pantalla).
  static const entering = Duration(milliseconds: 760);
  static const leaving = Duration(milliseconds: 520);

  @override
  State<AppsArch> createState() => _AppsArchState();
}

class _AppsArchState extends State<AppsArch> with TickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: AppsArch.entering,
    reverseDuration: AppsArch.leaving,
  )..forward();
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  /// Lo recorrido (px): con 0 la primera app está en el arranque; con más, las apps han avanzado hacia atrás y llegan otras a la cima.
  double _scroll = 0;
  double _from = 0, _to = 0;
  double _tangent = 0;
  double _min = 0, _max = 0;

  @override
  void initState() {
    super.initState();
    _slide.addListener(
      () => setState(
        () => _scroll = lerpDouble(
          _from,
          _to,
          Curves.easeOutCubic.transform(_slide.value),
        )!,
      ),
    );
  }

  @override
  void didUpdateWidget(AppsArch old) {
    super.didUpdateWidget(old);
    if (widget.closing && !old.closing) {
      _slide.stop();
      unawaited(_in.reverse().whenComplete(() => widget.onClosed?.call()));
    }
  }

  @override
  void dispose() {
    _in.dispose();
    _slide.dispose();
    super.dispose();
  }

  /// Lleva el recorrido a `target` con suavidad.
  void _glideTo(double target) {
    _from = _scroll;
    _to = target.clamp(_min, _max);
    _slide.forward(from: 0);
  }

  /// La letra de la app que está en la cima con ese recorrido.
  String? _apexLetter(ArchPath arch, double scroll) {
    final apps = widget.apps;
    if (apps.isEmpty) return null;
    final i = ((arch.apex - AppsArch.spacing / 2 + scroll) / AppsArch.spacing)
        .round()
        .clamp(0, apps.length - 1);
    return AppsArch.letterFor(apps[i].label);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final insets = MediaQuery.paddingOf(context);
        final arch = ArchPath(size: size, insets: insets);
        final apps = widget.apps;
        const first = AppsArch.spacing / 2;
        // se puede llevar cualquier app hasta la cima, la primera y la última incluidas
        _min = first - arch.apex;
        _max = math.max(
          _min,
          first + (apps.length - 1) * AppsArch.spacing - arch.apex,
        );
        final scroll = _scroll.clamp(_min, _max);
        final active = _apexLetter(arch, scroll);
        final present = {for (final a in apps) AppsArch.letterFor(a.label)};
        // la columna del centro: de debajo de la cima a encima de la cruz
        final colTop = arch.yTop + 76;
        final colBottom = size.height - insets.bottom - 62;
        final rowH = math.max(
          17.0,
          (colBottom - colTop) / AppsArch.letters.length,
        );
        const colW = 46.0;
        final colRect = Rect.fromLTWH(
          (size.width - colW) / 2,
          colTop,
          colW,
          rowH * AppsArch.letters.length,
        );

        void toLetter(String letter) {
          final i = apps.indexWhere(
            (a) => AppsArch.letterFor(a.label) == letter,
          );
          if (i >= 0) _glideTo(first + i * AppsArch.spacing - arch.apex);
        }

        return GestureDetector(
          key: const Key('apps-arch'),
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) {
            if (widget.closing) return;
            _slide.stop();
            _tangent = arch.at(arch.nearest(d.localPosition)).$2;
          },
          onPanUpdate: (d) {
            // lo que se arrastra a lo largo de la curva en el punto donde se empezó: las apps siguen al dedo
            final along =
                d.delta.dx * math.cos(_tangent) +
                d.delta.dy * math.sin(_tangent);
            setState(() => _scroll = (_scroll - along).clamp(_min, _max));
          },
          onPanEnd: (d) {
            final v = d.velocity.pixelsPerSecond;
            final along = v.dx * math.cos(_tangent) + v.dy * math.sin(_tangent);
            _glideTo(_scroll - along * 0.22); // un empujón: sigue un poco más
          },
          child: AnimatedBuilder(
            animation: _in,
            builder: (context, _) {
              // al entrar, la ola las materializa a su paso (de arriba a la izquierda a abajo a la derecha); al salir, las deshace igual
              final colShown = WaveSweep.visibility(_in, WaveSweep.along(colRect.center, size));
              final closeShown = WaveSweep.visibility(_in, WaveSweep.along(Offset(size.width / 2, size.height - insets.bottom - 28), size));
              return Stack(
                fit: StackFit.expand,
                children: [
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _RailPainter(
                        arch: arch,
                        accent: c.accent,
                        progress: _in.value,
                      ),
                    ),
                  ),
                  for (var i = 0; i < apps.length; i++)
                    ..._item(
                      context,
                      arch,
                      apps[i],
                      i,
                      first + AppsArch.spacing * i - scroll,
                      size,
                    ),
                  // el abecedario, en columna, en el centro
                  Positioned.fromRect(
                    rect: colRect,
                    child: Opacity(
                      opacity: SectionMotion.glitchOpacity(colShown, 77),
                      child: GestureDetector(
                        key: const Key('letter-column'),
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragUpdate: (d) {
                          final i = (d.localPosition.dy / rowH).floor().clamp(
                            0,
                            AppsArch.letters.length - 1,
                          );
                          final l = AppsArch.letters[i];
                          if (present.contains(l) && l != active) toLetter(l);
                        },
                        child: Column(
                          children: [
                            for (final letter in AppsArch.letters)
                              SizedBox(
                                height: rowH,
                                child: GestureDetector(
                                  key: Key('letter-$letter'),
                                  behavior: HitTestBehavior.opaque,
                                  onTap: present.contains(letter)
                                      ? () => toLetter(letter)
                                      : null,
                                  child: Container(
                                    alignment: Alignment.center,
                                    color: active == letter ? c.accent : null,
                                    child: Text(
                                      letter,
                                      style: TextStyle(
                                        fontFamily: monoFont,
                                        fontSize: 15,
                                        height: 1,
                                        fontWeight: active == letter
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: active == letter
                                            ? c.onAccent
                                            : (present.contains(letter)
                                                  ? c.ink
                                                  : c.dim.withValues(
                                                      alpha: 0.35,
                                                    )),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // cerrar
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: insets.bottom + 6,
                    child: Opacity(
                      opacity: SectionMotion.glitchOpacity(closeShown, 91),
                      child: Center(
                        child: GestureDetector(
                          key: const Key('arch-close'),
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.onClose,
                          child: Semantics(
                            button: true,
                            label: 'Cerrar',
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: c.accent.withValues(alpha: 0.7),
                                ),
                              ),
                              child: Icon(
                                Icons.close_rounded,
                                size: 24,
                                color: c.accent,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // al cerrarse, la ola que las deshace (al abrirse la dibuja `SectionHost`, junto con el contenido que se va)
                  if (widget.closing)
                    IgnorePointer(
                      child: CustomPaint(
                        painter: WavePainter(t: WaveSweep.timeFor(_in), accent: c.accent),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// Una app en su sitio de la curva (`s` es su distancia). Solo el icono, centrado en el punto. Se materializa (o se deshace) cuando la ola
  /// pasa por su sitio, con el parpadeo y los saltos del holograma.
  List<Widget> _item(
    BuildContext context,
    ArchPath arch,
    InstalledApp app,
    int i,
    double s,
    Size size,
  ) {
    // las que no caben en la curva no se pintan
    if (s < -AppsArch.spacing / 2 || s > arch.length + AppsArch.spacing / 2) {
      return const [];
    }
    final c = context.colors;
    final (point, _) = arch.at(s);
    // cerca de los extremos de la curva se apaga
    final edge = s < 0
        ? s
        : (s > arch.length ? arch.length - s : math.min(s, arch.length - s));
    final fade = ((edge + AppsArch.spacing / 2) / AppsArch.spacing).clamp(
      0.0,
      1.0,
    );
    final shown = WaveSweep.visibility(_in, WaveSweep.along(point, size));
    final opacity = SectionMotion.glitchOpacity(shown, i) * fade;
    final jump = SectionMotion.glitchShift(shown, i, MotionEdge.top);
    const half = AppsArch.icon / 2;
    const touch = 56.0;
    return [
      Positioned(
        left: point.dx - touch / 2 + jump.dx,
        top: point.dy - touch / 2 + jump.dy,
        width: touch,
        height: touch,
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Semantics(
            button: true,
            label: app.label,
            child: GestureDetector(
              key: Key('arch-app-${app.package}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onOpen(app),
              child: Center(
                child: ScanlineAppIcon(
                  bytes: app.icon,
                  size: half * 2,
                  errorBuilder: (_, _, _) =>
                      Icon(Icons.apps_rounded, size: half * 2, color: c.dim),
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }
}

/// La línea fina de la curva, que se dibuja de un extremo al otro al abrirse.
class _RailPainter extends CustomPainter {
  const _RailPainter({
    required this.arch,
    required this.accent,
    required this.progress,
  });

  final ArchPath arch;
  final Color accent;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = accent.withValues(alpha: 0.45);
    for (final m in arch.line.computeMetrics()) {
      canvas.drawPath(
        m.extractPath(0, m.length * progress.clamp(0.0, 1.0)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RailPainter old) =>
      old.arch.length != arch.length ||
      old.accent != accent ||
      old.progress != progress;
}
