import 'package:flutter/material.dart';

import '../state/player_controller.dart';
import '../theme.dart';
import 'widgets/focus_space.dart';
import 'widgets/pixel_glyph.dart';

/// Lo que se puede hacer con un álbum desde su disco (mantenerlo presionado).
enum AlbumAction { shuffle, move, delete }

/// Las opciones del álbum: aleatorio, mover, borrar y el medidor de **velocidad y tono**. Devuelve la acción elegida o `null` si se cierra.
/// El medidor actúa al instante, sin cerrar el panel.
Future<AlbumAction?> showAlbumOptions(
  BuildContext context, {
  required String title,
  required bool canShuffle,
  required bool canEdit,
  PlayerController? player,
}) =>
    showFocusPanel<AlbumAction>(
      context,
      title: title,
      builder: (context) => _AlbumOptions(canShuffle: canShuffle, canEdit: canEdit, player: player),
    );

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

class _AlbumOptions extends StatelessWidget {
  const _AlbumOptions({required this.canShuffle, required this.canEdit, required this.player});

  final bool canShuffle;
  final bool canEdit;
  final PlayerController? player;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (canShuffle)
              ListTile(
                key: const Key('album-opt-shuffle'),
                leading: const LcdIcon(Icons.shuffle_rounded),
                title: const Text('Aleatorio del álbum'),
                onTap: () => Navigator.of(context).pop(AlbumAction.shuffle),
              ),
            if (canEdit) ...[
              ListTile(
                key: const Key('album-opt-move'),
                leading: const LcdIcon(Icons.drive_file_move_outlined),
                title: const Text('Mover álbum a…'),
                onTap: () => Navigator.of(context).pop(AlbumAction.move),
              ),
              ListTile(
                key: const Key('album-opt-delete'),
                leading: LcdIcon(Icons.delete_outline_rounded, color: c.warn),
                title: Text('Borrar álbum', style: TextStyle(color: c.warn)),
                onTap: () => Navigator.of(context).pop(AlbumAction.delete),
              ),
            ],
            if (player != null) RateMeter(player: player!),
          ],
        ),
      ),
    );
  }
}

/// El medidor de velocidad y tono: de lento a rápido, como un disco al que se le cambia la velocidad (el tono sigue a la velocidad).
class RateMeter extends StatelessWidget {
  const RateMeter({super.key, required this.player});

  final PlayerController player;

  /// Lo que se mueve el medidor de un paso al siguiente.
  static const step = 0.05;

  /// «0.85×» (sin ceros de más).
  static String label(double rate) {
    final v = (rate * 100).round() / 100;
    final text = v == v.roundToDouble() ? v.round().toString() : v.toString();
    return '${text.replaceAll('.', ',')}×';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const min = PlayerController.minRate;
    const max = PlayerController.maxRate;
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const LcdIcon(Icons.speed_rounded),
                const SizedBox(width: 12),
                const Expanded(child: Text('Velocidad y tono')),
                Text(label(player.rate), key: const Key('album-rate-label'), style: TextStyle(color: c.accent, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(width: 4),
                TextButton(
                  key: const Key('album-rate-reset'),
                  style: TextButton.styleFrom(minimumSize: const Size(44, 40)),
                  onPressed: player.rate == 1 ? null : () => player.setRate(1),
                  child: const Text('1×'),
                ),
              ],
            ),
            Slider(
              key: const Key('album-rate'),
              min: min,
              max: max,
              divisions: ((max - min) / step).round(),
              value: player.rate.clamp(min, max).toDouble(),
              onChanged: (v) => player.setRate(double.parse(v.toStringAsFixed(2))),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('más lento', style: TextStyle(color: c.dim, fontSize: 15)),
                Text('más rápido', style: TextStyle(color: c.dim, fontSize: 15)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Cambia la velocidad y el tono a la vez. Se queda así entre canciones hasta volver a 1×.',
                style: TextStyle(color: c.dim, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
