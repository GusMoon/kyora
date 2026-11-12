import 'package:flutter/material.dart';

import '../../state/player_controller.dart';
import '../../theme.dart';
import '../../util/format.dart';
import 'cover.dart';
import 'pixel_glyph.dart';
import 'cut_border.dart';

/// La tarjeta de lo que suena, abajo: una píldora oscura con la portada en pixel art, el nombre, el artista (o un mensaje del sistema),
/// pausa y siguiente, y una barra de avance con el acento. Al tocarla lleva al disco de esa canción. No se
/// dibuja si no hay nada cargado.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.player, this.onOpen});

  final PlayerController player;

  /// Llevar al disco de la canción que suena.
  final VoidCallback? onOpen;

  static const radius = 28.0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final track = player.current;
        if (track == null) return const SizedBox.shrink();
        final c = context.colors;
        final file = player.coverFileOf(track);
        final named = splitArtistTitle(track.title);
        final total = player.duration.inMilliseconds;
        final status = player.error ?? (player.loading ? 'cargando…' : null);
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: DecoratedBox(
              key: const Key('mini-card'),
              decoration: cutDecoration(color: c.surface, edge: c.edge, cut: 18),
              child: GestureDetector(
                key: const Key('mini-player'),
                behavior: HitTestBehavior.opaque,
                onTap: onOpen,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 4, 6),
                      child: Row(
                        children: [
                          Cover(url: track.coverUrl, file: file, size: 52, radius: 16),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  named.title,
                                  key: const Key('mini-title'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontFamily: appFont, color: c.ink, fontSize: 16, fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  status?.toLowerCase() ?? (named.artist ?? track.playlist ?? 'Kyra'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: status != null ? lcdStatus(color: c.warn) : TextStyle(fontFamily: appFont, fontSize: 15, color: c.dim),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            key: const Key('mini-toggle'),
                            tooltip: player.playing ? 'Pausa' : 'Reproducir',
                            iconSize: 28,
                            style: IconButton.styleFrom(backgroundColor: c.accent, foregroundColor: c.onAccent),
                            color: c.onAccent,
                            icon: LcdIcon(player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                            onPressed: player.toggle,
                          ),
                          IconButton(
                            key: const Key('mini-next'),
                            tooltip: 'Siguiente',
                            iconSize: 28,
                            color: c.ink,
                            icon: const LcdIcon(Icons.skip_next_rounded),
                            onPressed: player.next,
                          ),
                        ],
                      ),
                    ),
                    // el avance se repinta solo, sin reconstruir el resto de la tarjeta
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: ValueListenableBuilder<Duration>(
                        valueListenable: player.positionListenable,
                        builder: (context, position, _) => LinearProgressIndicator(
                          key: const Key('mini-progress'),
                          value: total > 0 ? (position.inMilliseconds / total).clamp(0.0, 1.0) : 0.0,
                          minHeight: 4,
                          color: c.accent,
                          backgroundColor: c.plate,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
