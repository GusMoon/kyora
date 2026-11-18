import 'package:flutter/material.dart';

import '../data/music_store.dart';
import '../state/local_music_controller.dart';
import 'widgets/focus_space.dart';
import 'widgets/pixel_glyph.dart';

/// «Cambiar foto» de un álbum (`albumId`: `received`, `root` o la dirección de su carpeta): elegirle una imagen (solo en este teléfono) o
/// quitársela. Lo usan el menú de la tarjeta del álbum y la barra de la vista del álbum.
Future<void> changeAlbumCover(
  BuildContext context, {
  required LocalMusicController local,
  required String albumId,
  required String title,
  required Future<String?> Function() pickCover,
}) async {
  final has = local.albumCoverOf(albumId) != null;
  final choice = await showFocusPanel<String>(
    context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          ListTile(
            key: const Key('album-cover-pick'),
            leading: const LcdIcon(Icons.image_outlined),
            title: Text(has ? 'Cambiar portada' : 'Poner portada'),
            onTap: () => Navigator.pop(context, 'pick'),
          ),
          if (has)
            ListTile(
              key: const Key('album-cover-clear'),
              leading: const LcdIcon(Icons.hide_image_outlined),
              title: const Text('Quitar portada'),
              onTap: () => Navigator.pop(context, 'clear'),
            ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    if (choice == 'clear') {
      await local.clearAlbumCover(albumId);
      return;
    }
    final path = await pickCover();
    if (path == null || !context.mounted) return;
    await local.setAlbumCover(albumId, path);
  } on TrackSaveException catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(error.message)));
  }
}
