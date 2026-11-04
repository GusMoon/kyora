import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../util/palette.dart';
import '../../util/vinyl_marble.dart';
import 'album_art.dart';

/// Un disco de vinilo con los colores de la portada del álbum. Lo que **gira** (el plástico jaspeado, los surcos, la etiqueta con la portada
/// y el agujero) va en su propia capa, que solo se rota; lo que **no gira** (los brillos de la luz) va encima: es lo que lo hace parecer de
/// verdad, porque en un disco real el reflejo se queda quieto mientras el plástico pasa por debajo.
class VinylDisc extends StatefulWidget {
  const VinylDisc({super.key, required this.id, required this.file, required this.url, required this.icon, required this.size, this.angle});

  /// El álbum: con el mismo, siempre el mismo dibujo.
  final String id;
  final String? file;
  final String? url;
  final IconData icon;
  final double size;

  /// Cuánto está girado (rad). Sin esto, quieto.
  final ValueListenable<double>? angle;

  /// Lo que ocupa la etiqueta y el agujero, del diámetro del disco.
  static const label = 0.40;
  static const hole = 0.026;

  /// El lado de la imagen del jaspeado.
  static const marbleSize = 320;

  /// Cuántos dibujos se guardan (los últimos usados).
  static const remembered = 12;

  static final LinkedHashMap<String, Future<ui.Image?>> _known = LinkedHashMap();

  /// El jaspeado de ese álbum: se calcula una vez, en otro hilo.
  static Future<ui.Image?> _marble(String id, String? file, String? url, List<Color> fallback) {
    final key = '$id|${file ?? url ?? ''}';
    final known = _known.remove(key);
    if (known != null) return _known[key] = known;
    if (_known.length >= remembered) _known.remove(_known.keys.first);
    return _known[key] = _paint(key, file, url, fallback);
  }

  static Future<ui.Image?> _paint(String key, String? file, String? url, List<Color> fallback) async {
    try {
      final palette = await paletteOf(file: file, url: url) ?? fallback;
      final spec = MarbleSpec(colors: [for (final color in palette) color.toARGB32()], size: marbleSize, seed: marbleSeed(key));
      final pixels = await compute(marblePixels, spec);
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(pixels, marbleSize, marbleSize, ui.PixelFormat.rgba8888, done.complete);
      return await done.future;
    } catch (_) {
      return null; // se queda con el degradado
    }
  }

  @override
  State<VinylDisc> createState() => _VinylDiscState();
}

class _VinylDiscState extends State<VinylDisc> {
  ui.Image? _image;
  String? _loaded;

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

  void _load() {
    final key = '${widget.id}|${widget.file ?? widget.url ?? ''}';
    if (key == _loaded) return;
    _loaded = key;
    final c = context.colors;
    unawaited(VinylDisc._marble(widget.id, widget.file, widget.url, [c.pick, c.plate, c.accent, c.dim]).then((image) {
      if (mounted && key == _loaded) setState(() => _image = image);
    }));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = widget.size;
    final Widget surface = RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(child: CustomPaint(key: const Key('vinyl-surface'), painter: _SurfacePainter(image: _image, near: c.pick, far: c.plate))),
            ClipOval(child: AlbumArt(file: widget.file, url: widget.url, icon: widget.icon, size: size * VinylDisc.label, radius: 0)),
            Container(
              key: const Key('disc-hole'),
              width: size * VinylDisc.hole,
              height: size * VinylDisc.hole,
              decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFF2F2F4), border: Border.all(color: const Color(0xCC000000), width: 1)),
            ),
          ],
        ),
      ),
    );
    final angle = widget.angle;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // la sombra sobre lo de detrás
          const Positioned.fill(
            child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x99000000), blurRadius: 30, offset: Offset(0, 16))])),
          ),
          if (angle == null) surface else ValueListenableBuilder<double>(valueListenable: angle, child: surface, builder: (context, value, child) => Transform.rotate(angle: value, child: child)),
          Positioned.fill(child: RepaintBoundary(child: CustomPaint(key: const Key('vinyl-light'), painter: _LightPainter()))),
        ],
      ),
    );
  }
}

/// El plástico: el jaspeado, oscurecido hacia los bordes, con los surcos, las pistas y el canto.
class _SurfacePainter extends CustomPainter {
  _SurfacePainter({required this.image, required this.near, required this.far});

  final ui.Image? image;
  final Color near;
  final Color far;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = size.center(Offset.zero);
    final disc = Rect.fromCircle(center: c, radius: r);
    canvas.save();
    canvas.clipPath(Path()..addOval(disc));

    final marble = image;
    if (marble != null) {
      canvas.drawImageRect(marble, Rect.fromLTWH(0, 0, marble.width.toDouble(), marble.height.toDouble()), disc, Paint()..filterQuality = FilterQuality.medium);
    } else {
      canvas.drawCircle(c, r, Paint()..shader = RadialGradient(colors: [near, far]).createShader(disc));
    }
    // el volumen: algo más oscuro en la zona sin surcos de junto a la etiqueta y en el borde
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x66000000), Color(0x59000000), Color(0x00000000), Color(0x00000000), Color(0x73000000)],
          stops: [0.0, 0.46, 0.50, 0.86, 1.0],
        ).createShader(disc),
    );

    // los surcos: muchos círculos finísimos, y cada tanto el hueco liso entre dos pistas
    final dark = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = const Color(0x2E000000);
    final light = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = const Color(0x0DFFFFFF);
    final first = r * 0.48, last = r * 0.975;
    var i = 0;
    for (var radius = first; radius < last; radius += math.max(1.5, r / 90)) {
      canvas.drawCircle(c, radius, i.isEven ? dark : light);
      i++;
    }
    for (final at in const [0.58, 0.68, 0.77, 0.87]) {
      canvas.drawCircle(
        c,
        r * at,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.4, r * 0.012)
          ..color = const Color(0x40000000),
      );
      canvas.drawCircle(
        c,
        r * at + math.max(1, r * 0.008),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7
          ..color = const Color(0x17FFFFFF),
      );
    }
    // el canto
    canvas.drawCircle(
      c,
      r - 0.8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = const Color(0x24FFFFFF),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SurfacePainter old) => old.image != image || old.near != near || old.far != far;
}

/// Los reflejos de la luz sobre los surcos: dos fuertes enfrentados y dos más tenues. No giran con el disco.
class _LightPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = size.center(Offset.zero);
    final inner = r * VinylDisc.label;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      (r + inner) / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r - inner
        ..shader = const SweepGradient(
          transform: GradientRotation(-math.pi * 0.36),
          colors: [
            Color(0x00FFFFFF),
            Color(0x33FFFFFF),
            Color(0x00FFFFFF),
            Color(0x00FFFFFF),
            Color(0x12FFFFFF),
            Color(0x00FFFFFF),
            Color(0x00FFFFFF),
            Color(0x2EFFFFFF),
            Color(0x00FFFFFF),
            Color(0x00FFFFFF),
            Color(0x12FFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: [0.0, 0.07, 0.14, 0.24, 0.30, 0.36, 0.50, 0.57, 0.64, 0.74, 0.80, 0.86],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_LightPainter old) => false;
}
