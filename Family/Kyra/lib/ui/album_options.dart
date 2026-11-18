import 'package:flutter/material.dart';

import '../theme.dart';
import 'widgets/focus_space.dart';

/// ¿De verdad borrar `count` canciones de «title»? No hay vuelta atrás.
Future<bool> confirmDeleteAlbum(BuildContext context, {required String title, required int count}) async {
  final sure = await showFocusPanel<bool>(
    context,
    title: 'Borrar álbum',
    builder: (context) => FocusDialog(
      content: Text(
        '¿Borrar ${count == 1 ? 'la canción' : 'las $count canciones'} de «$title» del teléfono? No se puede deshacer.',
        key: const Key('album-delete-text'),
      ),
      actions: [
        TextButton(key: const Key('album-delete-cancel'), onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
        FilledButton(
          key: const Key('album-delete-confirm'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40), backgroundColor: context.colors.warn),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Borrar'),
        ),
      ],
    ),
  );
  return sure ?? false;
}

/// Lo que se decide al borrar un álbum que tiene canciones.
enum AlbumDeletion { moveFirst, deleteAll }

/// Borrar un álbum **con canciones**: avisa de que las canciones deben pasarse a otro álbum o, si no, se borrarán junto con el álbum.
/// Devuelve qué hacer o `null` si se cancela.
Future<AlbumDeletion?> askDeleteAlbum(BuildContext context, {required String title, required int count}) => showFocusPanel<AlbumDeletion>(
  context,
  title: 'Borrar álbum',
  builder: (context) => FocusDialog(
    content: Text(
      '«$title» tiene ${count == 1 ? '1 canción' : '$count canciones'}. Debes pasarlas a otro álbum; si no, se borrarán junto con el álbum y no se puede deshacer.',
      key: const Key('album-delete-warning'),
    ),
    actions: [
      TextButton(key: const Key('album-delete-cancel'), onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
      TextButton(
        key: const Key('album-delete-move'),
        onPressed: () => Navigator.of(context).pop(AlbumDeletion.moveFirst),
        child: const Text('Pasarlas a otro álbum'),
      ),
      FilledButton(
        key: const Key('album-delete-all'),
        style: FilledButton.styleFrom(minimumSize: const Size(0, 40), backgroundColor: context.colors.warn),
        onPressed: () => Navigator.of(context).pop(AlbumDeletion.deleteAll),
        child: const Text('Borrar todo'),
      ),
    ],
  ),
);

/// ¿De verdad borrar esta canción del teléfono? No hay vuelta atrás.
Future<bool> confirmDeleteSong(BuildContext context, {required String title}) async {
  final sure = await showFocusPanel<bool>(
    context,
    title: 'Borrar canción',
    builder: (context) => FocusDialog(
      content: Text('¿Borrar «$title» del teléfono? No se puede deshacer.', key: const Key('song-delete-text')),
      actions: [
        TextButton(key: const Key('song-delete-cancel'), onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
        FilledButton(
          key: const Key('song-delete-confirm'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40), backgroundColor: context.colors.warn),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Borrar'),
        ),
      ],
    ),
  );
  return sure ?? false;
}

/// «0.85×» (sin ceros de más).
String _times(double value) {
  final v = (value * 100).round() / 100;
  final text = v == v.roundToDouble() ? v.round().toString() : v.toString();
  return '${text.replaceAll('.', ',')}×';
}

/// Cómo se mueve y se escribe la velocidad (y el tono) en el reactor de opciones: de 0,05 en 0,05 y como «0,85×».
abstract final class RateMeter {
  /// Lo que se mueve el valor de un paso al siguiente.
  static const step = 0.05;

  static String label(double rate) => _times(rate);
}

/// ¿De verdad borrar un álbum **vacío**? No hay vuelta atrás.
Future<bool> confirmDeleteEmptyAlbum(BuildContext context, {required String title}) async {
  final sure = await showFocusPanel<bool>(
    context,
    title: 'Borrar álbum',
    builder: (context) => FocusDialog(
      content: Text('¿Borrar el álbum «$title»? No se puede deshacer.', key: const Key('album-delete-empty-text')),
      actions: [
        TextButton(key: const Key('album-delete-cancel'), onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
        FilledButton(
          key: const Key('album-delete-confirm'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40), backgroundColor: context.colors.warn),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Borrar'),
        ),
      ],
    ),
  );
  return sure ?? false;
}
