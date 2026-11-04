import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme.dart';

/// La portada de un álbum (o un recuadro con el icono si no tiene). Se decodifica a un tamaño fijo, así se puede escalar al animarla sin
/// volver a leer la imagen.
class AlbumArt extends StatelessWidget {
  const AlbumArt({super.key, required this.file, required this.url, required this.icon, required this.size, required this.radius});

  final String? file;
  final String? url;
  final IconData icon;
  final double size;
  final double radius;

  /// A qué ancho se decodifica la imagen.
  static const decodeWidth = 640;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final blank = DecoratedBox(
      key: const Key('art-blank'),
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c.pick, c.plate])),
      child: Center(child: Icon(icon, size: size * 0.32, color: c.dim)),
    );
    final Widget image;
    if (file != null) {
      image = Image.file(File(file!), key: const Key('art-file'), width: size, height: size, cacheWidth: decodeWidth, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (context, _, _) => blank);
    } else if (url != null) {
      image = Image.network(url!, key: const Key('art-network'), width: size, height: size, cacheWidth: decodeWidth, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (context, _, _) => blank, loadingBuilder: (context, child, progress) => progress == null ? child : blank);
    } else {
      image = blank;
    }
    return SizedBox(width: size, height: size, child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: image));
  }
}
