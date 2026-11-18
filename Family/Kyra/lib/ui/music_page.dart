import 'dart:async';

import 'package:flutter/material.dart';

import '../data/favorites_store.dart';
import '../models/track.dart';
import '../state/local_music_controller.dart';
import '../state/music_controller.dart';
import '../state/player_controller.dart';
import '../theme.dart';
import '../util/picker.dart';
import 'admin_music_dialogs.dart';
import 'album_view.dart';
import 'cover_picker.dart';
import 'folder_settings.dart';
import 'music_actions.dart';
import 'widgets/album_grid.dart';
import 'widgets/music_rows.dart';
import 'widgets/section_motion.dart';

/// La música: **solo los álbumes**, en una cuadrícula de **tres por fila** que ocupa la pantalla y se desplaza en vertical («Canciones enviadas»,
/// tu carpeta del teléfono y las carpetas de primer nivel que tenga). Tocar uno lo abre (`AlbumView`): un disco sale de la portada.
/// Sin título, sin favoritas y sin la tarjeta de lo que suena; solo dos iconos discretos arriba: el aleatorio entre todos los álbumes (si no
/// empieza solo, según Configuración) y volver a leer.
class MusicPage extends StatefulWidget {
  const MusicPage({super.key, required this.controller, this.player, this.local, this.favorites, this.openAlbum, this.pickCover = pickCoverImage});

  final MusicController controller;

  /// Un álbum que otra pantalla pide abrir (su id: `received`, `root` o la carpeta). Al leerlo se vacía.
  final ValueNotifier<String?>? openAlbum;

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

  /// Se están reuniendo las canciones de todos los álbumes para el aleatorio.
  bool _preparing = false;

  /// Ya se miró si había que empezar a sonar solo (una vez por visita).
  bool _autoChecked = false;

  @override
  void initState() {
    super.initState();
    _notices = widget.controller.notices.listen((text) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    });
    widget.openAlbum?.addListener(_openRequested);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openRequested());
  }

  @override
  void dispose() {
    widget.openAlbum?.removeListener(_openRequested);
    unawaited(_notices?.cancel());
    super.dispose();
  }

  /// Otra pantalla (el botón del álbum del reproductor de Inicio) pidió abrir un álbum: se lleva la cuadrícula hasta él y se abre.
  void _openRequested() {
    final request = widget.openAlbum;
    final id = request?.value;
    if (id == null || !mounted) return;
    request!.value = null;
    final albums = _albums(widget.local);
    final at = albums.indexWhere((a) => a.id == id);
    if (at < 0) return;
    _deck.jumpTo(at);
    _openAlbum(albums, at, hologram: false); // viene de otra sección, que ya se materializa con su holograma
  }

  /// **Aleatorio entre todo**: reúne las canciones de todos los álbumes (las enviadas y las de cada carpeta) y pone una cualquiera, con todas
  /// como cola y el aleatorio puesto: después sigue al azar saltando de un álbum a otro.
  Future<void> _shuffleAll() async {
    final player = widget.player;
    if (player == null || _preparing) return;
    setState(() => _preparing = true);
    try {
      final local = widget.local;
      final mine = local == null ? const <Track>[] : await local.allTracks();
      final all = [...widget.controller.tracks, ...mine];
      if (all.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aún no hay canciones para el aleatorio.')));
        return;
      }
      await player.playShuffled(all);
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  /// Si en Configuración se eligió que empiece a sonar sola y no suena nada, arranca el aleatorio (una vez, al abrir Música).
  void _autoShuffle() {
    if (_autoChecked || widget.controller.loading) return;
    _autoChecked = true;
    final player = widget.player;
    if (!widget.controller.settings.autoShuffle || player == null || player.current != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_shuffleAll());
    });
  }

  Future<void> _settings() => showFolderSettings(context, widget.controller);

  /// Los álbumes que se pueden abrir, en el orden de la cuadrícula.
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

  /// Abre el álbum `index` de `albums` (con el efecto de holograma).
  void _openAlbum(List<AlbumEntry> albums, int index, {bool hologram = true}) {
    final local = widget.local;
    final first = albums[index];
    _showAlbum(first);
    final route = albumOpenRoute<void>(
      hologram: hologram,
      builder: (_) => AlbumView(
        albums: albums,
        initial: index,
        music: widget.controller,
        local: local,
        player: widget.player,
        favorites: widget.favorites,
        pickCover: widget.pickCover,
        onShown: (entry) {
          _showAlbum(entry);
          final at = albums.indexWhere((a) => a.id == entry.id);
          if (at >= 0) _deck.jumpTo(at); // al volver, la cuadrícula está en el último álbum que se vio
        },
        onMove: local == null ? null : () => _moveSelected(local),
      ),
    );
    unawaited(Navigator.of(context).push(route));
    // cuando termina de volver (no cuando empieza), el controlador vuelve a la raíz
    unawaited(
      route.completed.then((_) {
        if (local != null) unawaited(local.goTo(0));
      }),
    );
  }

  /// Las acciones de música (las mismas que en KyraFamily), con los paneles de KyraAdmin.
  MusicActions _actions(LocalMusicController local) => MusicActions(local: local, player: widget.player, dialogs: AdminMusicDialogs(this));

  /// «Mover»: elige el álbum de destino para las canciones marcadas y las mueve de verdad.
  Future<void> _moveSelected(LocalMusicController local) => _actions(local).moveSelected();

  // ---------- el menú de consola de una tarjeta: cambiar nombre, borrar álbum, cambiar foto ----------

  /// Las opciones de la tarjeta de un álbum. Cambiar el nombre y borrar solo valen en las carpetas (no en «Canciones enviadas» ni en la carpeta
  /// elegida, que es la raíz); la foto, en todos.
  List<CardAction> _actionsFor(AlbumEntry e, LocalMusicController local) => [
    if (e.folder != null) CardAction(id: 'rename', label: 'Cambiar nombre', icon: Icons.edit_outlined, onTap: () => unawaited(_renameAlbum(e, local))),
    if (e.folder != null) CardAction(id: 'delete', label: 'Borrar álbum', icon: Icons.delete_outline_rounded, warn: true, onTap: () => unawaited(_deleteAlbum(e, local))),
    CardAction(
      id: 'cover',
      label: 'Cambiar foto',
      icon: Icons.image_outlined,
      onTap: () => unawaited(changeAlbumCover(context, local: local, albumId: e.id, title: e.title, pickCover: widget.pickCover)),
    ),
  ];

  Future<void> _renameAlbum(AlbumEntry e, LocalMusicController local) => _actions(local).renameAlbum(e);

  /// **Borrar álbum.** Vacío: se confirma y se borra. Con canciones, pasarlas a otro álbum o borrarlo todo (ver `MusicActions.deleteAlbum`).
  Future<void> _deleteAlbum(AlbumEntry e, LocalMusicController local) => _actions(local).deleteAlbum(e);

  Future<void> _newFolder(LocalMusicController local) => _actions(local).newAlbum();

  @override
  Widget build(BuildContext context) => _page(context);

  Widget _page(BuildContext context) {
    final local = widget.local;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.controller, ?local, ?widget.favorites]),
      builder: (context, _) {
        _autoShuffle();
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            bottom: false,
            child: local == null ? _receivedOnly() : _home(local),
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
        FlyIn(
          edge: MotionEdge.left,
          order: 1,
          child: MusicBanner(controller: c),
        ),
        Expanded(
          child: FlyIn(edge: MotionEdge.bottom, order: 3, child: list()),
        ),
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
          onTap: () => _openAlbum(albums, i),
          actions: _actionsFor(albums[i], local),
        ),
      if (!local.hasFolder) DeckCard(id: 'card-choose', title: 'Elegir carpeta', icon: Icons.folder_open_rounded, onTap: _settings),
      if (local.hasFolder && !broken) DeckCard(id: 'card-new-folder', title: 'Nuevo álbum', icon: Icons.add_rounded, onTap: () => _newFolder(local)),
    ];

    Future<void> refresh() async {
      await Future.wait([c.refresh(), local.refresh()]);
    }

    final colors = context.colors;
    final mono = TextStyle(fontFamily: monoFont, fontSize: 15, color: colors.dim);

    // solo los álbumes: la cuadrícula ocupa toda la pantalla; el aleatorio (si no empieza solo) y volver a leer, dos iconos discretos arriba a la derecha
    return Stack(
      key: const Key('music-scroll'),
      children: [
        Positioned.fill(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (broken)
                FlyIn(
                  edge: MotionEdge.left,
                  order: 1,
                  child: MusicMessage(
                    local.error!,
                    warn: true,
                    actionLabel: local.folderLost ? 'Elegir carpeta' : 'Reintentar',
                    onAction: local.folderLost ? _settings : local.refresh,
                  ),
                ),
              Expanded(
                child: FlyIn(
                  edge: MotionEdge.left,
                  order: 2,
                  child: AlbumGrid(cards: cards, controller: _deck),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: FlyIn(
            edge: MotionEdge.top,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.player != null && (!c.settings.autoShuffle || _preparing))
                  _preparing
                      ? Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('preparando…', key: const Key('music-shuffle-preparing'), style: mono))
                      : IconButton(key: const Key('music-shuffle-all'), tooltip: 'Aleatorio', onPressed: _shuffleAll, icon: Icon(Icons.shuffle_rounded, color: colors.accent)),
                IconButton(key: const Key('music-refresh'), tooltip: 'Volver a leer', onPressed: () => unawaited(refresh()), icon: Icon(Icons.refresh_rounded, color: colors.dim)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
