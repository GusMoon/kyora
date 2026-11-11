import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../util/cover_tint.dart';
import '../../util/wallpaper_color.dart';
import 'lcd_image.dart';
import 'marble_texture.dart';

/// Un disco de vinilo **realista**: plástico **jaspeado** (translúcido, con nubes y manchas de humo oscuro, hecho con los colores de la portada; si la
/// portada es gris, con el acento de la app), surcos finos y bandas entre pistas, dos destellos de luz que no se mueven mientras el disco gira por debajo, el canto con su bisel y, en el centro, la
/// **etiqueta con la portada** y el agujero del eje. Se pinta con curvas y degradados: sin cuadrícula ni píxeles.
class VinylDisc extends StatefulWidget {
  const VinylDisc({super.key, required this.id, required this.file, required this.url, required this.icon, required this.size, this.angle});

  /// El álbum.
  final String id;
  final String? file;
  final String? url;
  final IconData icon;
  final double size;

  /// Cuánto está girado (rad). Sin esto, quieto.
  final ValueListenable<double>? angle;

  /// Lo que ocupa la etiqueta y el agujero, del diámetro del disco.
  static const label = 0.40;
  static const hole = 0.04;

  /// A qué ancho se lee la portada para la etiqueta.
  static const labelResolution = 20;
  static const labelPixels = 256;

  @override
  State<VinylDisc> createState() => _VinylDiscState();
}

class _VinylDiscState extends State<VinylDisc> {
  ui.Image? _image;
  String? _loaded;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(VinylDisc old) {
    super.didUpdateWidget(old);
    _load();
  }

  @override
  void dispose() {
    _stop();
    _image?.dispose();
    super.dispose();
  }

  void _stop() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  void _load() {
    final source = widget.file ?? widget.url;
    if (source == _loaded) return;
    _loaded = source;
    _stop();
    _image?.dispose();
    _image = null;
    if (source == null) return;
    final provider = widget.file != null ? FileImage(File(widget.file!)) as ImageProvider : NetworkImage(widget.url!);
    final stream = ResizeImage(provider, width: VinylDisc.labelPixels).resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (info, _) async {
        final mine = info.image.clone();
        if (!mounted || _loaded != source) {
          mine.dispose();
          return;
        }
        setState(() {
          _image?.dispose();
          _image = mine;
        });
        // el color de la portada, para teñir el plástico (y el anillo de avance y el sonido)
        final art = await LcdImage.pixelArtOf(info.image, VinylDisc.labelResolution, colors: 8);
        if (art != null) CoverTints.learn(source, art);
      },
      onError: (_, _) {},
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final source = widget.file ?? widget.url;
    return ValueListenableBuilder<Color?>(
      valueListenable: CoverTints.watch(source),
      builder: (context, tint, _) => ValueListenableBuilder<CoverPalette?>(
        valueListenable: CoverTints.watchPalette(source),
        builder: (context, palette, _) {
          // el disco, de los colores de su portada; sin color (o sin portada), el acento de la app
          final ink = tint ?? c.accent;
          final colors = palette ?? CoverPalette.fromColor(ink);
          return SizedBox.square(
            dimension: widget.size,
            child: RepaintBoundary(
              child: CustomPaint(
                key: const Key('vinyl-surface'),
                painter: VinylPainter(angle: widget.angle, label: _image, ink: ink, marble: MarbleTexture.of(colors, MarbleTexture.seedOf(source ?? widget.id))),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Pinta el disco. Se repinta solo cuando cambia el ángulo (no reconstruye ningún widget).
class VinylPainter extends CustomPainter {
  VinylPainter({required this.angle, required this.label, required this.ink, this.marble}) : super(repaint: angle);

  final ValueListenable<double>? angle;

  /// La portada de la etiqueta (sin ella, un círculo liso del color del disco).
  final ui.Image? label;
  final Color ink;

  /// La textura jaspeada del plástico (ver `MarbleTexture`). Sin ella, el plástico liso con unas vetas suaves.
  final ui.Image? marble;

  /// El color del plástico: el mismo de la portada, vivo pero sin llegar a quemar (que se vean los surcos).
  static Color plastic(Color ink) {
    final hsl = HSLColor.fromColor(ink);
    return hsl.withSaturation((hsl.saturation * 0.9).clamp(0.0, 1.0)).withLightness((hsl.lightness * 0.9).clamp(0.2, 0.62)).toColor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);
    final rot = angle?.value ?? 0;
    final base = plastic(ink);
    final light = Color.lerp(base, Colors.white, 0.28)!;
    final dark = Color.lerp(base, Colors.black, 0.55)!;
    final disc = Rect.fromCircle(center: center, radius: r);

    // el plástico, algo más claro hacia el borde
    canvas.drawCircle(
      center,
      r,
      Paint()..shader = RadialGradient(colors: [dark, base, Color.lerp(base, light, 0.35)!, dark], stops: const [0.0, 0.5, 0.86, 1.0]).createShader(disc),
    );

    // el jaspeado: la textura de la portada, que gira con el disco
    final texture = marble;
    if (texture != null) {
      canvas.save();
      canvas.clipPath(Path()..addOval(disc));
      canvas.translate(r, r);
      canvas.rotate(rot);
      canvas.drawImageRect(
        texture,
        Rect.fromLTWH(0, 0, texture.width.toDouble(), texture.height.toDouble()),
        Rect.fromCenter(center: Offset.zero, width: r * 2.9, height: r * 2.9), // un poco más grande: al girar no asoman las esquinas
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
      // el volumen del plástico: se oscurece hacia el borde y se aclara hacia el aro
      canvas.drawCircle(center, r, Paint()..shader = RadialGradient(colors: [Colors.transparent, Colors.transparent, Colors.black.withValues(alpha: 0.26)], stops: const [0.0, 0.72, 1.0]).createShader(disc));
    }

    // las vetas: manchas más claras y más oscuras, que giran con el disco (sin jaspeado)
    canvas.save();
    canvas.translate(r, r);
    canvas.rotate(rot);
    for (var i = 0; texture == null && i < 7; i++) {
      final a = i * 2.399963; // el ángulo áureo: reparte las manchas sin que se repitan
      final d = r * (0.42 + 0.46 * ((i * 0.37) % 1.0));
      final at = Offset(math.cos(a) * d, math.sin(a) * d);
      final spot = r * (0.22 + 0.12 * ((i * 0.61) % 1.0));
      final tone = i.isEven ? light : dark;
      canvas.drawCircle(
        at,
        spot,
        Paint()..shader = RadialGradient(colors: [tone.withValues(alpha: 0.34), tone.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: at, radius: spot)),
      );
    }
    canvas.restore();

    // los surcos: anillos finísimos, y las bandas lisas entre pistas
    final groove = Paint()..style = PaintingStyle.stroke..strokeWidth = 0.7;
    for (var g = r * 0.47; g < r * 0.95; g += r * 0.0185) {
      groove.color = (((g / r * 100).floor()) % 2 == 0 ? Colors.black : Colors.white).withValues(alpha: 0.07);
      canvas.drawCircle(center, g, groove);
    }
    final gap = Paint()..style = PaintingStyle.stroke..strokeWidth = r * 0.022..color = Colors.black.withValues(alpha: 0.28);
    for (final at in const [0.58, 0.69, 0.79, 0.88]) {
      canvas.drawCircle(center, r * at, gap);
    }

    // los destellos: dos cuñas de luz opuestas que no giran con el disco
    canvas.save();
    canvas.clipPath(Path()..addOval(disc));
    canvas.drawRect(
      disc,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = SweepGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.2),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.2),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.07, 0.14, 0.5, 0.57, 0.64],
          transform: const GradientRotation(-0.9),
        ).createShader(disc),
    );
    canvas.restore();

    // el canto: el borde oscuro y un hilo de luz por dentro
    canvas.drawCircle(center, r - 1, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = Colors.black.withValues(alpha: 0.55));
    canvas.drawCircle(center, r - 4, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = Colors.white.withValues(alpha: 0.12));

    // la etiqueta, con la portada (que gira con el disco)
    final lr = r * VinylDisc.label;
    canvas.drawCircle(center, lr + r * 0.015, Paint()..color = Colors.black.withValues(alpha: 0.6));
    final image = label;
    if (image == null) {
      canvas.drawCircle(center, lr, Paint()..color = Color.lerp(base, Colors.black, 0.35)!);
    } else {
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: lr)));
      canvas.translate(r, r);
      canvas.rotate(rot);
      final side = math.min(image.width, image.height).toDouble();
      canvas.drawImageRect(
        image,
        Rect.fromLTWH((image.width - side) / 2, (image.height - side) / 2, side, side),
        Rect.fromCircle(center: Offset.zero, radius: lr),
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
      // un velo mate sobre la etiqueta
      canvas.drawCircle(center, lr, Paint()..color = Colors.black.withValues(alpha: 0.08));
    }
    canvas.drawCircle(center, lr, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = Colors.white.withValues(alpha: 0.18));

    // el agujero del eje
    final hr = r * VinylDisc.hole;
    canvas.drawCircle(center, hr + 1.5, Paint()..color = Colors.black.withValues(alpha: 0.5));
    canvas.drawCircle(center, hr, Paint()..color = const Color(0xFF0A0A0C));
  }

  @override
  bool shouldRepaint(VinylPainter old) => old.label != label || old.ink != ink || old.angle != angle || old.marble != marble;
}
