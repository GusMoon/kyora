import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme.dart';

/// La carátula de una canción: una imagen de internet (`url`) o un archivo del teléfono (`file`, la imagen incrustada del .mp3).
/// Sin carátula, o si no carga, un recuadro con una nota musical.
class Cover extends StatelessWidget {
  const Cover({super.key, required this.url, required this.size, this.radius = 10, this.file});

  final String? url;
  final double size;
  final double radius;

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
      child: Icon(Icons.music_note_rounded, color: context.colors.dim, size: size * 0.45),
    );
    final address = url;
    final Widget image;
    if (file != null) {
      image = Image.file(File(file!), key: const Key('cover-file'), width: size, height: size, cacheWidth: (size * 3).round(), fit: BoxFit.cover, errorBuilder: (context, error, stack) => placeholder);
    } else if (address != null) {
      image = Image.network(
        address,
        key: const Key('cover-image'),
        width: size,
        height: size,
        cacheWidth: (size * 3).round(), // decodificada al tamaño que se ve, no al de la imagen original
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => placeholder,
        loadingBuilder: (context, child, progress) => progress == null ? child : placeholder,
      );
    } else {
      image = placeholder;
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: image);
  }
}
