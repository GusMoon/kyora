import 'dart:async';

import 'package:flutter/material.dart';

import '../data/favorites_store.dart';
import '../data/music_store.dart';
import '../models/track.dart';
import '../state/local_music_controller.dart';
import '../state/music_controller.dart';
import '../state/player_controller.dart';
import '../theme.dart';
import '../util/format.dart';
import '../util/picker.dart';
import 'folder_settings.dart';
import 'move_sheet.dart';
import 'album_page.dart';
import 'player_page.dart';
import 'widgets/album_route.dart';
import 'widgets/album_grid.dart';
import 'widgets/song_row.dart';
import 'widgets/subalbum_strip.dart';

/// La música. Al abrirla sale una pila de álbumes: «Canciones enviadas» (las que te mandan desde la PC), tu carpeta del teléfono y sus
/// subcarpetas, que son los álbumes. Arriba, una píldora cambia entre «Álbumes» y «Favoritos» (las canciones con el corazón).
/// Cada álbum abre su lista; ahí las canciones se escuchan tocándolas, y las enviadas se guardan desde el menú ⋯ de cada una.
class MusicPage extends StatefulWidget {
  const MusicPage({super.key, required this.controller, this.player, this.local, this.favorites, this.pickCover = pickCoverImage});

  final MusicController controller;

  /// Los .mp3 de la carpeta elegida. Sin esto no hay tarjetas y solo se ven las enviadas.
  final LocalMusicController? local;

  /// Las canciones con el corazón puesto. Sin esto no salen los corazones.
  final FavoritesController? favorites;

  /// El reproductor. Sin él, tocar una canción la guarda (y no hay barra de reproducción).
  final PlayerController? player;

  /// Elige la imagen para una canción: su ruta, o `null` si se cancela.
  final Future<String?> Function() pickCover;

  @override
  State<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends State<MusicPage> {
  StreamSubscription<String>? _notices;

  /// La pestaña de arriba: «Álbumes» (por defecto) o «Favoritos».
  bool _favoritesTab = false;

  @override
  void initState() {
    super.initState();
    _notices = widget.controller.notices.listen((text) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    });
  }

  @override
  void dispose() {
    unawaited(_notices?.cancel());
    super.dispose();
  }

  Future<void> _settings() => showFolderSettings(context, widget.controller);

  /// Abre las canciones enviadas: las portadas salen de la placa tocada.
  void _openReceived(Rect origin) {
    unawaited(
      Navigator.of(context).push(
        albumRoute<void>(
          builder: (_, animation) => _ReceivedAlbum(
            controller: widget.controller,
            local: widget.local,
            player: widget.player,
            favorites: widget.favorites,
            animation: animation,
            origin: origin,
            onChangeCover: _changeCover,
          ),
        ),
      ),
    );
  }

  /// Abre un álbum del teléfono (`folder` = null: la carpeta raíz; si no, una carpeta, que ya está abierta en el controlador). Dentro,
  /// sus subcarpetas salen arriba como subálbumes y se abren igual, una encima de otra; al volver, el controlador sube un nivel.
  void _openAlbum(LocalMusicController local, Rect origin, {LocalFolder? folder}) {
    final depth = local.path.length;
    unawaited(
      Navigator.of(context)
          .push(
            albumRoute<void>(
              builder: (_, animation) => _LocalAlbum(
                local: local,
                music: widget.controller,
                title: folder?.name ?? local.folderName,
                dirUri: folder?.uri,
                player: widget.player,
                favorites: widget.favorites,
                animation: animation,
                origin: origin,
                onChangeCover: _changeCover,
                onMove: () => _moveSelected(local),
                onOpenSub: (sub, rect) {
                  unawaited(local.open(sub));
                  _openAlbum(local, rect, folder: sub);
                },
              ),
            ),
          )
          .then((_) => local.goTo(depth > 0 ? depth - 1 : 0)),
    );
  }

  /// «Mover»: elige el álbum de destino para las canciones marcadas y las mueve de verdad.
  Future<void> _moveSelected(LocalMusicController local) async {
    final target = await showMoveSheet(context, local, count: local.selectedCount);
    if (target == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await local.moveSelected(toUri: target.uri);
      final bad = result.failures.length;
      final done = result.moved == 1 ? 'Se movió 1 canción' : 'Se movieron ${result.moved} canciones';
      final text = result.moved == 0 && bad == 0
          ? 'No había nada que mover.'
          : [
              if (result.moved > 0) '$done a «${target.name}».',
              if (bad > 0) 'No se ${bad == 1 ? 'pudo mover 1' : 'pudieron mover $bad'}: ${result.failures.values.first}',
            ].join(' ');
      messenger.showSnackBar(SnackBar(content: Text(text)));
    } on TrackSaveException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _changeCover(Track track) async {
    final local = widget.local;
    if (local == null) return;
    final path = await widget.pickCover();
    if (path == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final player = widget.player;
    try {
      Future<Track> change() => local.changeCover(track, path);
      final updated = await (player == null ? change() : player.whileRewriting(track, change));
      await widget.favorites?.rename(track.durationKey, updated.durationKey);
      messenger.showSnackBar(
        SnackBar(content: Text(track.isLocal ? 'Imagen cambiada en el archivo de la canción.' : 'Imagen cambiada en este teléfono.')),
      );
    } on TrackSaveException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Mantener pulsado un álbum: elegirle una imagen de portada (solo en este teléfono) o quitársela.
  Future<void> _albumCover(LocalMusicController local, String albumId, String name) async {
    final has = local.albumCoverOf(albumId) != null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            ListTile(
              key: const Key('album-cover-pick'),
              leading: const Icon(Icons.image_outlined),
              title: Text(has ? 'Cambiar portada' : 'Poner portada'),
              onTap: () => Navigator.pop(context, 'pick'),
            ),
            if (has)
              ListTile(
                key: const Key('album-cover-clear'),
                leading: const Icon(Icons.hide_image_outlined),
                title: const Text('Quitar portada'),
                onTap: () => Navigator.pop(context, 'clear'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (choice == 'clear') {
        await local.clearAlbumCover(albumId);
        return;
      }
      final path = await widget.pickCover();
      if (path == null || !mounted) return;
      await local.setAlbumCover(albumId, path);
    } on TrackSaveException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _newFolder(LocalMusicController local) async {
    final name = await askFolderName(context);
    if (name == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final folder = await local.createFolder(name);
      messenger.showSnackBar(SnackBar(content: Text('Se creó el álbum «${folder.name}».')));
    } on TrackSaveException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = widget.local;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.controller, ?local, ?widget.favorites]),
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            centerTitle: true,
            title: local == null
                ? const Text('Música', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))
                : AlbumTabs(favorites: _favoritesTab, onChanged: (value) => setState(() => _favoritesTab = value)),
          ),
          body: Column(
            children: [
              Expanded(
                child: local == null
                    ? _ReceivedBody(controller: widget.controller, player: widget.player, favorites: widget.favorites)
                    : _favoritesTab
                    ? _favorites(local)
                    : _home(local),
              ),
              if (widget.player != null) MiniPlayer(player: widget.player!),
            ],
          ),
        );
      },
    );
  }

  Widget _home(LocalMusicController local) {
    final c = widget.controller;
    final broken = local.atRoot && local.error != null;

    // la portada de cada álbum: la que le pusiste o, si no, la de su primera canción
    ({String? file, String? url}) coverOf(String albumId, List<Track>? songs) {
      final own = local.albumCoverOf(albumId);
      if (own != null) return (file: own, url: null);
      return coverOfTracks(local, songs);
    }

    final received = coverOf('received', c.tracks);
    final root = coverOf('root', local.tracksIn(null));
    final plates = <AlbumPlate>[
      AlbumPlate(
        id: 'card-received',
        title: 'Canciones enviadas',
        icon: Icons.headphones_rounded,
        coverFile: received.file,
        coverUrl: received.url,
        onTap: _openReceived,
        onLongPress: () => _albumCover(local, 'received', 'Canciones enviadas'),
      ),
      if (!local.hasFolder)
        AlbumPlate(id: 'card-choose', title: 'Elegir carpeta', icon: Icons.folder_open_rounded, onTap: (_) => _settings())
      else if (!broken) ...[
        AlbumPlate(
          id: 'card-root',
          title: local.folderName,
          icon: Icons.smartphone_rounded,
          coverFile: root.file,
          coverUrl: root.url,
          onTap: (origin) => _openAlbum(local, origin),
          onLongPress: () => _albumCover(local, 'root', local.folderName),
        ),
        for (final folder in local.rootFolders)
          AlbumPlate(
            id: 'card-folder-${folder.name}',
            title: folder.name,
            icon: Icons.album_rounded,
            coverFile: coverOf(folder.uri, local.tracksIn(folder.uri)).file,
            onTap: (origin) {
              unawaited(local.open(folder));
              _openAlbum(local, origin, folder: folder);
            },
            onLongPress: () => _albumCover(local, folder.uri, folder.name),
          ),
        AlbumPlate(id: 'card-new-folder', title: 'Nuevo álbum', icon: Icons.add_rounded, onTap: (_) => _newFolder(local)),
      ],
    ];

    Future<void> refresh() async {
      await Future.wait([c.refresh(), local.refresh()]);
    }

    final header = broken
        ? _Message(
            local.error!,
            warn: true,
            actionLabel: local.folderLost ? 'Elegir carpeta' : 'Reintentar',
            onAction: local.folderLost ? _settings : local.refresh,
          )
        : null;
    return AlbumGrid(plates: plates, onRefresh: refresh, header: header);
  }

  /// «Favoritos»: las canciones con el corazón puesto, las enviadas primero y luego las de los álbumes del teléfono ya leídos.
  Widget _favorites(LocalMusicController local) {
    final f = widget.favorites;
    final c = widget.controller;
    final sent = [
      for (final t in c.tracks)
        if (f != null && f.isFavorite(t.durationKey)) t,
    ];
    final mine = [
      for (final t in local.knownTracks())
        if (f != null && f.isFavorite(t.durationKey)) t,
    ];
    if (sent.isEmpty && mine.isEmpty) {
      return const _Message('Aún no tienes favoritas.\nToca el corazón de una canción y aparecerá aquí.', key: Key('favorites-empty'));
    }
    return ListView(
      key: const Key('favorites-list'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (var i = 0; i < sent.length; i++)
          _TrackTile(track: sent[i], number: i + 1, controller: c, player: widget.player, favorites: f, local: local, onChangeCover: _changeCover),
        for (var i = 0; i < mine.length; i++)
          _LocalTile(
            track: mine[i],
            number: sent.length + i + 1,
            all: mine,
            local: local,
            player: widget.player,
            favorites: f,
            onChangeCover: _changeCover,
            line: 'Favorita',
          ),
      ],
    );
  }
}

class _ReceivedBody extends StatelessWidget {
  const _ReceivedBody({required this.controller, this.player, this.favorites});

  final MusicController controller;
  final PlayerController? player;
  final FavoritesController? favorites;

  Widget _list() {
    final c = controller;
    if (c.loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    if (c.error != null && c.tracks.isEmpty) {
      return _Message(c.error!, warn: true, onRetry: c.refresh);
    }
    if (c.tracks.isEmpty) {
      return const _Message('Aún no hay canciones.\nLas que te manden desde la PC aparecen aquí.');
    }
    return ListView.builder(
      key: const Key('track-list'),
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: c.tracks.length,
      itemBuilder: (context, i) => _TrackTile(track: c.tracks[i], number: i + 1, controller: c, player: player, favorites: favorites),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _Banner(controller: controller),
      Expanded(child: _list()),
    ],
  );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.controller});

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

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.number,
    required this.controller,
    this.player,
    this.favorites,
    this.local,
    this.onChangeCover,
  });

  final Track track;
  final int number;
  final MusicController controller;
  final PlayerController? player;
  final FavoritesController? favorites;
  final LocalMusicController? local;
  final void Function(Track track)? onChangeCover;

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
      action: _ReceivedButton(track: track, controller: controller),
      trailing: _SentMenu(track: track, controller: controller, local: local, onChangeCover: onChangeCover),
      onTap: () {
        final p = player;
        if (p != null) {
          unawaited(p.play(track, controller.tracks));
        } else if (canSave) {
          unawaited(controller.save(track));
        }
      },
    );
  }
}

/// El menú ⋯ de una canción enviada: guardarla en el teléfono (o reintentar) y cambiarle la imagen. Mientras guarda, un círculo girando.
class _SentMenu extends StatelessWidget {
  const _SentMenu({required this.track, required this.controller, this.local, this.onChangeCover});

  final Track track;
  final MusicController controller;
  final LocalMusicController? local;
  final void Function(Track track)? onChangeCover;

  @override
  Widget build(BuildContext context) {
    final state = controller.stateOf(track);
    final canSave = state == TrackState.pending || state == TrackState.failed;
    if (state == TrackState.saving || local?.isChangingCover(track) == true) {
      return const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)));
    }
    return PopupMenuButton<String>(
      key: Key('more-${track.id}'),
      tooltip: 'Más opciones',
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_vert_rounded, color: context.colors.dim),
      onSelected: (value) {
        if (value == 'cover') {
          onChangeCover?.call(track);
        } else {
          unawaited(controller.save(track));
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          key: Key('save-${track.id}'),
          value: 'save',
          enabled: canSave,
          child: Text(state == TrackState.saved ? 'Guardada en el teléfono' : (state == TrackState.failed ? 'Reintentar' : 'Guardar en el teléfono')),
        ),
        if (onChangeCover != null) PopupMenuItem(key: Key('cover-${track.id}'), value: 'cover', child: const Text('Cambiar imagen')),
      ],
    );
  }
}

/// El corazón de una canción (favorita o no), con la clave de su lugar en la lista.
class _HeartButton extends StatelessWidget {
  const _HeartButton({required this.track, required this.number, required this.favorites});

  final Track track;
  final int number;
  final FavoritesController favorites;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: favorites,
      builder: (context, _) {
        final on = favorites.isFavorite(track.durationKey);
        return IconButton(
          key: Key('fav-$number'),
          tooltip: on ? 'Quitar de favoritas' : 'Marcar como favorita',
          visualDensity: VisualDensity.compact,
          icon: Icon(on ? Icons.favorite : Icons.favorite_border, color: on ? c.accent : c.dim, size: 24),
          onPressed: () => unawaited(favorites.toggle(track.durationKey)),
        );
      },
    );
  }
}

/// El menú ⋯ de una canción del teléfono: cambiarle la imagen.
class _LocalMenu extends StatelessWidget {
  const _LocalMenu({required this.track, required this.local, required this.onChangeCover});

  final Track track;
  final LocalMusicController local;
  final void Function(Track track) onChangeCover;

  @override
  Widget build(BuildContext context) {
    if (local.isChangingCover(track)) return const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)));
    return PopupMenuButton<String>(
      key: Key('more-${track.id}'),
      tooltip: 'Más opciones',
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_vert_rounded, color: context.colors.dim),
      onSelected: (_) => onChangeCover(track),
      itemBuilder: (_) => [PopupMenuItem(key: Key('cover-${track.id}'), value: 'cover', child: const Text('Cambiar imagen'))],
    );
  }
}

/// «Recibido» en una canción enviada: guarda la canción en el teléfono si aún no está y solo entonces avisa a Supabase (que desde ahí
/// puede quitarla de su lado). Ya confirmada, queda una marca «Recibida».
class _ReceivedButton extends StatelessWidget {
  const _ReceivedButton({required this.track, required this.controller});

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

/// Un álbum del teléfono (`dirUri` null: la carpeta raíz): las canciones como un anillo que se gira y, arriba, sus subcarpetas como
/// subálbumes. Mantener pulsada una canción empieza a marcar varias para moverlas a otro álbum; «atrás» primero quita la marca.
class _LocalAlbum extends StatelessWidget {
  const _LocalAlbum({
    required this.local,
    required this.music,
    required this.title,
    required this.dirUri,
    required this.animation,
    required this.origin,
    required this.onMove,
    required this.onOpenSub,
    this.player,
    this.favorites,
    this.onChangeCover,
  });

  final LocalMusicController local;
  final MusicController music;
  final String title;
  final String? dirUri;
  final Animation<double> animation;
  final Rect origin;
  final VoidCallback onMove;
  final void Function(LocalFolder folder, Rect origin) onOpenSub;
  final PlayerController? player;
  final FavoritesController? favorites;
  final void Function(Track track)? onChangeCover;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: local,
      builder: (context, _) {
        final songs = local.tracksIn(dirUri);
        final folders = local.foldersIn(dirUri) ?? const <LocalFolder>[];
        final current = local.currentUri == dirUri; // la carpeta que el controlador tiene abierta: la de arriba de todo
        final failed = local.error != null && current;
        Widget? notice;
        if (!local.hasFolder) {
          notice = _Message(
            'Elige una carpeta y aquí verás los .mp3 que tengas en ella.\nTambién se guardarán ahí las canciones que te manden.',
            actionLabel: 'Elegir carpeta',
            onAction: () => showFolderSettings(context, music),
          );
        } else if (failed) {
          notice = _Message(
            local.error!,
            warn: true,
            actionLabel: local.folderLost ? 'Elegir carpeta' : 'Reintentar',
            onAction: local.folderLost ? () => showFolderSettings(context, music) : local.refresh,
          );
        } else if (songs == null) {
          notice = const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
        } else if (songs.isEmpty && folders.isEmpty) {
          notice = _Message('No hay archivos .mp3 en «$title».', actionLabel: 'Actualizar', onAction: local.refresh);
        }
        final list = songs ?? const <Track>[];
        final cover = coverOfTracks(local, list);
        final marking = current && local.selecting;
        return AlbumPage(
          title: title,
          animation: animation,
          origin: origin,
          tracks: list,
          coverFile: cover.file,
          coverUrl: cover.url,
          player: player,
          notice: notice,
          artOf: local.artOf,
          cardKey: (track) => Key('local-${track.id}'),
          onPlay: (track, _) {
            final p = player;
            if (p != null) unawaited(p.play(track, list));
          },
          subtitleOf: (track) => (
            text: songLine(artist: splitArtistTitle(track.title).artist ?? title, duration: local.durationOf(track) ?? player?.durationOf(track)),
            warn: false,
          ),
          actionsOf: (context, track, index) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (favorites != null) _HeartButton(track: track, number: index + 1, favorites: favorites!),
              if (onChangeCover != null)
                SizedBox(
                  width: 40,
                  height: 40,
                  child: _LocalMenu(track: track, local: local, onChangeCover: onChangeCover!),
                ),
            ],
          ),
          subalbums: [
            for (final folder in folders)
              SubAlbum(
                id: folder.name,
                title: folder.name,
                subtitle: folder.count == 1 ? '1 canción' : '${folder.count} canciones',
                coverFile: coverOfTracks(local, local.tracksIn(folder.uri)).file,
                onOpen: (rect) => onOpenSub(folder, rect),
              ),
          ],
          checked: marking ? local.isSelected : null,
          onToggle: local.toggleSelect,
          onLongPress: current ? local.toggleSelect : null,
          topBar: marking ? _SelectionBar(local: local, onMove: onMove) : null,
          canPop: !marking,
          onBlockedPop: local.clearSelection,
        );
      },
    );
  }
}

/// Las canciones enviadas: el anillo con ellas. Bajo la de enfrente van «Recibido», la marca de guardada, el corazón y el menú ⋯ (guardar,
/// cambiar imagen).
class _ReceivedAlbum extends StatelessWidget {
  const _ReceivedAlbum({
    required this.controller,
    required this.animation,
    required this.origin,
    this.local,
    this.player,
    this.favorites,
    this.onChangeCover,
  });

  final MusicController controller;
  final LocalMusicController? local;
  final Animation<double> animation;
  final Rect origin;
  final PlayerController? player;
  final FavoritesController? favorites;
  final void Function(Track track)? onChangeCover;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, ?local]),
      builder: (context, _) {
        final c = controller;
        Widget? notice;
        if (c.loading) {
          notice = const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
        } else if (c.error != null && c.tracks.isEmpty) {
          notice = _Message(c.error!, warn: true, onRetry: c.refresh);
        } else if (c.tracks.isEmpty) {
          notice = const _Message('Aún no hay canciones.\nLas que te manden desde la PC aparecen aquí.');
        }
        final cover = local == null
            ? (file: null, url: c.tracks.where((t) => t.coverUrl != null).firstOrNull?.coverUrl)
            : coverOfTracks(local!, c.tracks);
        return AlbumPage(
          title: 'Canciones enviadas',
          animation: animation,
          origin: origin,
          tracks: c.tracks,
          coverFile: cover.file,
          coverUrl: cover.url,
          player: player,
          notice: notice,
          banner: _Banner(controller: c),
          artOf: (track) => local?.artOf(track),
          cardKey: (track) => Key('track-${track.id}'),
          onPlay: (track, _) {
            final p = player;
            if (p != null) {
              unawaited(p.play(track, c.tracks));
            } else if (c.stateOf(track) == TrackState.pending || c.stateOf(track) == TrackState.failed) {
              unawaited(c.save(track));
            }
          },
          subtitleOf: (track) {
            if (c.stateOf(track) == TrackState.failed) {
              return (text: '${c.failureOf(track) ?? 'No se pudo guardar'} · toca ⋯ para reintentar', warn: true);
            }
            return (text: songLine(artist: splitArtistTitle(track.title).artist ?? track.playlist, duration: player?.durationOf(track)), warn: false);
          },
          actionsOf: (context, track, index) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ReceivedButton(track: track, controller: c),
              if (c.stateOf(track) == TrackState.saved)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.check_circle, key: const Key('saved'), size: 16, color: context.colors.accent),
                ),
              if (favorites != null) _HeartButton(track: track, number: index + 1, favorites: favorites!),
              SizedBox(
                width: 40,
                height: 40,
                child: _SentMenu(track: track, controller: c, local: local, onChangeCover: onChangeCover),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Mientras hay canciones marcadas: cuántas, marcar todas, cancelar y «Mover».
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.local, required this.onMove});

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

class _LocalTile extends StatelessWidget {
  const _LocalTile({
    required this.track,
    required this.number,
    required this.all,
    required this.local,
    required this.player,
    required this.favorites,
    this.onChangeCover,
    this.line,
  });

  final void Function(Track track)? onChangeCover;

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
          trailing: onChangeCover == null ? null : _LocalMenu(track: track, local: local, onChangeCover: onChangeCover!),
          onTap: p == null ? null : () => unawaited(p.play(track, all)),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {super.key, this.warn = false, this.onRetry, this.actionLabel, this.onAction});

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

/// La portada de un álbum: la de la primera de sus canciones que la tenga (la imagen incrustada o, en las enviadas, la de internet).
({String? file, String? url}) coverOfTracks(LocalMusicController local, List<Track>? songs) {
  for (final song in songs ?? const <Track>[]) {
    final file = local.artOf(song);
    if (file != null) return (file: file, url: null);
    if (song.coverUrl != null) return (file: null, url: song.coverUrl);
  }
  return (file: null, url: null);
}
