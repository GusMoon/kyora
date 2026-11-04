import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/favorites_store.dart';
import '../../models/track.dart';
import '../../state/local_music_controller.dart';
import '../../state/music_controller.dart';
import '../../state/player_controller.dart';
import '../../theme.dart';
import '../../util/format.dart';
import 'song_row.dart';

/// Los trozos de la pantalla de música que se comparten entre la principal (álbumes y favoritas) y la de cada álbum.

class MusicMessage extends StatelessWidget {
  const MusicMessage(this.text, {super.key, this.warn = false, this.onRetry, this.actionLabel, this.onAction});

  final String text;
  final bool warn;
  final Future<void> Function()? onRetry;

  /// Un botón con otro nombre y otra acción (por ejemplo «Elegir carpeta»).
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: warn ? context.colors.warn : context.colors.dim),
            ),
            if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Reintentar')),
            if (onAction != null) TextButton(key: const Key('message-action'), onPressed: onAction, child: Text(actionLabel ?? 'Reintentar')),
          ],
        ),
      ),
    );
  }
}


class MusicBanner extends StatelessWidget {
  const MusicBanner({super.key, required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    final pending = controller.pendingCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              pending == 0 ? 'Todo guardado en ${controller.settings.where}.' : '$pending por guardar en ${controller.settings.where}.',
              key: const Key('music-banner'),
              style: TextStyle(color: context.colors.dim, fontSize: 14),
            ),
          ),
          if (pending > 0) TextButton(key: const Key('save-all'), onPressed: controller.saveAll, child: const Text('Guardar todas')),
        ],
      ),
    );
  }
}

/// Una canción enviada en una lista: «Recibido», el corazón y el menú ⋯ (guardar).
class SentTile extends StatelessWidget {
  const SentTile({
    super.key,
    required this.track,
    required this.number,
    required this.controller,
    this.player,
    this.favorites,
    this.local,
    this.onPlayed,
    this.queue,
  });

  /// La lista de la que sale la cola al tocarla (por defecto, todas las enviadas).
  final List<Track>? queue;

  final Track track;
  final int number;
  final MusicController controller;
  final PlayerController? player;
  final FavoritesController? favorites;
  final LocalMusicController? local;

  /// Se llama al tocar la canción para reproducirla (por ejemplo, para recoger la lista).
  final VoidCallback? onPlayed;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([?player, ?favorites, ?local]),
      builder: (context, _) {
        final p = player;
        final isCurrent = p?.current?.id == track.id;
        return _build(context, isCurrent, isCurrent && p!.playing, p?.durationOf(track));
      },
    );
  }

  Widget _build(BuildContext context, bool isCurrent, bool isPlaying, Duration? length) {
    final state = controller.stateOf(track);
    final failure = controller.failureOf(track);
    final named = splitArtistTitle(track.title);
    final canSave = state == TrackState.pending || state == TrackState.failed;
    final f = favorites;
    return SongRow(
      key: Key('track-${track.id}'),
      number: number,
      title: named.title,
      line: state == TrackState.failed ? '${failure ?? 'No se pudo guardar'} · toca ⋯ para reintentar' : (named.artist ?? track.playlist ?? ''),
      warn: state == TrackState.failed,
      saved: state == TrackState.saved,
      coverUrl: track.coverUrl,
      coverFile: local?.artOf(track),
      duration: length,
      current: isCurrent,
      playing: isPlaying,
      favorite: f?.isFavorite(track.durationKey),
      onFavorite: f == null ? null : () => unawaited(f.toggle(track.durationKey)),
      action: ReceivedButton(track: track, controller: controller),
      trailing: SentMenu(track: track, controller: controller),
      onTap: () {
        final p = player;
        if (p != null) {
          unawaited(p.play(track, queue ?? controller.tracks));
        } else if (canSave) {
          unawaited(controller.save(track));
        }
        onPlayed?.call();
      },
    );
  }
}

/// El menú ⋯ de una canción enviada: guardarla en el teléfono (o reintentar). Mientras guarda, un círculo girando.
class SentMenu extends StatelessWidget {
  const SentMenu({super.key, required this.track, required this.controller});

  final Track track;
  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.stateOf(track);
    final canSave = state == TrackState.pending || state == TrackState.failed;
    if (state == TrackState.saving) {
      return const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)));
    }
    return PopupMenuButton<String>(
      key: Key('more-${track.id}'),
      tooltip: 'Más opciones',
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_vert_rounded, color: context.colors.dim),
      onSelected: (_) => unawaited(controller.save(track)),
      itemBuilder: (_) => [
        PopupMenuItem(
          key: Key('save-${track.id}'),
          value: 'save',
          enabled: canSave,
          child: Text(state == TrackState.saved ? 'Guardada en el teléfono' : (state == TrackState.failed ? 'Reintentar' : 'Guardar en el teléfono')),
        ),
      ],
    );
  }
}

/// «Recibido» en una canción enviada: guarda la canción en el teléfono si aún no está y solo entonces avisa a Supabase (que desde ahí
/// puede quitarla de su lado). Ya confirmada, queda una marca «Recibida».
class ReceivedButton extends StatelessWidget {
  const ReceivedButton({super.key, required this.track, required this.controller});

  final Track track;
  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (controller.isReceived(track)) {
      return Tooltip(
        message: 'Recibida',
        child: Icon(Icons.done_all_rounded, key: Key('received-mark-${track.id}'), size: 20, color: c.accent),
      );
    }
    final busy = controller.isConfirming(track);
    return OutlinedButton(
      key: Key('received-${track.id}'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 28),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: c.accent,
        side: BorderSide(color: c.accent.withValues(alpha: 0.6)),
        textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
      ),
      onPressed: busy || controller.stateOf(track) == TrackState.saving ? null : () => unawaited(controller.confirmReceived(track)),
      child: busy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Recibido'),
    );
  }
}

/// Mientras hay canciones marcadas: cuántas, marcar todas, cancelar y «Mover».
class SelectionBar extends StatelessWidget {
  const SelectionBar({super.key, required this.local, required this.onMove});

  final LocalMusicController local;
  final VoidCallback onMove;

  @override
  Widget build(BuildContext context) {
    final n = local.selectedCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 12, 4),
      child: Row(
        children: [
          IconButton(key: const Key('cancel-selection'), tooltip: 'Cancelar', icon: const Icon(Icons.close_rounded), onPressed: local.clearSelection),
          Expanded(
            child: Text(
              n == 1 ? '1 seleccionada' : '$n seleccionadas',
              key: const Key('selection-count'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(key: const Key('select-all'), tooltip: 'Marcar todas', icon: const Icon(Icons.select_all_rounded), onPressed: local.selectAll),
          FilledButton.tonalIcon(
            key: const Key('move-selected'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: onMove,
            icon: const Icon(Icons.drive_file_move_outline),
            label: const Text('Mover'),
          ),
        ],
      ),
    );
  }
}

/// Una canción del teléfono en una lista. Con `selected` (modo selección) tocarla la marca o desmarca; mantenerla pulsada empieza a marcar.
class LocalTile extends StatelessWidget {
  const LocalTile({
    super.key,
    required this.track,
    required this.number,
    required this.all,
    required this.local,
    required this.player,
    required this.favorites,
    this.line,
    this.selected,
    this.onHold,
    this.onToggle,
    this.onPlayed,
  });

  /// `null` fuera del modo selección; si no, si esta canción está marcada.
  final bool? selected;
  final ValueChanged<Track>? onHold;
  final ValueChanged<Track>? onToggle;
  final VoidCallback? onPlayed;

  /// El texto de debajo del título cuando la canción no trae artista.
  final String? line;

  final Track track;
  final int number;
  final List<Track> all;
  final LocalMusicController local;
  final PlayerController? player;
  final FavoritesController? favorites;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([?player, ?favorites]),
      builder: (context, _) {
        final p = player;
        final isCurrent = p?.current?.id == track.id;
        final named = splitArtistTitle(track.title);
        final f = favorites;
        return SongRow(
          key: Key('local-${track.id}'),
          number: number,
          title: named.title,
          line: named.artist ?? line ?? local.folderName,
          coverFile: local.artOf(track),
          duration: local.durationOf(track) ?? p?.durationOf(track),
          current: isCurrent,
          playing: isCurrent && p!.playing,
          favorite: f?.isFavorite(track.durationKey),
          onFavorite: f == null ? null : () => unawaited(f.toggle(track.durationKey)),
          selected: selected,
          onLongPress: onHold == null ? null : () => onHold!(track),
          onTap: selected != null
              ? () => onToggle?.call(track)
              : (p == null
                  ? null
                  : () {
                      unawaited(p.play(track, all));
                      onPlayed?.call();
                    }),
        );
      },
    );
  }
}

