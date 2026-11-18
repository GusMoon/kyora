import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/audio_engine.dart' show RepeatKind;
import '../../data/favorites_store.dart';
import '../../data/music_store.dart';
import '../../models/track.dart';
import '../../state/local_music_controller.dart';
import '../../state/music_controller.dart';
import '../../state/player_controller.dart';
import '../../util/format.dart' show splitArtistTitle;
import '../../util/picker.dart';
import '../../util/track_search.dart';
import '../album_view.dart' show AlbumEntry;
import '../music_actions.dart';
import 'neo_dialogs.dart';
import 'neo_music_dialogs.dart';
import 'neo_pager.dart';
import 'neo_theme.dart';
import 'neo_widgets.dart';

/// La **música** de KyraFamily, con todo lo que tiene KyraAdmin pero en el diseño cyber-brutalista:
///  · los álbumes (las canciones enviadas, la carpeta del teléfono y sus carpetas): abrir, **nuevo álbum**, y con ⋯ (o manteniendo
///    presionado) **cambiar nombre**, **cambiar foto** y **borrar** (pasando antes sus canciones a otro álbum, o borrándolo todo);
///  · dentro de un álbum: **buscar**, **marcar varias** (todas, mover, borrar) y con ⋯ en cada canción **renombrar, mover, borrar** y
///    **favorita**; en las enviadas, **guardar** (una o todas) y avisar de que llegó (**recibido**);
///  · la tarjeta de lo que suena: aleatorio, anterior, reproducir, siguiente, **repetir**, **velocidad** y detener.
class NeoMusicPage extends StatefulWidget {
  const NeoMusicPage({super.key, required this.controller, required this.player, required this.local, this.favorites, this.pickCover = pickCoverImage});

  final MusicController controller;
  final PlayerController player;
  final LocalMusicController local;
  final FavoritesController? favorites;

  /// Cómo se elige la foto de un álbum (la galería; en las pruebas, una falsa).
  final Future<String?> Function() pickCover;

  @override
  State<NeoMusicPage> createState() => _NeoMusicPageState();
}

class _NeoMusicPageState extends State<NeoMusicPage> {
  AlbumEntry? _album;
  bool _shuffling = false;
  bool _searching = false;
  String? _notice;
  final _query = TextEditingController();

  MusicController get _music => widget.controller;
  LocalMusicController get _local => widget.local;
  PlayerController get _player => widget.player;

  MusicActions get _actions => MusicActions(local: _local, player: _player, dialogs: NeoMusicDialogs(this));

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<AlbumEntry> _albums() => [
        const AlbumEntry(id: 'received', title: 'Enviadas', icon: Icons.headphones_rounded),
        if (_local.hasFolder) ...[
          AlbumEntry(id: 'root', title: _local.folderName, icon: Icons.smartphone_rounded),
          for (final folder in _local.rootFolders) AlbumEntry(id: folder.uri, title: folder.name, icon: Icons.album_rounded, folder: folder),
        ],
      ];

  void _openAlbum(AlbumEntry album) {
    final folder = album.folder;
    if (!album.received) {
      if (folder != null) {
        if (!_local.atRoot) unawaited(_local.goTo(0));
        unawaited(_local.open(folder));
      } else if (!_local.atRoot) {
        unawaited(_local.goTo(0));
      }
    }
    setState(() => _album = album);
  }

  void _closeAlbum() {
    _local.clearSelection();
    _query.clear();
    if (!_local.atRoot) unawaited(_local.goTo(0));
    setState(() {
      _album = null;
      _searching = false;
    });
  }

  Future<void> _pickFolder() async {
    try {
      final picked = await _music.pickFolder();
      if (picked == null) return;
      await _music.updateSettings(_music.settings.withTree(picked.uri, picked.name));
    } on TrackSaveException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    }
  }

  Future<void> _refresh() async {
    await _music.refresh();
    await _local.refresh();
  }

  Future<void> _shuffleAll() async {
    if (_shuffling) return;
    setState(() {
      _shuffling = true;
      _notice = null;
    });
    try {
      final mine = await _local.allTracks();
      final all = [..._music.tracks, ...mine];
      if (all.isEmpty) {
        if (mounted) setState(() => _notice = 'Aún no hay canciones para el aleatorio.');
        return;
      }
      await _player.playShuffled(all);
    } finally {
      if (mounted) setState(() => _shuffling = false);
    }
  }

  // ---------- los menús ----------

  /// El menú de un álbum: cambiar nombre y borrar (solo las carpetas) y cambiar foto (todos).
  Future<void> _albumMenu(AlbumEntry e) async {
    final choice = await showNeoMenu<String>(
      context,
      title: e.title,
      options: [
        if (e.folder != null) const NeoMenuOption(value: 'rename', label: 'Cambiar nombre', icon: Icons.edit_outlined, key: Key('neo-album-opt-rename')),
        const NeoMenuOption(value: 'cover', label: 'Cambiar foto', icon: Icons.image_outlined, key: Key('neo-album-opt-cover')),
        if (_local.albumCoverOf(e.id) != null)
          const NeoMenuOption(value: 'uncover', label: 'Quitar foto', icon: Icons.hide_image_outlined, key: Key('neo-album-opt-uncover')),
        if (e.folder != null) const NeoMenuOption(value: 'delete', label: 'Borrar álbum', icon: Icons.delete_outline_rounded, danger: true, key: Key('neo-album-opt-delete')),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'rename':
        await _actions.renameAlbum(e);
      case 'delete':
        await _actions.deleteAlbum(e);
        if (mounted && _album?.id == e.id) _closeAlbum();
      case 'cover':
        final picked = await widget.pickCover();
        if (picked == null || !mounted) return;
        try {
          await _local.setAlbumCover(e.id, picked);
        } on TrackSaveException catch (error) {
          if (mounted) neoToast(context, error.message);
        }
      case 'uncover':
        await _local.clearAlbumCover(e.id);
    }
  }

  /// ¿Se pueden mover, borrar y renombrar las canciones de este álbum? Solo en los del teléfono, ya abiertos.
  bool _canEdit(AlbumEntry e) => !e.received && _local.currentUri == e.dirUri;

  /// El menú de una canción.
  Future<void> _songMenu(AlbumEntry e, Track track) async {
    final favorites = widget.favorites;
    final favorite = favorites?.isFavorite(track.durationKey) ?? false;
    final state = e.received ? _music.stateOf(track) : null;
    final choice = await showNeoMenu<String>(
      context,
      title: splitArtistTitle(track.title).title,
      options: [
        if (favorites != null)
          NeoMenuOption(
            value: 'fav',
            label: favorite ? 'Quitar de favoritas' : 'Favorita',
            icon: favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            key: const Key('neo-song-opt-fav'),
          ),
        if (state == TrackState.pending || state == TrackState.failed)
          const NeoMenuOption(value: 'save', label: 'Guardar en el teléfono', icon: Icons.download_rounded, key: Key('neo-song-opt-save')),
        if (e.received && state == TrackState.saved && !_music.isReceived(track))
          const NeoMenuOption(value: 'received', label: 'Ya la tengo (recibido)', icon: Icons.done_all_rounded, key: Key('neo-song-opt-received')),
        if (_canEdit(e)) ...[
          const NeoMenuOption(value: 'rename', label: 'Cambiar nombre', icon: Icons.edit_outlined, key: Key('neo-song-opt-rename')),
          const NeoMenuOption(value: 'move', label: 'Mover a otro álbum', icon: Icons.drive_file_move_outlined, key: Key('neo-song-opt-move')),
          const NeoMenuOption(value: 'delete', label: 'Borrar canción', icon: Icons.delete_outline_rounded, danger: true, key: Key('neo-song-opt-delete')),
        ],
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'fav':
        await favorites?.toggle(track.durationKey);
      case 'save':
        await _music.save(track);
      case 'received':
        final ok = await _music.confirmReceived(track);
        if (mounted) neoToast(context, ok ? 'Listo: se avisó que ya la tienes.' : 'No se pudo avisar. Inténtalo otra vez.');
      case 'rename':
        await _actions.renameTrack(track);
      case 'move':
        await _actions.moveTrack(track);
      case 'delete':
        await _actions.deleteTrack(track, title: splitArtistTitle(track.title).title);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_music, _local, _player, ?widget.favorites]),
      builder: (context, _) {
        final album = _album;
        return PopScope(
          // «atrás» dentro de un álbum: primero quita las marcas o la búsqueda, luego vuelve a los álbumes
          canPop: album == null,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_local.selecting) {
              _local.clearSelection();
            } else if (_searching) {
              _query.clear();
              setState(() => _searching = false);
            } else {
              _closeAlbum();
            }
          },
          child: Column(
            children: [
              Expanded(child: album == null ? _grid() : _tracks(album)),
              if (_player.hasCurrent) NeoSlide(order: 4, child: _NowPlaying(player: _player, favorites: widget.favorites)),
            ],
          ),
        );
      },
    );
  }

  // ---------- los álbumes ----------

  Widget _grid() {
    final s = context.neo;
    final albums = _albums();
    return ListView(
      key: const Key('neo-music-list'),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
      children: [
        NeoSlide(
          order: 0,
          child: NeoHero(
            index: '01',
            title: 'Música',
            tagline: 'Álbumes. Canciones. Sin prisa.',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                NeoIconButton(key: const Key('neo-music-refresh'), icon: Icons.refresh_rounded, tooltip: 'Actualizar', onTap: () => unawaited(_refresh())),
                const SizedBox(width: 8),
                NeoIconButton(
                  key: const Key('neo-music-shuffle'),
                  icon: Icons.shuffle_rounded,
                  tooltip: 'Aleatorio',
                  color: s.pop,
                  onTap: _shuffling ? null : () => unawaited(_shuffleAll()),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        if (_notice != null) ...[NeoNotice(_notice!, noticeKey: const Key('neo-music-notice')), const SizedBox(height: 14)],
        if (!_local.hasFolder) ...[
          NeoSlide(
            order: 1,
            child: NeoWindow(
              title: 'Tu carpeta de música',
              index: '02',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Elige la carpeta del teléfono donde están tus canciones y aparecerán aquí como álbumes.', style: neoBody(color: s.ink)),
                  const SizedBox(height: 14),
                  NeoButton(key: const Key('neo-pick-folder'), label: 'Elegir carpeta', icon: Icons.folder_open_rounded, onTap: () => unawaited(_pickFolder())),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
        ],
        if (_local.error != null && _local.atRoot) ...[NeoNotice(_local.error!), const SizedBox(height: 14)],
        NeoSlide(
          order: 2,
          child: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 0.88,
            children: [
              for (final a in albums)
                _AlbumCard(album: a, music: _music, local: _local, onTap: () => _openAlbum(a), onMenu: () => unawaited(_albumMenu(a))),
            ],
          ),
        ),
        if (_local.hasFolder) ...[
          const SizedBox(height: 18),
          NeoSlide(
            order: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NeoButton(key: const Key('neo-new-album'), label: 'Nuevo álbum', icon: Icons.create_new_folder_outlined, onTap: () => unawaited(_actions.newAlbum())),
                const SizedBox(height: 10),
                NeoButton(label: 'Cambiar carpeta', icon: Icons.folder_open_rounded, color: s.paper, onTap: () => unawaited(_pickFolder())),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ---------- las canciones de un álbum ----------

  List<Track> _songsOf(AlbumEntry album) => album.received ? _music.tracks : _local.songs;

  Widget _tracks(AlbumEntry album) {
    final s = context.neo;
    final all = _songsOf(album);
    final songs = _searching ? searchTracks(_query.text, all) : all;
    final loading = album.received ? _music.loading : (_local.loading && all.isEmpty);
    final error = album.received ? (all.isEmpty ? _music.error : null) : _local.error;
    final editable = _canEdit(album);
    final selecting = editable && _local.selecting;
    final pending = album.received ? _music.pendingCount : 0;
    return Column(
      children: [
        NeoSlide(
          order: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
            child: Row(
              children: [
                NeoIconButton(key: const Key('neo-album-back'), icon: Icons.arrow_back_rounded, tooltip: 'Volver', onTap: _closeAlbum),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('/${all.length} CANCIONES', style: neoLabel(size: 11, color: s.accentDeep)),
                      Text(album.title.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: neoHeading(size: 24, color: s.ink)),
                    ],
                  ),
                ),
                NeoIconButton(
                  key: const Key('neo-album-search'),
                  icon: _searching ? Icons.search_off_rounded : Icons.search_rounded,
                  tooltip: 'Buscar',
                  size: 40,
                  onTap: all.isEmpty
                      ? null
                      : () => setState(() {
                            _searching = !_searching;
                            if (!_searching) _query.clear();
                          }),
                ),
                if (editable) ...[
                  const SizedBox(width: 8),
                  NeoIconButton(
                    key: const Key('neo-album-select'),
                    icon: Icons.checklist_rounded,
                    tooltip: 'Marcar',
                    size: 40,
                    color: selecting ? s.pop : null,
                    onTap: all.isEmpty ? null : () => selecting ? _local.clearSelection() : _local.toggleSelect(all.first),
                  ),
                ],
                const SizedBox(width: 8),
                NeoIconButton(key: const Key('neo-album-menu'), icon: Icons.more_horiz_rounded, tooltip: 'Opciones', size: 40, onTap: () => unawaited(_albumMenu(album))),
              ],
            ),
          ),
        ),
        if (_searching)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              key: const Key('neo-album-search-field'),
              controller: _query,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              style: neoBody(color: s.ink, weight: FontWeight.w700),
              decoration: const InputDecoration(hintText: 'Buscar en este álbum', prefixIcon: Icon(Icons.search_rounded)),
            ),
          ),
        if (selecting)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: NeoBox(
              key: const Key('neo-selection-bar'),
              color: s.pop,
              strong: true,
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(child: Text('${_local.selectedCount} MARCADAS', style: neoLabel(size: 12, color: s.onPop))),
                  _BarAction(key: const Key('neo-select-all'), icon: Icons.select_all_rounded, tooltip: 'Todas', onTap: _local.selectAll),
                  _BarAction(key: const Key('neo-select-move'), icon: Icons.drive_file_move_outlined, tooltip: 'Mover', onTap: () => unawaited(_actions.moveSelected())),
                  _BarAction(
                    key: const Key('neo-select-delete'),
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Borrar',
                    onTap: () => unawaited(_actions.deleteSelected(albumTitle: album.title)),
                  ),
                  _BarAction(key: const Key('neo-select-cancel'), icon: Icons.close_rounded, tooltip: 'Cancelar', onTap: _local.clearSelection),
                ],
              ),
            ),
          ),
        if (pending > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: NeoButton(
              key: const Key('neo-save-all'),
              label: pending == 1 ? 'Guardar 1 pendiente' : 'Guardar $pending pendientes',
              icon: Icons.download_rounded,
              color: s.pop,
              onTap: () => unawaited(_music.saveAll()),
            ),
          ),
        Expanded(
          child: NeoSlide(
            order: 1,
            child: loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 3))
                : (error != null && all.isEmpty)
                    ? Padding(padding: const EdgeInsets.all(16), child: Align(alignment: Alignment.topCenter, child: NeoNotice(error)))
                    : songs.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: NeoWindow(
                                title: _searching ? 'Sin resultados' : 'Vacío',
                                child: Text(
                                  _searching
                                      ? 'Ninguna canción coincide con «${_query.text}».'
                                      : album.received
                                          ? 'Aún no hay canciones.\nLas que te manden aparecen aquí.'
                                          : 'Este álbum no tiene canciones.',
                                  style: neoBody(color: s.ink),
                                ),
                              ),
                            ),
                          )
                        : ListView.separated(
                            key: const Key('neo-track-list'),
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                            itemCount: songs.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final t = songs[i];
                              return _TrackTile(
                                track: t,
                                number: all.indexOf(t) + 1,
                                player: _player,
                                state: album.received ? _music.stateOf(t) : null,
                                received: album.received && _music.isReceived(t),
                                favorite: widget.favorites?.isFavorite(t.durationKey) ?? false,
                                selecting: selecting,
                                selected: selecting && _local.selectedSongs.any((x) => x.id == t.id),
                                onTap: selecting ? () => _local.toggleSelect(t) : () => unawaited(_player.play(t, songs)),
                                onLongPress: editable ? () => _local.toggleSelect(t) : () => unawaited(_songMenu(album, t)),
                                onMenu: () => unawaited(_songMenu(album, t)),
                              );
                            },
                          ),
          ),
        ),
      ],
    );
  }
}

class _BarAction extends StatelessWidget {
  const _BarAction({super.key, required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(tooltip: tooltip, onPressed: onTap, icon: Icon(icon, color: context.neo.onPop, size: 22));
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album, required this.music, required this.local, required this.onTap, required this.onMenu});

  final AlbumEntry album;
  final MusicController music;
  final LocalMusicController local;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final s = context.neo;
    final art = local.albumArt(album.id);
    final colors = [s.pop, s.paper, s.soft];
    final tint = colors[album.id.hashCode.abs() % colors.length];
    return NeoPress(
      key: Key('neo-album-${album.id}'),
      onTap: onTap,
      onLongPress: onMenu,
      strong: false,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(color: tint, border: Border(bottom: BorderSide(color: s.line, width: Neo.border))),
              child: art != null ? Image.file(File(art), fit: BoxFit.cover, errorBuilder: (_, _, _) => _glyph(s, tint)) : _glyph(s, tint),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 0, 4),
            child: Row(
              children: [
                Expanded(child: Text(album.title.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: neoLabel(size: 12, color: s.ink))),
                IconButton(
                  key: Key('neo-album-more-${album.id}'),
                  tooltip: 'Opciones',
                  visualDensity: VisualDensity.compact,
                  onPressed: onMenu,
                  icon: Icon(Icons.more_horiz_rounded, size: 20, color: s.accent),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _glyph(NeoScheme s, Color tint) => Center(child: Icon(album.icon, size: 46, color: s.onColor(tint)));
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.number,
    required this.player,
    required this.state,
    required this.received,
    required this.favorite,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onMenu,
  });

  final Track track;
  final int number;
  final PlayerController player;

  /// En las enviadas: si ya está en el teléfono (`null` en los álbumes del teléfono).
  final TrackState? state;
  final bool received;
  final bool favorite;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final s = context.neo;
    final current = player.current?.id == track.id;
    final fill = selected ? s.pop : (current ? s.soft : s.paper);
    final parts = splitArtistTitle(track.title);
    final status = switch (state) {
      TrackState.pending => 'PENDIENTE',
      TrackState.saving => 'GUARDANDO…',
      TrackState.failed => 'NO SE GUARDÓ',
      TrackState.saved => received ? 'RECIBIDA' : 'GUARDADA',
      null => null,
    };
    return NeoPress(
      key: Key('neo-track-${track.id}'),
      color: fill,
      strong: selected,
      padding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: current ? s.ink : s.accent, border: Border.all(color: s.ink, width: Neo.border)),
            child: selecting
                ? Icon(selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, color: current ? s.paper : s.onAccent, size: 22)
                : current && player.playing
                    ? Icon(Icons.graphic_eq_rounded, color: s.pop, size: 22)
                    : Text('$number', style: neoLabel(size: 13, color: current ? s.paper : s.onAccent)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(parts.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: neoBody(weight: FontWeight.w700, color: s.onColor(fill))),
                if (parts.artist != null || status != null)
                  Text(
                    [?parts.artist, ?status].join(' · ').toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: neoLabel(size: 10, color: state == TrackState.failed ? Neo.warn : s.dim),
                  ),
              ],
            ),
          ),
          if (favorite) Icon(Icons.favorite_rounded, size: 16, color: s.accent),
          IconButton(
            key: Key('neo-track-more-${track.id}'),
            tooltip: 'Opciones',
            visualDensity: VisualDensity.compact,
            onPressed: onMenu,
            icon: Icon(Icons.more_vert_rounded, color: s.onColor(fill)),
          ),
        ],
      ),
    );
  }
}

String _mmss(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  return '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
}

/// Las velocidades que se van eligiendo con el botón.
const _rates = [0.75, 1.0, 1.25, 1.5];

/// La tarjeta de lo que suena: portada, título, favorita, barra de avance (se toca para saltar) y los controles.
class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.player, required this.favorites});

  final PlayerController player;
  final FavoritesController? favorites;

  @override
  Widget build(BuildContext context) {
    final s = context.neo;
    final track = player.current!;
    final cover = player.coverFileOf(track);
    final favorite = favorites?.isFavorite(track.durationKey) ?? false;
    final nextRate = _rates[(_rates.indexWhere((r) => (r - player.rate).abs() < 0.01) + 1) % _rates.length];
    final repeatIcon = switch (player.repeat) {
      RepeatKind.off => Icons.repeat_rounded,
      RepeatKind.all => Icons.repeat_on_rounded,
      RepeatKind.one => Icons.repeat_one_on_rounded,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: NeoBox(
        key: const Key('neo-now-playing'),
        strong: true,
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(color: s.accent, border: Border.all(color: s.ink, width: Neo.border)),
                  child: cover != null
                      ? Image.file(File(cover), fit: BoxFit.cover, errorBuilder: (_, _, _) => Icon(Icons.music_note_rounded, color: s.onAccent))
                      : Icon(Icons.music_note_rounded, color: s.onAccent, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SUENA AHORA', style: neoLabel(size: 10, color: s.dim)),
                      const SizedBox(height: 2),
                      Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: neoBody(weight: FontWeight.w700, color: s.ink)),
                    ],
                  ),
                ),
                if (favorites != null)
                  IconButton(
                    key: const Key('neo-fav'),
                    tooltip: favorite ? 'Quitar de favoritas' : 'Favorita',
                    onPressed: () => unawaited(favorites!.toggle(track.durationKey)),
                    icon: Icon(favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: favorite ? s.accent : s.ink),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<Duration>(
              valueListenable: player.positionListenable,
              builder: (context, position, _) {
                final total = player.duration;
                final fraction = total.inMilliseconds <= 0 ? 0.0 : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
                return Row(
                  children: [
                    Text(_mmss(position), style: neoLabel(size: 11, color: s.ink)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) => GestureDetector(
                          key: const Key('neo-progress'),
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (d) {
                            if (total.inMilliseconds > 0) unawaited(player.seek(total * (d.localPosition.dx / box.maxWidth).clamp(0.0, 1.0)));
                          },
                          child: Container(
                            height: 14,
                            decoration: BoxDecoration(color: s.soft, border: Border.all(color: s.ink, width: Neo.border)),
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(widthFactor: fraction, child: Container(color: s.accent)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_mmss(total), style: neoLabel(size: 11, color: s.ink)),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                NeoIconButton(
                  key: const Key('neo-shuffle'),
                  icon: Icons.shuffle_rounded,
                  tooltip: 'Aleatorio',
                  size: 38,
                  color: player.shuffle ? s.pop : null,
                  onTap: () => unawaited(player.toggleShuffle()),
                ),
                NeoIconButton(key: const Key('neo-prev'), icon: Icons.skip_previous_rounded, tooltip: 'Anterior', size: 38, onTap: () => unawaited(player.previous())),
                NeoIconButton(
                  key: const Key('neo-play'),
                  icon: player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  tooltip: player.playing ? 'Pausar' : 'Reproducir',
                  color: s.accent,
                  size: 50,
                  onTap: () => unawaited(player.toggle()),
                ),
                NeoIconButton(key: const Key('neo-next'), icon: Icons.skip_next_rounded, tooltip: 'Siguiente', size: 38, onTap: () => unawaited(player.next())),
                NeoIconButton(
                  key: const Key('neo-repeat'),
                  icon: repeatIcon,
                  tooltip: 'Repetir',
                  size: 38,
                  color: player.repeat == RepeatKind.off ? null : s.pop,
                  onTap: () => unawaited(player.cycleRepeat()),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: NeoButton(
                    key: const Key('neo-rate'),
                    label: 'Velocidad ${player.rate.toStringAsFixed(2).replaceAll('.', ',')}×',
                    icon: Icons.speed_rounded,
                    color: s.paper,
                    onTap: () => unawaited(player.setRate(nextRate)),
                  ),
                ),
                const SizedBox(width: 8),
                NeoIconButton(key: const Key('neo-stop'), icon: Icons.stop_rounded, tooltip: 'Detener', size: 50, onTap: () => unawaited(player.stop())),
              ],
            ),
            if (player.error != null) ...[const SizedBox(height: 8), NeoNotice(player.error!)],
          ],
        ),
      ),
    );
  }
}
