import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../theme.dart';
import 'pixel_glyph.dart';
import 'section_motion.dart';
import 'wave_sweep.dart';

/// Una opción del menú circular.
class RadialEntry {
  const RadialEntry({
    required this.id,
    required this.icon,
    required this.label,
    this.glyph,
    this.image,
  });

  final String id;
  final IconData icon;
  final String label;

  /// Su icono de puntos (sin él, `icon`).
  final PixelGlyph? glyph;

  /// El icono de una app del teléfono (PNG). Manda sobre los demás.
  final Uint8List? image;
}

/// Qué enseña el aro: las **funciones** (las secciones y acciones de Kyra) o las **aplicaciones** (las 8 elegidas). Se abre con un giro del
/// dedo (a la izquierda, aplicaciones; a la derecha, funciones) y se cambia girando el aro igual.
enum LauncherMode { functions, apps }

/// El icono de una opción: el de la app, el de puntos o el normal.
Widget _entryIcon(RadialEntry entry, double size, Color color, {Key? key}) {
  if (entry.image != null) {
    return ClipRect(
      key: key,
      child: Image.memory(
        entry.image!,
        width: size,
        height: size,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) =>
            LcdIcon(Icons.apps_rounded, size: size, color: color),
      ),
    );
  }
  return entry.glyph == null
      ? LcdIcon(entry.icon, key: key, size: size, color: color)
      : PixelIcon(entry.glyph!, key: key, size: size * 0.82, color: color);
}

/// Dónde cae cada opción del menú circular. Es solo geometría (sin widgets) para poder probarla: un **aro completo** alrededor del dedo,
/// partido en tantas cuñas iguales como opciones, con la primera arriba y las demás en el sentido del reloj. Cada opción cae **siempre en la
/// misma dirección**, se toque donde se toque, para poder memorizarla; cerca de un borde el aro entero se corre lo justo hacia dentro, sin
/// girar. Se elige por el **ángulo** en que está el dedo visto desde el centro.
class RadialGeometry {
  RadialGeometry({
    required this.count,
    required this.bounds,
    required this.touch,
  }) : step = 2 * math.pi / math.max(1, count) {
    const reach = outer + margin;
    center = Offset(
      _inside(touch.dx, bounds.left + reach, bounds.right - reach),
      _inside(touch.dy, bounds.top + reach, bounds.bottom - reach),
    );
  }

  /// `value` dentro de `[low, high]`; si el aro no cabe (`low > high`), a medio camino.
  static double _inside(double value, double low, double high) =>
      low > high ? (low + high) / 2 : value.clamp(low, high);

  /// Cuántas opciones hay.
  final int count;

  /// La zona de la pantalla donde caben (sin las barras del sistema).
  final Rect bounds;

  /// Donde se puso el dedo.
  final Offset touch;

  /// El centro del menú (el del dedo, corrido si hacía falta para que todo se vea).
  late final Offset center;

  /// El ángulo de cada cuña (rad): la vuelta entera repartida entre todas.
  final double step;

  /// Los radios del aro por dentro y por fuera, la distancia del centro a cada icono, el radio del disco del centro, el lado de cada opción,
  /// el aire con el borde de la pantalla y el radio sin selección en el centro.
  static const inner = 62.0;
  static const outer = 142.0;
  static const radius = (inner + outer) / 2;
  static const hub = 52.0;
  static const item = 52.0;
  static const margin = 8.0;
  static const deadZone = 40.0;

  /// El ángulo (rad) de la primera opción: arriba.
  static const first = -math.pi / 2;

  /// El ángulo (rad) del centro de la cuña `i`, con el aro girado `turn` rad. No depende de dónde se ponga el dedo.
  double angleOf(int i, [double turn = 0]) => first + step * i + turn;

  /// El centro del icono de la opción `i`.
  Offset positionOf(int i, [double turn = 0]) =>
      center + Offset.fromDirection(angleOf(i, turn), radius);

  /// La opción a la que apunta el dedo, o nada si está en el centro.
  int? pick(Offset finger) {
    final v = finger - center;
    if (v.distance < deadZone || count == 0) return null;
    return ((v.direction - first) / step).round() % count;
  }

  /// La opción tocada (dentro del aro), o nada si el toque cae en el centro o fuera del aro.
  int? hit(Offset finger) {
    final d = (finger - center).distance;
    if (d < hub || d > outer + margin) return null;
    return pick(finger);
  }

  /// ¿El toque cae en el disco del centro?
  bool inHub(Offset finger) => (finger - center).distance <= hub;

  /// ¿El toque cae dentro del menú (aro o centro)?
  bool contains(Offset finger) => (finger - center).distance <= outer + margin;

  /// Lo que gira el dedo (rad) al pasar de `from` a `to` alrededor del centro: positivo en el sentido del reloj (a la derecha).
  double turnBetween(Offset from, Offset to) {
    final a = (from - center).direction;
    final b = (to - center).direction;
    var d = b - a;
    while (d > math.pi) {
      d -= 2 * math.pi;
    }
    while (d < -math.pi) {
      d += 2 * math.pi;
    }
    return d;
  }
}

/// Si el reactor gira solo mientras el menú está abierto. Las pruebas lo apagan (una animación sin fin no deja «asentarse» a `pumpAndSettle`).
abstract final class ReactorSpin {
  static bool enabled = true;

  /// Lo que tarda el reactor en dar una vuelta entera (lo más lento; las demás piezas dan vueltas enteras en esto, a su ritmo).
  static const period = Duration(seconds: 12);
}

/// El **hueco** que el menú abre en el contenido: un círculo un poco mayor que el reactor, de borde dentado de «píxeles» mientras se abre.
abstract final class RadialCutout {
  /// El radio del hueco una vez abierto.
  static const radius = RadialGeometry.outer + RadialMenuView.halo + 10;

  /// Cuánto baja la opacidad del contenido de alrededor al abrirse (sin oscurecerlo: se ve el fondo a través).
  static const fade = 0.45;

  static const _segments = 96;

  /// El contorno del hueco con el avance `open` (0 → 1): crece con suavidad y, mientras crece, su borde salta a saltos.
  static Path path(Offset center, double open) {
    final t = Curves.easeOutCubic.transform(open.clamp(0.0, 1.0));
    final r = radius * t;
    final tick = (open * 14).floor();
    final path = Path();
    for (var k = 0; k < _segments; k++) {
      final jitter = (SectionMotion.noise(k, tick) - 0.5) * 0.22 * (1 - t);
      final p =
          center +
          Offset.fromDirection(2 * math.pi * k / _segments, r * (1 + jitter));
      k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }
}

/// Envuelve el contenido de la app: con el menú abierto le **abre un hueco** del tamaño del reactor (el contenido cercano se corta para
/// dejarle sitio) y le baja la opacidad (se ve el fondo a través), sin oscurecer nada. Con [reveal] (0 → 1) el contenido **se materializa o se
/// deshace** con parpadeo de holograma (todas las apps lo sustituyen: en 0 no se ve, pero sigue vivo). Sin menú ni cambio es transparente.
class RadialCut extends StatelessWidget {
  const RadialCut({
    super.key,
    required this.center,
    required this.opening,
    required this.child,
    this.reveal = const AlwaysStoppedAnimation<double>(1),
  });

  /// El centro del hueco (en las coordenadas de este widget) o `null` sin menú.
  final Offset? center;

  /// 0 → 1 al abrirse (y de vuelta a 0 al cerrarse).
  final Animation<double> opening;

  /// 1 con el contenido a la vista; 0 con el contenido quitado.
  final Animation<double> reveal;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([opening, reveal]),
      child: child,
      builder: (context, child) {
        final at = center;
        final t = opening.value.clamp(0.0, 1.0);
        final r = reveal.value.clamp(0.0, 1.0);
        // mientras se deshace o vuelve, una ola lo cruza de arriba a la izquierda a abajo a la derecha (`WaveSweep`): lo que ya pasó se ve
        // (al volver) o ya no (al irse)
        final waving = r > 0 && r < 1;
        final hiding = WaveSweep.hiding(reveal);
        final waveT = WaveSweep.timeFor(reveal);
        return Offstage(
          offstage: r <= 0,
          child: ClipPath(
            key: const Key('radial-cut'),
            clipper: _CutClipper(at, t),
            clipBehavior: at == null ? Clip.none : Clip.hardEdge,
            child: Opacity(
              opacity:
                  SectionMotion.glitchOpacity(r, 21) *
                  (at == null
                      ? 1
                      : 1 - RadialCutout.fade * Curves.easeOut.transform(t)),
              child: waving
                  ? ShaderMask(
                      key: const Key('wave-mask'),
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (rect) =>
                          WaveSweep.mask(rect, waveT, hiding: hiding),
                      child: child,
                    )
                  : child,
            ),
          ),
        );
      },
    );
  }
}

class _CutClipper extends CustomClipper<Path> {
  const _CutClipper(this.center, this.open);

  final Offset? center;
  final double open;

  @override
  Path getClip(Size size) {
    final at = center;
    final all = Path()..addRect(Offset.zero & size);
    if (at == null) return all;
    return Path.combine(
      PathOperation.difference,
      all,
      RadialCutout.path(at, open),
    );
  }

  @override
  bool shouldReclip(covariant _CutClipper old) =>
      old.center != center || old.open != open;
}

/// El menú circular a la vista, como un **reactor** holográfico: el aro de opciones es el cuerpo del reactor, rodeado de anillos de marcas y
/// de arcos de energía que **giran sin parar** en sentidos distintos, con un núcleo de aspas en el centro. Al abrirse parpadea, lo barre una
/// franja de luz y el contenido de alrededor se corta para hacerle sitio (el borde del hueco se deshace en fragmentos). Nada se oscurece. En
/// el centro, el icono y el nombre de lo elegido (o, sin elegir, el modo: funciones o aplicaciones) y debajo la pista del giro.
class RadialMenuView extends StatelessWidget {
  const RadialMenuView({
    super.key,
    required this.geometry,
    required this.entries,
    required this.selected,
    required this.currentId,
    required this.opening,
    this.spin = const AlwaysStoppedAnimation<double>(0),
    this.swap = const AlwaysStoppedAnimation<double>(1),
    this.mode = LauncherMode.functions,
    this.turn = 0,
  });

  final RadialGeometry geometry;
  final List<RadialEntry> entries;
  final int? selected;

  /// El `id` de la sección que se ve (va marcada).
  final String currentId;

  /// 0 → 1 al abrirse.
  final Animation<double> opening;

  /// 0 → 1 en bucle: una vuelta del reactor.
  final Animation<double> spin;

  /// 0 → 1 cuando el aro pasa de funciones a aplicaciones (o al revés): las opciones nuevas se materializan en su sitio.
  final Animation<double> swap;

  /// Lo que enseña el aro, y lo que va girado (rad) mientras el dedo lo gira.
  final LauncherMode mode;
  final double turn;

  /// El aro crece con suavidad y se para sin rebote (un rebote al final se vería como un salto).
  static const openCurve = Curves.easeOutCubic;

  /// El aire alrededor del aro para los anillos del reactor.
  static const halo = 30.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const side = (RadialGeometry.outer + halo) * 2;
    const middle = Offset(side / 2, side / 2);
    final current = entries.where((e) => e.id == currentId).firstOrNull;
    final shown = selected == null
        ? (mode == LauncherMode.functions ? current : null)
        : entries[selected!];
    final modeLabel = mode == LauncherMode.functions ? 'FUNCIONES' : 'APPS';
    return IgnorePointer(
      child: Stack(
        key: const Key('radial-menu'),
        fit: StackFit.expand,
        children: [
          // el borde del hueco que se abre en el contenido: se deshace en fragmentos
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                key: const Key('radial-edge'),
                painter: _EdgePainter(
                  center: geometry.center,
                  open: opening,
                  accent: c.accent,
                ),
              ),
            ),
          ),
          Positioned(
            left: geometry.center.dx - side / 2,
            top: geometry.center.dy - side / 2,
            width: side,
            height: side,
            child: ScaleTransition(
              scale: CurvedAnimation(parent: opening, curve: openCurve),
              // el parpadeo del holograma al proyectarse
              child: AnimatedBuilder(
                animation: opening,
                // (solo parpadea en la primera mitad de la apertura: así al final no hay un salto de brillo)
                builder: (context, child) => Opacity(
                  opacity: SectionMotion.glitchOpacity(
                    (opening.value / 0.55).clamp(0.0, 1.0),
                    7,
                  ),
                  child: child,
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          key: const Key('radial-reactor'),
                          painter: _ReactorPainter(
                            count: entries.length,
                            step: geometry.step,
                            turn: turn,
                            selected: selected,
                            ink: c.edge,
                            accent: c.accent,
                            open: opening,
                            spin: spin,
                          ),
                        ),
                      ),
                    ),
                    for (var i = 0; i < entries.length; i++)
                      Positioned(
                        left:
                            (geometry.positionOf(i, turn) -
                                    geometry.center +
                                    middle)
                                .dx -
                            RadialGeometry.item / 2,
                        top:
                            (geometry.positionOf(i, turn) -
                                    geometry.center +
                                    middle)
                                .dy -
                            RadialGeometry.item / 2,
                        width: RadialGeometry.item,
                        height: RadialGeometry.item,
                        child: AnimatedBuilder(
                          animation: swap,
                          builder: (context, child) => Opacity(
                            opacity: SectionMotion.glitchOpacity(
                              swap.value,
                              i + 1,
                            ),
                            child: child,
                          ),
                          child: _Option(
                            entry: entries[i],
                            selected: selected == i,
                            current: entries[i].id == currentId,
                          ),
                        ),
                      ),
                    // el núcleo: lo que se va a abrir o, sin elegir, el modo
                    AnimatedBuilder(
                      animation: swap,
                      builder: (context, child) => Opacity(
                        opacity: SectionMotion.glitchOpacity(swap.value, 31),
                        child: child,
                      ),
                      child: Center(
                        child: SizedBox(
                          width: RadialGeometry.hub * 2 - 8,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (shown != null) ...[
                                _entryIcon(
                                  shown,
                                  30,
                                  c.accent,
                                  key: const Key('radial-center'),
                                ),
                                const SizedBox(height: 6),
                              ],
                              Text(
                                shown?.label ?? modeLabel,
                                key: const Key('radial-label'),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.clip,
                                style: lcdLabel(
                                  color: shown == null ? c.accent : c.ink,
                                ),
                              ),
                              if (shown == null && mode == LauncherMode.apps)
                                Text(
                                  '▲ TODAS',
                                  key: const Key('radial-all-hint'),
                                  style: TextStyle(
                                    fontFamily: monoFont,
                                    fontSize: 15,
                                    color: c.dim,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // la pista del giro, debajo del reactor
          Positioned(
            left: geometry.center.dx - 150,
            width: 300,
            top: geometry.center.dy + RadialGeometry.outer + halo - 2,
            child: FadeTransition(
              opacity: opening,
              child: Text(
                '↺ APPS · FUNCIONES ↻',
                key: const Key('radial-turn-hint'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: monoFont,
                  fontSize: 15,
                  letterSpacing: 1,
                  color: c.ink.withValues(alpha: 0.85),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// El icono de una opción sobre su cuña. La elegida va en vídeo inverso (un bloque de tinta con el icono del color de la pantalla); la
/// sección en la que se está lleva un recuadro de tinta.
class _Option extends StatelessWidget {
  const _Option({
    required this.entry,
    required this.selected,
    required this.current,
  });

  final RadialEntry entry;
  final bool selected;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: entry.label,
      selected: current,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: DecoratedBox(
          key: Key('radial-${entry.id}'),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? c.accent : null,
            border: current && !selected
                ? Border.all(color: c.accent, width: 1.5)
                : null,
          ),
          child: Center(
            child: _entryIcon(
              entry,
              26,
              selected ? c.onAccent : (current ? c.accent : c.ink),
            ),
          ),
        ),
      ),
    );
  }
}

/// El borde del hueco: su contorno dentado con un destello del acento y, alrededor, los **fragmentos** del contenido que se deshace (rayitas
/// tangentes que parpadean mientras se abre y se quedan pocas y tenues).
class _EdgePainter extends CustomPainter {
  _EdgePainter({required this.center, required this.open, required this.accent})
    : super(repaint: open);

  final Offset center;
  final Animation<double> open;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final o = open.value.clamp(0.0, 1.0);
    if (o <= 0) return;
    final t = Curves.easeOutCubic.transform(o);
    final r = RadialCutout.radius * t;
    // el parpadeo del contorno se apaga poco a poco al terminar de abrirse (así no hay un salto al final)
    final flicker = SectionMotion.noise(3, (o * 14).floor()) < 0.25
        ? 1 - 0.6 * (1 - o)
        : 1.0;
    canvas.drawPath(
      RadialCutout.path(center, o),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = accent.withValues(alpha: 0.65 * flicker),
    );
    canvas.drawCircle(
      center,
      r + 5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = accent.withValues(alpha: 0.22 * t),
    );
    final tick = (o * 14).floor();
    final bit = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.butt;
    for (var i = 0; i < 80; i++) {
      final angle = SectionMotion.noise(i, 1) * 2 * math.pi;
      final out = 6 + SectionMotion.noise(i, 2) * 34;
      final length = 6 + SectionMotion.noise(i, 3) * 26;
      // mientras se abre, cada fragmento aparece o no a cada salto (con más fuerza cuanto menos abierto); ya abierto, solo quedan algunos,
      // tenues. Todo cambia de forma continua: no hay un salto cuando termina
      final stays = SectionMotion.noise(i, 4) > 0.8;
      final flash = SectionMotion.noise(i, tick + 40) < 0.55;
      final alpha = stays
          ? 0.28 + (flash ? 0.42 * (1 - o) : 0)
          : (flash ? 0.7 * (1 - o) : 0);
      if (alpha <= 0) continue;
      final from = center + Offset.fromDirection(angle, r + out);
      final tangent = Offset.fromDirection(angle + math.pi / 2, length);
      bit.color = accent.withValues(alpha: alpha * (1 - out / 52));
      canvas.drawLine(from, from + tangent, bit);
    }
  }

  @override
  bool shouldRepaint(_EdgePainter old) =>
      old.center != center || old.accent != accent;
}

/// Pinta el reactor: el cuerpo del aro (cristal oscuro con filos de neón), las separaciones y la cuña elegida, un anillo punteado por dentro
/// que gira, tres anillos por fuera (arcos de energía, marcas y un anillo fino) que giran en sentidos distintos, y el núcleo del centro con
/// sus aspas girando y un latido de luz. Al proyectarse lo barre una franja de luz de arriba abajo.
class _ReactorPainter extends CustomPainter {
  _ReactorPainter({
    required this.count,
    required this.step,
    required this.turn,
    required this.selected,
    required this.ink,
    required this.accent,
    required this.open,
    required this.spin,
  }) : super(repaint: Listenable.merge([open, spin]));

  final int count;
  final double step;
  final double turn;
  final int? selected;
  final Color ink;
  final Color accent;

  /// 0 → 1 al abrirse, y 0 → 1 en cada vuelta del reactor.
  final Animation<double> open;
  final Animation<double> spin;

  static const _full = 2 * math.pi;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final t = open.value.clamp(0.0, 1.0);
    final s = spin.value * _full; // una vuelta del reactor
    const outer = RadialGeometry.outer,
        inner = RadialGeometry.inner,
        hub = RadialGeometry.hub;
    final body = Path()
      ..addOval(Rect.fromCircle(center: c, radius: outer))
      ..addOval(Rect.fromCircle(center: c, radius: inner))
      ..fillType = PathFillType.evenOdd;

    // el resplandor de detrás del aro
    canvas.drawCircle(
      c,
      outer + 26,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withValues(alpha: 0),
            accent.withValues(alpha: 0.16 * t),
            accent.withValues(alpha: 0),
          ],
          stops: const [0.62, 0.8, 1],
        ).createShader(Rect.fromCircle(center: c, radius: outer + 26)),
    );
    // el cuerpo: cristal oscuro con un toque del acento
    canvas.drawPath(
      body,
      Paint()
        ..color = Color.alphaBlend(
          accent.withValues(alpha: 0.08),
          Colors.black.withValues(alpha: 0.78),
        ),
    );
    final pick = selected;
    if (pick != null && count > 0) {
      final from = RadialGeometry.first + turn + step * pick - step / 2;
      final wedge = Path()
        ..arcTo(Rect.fromCircle(center: c, radius: outer - 1), from, step, true)
        ..arcTo(
          Rect.fromCircle(center: c, radius: inner + 1),
          from + step,
          -step,
          false,
        )
        ..close();
      canvas.drawPath(wedge, Paint()..color = accent.withValues(alpha: 0.32));
    }
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = ink;
    if (count > 1) {
      for (var i = 0; i < count; i++) {
        final angle = RadialGeometry.first + turn + step * i - step / 2;
        canvas.drawLine(
          c + Offset.fromDirection(angle, inner),
          c + Offset.fromDirection(angle, outer),
          line,
        );
      }
    }
    // los filos de neón del cuerpo: un halo ancho y tenue y encima el filo fino
    for (final r in [outer - 0.5, inner]) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..color = accent.withValues(alpha: 0.1),
      );
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = accent.withValues(alpha: 0.85),
      );
    }

    // por dentro: un anillo punteado que gira al revés
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = accent.withValues(alpha: 0.55);
    final innerRing = Rect.fromCircle(center: c, radius: inner - 7);
    for (var i = 0; i < 24; i++) {
      canvas.drawArc(innerRing, -s + i * _full / 24, _full / 48, false, dash);
    }

    // por fuera: arcos de energía (giran con el reactor), marcas (al revés, más despacio) y un anillo fino
    final arcs = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.butt
      ..color = accent.withValues(alpha: 0.9);
    final arcRing = Rect.fromCircle(center: c, radius: outer + 9);
    final spinUp = s + (1 - t) * math.pi;
    for (var i = 0; i < 6; i++) {
      canvas.drawArc(
        arcRing,
        spinUp + i * _full / 6,
        _full / 6 * 0.58,
        false,
        arcs,
      );
    }
    final tick = Paint()
      ..strokeWidth = 1.2
      ..color = accent.withValues(alpha: 0.6 * t);
    for (var i = 0; i < 72; i++) {
      final a = -s + i * _full / 72;
      final long = i % 6 == 0;
      canvas.drawLine(
        c + Offset.fromDirection(a, outer + 19 - (long ? 3 : 0)),
        c + Offset.fromDirection(a, outer + 23 + (long ? 3 : 0)),
        tick,
      );
    }
    canvas.drawCircle(
      c,
      outer + 27,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = accent.withValues(alpha: 0.35 * t),
    );

    // el núcleo: disco oscuro, doble filo, aspas que giran y un latido de luz
    canvas.drawCircle(
      c,
      hub,
      Paint()..color = Colors.black.withValues(alpha: 0.82),
    );
    final pulse = 0.5 + 0.5 * math.sin(spin.value * _full * 3);
    canvas.drawCircle(
      c,
      hub - 2,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withValues(alpha: 0.05 + 0.2 * pulse),
            accent.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: hub)),
    );
    final blade = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.butt
      ..color = accent.withValues(alpha: 0.5);
    for (var i = 0; i < 6; i++) {
      final a = s * 2 + i * _full / 6;
      canvas.drawLine(
        c + Offset.fromDirection(a, hub * 0.7),
        c + Offset.fromDirection(a, hub - 4),
        blade,
      );
    }
    canvas.drawCircle(
      c,
      hub,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = accent,
    );
    canvas.drawCircle(
      c,
      hub - 7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = accent.withValues(alpha: 0.4),
    );

    // la franja de luz que barre el reactor de arriba abajo al proyectarse
    if (t < 1) {
      final y = c.dy - outer + 2 * outer * t;
      canvas.save();
      canvas.clipPath(body);
      final band = Rect.fromLTRB(0, y - 10, size.width, y + 10);
      canvas.drawRect(
        band,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              accent.withValues(alpha: 0),
              accent.withValues(alpha: 0.6),
              accent.withValues(alpha: 0),
            ],
          ).createShader(band),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ReactorPainter old) =>
      old.count != count ||
      old.step != step ||
      old.turn != turn ||
      old.selected != selected ||
      old.ink != ink ||
      old.accent != accent;
}
