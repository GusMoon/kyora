import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../util/cover_tint.dart';
import 'lcd_image.dart';

/// Un fondo hecho con **la portada**, tal cual (sin desenfocar), a pantalla completa y teñida con su color. El oscurecido plano y las líneas
/// de barrido los pone encima quien lo use (`HackerScreen`). Debajo lleva el color de la portada, que se ve mientras la imagen carga.
///
/// Al cargar la portada apunta su color (`CoverTints`), así otras partes (el disco, el anillo de avance, los colores de la app) lo usan también.
class CoverBackdrop extends StatefulWidget {
  const CoverBackdrop({super.key, this.file, this.url}) : assert(file != null || url != null);

  /// La portada: un archivo del teléfono o una dirección de internet.
  final String? file;
  final String? url;

  /// A cuántos cuadros se reduce la portada para sacar su color.
  static const _tintResolution = 20;

  @override
  State<CoverBackdrop> createState() => _CoverBackdropState();
}

class _CoverBackdropState extends State<CoverBackdrop> {
  String? _learning;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  String get _source => widget.file ?? widget.url!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _learn();
  }

  @override
  void didUpdateWidget(CoverBackdrop old) {
    super.didUpdateWidget(old);
    _learn();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _stop() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  /// Si aún no se sabe el color de esta portada, lo saca de la imagen (pequeña) y lo apunta.
  void _learn() {
    final source = _source;
    if (source == _learning) return;
    _learning = source;
    _stop();
    if (CoverTints.of(source) != null) return;
    final provider = widget.file != null ? FileImage(File(widget.file!)) as ImageProvider : NetworkImage(widget.url!);
    final stream = ResizeImage(provider, width: 64).resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (info, _) async {
        final art = await LcdImage.pixelArtOf(info.image, CoverBackdrop._tintResolution, colors: 8);
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
    final source = _source;
    return ValueListenableBuilder<Color?>(
      valueListenable: CoverTints.watch(source),
      builder: (context, tint, _) {
        final color = tint ?? context.colors.accent;
        // solo el tamaño y la densidad: `MediaQuery.of` reconstruiría el fondo con cada cambio (teclado, márgenes…)
        final screen = MediaQuery.sizeOf(context);
        const none = SizedBox.shrink();
        // se decodifica al ancho de la pantalla (nítida: ya no se desenfoca)
        final width = (screen.width * MediaQuery.devicePixelRatioOf(context)).round().clamp(240, 1080);
        final photo = widget.file != null
            ? Image.file(File(widget.file!), key: const Key('backdrop-cover'), fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: width, errorBuilder: (_, _, _) => none)
            : Image.network(widget.url!, key: const Key('backdrop-cover'), fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: width, errorBuilder: (_, _, _) => none);
        return TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: color),
          duration: const Duration(milliseconds: 420),
          builder: (context, c, _) {
            final base = c ?? color;
            return RepaintBoundary(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(key: const Key('matte-backdrop'), color: Color.lerp(const Color(0xFF050506), base, 0.4)!),
                  // la portada, tal cual
                  SizedBox(width: screen.width, height: screen.height, child: photo),
                  // el color de la portada por encima
                  ColoredBox(key: const Key('backdrop-tint'), color: base.withValues(alpha: 0.14)),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
