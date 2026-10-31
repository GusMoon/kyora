import 'package:flutter/material.dart';

/// Una foto a pantalla completa, con zoom y desplazamiento.
class ImageViewerPage extends StatelessWidget {
  const ImageViewerPage({super.key, required this.image, required this.title});

  final ImageProvider image;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, title: Text(title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16))),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: Image(
            image: image,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 56),
          ),
        ),
      ),
    );
  }
}
