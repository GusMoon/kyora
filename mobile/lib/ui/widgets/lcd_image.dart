import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../util/pixel_art.dart';

/// Cómo se ve una imagen en la pantalla.
enum LcdImageMode {
  /// **Pixel art**: reducida a pocos cuadros grandes y a una **paleta corta de colores planos** (como un dibujo de pixel art), pintada sin
  /// suavizar (las portadas de los álbumes).
  pixel,

  /// **En dos tonos**: solo la tinta y el fondo, con un difuminado ordenado (Bayer 4×4) que hace de sombreado con una trama de puntos (las
  /// fotos del chat).
  twoTone,
}

/// Una imagen (portada, foto) vista en la pantalla: se reduce a poca resolución y se pinta **sin suavizar**, así los píxeles se ven
/// escalonados. Según el `mode`, con sus colores (**pixel**) o en dos tonos con trama (**twoTone**). Lo ya convertido se guarda (por imagen,
/// resolución, modo y paleta).
class LcdImage extends StatefulWidget {
  const LcdImage({
    super.key,
    required this.image,
    this.resolution = coverResolution,
    this.mode = LcdImageMode.twoTone,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.error,
    this.placeholder,
  });

  /// La resolución (el lado mayor, en cuadros) de una portada (pixel art: cuadros bien grandes) y la del visor de fotos.
  static const coverResolution = 36;
  static const pixelColors = 10;
  static const viewerResolution = 360;

  final ImageProvider image;
  final int resolution;
  final LcdImageMode mode;
  final BoxFit fit;
  final double? width;
  final double? height;

  /// Cuántos píxeles de pantalla mide cada cuadro del mosaico, y lo mínimo que se reduce (para que una miniatura también se vea a cuadros).
  static const cell = 8.0;
  static const minPixelResolution = 12;

  /// La resolución de verdad: en pixel art depende del tamaño en pantalla (cuadros de unos 8 px, sin pasar de `resolution`); en dos tonos,
  /// la dada.
  int get effectiveResolution {
    final side = width ?? height;
    if (mode != LcdImageMode.pixel || side == null || !side.isFinite) return resolution;
    return (side / cell).round().clamp(minPixelResolution, resolution);
  }

  /// Lo que se ve si la imagen no se puede leer, y mientras se prepara (sin nada: vacío).
  final Widget? error;
  final Widget? placeholder;

  /// La matriz de Bayer 4×4: el umbral de cada píxel según su posición.
  static const bayer = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
  ];

  /// Pasa unos píxeles RGBA a dos tonos: los claros, al fondo; los oscuros, a la tinta (con la trama en medio).
  static Uint8List dither(Uint8List rgba, int width, int height, Color ink, Color screen) {
    final out = Uint8List(rgba.length);
    int c8(double v) => (v * 255).round().clamp(0, 255);
    final inkRgb = [c8(ink.r), c8(ink.g), c8(ink.b)];
    final screenRgb = [c8(screen.r), c8(screen.g), c8(screen.b)];
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        final alpha = rgba[i + 3] / 255;
        // sobre transparente, el fondo
        final lum = ((0.2126 * rgba[i] + 0.7152 * rgba[i + 1] + 0.0722 * rgba[i + 2]) / 255) * alpha + (1 - alpha);
        final threshold = (bayer[y & 3][x & 3] + 0.5) / 16;
        final rgb = lum > threshold ? screenRgb : inkRgb;
        out[i] = rgb[0];
        out[i + 1] = rgb[1];
        out[i + 2] = rgb[2];
        out[i + 3] = 255;
      }
    }
    return out;
  }

  static final _cache = <String, ui.Image>{};

  /// Reduce `image` a `resolution` cuadros de lado y la pasa a una paleta corta (pixel art): los píxeles listos para pintar.
  static Future<PixelArt?> pixelArtOf(ui.Image image, int resolution, {int colors = pixelColors}) async {
    final scale = resolution / (image.width > image.height ? image.width : image.height);
    final w = (image.width * (scale < 1 ? scale : 1)).round().clamp(1, 4096);
    final h = (image.height * (scale < 1 ? scale : 1)).round().clamp(1, 4096);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final small = await recorder.endRecording().toImage(w, h);
    final bytes = await small.toByteData(format: ui.ImageByteFormat.rawRgba);
    small.dispose();
    if (bytes == null) return null;
    return PixelArt(w, h, quantize(bytes.buffer.asUint8List(), w, h, k: colors));
  }

  @override
  State<LcdImage> createState() => _LcdImageState();
}

class _LcdImageState extends State<LcdImage> {
  ui.Image? _result;
  bool _failed = false;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  String? _key;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(LcdImage old) {
    super.didUpdateWidget(old);
    if (old.image != widget.image || old.effectiveResolution != widget.effectiveResolution || old.mode != widget.mode) _load();
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  void _stopListening() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  void _load() {
    final c = context.colors;
    // en el mosaico los colores son los de la imagen: no dependen de la paleta
    final palette = widget.mode == LcdImageMode.pixel ? '' : '${c.ink.toARGB32()}|${c.background.toARGB32()}';
    final key = '${widget.image.hashCode}|${widget.image}|${widget.effectiveResolution}|${widget.mode.name}|$palette';
    if (key == _key) return;
    _key = key;
    final cached = LcdImage._cache[key];
    if (cached != null) {
      setState(() {
        _result = cached;
        _failed = false;
      });
      return;
    }
    _stopListening();
    // se decodifica ya pequeña: solo hace falta la trama
    final source = ResizeImage(widget.image, width: widget.effectiveResolution * 2, policy: ResizeImagePolicy.fit, allowUpscaling: false);
    final stream = source.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (info, _) => unawaited(_convert(info.image, key, c.ink, c.background)),
      onError: (_, _) {
        if (mounted) setState(() => _failed = true);
      },
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  Future<void> _convert(ui.Image image, String key, Color ink, Color screen) async {
    final ui.Image result;
    if (widget.mode == LcdImageMode.pixel) {
      // pixel art: pocos cuadros grandes y una paleta corta
      final art = await LcdImage.pixelArtOf(image, widget.effectiveResolution);
      if (art == null) return;
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(art.rgba, art.width, art.height, ui.PixelFormat.rgba8888, done.complete);
      result = await done.future;
    } else {
      final scale = widget.effectiveResolution / (image.width > image.height ? image.width : image.height);
      final w = (image.width * (scale < 1 ? scale : 1)).round().clamp(1, 4096);
      final h = (image.height * (scale < 1 ? scale : 1)).round().clamp(1, 4096);
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Paint()..filterQuality = FilterQuality.medium,
      );
      final small = await recorder.endRecording().toImage(w, h);
      final bytes = await small.toByteData(format: ui.ImageByteFormat.rawRgba);
      small.dispose();
      if (bytes == null) return;
      final pixels = LcdImage.dither(bytes.buffer.asUint8List(), w, h, ink, screen);
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(pixels, w, h, ui.PixelFormat.rgba8888, done.complete);
      result = await done.future;
    }
    if (LcdImage._cache.length > 80) LcdImage._cache.clear();
    LcdImage._cache[key] = result;
    if (mounted && _key == key) {
      setState(() {
        _result = result;
        _failed = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.error ?? SizedBox(width: widget.width, height: widget.height);
    final result = _result;
    if (result == null) return widget.placeholder ?? SizedBox(width: widget.width, height: widget.height);
    return RawImage(
      key: const Key('lcd-image'),
      image: result,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      // sin suavizar: los píxeles de la trama se ven escalonados
      filterQuality: FilterQuality.none,
    );
  }
}
