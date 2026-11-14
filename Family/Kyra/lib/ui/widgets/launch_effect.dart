import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/installed_apps.dart';
import '../../theme.dart';
import 'cyber_panel.dart';
import 'cut_border.dart';
import 'hack_text.dart';
import 'section_motion.dart';

/// El efecto que se ve un instante al **abrir una app del teléfono**, antes de que Android la ponga en pantalla: la pantalla se oscurece, un
/// barrido de escaneo la cruza de arriba abajo y en el centro se materializa —con saltos y parpadeo de holograma— un marco con el icono de la
/// app, su nombre escrito con el efecto «hacking» y una barra de segmentos que se llena. Es de Kyra, no de Android: la animación con la que
/// Android abre la app (entrando por un lado) no se puede cambiar desde aquí, así que esta va **antes** y la tapa.
///
/// [progress] va de 0 a 1 y sin curva: la primera parte ([buildEnd]) es la aparición y la carga; el resto, el fundido final.
class LaunchEffect extends StatelessWidget {
  const LaunchEffect({super.key, required this.app, required this.progress});

  final InstalledApp app;
  final Animation<double> progress;

  /// Hasta dónde llega la aparición (la app se lanza aquí); lo que queda hasta 1 es el fundido de salida.
  static const buildEnd = 2 / 3;

  /// Los segmentos de la barra de carga.
  static const segments = 12;

  /// Cuánto se ve el efecto en el avance `t`: sube en el primer tramo y baja en el fundido final.
  static double visibility(double t) {
    final appear = Curves.easeOut.transform((t / 0.22).clamp(0.0, 1.0));
    final out = ((t - buildEnd) / (1 - buildEnd)).clamp(0.0, 1.0);
    return appear * (1 - out);
  }

  /// La carga de la barra (0 → 1) durante la aparición.
  static double loading(double t) => Curves.easeInOut.transform(((t - 0.12) / (buildEnd - 0.12)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final seed = app.package.hashCode & 0xffff;
    return AbsorbPointer(
      child: AnimatedBuilder(
        animation: progress,
        builder: (context, _) {
          final t = progress.value;
          final shown = visibility(t);
          if (shown <= 0) return const SizedBox.shrink();
          // la materialización del marco: salta y parpadea hasta quedar nítido (como los bloques de las secciones)
          final materialize = Curves.easeOut.transform((t / 0.3).clamp(0.0, 1.0));
          final fade = ((t - buildEnd) / (1 - buildEnd)).clamp(0.0, 1.0);
          final lit = (loading(t) * LaunchEffect.segments).round();
          return Stack(
            key: const Key('launch-effect'),
            fit: StackFit.expand,
            children: [
              ColoredBox(color: Colors.black.withValues(alpha: 0.82 * shown)),
              CustomPaint(painter: _ScanPainter(t: t, accent: c.accent, shown: shown)),
              Center(
                child: Opacity(
                  opacity: (SectionMotion.glitchOpacity(materialize, seed) * (1 - fade)).clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: SectionMotion.glitchShift(materialize, seed, MotionEdge.left),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: CyberPanel(
                        active: materialize,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('> ABRIENDO', style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 1.5, color: c.accent)),
                              const SizedBox(height: 16),
                              Center(
                                child: Container(
                                  width: 92,
                                  height: 92,
                                  padding: const EdgeInsets.all(10),
                                  decoration: cutDecoration(color: Colors.black.withValues(alpha: 0.35), edge: c.accent, cut: 12),
                                  child: Image.memory(app.icon, key: const Key('launch-icon'), fit: BoxFit.contain, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                                ),
                              ),
                              const SizedBox(height: 16),
                              HackText(
                                app.label.toUpperCase(),
                                textKey: const Key('launch-label'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(fontFamily: monoFont, fontSize: 18, letterSpacing: 1.6, color: c.ink),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                key: const Key('launch-bar'),
                                children: [
                                  for (var i = 0; i < LaunchEffect.segments; i++)
                                    Expanded(child: Container(height: 6, margin: const EdgeInsets.only(right: 2), color: i < lit ? c.accent : c.accent.withValues(alpha: 0.16))),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// El barrido de escaneo: finas líneas horizontales y una franja luminosa que baja por la pantalla mientras carga.
class _ScanPainter extends CustomPainter {
  const _ScanPainter({required this.t, required this.accent, required this.shown});

  final double t;
  final Color accent;
  final double shown;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final lines = Paint()
      ..strokeWidth = 1
      ..color = accent.withValues(alpha: 0.07 * shown);
    for (var y = 0.0; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), lines);
    }
    final sweep = (t / LaunchEffect.buildEnd).clamp(0.0, 1.0);
    final y = size.height * Curves.easeInOut.transform(sweep);
    final glow = Rect.fromLTWH(0, y - 70, size.width, 70);
    canvas.drawRect(
      glow,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [accent.withValues(alpha: 0), accent.withValues(alpha: 0.22 * shown)],
        ).createShader(glow),
    );
    canvas.drawRect(Rect.fromLTWH(0, y - 1, size.width, 2), Paint()..color = accent.withValues(alpha: 0.85 * shown));
    // unas marcas que saltan a los lados de la franja (interferencia)
    final tick = (t * 40).floor();
    for (var i = 0; i < 3; i++) {
      final w = size.width * (0.05 + SectionMotion.noise(i * 7 + 3, tick) * 0.18);
      final x = SectionMotion.noise(i * 11 + 5, tick) * (size.width - w);
      canvas.drawRect(Rect.fromLTWH(x, y - 1 - i * 3, math.max(w, 6), 2), Paint()..color = accent.withValues(alpha: 0.5 * shown));
    }
  }

  @override
  bool shouldRepaint(covariant _ScanPainter old) => old.t != t || old.accent != accent || old.shown != shown;
}
