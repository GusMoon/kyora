import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme.dart';
import 'cut_border.dart';
import 'pixel_glyph.dart';

/// La carátula de una canción o un álbum: una imagen de internet (`url`) o un archivo del teléfono (`file`, la imagen incrustada del .mp3).
/// Se ve **entera y con sus colores**, dentro del marco de los componentes (esquinas cortadas y líneas de barrido). Sin carátula, o si no
/// carga, un recuadro oscuro con una nota musical. `radius` es lo que se corta en cada esquina.
class Cover extends StatelessWidget {
  const Cover({super.key, required this.url, required this.size, this.radius = 14, this.file, this.focused = false});

  final String? url;
  final double size;
  final double radius;
  final bool focused;

  /// La ruta de una imagen en el teléfono. Si hay, manda sobre `url`.
  final String? file;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      key: const Key('cover-placeholder'),
      width: size,
      height: size,
      color: context.colors.plate,
      alignment: Alignment.center,
      child: LcdIcon(Icons.music_note_rounded, color: context.colors.dim, size: size * 0.45),
    );
    final address = url;
    final Widget image;
    if (file != null) {
      image = Image.file(File(file!), key: const Key('cover-file'), width: size, height: size, fit: BoxFit.cover, cacheWidth: _decode(context), gaplessPlayback: true, errorBuilder: (_, _, _) => placeholder);
    } else if (address != null) {
      image = Image.network(address, key: const Key('cover-image'), width: size, height: size, fit: BoxFit.cover, cacheWidth: _decode(context), gaplessPlayback: true, errorBuilder: (_, _, _) => placeholder);
    } else {
      image = placeholder;
    }
    return SizedBox(width: size, height: size, child: CoverFrame(cut: radius, focused: focused, child: image));
  }

  int? _decode(BuildContext context) {
    final px = size * MediaQuery.devicePixelRatioOf(context);
    return px.isFinite && px > 0 ? px.round().clamp(64, 1024) : null;
  }
}
