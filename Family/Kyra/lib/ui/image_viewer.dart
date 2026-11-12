import 'package:flutter/material.dart';
import 'widgets/lcd_image.dart';
import 'widgets/pixel_glyph.dart';

/// Una foto a pantalla completa, con zoom y desplazamiento.
class ImageViewerPage extends StatelessWidget {
  const ImageViewerPage({super.key, required this.image, required this.title});

  final ImageProvider image;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16))),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          // la foto en dos tonos (tinta sobre el fondo), con más resolución que una portada
          child: LcdImage(image: image, resolution: LcdImage.viewerResolution, fit: BoxFit.contain, error: const LcdIcon(Icons.broken_image_outlined, size: 56)),
        ),
      ),
    );
  }
}
