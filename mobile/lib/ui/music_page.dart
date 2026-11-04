import 'dart:async';

import 'package:flutter/material.dart';

import '../data/favorites_store.dart';
import '../data/music_store.dart';
import '../state/local_music_controller.dart';
import '../state/music_controller.dart';
import '../state/player_controller.dart';
import '../theme.dart';
import '../util/picker.dart';
import 'album_view.dart';
import 'folder_settings.dart';
import 'move_sheet.dart';
import 'player_page.dart';
import 'widgets/album_deck.dart';
import 'widgets/music_rows.dart';
import 'widgets/section_motion.dart';

/// La música. Al abrirla sale, en grande, un álbum de la **ruleta**: «Canciones enviadas» (las que te mandan desde la PC), tu carpeta del
/// teléfono y las carpetas de primer nivel que tenga. Tirando a un lado o al otro gira. Debajo, tus canciones favoritas (las del corazón), cada
/// una con la portada de su álbum. Tocar el álbum de enfrente lo abre (`AlbumView`): un disco sale de la tarjeta.
class MusicPage extends StatefulWidget {
  const MusicPage({super.key, required this.controller, this.player, this.local, this.favorites, this.pickCover = pickCoverImage});

  final MusicController controller;

  /// Los .mp3 de la carpeta elegida. Sin esto no hay álbumes del teléfono y solo se ven las enviadas.
  final LocalMusicController? local;

  /// Las canciones con el corazón puesto. Sin esto no salen los corazones.
  final FavoritesController? favorites;

  /// El reproductor. Sin él, tocar una canción la guarda (y no hay barra de reproducción).
  final PlayerController? player;

  /// Elige la imagen para un álbum: su ruta, o `null` si se cancela.
  final Future<String?> Function() pickCover;

  @override
  State<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends State<MusicPage> {
  StreamSubscription<String>? _notices;
  final DeckController _deck = DeckController();

  /// Dónde está en la pantalla la portada de cada tarjeta (de ahí sale el disco y ahí vuelve).
  final Map<String, GlobalKey> _cardKeys = {};

  /// La tarjeta cuya portada no se pinta mientras el álbum está abierto (la está pintando el disco al volver).
  String? _hidden;

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

  GlobalKey _keyFor(String id) => _cardKeys.putIfAbsent(id, GlobalKey.new);

  Future<void> _settings() => showFolderSettings(context, widget.controller);

  /// Los álbumes que se pueden abrir, en el orden del mazo.
  List<AlbumEntry> _albums(LocalMusicController? local) {
    final broken = local != null && local.atRoot && local.error != null;
    return [
      const AlbumEntry(id: 'received', title: 'Canciones enviadas', icon: Icons.headphones_rounded),
      if (local != null && local.hasFolder && !broken) ...[
        AlbumEntry(id: 'root', title: local.folderName, icon: Icons.smartphone_rounded),
        for (final folder in local.rootFolders) AlbumEntry(id: folder.uri, title: folder.name, icon: Icons.album_rounded, folder: folder),
      ],
    ];
  }

  /// La clave con la que se encuentra la tarjeta de un álbum (`card-received`, `card-root`, `card-folder-Rock`…).
  static String _cardId(AlbumEntry e) => switch (e.id) {
        'received' => 'card-received',
        'root' => 'card-root',
        _ => 'card-folder-${e.title}',
      };

  Rect _originOf(String id) {
    final context = _cardKeys[id]?.currentContext;
    return context == null ? Rect.zero : rectOf(context);
  }

  /// Pone al controlador en la carpeta del álbum que se ve (la raíz o una de sus carpetas), para leerla y poder marcar sus canciones.
  void _showAlbum(AlbumEntry entry) {
    final local = widget.local;
    if (local == null || entry.received) return;
    final folder = entry.folder;
    final already = folder == null ? local.atRoot : (local.path.length == 1 && local.currentUri == folder.uri);
    if (already) return;
    if (!local.atRoot) unawaited(local.goTo(0));
    if (folder != null) unawaited(local.open(folder));
  }

  /// Abre el álbum `index` de `albums`: el disco sale de la tarjeta (`origin`). Se puede pasar a los demás deslizando.
  void _openAlbum(List<AlbumEntry> albums, int index, Rect origin) {
    final local = widget.local;
    final first = albums[index];
    _showAlbum(first);
    setState(() => _hidden = first.id);
    final route = albumOpenRoute<void>(
      builder: (_, animation) => AlbumView(
        albums: albums,
        initial: index,
        animation: animation,
        originOf: (id) {
          final rect = _originOf(id);
          return rect.isEmpty && id == first.id ? origin : rect;
        },
        music: widget.controller,
        local: local,
        player: widget.player,
        favorites: widget.favorites,
        pickCover: widget.pickCover,
        onShown: (entry) {
          _showAlbum(entry);
          final at = albums.indexWhere((a) => a.id == entry.id);
          if (at >= 0) _deck.jumpTo(at); // al volver, la ruleta está en el último álbum que se vio
          if (mounted) setState(() => _hidden = entry.id);
        },
        onMove: local == null ? null : () => _moveSelected(local),
      ),
    );
    unawaited(Navigator.of(context).push(route));
    // cuando termina de volver (no cuando empieza), la tarjeta vuelve a pintarse y el controlador a la raíz
    unawaited(route.completed.then((_) {
      if (mounted) setState(() => _hidden = null);
      if (local != null) unawaited(local.goTo(0));
    }));
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
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Expanded(child: local == null ? _receivedOnly() : _home(local)),
                if (widget.player != null) FlyIn(edge: MotionEdge.bottom, order: 2, child: MiniPlayer(player: widget.player!)),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Sin carpeta del teléfono posible: solo la lista de las canciones enviadas.
  Widget _receivedOnly() {
    final c = widget.controller;
    Widget list() {
      if (c.loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
      if (c.error != null && c.tracks.isEmpty) return MusicMessage(c.error!, warn: true, onRetry: c.refresh);
      if (c.tracks.isEmpty) return const MusicMessage('Aún no hay canciones.\nLas que te manden desde la PC aparecen aquí.');
      return ListView.builder(
        key: const Key('track-list'),
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: c.tracks.length,
        itemBuilder: (context, i) => SentTile(track: c.tracks[i], number: i + 1, controller: c, player: widget.player, favorites: widget.favorites),
      );
    }

    return Column(
      children: [
        FlyIn(edge: MotionEdge.left, order: 1, child: MusicBanner(controller: c)),
        Expanded(child: FlyIn(edge: MotionEdge.bottom, order: 2, child: list())),
      ],
    );
  }

  Widget _home(LocalMusicController local) {
    final c = widget.controller;
    final albums = _albums(local);
    final broken = local.atRoot && local.error != null;

    ({String? file, String? url}) coverOf(AlbumEntry e) {
      final file = local.albumArt(e.id);
      if (file != null) return (file: file, url: null);
      if (e.received) return (file: null, url: c.tracks.where((t) => t.coverUrl != null).firstOrNull?.coverUrl);
      return (file: null, url: null);
    }

    final cards = <DeckCard>[
      for (var i = 0; i < albums.length; i++)
        DeckCard(
          id: _cardId(albums[i]),
          title: albums[i].title,
          icon: albums[i].icon,
          coverFile: coverOf(albums[i]).file,
          coverUrl: coverOf(albums[i]).url,
          onTap: (origin) => _openAlbum(albums, i, origin),
        ),
      if (!local.hasFolder) DeckCard(id: 'card-choose', title: 'Elegir carpeta', icon: Icons.folder_open_rounded, onTap: (_) => _settings()),
      if (local.hasFolder && !broken) DeckCard(id: 'card-new-folder', title: 'Nuevo álbum', icon: Icons.add_rounded, onTap: (_) => _newFolder(local)),
    ];
    // la clave de cada portada se guarda por el id del álbum (`received`, `root`, la dirección de la carpeta)
    final keys = {for (final album in albums) _cardId(album): _keyFor(album.id)};
    final hiddenCard = albums.where((album) => album.id == _hidden).map(_cardId).firstOrNull;

    Future<void> refresh() async {
      await Future.wait([c.refresh(), local.refresh()]);
    }

    final f = widget.favorites;
    final sent = [
      for (final t in c.tracks)
        if (f != null && f.isFavorite(t.durationKey)) t,
    ];
    final mine = [
      for (final t in local.knownTracks())
        if (f != null && f.isFavorite(t.durationKey)) t,
    ];
    final all = [...sent, ...mine];
    final colors = context.colors;

    return RefreshIndicator(
      onRefresh: refresh,
      child: CustomScrollView(
        key: const Key('music-scroll'),
        // al cambiar de sección los bloques llegan hasta el borde de la pantalla, sin cortarse en el de la lista
        clipBehavior: SectionMotion.movingOf(context) ? Clip.none : Clip.hardEdge,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (broken)
            SliverToBoxAdapter(
              child: FlyIn(
                edge: MotionEdge.left,
                order: 1,
                child: MusicMessage(
                  local.error!,
                  warn: true,
                  actionLabel: local.folderLost ? 'Elegir carpeta' : 'Reintentar',
                  onAction: local.folderLost ? _settings : local.refresh,
                ),
              ),
            ),
          SliverToBoxAdapter(child: FlyIn(edge: MotionEdge.left, order: 1, child: AlbumDeck(cards: cards, controller: _deck, hiddenId: hiddenCard, cardKeys: keys))),
          SliverToBoxAdapter(
            child: FlyIn(
              edge: MotionEdge.bottom,
              order: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
                child: Text('Favoritas', key: const Key('favorites-title'), style: TextStyle(color: colors.ink, fontSize: 20, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
          if (all.isEmpty)
            const SliverToBoxAdapter(
              child: FlyIn(
                edge: MotionEdge.bottom,
                order: 2,
                child: MusicMessage('Aún no tienes favoritas.\nToca el corazón de una canción y aparecerá aquí.', key: Key('favorites-empty')),
              ),
            )
          else
            SliverPadding(
              key: const Key('favorites-list'),
              padding: const EdgeInsets.only(bottom: 24),
              sliver: SliverList.builder(
                itemCount: all.length,
                itemBuilder: (context, i) {
                  final t = all[i];
                  // las filas se mueven juntas, como un solo bloque
                  return FlyIn(
                    edge: MotionEdge.bottom,
                    order: 2,
                    child: !t.isLocal
                        ? SentTile(track: t, number: i + 1, controller: c, player: widget.player, favorites: f, local: local, queue: all)
                        : LocalTile(track: t, number: i + 1, all: all, local: local, player: widget.player, favorites: f, line: 'Favorita'),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
