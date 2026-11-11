import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme.dart';
import 'cut_border.dart';
import 'pixel_glyph.dart';

/// La portada de un álbum (o un recuadro con el icono si no tiene), entera y con sus colores, en el marco de los componentes. Se decodifica a un
/// tamaño fijo, así se puede escalar al animarla sin volver a leer la imagen. `radius` es lo que se corta en cada esquina.
class AlbumArt extends StatelessWidget {
  const AlbumArt({super.key, required this.file, required this.url, required this.icon, required this.size, required this.radius});

  final String? file;
  final String? url;
  final IconData icon;
  final double size;
  final double radius;

  /// A qué ancho se decodifica la imagen.
  static const decodeWidth = 720;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final blank = Container(
      key: const Key('art-blank'),
      color: c.plate,
      child: Center(child: LcdIcon(icon, size: size * 0.32, color: c.dim)),
    );
    final Widget image;
    if (file != null) {
      image = Image.file(File(file!), key: const Key('art-file'), width: size, height: size, fit: BoxFit.cover, cacheWidth: decodeWidth, gaplessPlayback: true, errorBuilder: (_, _, _) => blank);
    } else if (url != null) {
      image = Image.network(url!, key: const Key('art-network'), width: size, height: size, fit: BoxFit.cover, cacheWidth: decodeWidth, gaplessPlayback: true, errorBuilder: (_, _, _) => blank);
    } else {
      image = blank;
    }
    return SizedBox(width: size, height: size, child: CoverFrame(cut: radius, child: image));
  }
}
