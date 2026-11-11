import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/audio_engine.dart';
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
import 'widgets/album_art.dart';
import 'widgets/album_stack.dart';
import 'widgets/cut_border.dart';
import 'widgets/app_backdrop.dart';
import 'widgets/cover_backdrop.dart';
import 'widgets/disc_player.dart';
import 'widgets/mini_player.dart';
import 'widgets/music_rows.dart';
import 'widgets/song_arc_list.dart';
import 'widgets/vinyl_disc.dart';
import 'widgets/pixel_glyph.dart';
import 'widgets/lcd_box.dart';
import 'widgets/hack_text.dart';
import 'widgets/focus_space.dart';

/// Un álbum que se puede abrir: las canciones enviadas (`received`), la carpeta elegida del teléfono (`root`) o una de sus carpetas.
class AlbumEntry {
  const AlbumEntry({required this.id, required this.title, required this.icon, this.folder});

  /// `received`, `root` o la dirección de la carpeta.
  final String id;
  final String title;
  final IconData icon;
  final LocalFolder? folder;

  bool get received => id == 'received';

  /// La carpeta de la que salen sus canciones (`null` = la raíz; las enviadas no tienen carpeta).
  String? get dirUri => folder?.uri;
}

/// La ruta del álbum: no pinta ninguna transición por su cuenta. La pantalla recibe la `animation` (0 → 1 al abrir, de vuelta al
/// cerrar) y con ella hace salir el disco de la tarjeta, deslizar la tarjeta y aparecer el fondo. Mientras se anima se sigue viendo la música
/// debajo.
PageRoute<T> albumOpenRoute<T>({required Widget Function(BuildContext context, Animation<double> animation) builder}) => PageRouteBuilder<T>(
  opaque: true, // mientras dura la animación se ve la música debajo; al terminar ya no hace falta
  transitionDuration: const Duration(milliseconds: 440),
  reverseTransitionDuration: const Duration(milliseconds: 340),
  pageBuilder: (context, animation, secondaryAnimation) => builder(context, animation),
  transitionsBuilder: (context, animation, secondaryAnimation, child) => child,
);

/// La vista de un álbum. De fondo, **la portada** nítida, con líneas de barrido y oscurecida; en el centro, algo más arriba que el medio,
/// el **disco de vinilo** (`DiscPlayer`): un toque reproduce o pausa y girarlo mueve la canción. Debajo, sin ningún fondo, el nombre de la
/// canción y, si suena una de este álbum, aleatorio, anterior, siguiente y repetir; si suena una de otro, abajo sale su tarjeta, que lleva a su disco.
///
/// **Mantener presionado el disco** abre la pila de álbumes para pasar a otro **sin parar la canción que suena**; tocar una portada la elige.
/// **Doble toque en cualquier parte menos en el disco** abre la lista de canciones (`SongArcList`): el disco encoge hasta la fila del centro y
/// las demás llegan por la curva. Otro doble toque o «atrás» la cierran. No hay deslizamientos de lado ni de arriba abajo.
///
/// Un álbum solo enseña sus canciones: lo que tenga en subcarpetas no se muestra.
///
/// Al abrirse, el disco sale de la tarjeta del álbum, como de su funda, y se coloca en el centro mientras la tarjeta se va hacia la izquierda;
/// al cerrarse hace el camino de vuelta.
class AlbumView extends StatefulWidget {
  const AlbumView({
    super.key,
    required this.albums,
    required this.initial,
    required this.animation,
    required this.originOf,
    required this.music,
    this.local,
    this.player,
    this.favorites,
    this.pickCover = pickCoverImage,
    this.onShown,
    this.onMove,
  });

  final List<AlbumEntry> albums;

  /// El álbum con el que se abre.
  final int initial;

  /// La animación de la ruta (0 → 1).
  final Animation<double> animation;

  /// Dónde está en la pantalla la tarjeta del álbum `id` (de donde sale el disco y adonde vuelve).
  final Rect Function(String id) originOf;

  final MusicController music;
  final LocalMusicController? local;
  final PlayerController? player;
  final FavoritesController? favorites;

  /// Elige la imagen para el álbum: su ruta, o `null` si se cancela.
  final Future<String?> Function() pickCover;

  /// Se llama cuando se pasa a otro álbum (y al abrir).
  final ValueChanged<AlbumEntry>? onShown;

  /// «Mover» las canciones marcadas.
  final VoidCallback? onMove;

  /// Lo que tarda en abrirse y cerrarse la lista.
  static const listTime = Duration(milliseconds: 460);

  /// El disco con su línea del avance: el rectángulo que ocupa, en una pantalla de `size`, un poco por encima del centro.
  static Rect discRect(Size size) {
    final d = math.min(size.width * 0.84, size.height * 0.58).clamp(120.0, 520.0);
    return Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.42), width: d, height: d);
  }

  @override
  State<AlbumView> createState() => _AlbumViewState();
}

class _AlbumViewState extends State<AlbumView> with TickerProviderStateMixin {
  late final AnimationController _list = AnimationController(vsync: this, duration: AlbumView.listTime)..addStatusListener(_onListStatus);
  late final CurvedAnimation _listFade = CurvedAnimation(
    parent: _list,
    curve: const Interval(0.25, 0.8, curve: Curves.easeOutCubic),
  );
  final GlobalKey _stage = GlobalKey();
  late int _shown = widget.initial;
  bool _listOpen = false;

  /// La canción que se enseña de cada álbum cuando no suena ninguna de él (la que quedó en el centro de la lista).
  final Map<String, int> _picked = {};

  /// Se está eligiendo otro álbum (la pila de portadas por encima del disco).
  bool _picking = false;
  final DeckController _pickDeck = DeckController();

  /// La canción que sonaba la última vez que se miró: si pasa a sonar una de otro álbum (el aleatorio entre todo), se pasa solo a ese álbum.
  String? _lastCurrent;

  late final CurvedAnimation _backgroundIn = CurvedAnimation(
    parent: widget.animation,
    curve: const Interval(0.15, 0.9, curve: Curves.easeOutCubic),
  );
  late final CurvedAnimation _barIn = CurvedAnimation(
    parent: widget.animation,
    curve: const Interval(0.55, 1.0, curve: Curves.easeOutCubic),
  );

  AlbumEntry get _entry => widget.albums[_shown];

  @override
  void initState() {
    super.initState();
    _lastCurrent = widget.player?.current?.id;
    widget.player?.addListener(_onPlayer);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onShown?.call(_entry);
    });
  }

  /// Si empieza a sonar una canción de otro álbum (el aleatorio salta de uno a otro), la ruleta gira sola hasta su disco.
  void _onPlayer() {
    final current = widget.player?.current;
    if (current == null || current.id == _lastCurrent) return;
    _lastCurrent = current.id;
    if (!mounted || _listOpen || _marking(_entry) || _isActive(_entry)) return;
    _goToCurrent();
  }

  @override
  void dispose() {
    widget.player?.removeListener(_onPlayer);
    _backgroundIn.dispose();
    _barIn.dispose();
    _listFade.dispose();
    _list.dispose();
    super.dispose();
  }

  void _onListStatus(AnimationStatus status) {
    // cerrada del todo, la lista deja de construirse
    if (status == AnimationStatus.dismissed && mounted) setState(() {});
  }

  void _openList() {
    final songs = _songs(_entry);
    if (songs == null || songs.isEmpty) return;
    setState(() => _listOpen = true);
    unawaited(_list.forward());
  }

  void _closeList() {
    setState(() => _listOpen = false);
    unawaited(_list.reverse());
  }

  // ---------- lo que hay en cada álbum ----------

  List<Track>? _songs(AlbumEntry e) => e.received ? widget.music.tracks : widget.local?.tracksIn(e.dirUri);

  /// La portada del álbum: la que se le puso o la de su primera canción; en las enviadas, la de internet de la primera que la traiga.
  ({String? file, String? url}) _coverOf(AlbumEntry e) {
    final file = widget.local?.albumArt(e.id);
    if (file != null) return (file: file, url: null);
    if (e.received) return (file: null, url: widget.music.tracks.where((t) => t.coverUrl != null).firstOrNull?.coverUrl);
    return (file: null, url: null);
  }

  /// ¿Es el álbum que el controlador tiene abierto? Solo en ese se marcan canciones y se ven sus errores.
  bool _isOpenIn(AlbumEntry e) => !e.received && widget.local != null && widget.local!.currentUri == e.dirUri;

  /// El número de la canción que se enseña: la que suena si es de este álbum; si no, la que se tocó en la lista, o la primera.
  int _focus(AlbumEntry e, List<Track> songs) {
    final current = widget.player?.current;
    if (current != null) {
      final i = songs.indexWhere((t) => t.id == current.id);
      if (i >= 0) return i;
    }
    return (_picked[e.id] ?? 0).clamp(0, songs.length - 1);
  }

  Widget? _notice(BuildContext context, AlbumEntry e, List<Track>? songs) {
    final music = widget.music;
    final local = widget.local;
    if (e.received) {
      if (music.loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
      if (music.error != null && music.tracks.isEmpty) return MusicMessage(music.error!, warn: true, onRetry: music.refresh);
      if (music.tracks.isEmpty) return const MusicMessage('Aún no hay canciones.\nLas que te manden desde la PC aparecen aquí.');
      return null;
    }
    if (local == null || !local.hasFolder) {
      return MusicMessage(
        'Elige una carpeta y aquí verás los .mp3 que tengas en ella.\nTambién se guardarán ahí las canciones que te manden.',
        actionLabel: 'Elegir carpeta',
        onAction: () => showFolderSettings(context, music),
      );
    }
    if (local.error != null && _isOpenIn(e)) {
      return MusicMessage(
        local.error!,
        warn: true,
        actionLabel: local.folderLost ? 'Elegir carpeta' : 'Reintentar',
        onAction: local.folderLost ? () => showFolderSettings(context, music) : local.refresh,
      );
    }
    if (songs == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    if (songs.isEmpty) return MusicMessage('No hay archivos .mp3 en «${e.title}».', actionLabel: 'Actualizar', onAction: local.refresh);
    return null;
  }

  // ---------- acciones ----------

  /// Pasa al disco de la canción que suena.
  void _goToCurrent() {
    final track = widget.player?.current;
    if (track == null) return;
    final id = widget.local?.albumIdOf(track) ?? 'received';
    final i = widget.albums.indexWhere((album) => album.id == id);
    if (i >= 0) _show(i);
  }

  /// Muestra el álbum `i` (sin tocar lo que suena).
  void _show(int i) {
    if (i == _shown) return;
    setState(() => _shown = i);
    widget.onShown?.call(widget.albums[i]);
  }

  /// Mantener presionado el disco: abre la pila para elegir otro álbum.
  void _openPicker() {
    if (_picking || _listOpen || widget.albums.length < 2) return;
    unawaited(HapticFeedback.mediumImpact().catchError((Object _) {}));
    setState(() => _picking = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickDeck.jumpTo(_shown));
  }

  void _closePicker() => setState(() => _picking = false);

  void _pick(int i) {
    setState(() => _picking = false);
    _show(i);
  }

  /// ¿La canción que suena es de este álbum?
  bool _isActive(AlbumEntry e) {
    final current = widget.player?.current;
    if (current == null) return false;
    return _songs(e)?.any((t) => t.id == current.id) ?? false;
  }

  /// Tocar el disco: reproduce (o pausa) la canción que se enseña.
  void _toggle(AlbumEntry e) {
    final songs = _songs(e);
    if (songs == null || songs.isEmpty) return;
    _playOrPause(e, songs[_focus(e, songs)], songs);
  }

  void _playOrPause(AlbumEntry e, Track track, List<Track> songs) {
    final player = widget.player;
    if (player == null) {
      if (e.received) unawaited(widget.music.save(track));
      return;
    }
    if (player.current?.id == track.id) {
      unawaited(player.toggle());
    } else {
      unawaited(player.play(track, songs));
    }
  }

  /// «Cambiar portada» dentro del álbum: elegirle una imagen (solo en este teléfono) o quitársela.
  Future<void> _changeCover(AlbumEntry e) async {
    final local = widget.local;
    if (local == null) return;
    final has = local.albumCoverOf(e.id) != null;
    final choice = await showFocusPanel<String>(context, builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                e.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
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
    if (choice == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (choice == 'clear') {
        await local.clearAlbumCover(e.id);
        return;
      }
      final path = await widget.pickCover();
      if (path == null || !mounted) return;
      await local.setAlbumCover(e.id, path);
    } on TrackSaveException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  // ---------- pantalla ----------

  bool _marking(AlbumEntry e) {
    final local = widget.local;
    return local != null && local.selecting && _isOpenIn(e);
  }

  @override
  Widget build(BuildContext context) {
    final local = widget.local;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.music, ?local, ?widget.player, ?widget.favorites]),
      builder: (context, _) => PopScope(
        // con canciones marcadas, «atrás» primero quita la marca; con la lista abierta, la cierra
        canPop: !_marking(_entry) && !_listOpen && !_picking,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_picking) {
            _closePicker();
          } else if (_marking(_entry)) {
            local?.clearSelection();
          } else if (_listOpen) {
            _closeList();
          }
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: LayoutBuilder(builder: (context, box) => _stageFor(context, box.biggest)),
        ),
      ),
    );
  }

  Widget _stageFor(BuildContext context, Size size) {
    final disc = AlbumView.discRect(size);
    final local = widget.local;
    final marking = _marking(_entry);
    return Stack(
      key: _stage,
      fit: StackFit.expand,
      children: [
        // el fondo: un color mate sacado de la portada (sin la portada borrosa); sin portada, el de la pantalla. Aparece poco a poco
        FadeTransition(
          opacity: _backgroundIn,
          child: KeyedSubtree(key: const Key('album-backdrop'), child: _backdrop(_coverOf(_entry))),
        ),
        // con la lista abierta, lo de debajo se tapa con una trama de tinta, y del todo al acabar de abrirse
        AnimatedBuilder(
          animation: _list,
          builder: (context, _) => KeyedSubtree(
            key: const Key('album-dark'),
            child: _list.value < 0.05
                ? const SizedBox.expand()
                : _list.value < 0.6
                ? const LcdDither(density: 0.25)
                : ColoredBox(color: context.colors.background),
          ),
        ),
        // el doble toque: va debajo del disco, no por encima. Así el disco tiene sus gestos para él y un toque en él no espera a ver si llega un segundo
        GestureDetector(
          key: const Key('album-background'),
          behavior: HitTestBehavior.opaque,
          onDoubleTap: _openList,
          child: const SizedBox.expand(),
        ),
        // el disco del álbum que se ve
        AnimatedBuilder(animation: Listenable.merge([widget.animation, _list]), builder: (context, _) => _discs(size, disc)),
        _caption(context, disc),
        // la tarjeta de lo que suena, si es de otro álbum
        if (widget.player != null && widget.player!.current != null && !_isActive(_entry) && !_listOpen && _list.isDismissed)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedBuilder(
              animation: _barIn,
              child: MiniPlayer(player: widget.player!, onOpen: _goToCurrent),
              builder: (context, child) => Transform.translate(offset: Offset(0, 120 * (1 - _barIn.value)), child: child),
            ),
          ),
        if (_listOpen || !_list.isDismissed) Positioned.fill(child: _listLayer(context)),
        if (_picking) Positioned.fill(child: _picker(context)),
        // la barra de arriba
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: FadeTransition(
            opacity: _barIn,
            child: SafeArea(
              bottom: false,
              child: marking
                  ? SelectionBar(local: local!, onMove: widget.onMove ?? () {})
                  : Row(
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: BackButton(key: Key('album-back')),
                        ),
                        Expanded(
                          child: IgnorePointer(
                            child: HackText(
                              _entry.title,
                              textKey: const Key('album-title'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        if (local != null)
                          IconButton(
                            key: const Key('album-cover'),
                            tooltip: 'Cambiar portada',
                            icon: const LcdIcon(Icons.image_outlined),
                            onPressed: () => unawaited(_changeCover(_entry)),
                          ),
                        const SizedBox(width: 4),
                      ],
                    ),
            ),
          ),
        ),
        // la transición: el disco sale de la tarjeta y la tarjeta se va a la izquierda
        AnimatedBuilder(
          animation: widget.animation,
          builder: (context, _) => widget.animation.isCompleted ? const SizedBox.shrink() : _openingLayers(context, size, disc),
        ),
      ],
    );
  }

  /// El disco del álbum que se ve. Con la lista abriéndose, encoge hasta la fila del centro.
  Widget _discs(Size size, Rect disc) {
    final t = Curves.easeInOutCubic.transform(_list.value);
    final vinyl = disc.width - 2 * DiscPlayer.inset;
    final scale = 1 + (SongArcList.thumb / vinyl - 1) * t;
    final move = (Offset(SongArcList.edge + SongArcList.thumb / 2, size.height / 2) - disc.center) * t;
    final fade = 1 - ((t - 0.75) / 0.25).clamp(0.0, 1.0);
    return Offstage(
      // mientras el disco viaja de la tarjeta al centro (o al revés) lo pinta la transición
      offstage: !widget.animation.isCompleted || fade == 0,
      child: IgnorePointer(
        ignoring: t > 0,
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Positioned(
              key: ValueKey('disc-${_entry.id}'),
              left: disc.left,
              top: disc.top,
              width: disc.width,
              height: disc.height,
              child: Transform.translate(
                offset: move,
                child: Transform.scale(scale: scale, child: Opacity(opacity: fade, child: _disc(_entry, disc))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _disc(AlbumEntry e, Rect disc) {
    final art = _coverOf(e);
    return DiscPlayer(
      id: e.id,
      file: art.file,
      url: art.url,
      icon: e.icon,
      size: disc.width,
      active: _isActive(e),
      player: widget.player,
      touchKey: Key('album-disc-${e.id}'),
      onTap: () => _toggle(e),
      onLongPress: _openPicker,
    );
  }

  /// Bajo el disco, sin fondo: el nombre y el artista de la canción, o el aviso si no hay canciones que enseñar.
  Widget _caption(BuildContext context, Rect disc) {
    final e = _entry;
    final songs = _songs(e);
    final notice = _notice(context, e, songs);
    final list = songs ?? const <Track>[];
    final track = list.isEmpty ? null : list[_focus(e, list)];
    final named = track == null ? null : splitArtistTitle(track.title);
    final player = widget.player;
    final Widget body;
    if (notice != null) {
      body = SingleChildScrollView(child: notice);
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IgnorePointer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                HackText(
                  named?.title ?? '',
                  order: 1,
                  textKey: const Key('album-song-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: lcdLabel(size: 20, color: context.colors.ink),
                ),
                if (track != null)
                  HackText(
                    songLine(
                      artist: named!.artist ?? (e.received ? track.playlist : e.title),
                      duration: widget.local?.durationOf(track) ?? widget.player?.durationOf(track),
                    ),
                    textKey: const Key('album-song-subtitle'),
                    order: 2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.colors.ink, fontSize: 15),
                  ),
              ],
            ),
          ),
          if (player != null && _isActive(e)) ...[
            if (player.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                // un error del sistema: en vídeo inverso, minúsculas y cursiva
                child: Container(
                  color: context.colors.ink,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    player.error!.toLowerCase(),
                    key: const Key('player-error'),
                    textAlign: TextAlign.center,
                    style: lcdStatus(color: context.colors.background),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _PlayerControls(player: player),
            ),
          ],
        ],
      );
    }
    return Positioned(
      left: 24,
      right: 24,
      top: disc.bottom + 8,
      bottom: 0,
      child: FadeTransition(
        opacity: _barIn,
        child: AnimatedBuilder(
          animation: _list,
          child: Align(alignment: Alignment.topCenter, child: body),
          builder: (context, child) => _list.isDismissed
              ? child!
              : Opacity(
                  opacity: (1 - _list.value * 2.5).clamp(0.0, 1.0),
                  child: IgnorePointer(child: child),
                ),
        ),
      ),
    );
  }

  /// El fondo del disco: la portada del álbum a pantalla completa, nítida, con líneas y oscurecida (`CoverBackdrop`); sin portada, el fondo de la
  /// pantalla.
  Widget _backdrop(({String? file, String? url}) cover) =>
      cover.file == null && cover.url == null
          ? const BackdropLayers()
          : Stack(fit: StackFit.expand, children: [CoverBackdrop(file: cover.file, url: cover.url), const HackerScreen()]);

  /// La pila de álbumes para elegir otro: sobre un velo oscuro, las portadas en cascada; tocar la del centro la elige, tocar otra la trae al centro.
  Widget _picker(BuildContext context) {
    final cards = [
      for (var i = 0; i < widget.albums.length; i++)
        DeckCard(
          id: 'pick-${widget.albums[i].id}',
          title: widget.albums[i].title,
          icon: widget.albums[i].icon,
          coverFile: _coverOf(widget.albums[i]).file,
          coverUrl: _coverOf(widget.albums[i]).url,
          onTap: (_) => _pick(i),
        ),
    ];
    return GestureDetector(
      key: const Key('album-picker'),
      behavior: HitTestBehavior.opaque,
      onTap: _closePicker,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.86),
        child: SafeArea(child: AlbumStack(cards: cards, controller: _pickDeck)),
      ),
    );
  }

  /// La lista de canciones, por encima del disco mientras está abierta.
  Widget _listLayer(BuildContext context) {
    final e = _entry;
    final local = widget.local;
    final player = widget.player;
    final favorites = widget.favorites;
    final songs = _songs(e) ?? const <Track>[];
    if (songs.isEmpty) return const SizedBox.shrink();
    final cover = _coverOf(e);
    final marking = _marking(e);
    final padTop = MediaQuery.paddingOf(context).top;
    return IgnorePointer(
      ignoring: !_listOpen,
      child: FadeTransition(
        opacity: _listFade,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SongArcList(
              key: ValueKey('album-list-${e.id}'),
              tracks: songs,
              focus: _focus(e, songs),
              opening: _list,
              file: cover.file,
              url: cover.url,
              icon: e.icon,
              keyOf: (t) => Key(e.received ? 'track-${t.id}' : 'local-${t.id}'),
              lineOf: (t) {
                final named = splitArtistTitle(t.title);
                final length = local?.durationOf(t) ?? player?.durationOf(t);
                if (e.received) {
                  if (widget.music.stateOf(t) == TrackState.failed) return '${widget.music.failureOf(t) ?? 'No se pudo guardar'} · toca ⋯ para reintentar';
                  return songLine(artist: named.artist ?? t.playlist, duration: length);
                }
                return songLine(artist: named.artist ?? e.title, duration: length);
              },
              warnOf: e.received ? (t) => widget.music.stateOf(t) == TrackState.failed : null,
              savedOf: e.received ? (t) => widget.music.stateOf(t) == TrackState.saved : null,
              isCurrent: (t) => player?.current?.id == t.id,
              isPlaying: (t) => player?.current?.id == t.id && player!.playing,
              onPlay: (t) => _playOrPause(e, t, songs),
              onFocus: (i) => setState(() => _picked[e.id] = i),
              onDoubleTap: _closeList,
              selectedOf: marking ? (t) => local!.isSelected(t) : null,
              onHold: !e.received && _isOpenIn(e) ? local?.toggleSelect : null,
              onToggle: local?.toggleSelect,
              actionsOf: favorites == null
                  ? null
                  : (t) {
                      final favorite = favorites.isFavorite(t.durationKey);
                      return [
                        IconButton(
                          key: Key('fav-${songs.indexOf(t) + 1}'),
                          tooltip: favorite ? 'Quitar de favoritas' : 'Marcar como favorita',
                          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                          padding: EdgeInsets.zero,
                          icon: LcdIcon(
                            favorite ? Icons.favorite : Icons.favorite_border,
                            color: context.colors.ink,
                            size: 22,
                          ),
                          onPressed: () => unawaited(favorites.toggle(t.durationKey)),
                        ),
                        const SizedBox(width: 4),
                      ];
                    },
              extraOf: !e.received
                  ? null
                  : (t) => [
                      ReceivedButton(track: t, controller: widget.music),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: SentMenu(track: t, controller: widget.music),
                      ),
                    ],
            ),
            if (e.received)
              Positioned(
                top: padTop + 56,
                left: 0,
                right: 0,
                child: MusicBanner(controller: widget.music),
              ),
          ],
        ),
      ),
    );
  }

  /// El disco que viaja y la tarjeta que se va (o que vuelve), según el avance de la ruta.
  Widget _openingLayers(BuildContext context, Size size, Rect disc) {
    final t = widget.animation.value.clamp(0.0, 1.0);
    final cover = _coverOf(_entry);
    final box = _stage.currentContext?.findRenderObject();
    final shift = box is RenderBox && box.attached ? box.localToGlobal(Offset.zero) : Offset.zero;
    var origin = widget.originOf(_entry.id).shift(-shift);
    if (origin.isEmpty) origin = Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.3), width: size.width * 0.6, height: size.width * 0.6);
    final vinyl = disc.deflate(DiscPlayer.inset);
    final rect = Rect.lerp(origin, vinyl, Curves.easeOutCubic.transform(t))!;
    // la tarjeta se va a la izquierda hasta salir de la pantalla
    final away = Curves.easeInOutCubic.transform((t / 0.85).clamp(0.0, 1.0));
    final cardLeft = origin.left - (origin.right + 8) * away;
    return IgnorePointer(
      child: Stack(
        key: const Key('album-opening'),
        children: [
          // el disco (debajo de la tarjeta al principio: sale de ella, como de su funda)
          Positioned.fromRect(
            rect: rect,
            child: FittedBox(
              key: const Key('album-opening-disc'),
              fit: BoxFit.contain,
              child: VinylDisc(id: _entry.id, file: cover.file, url: cover.url, icon: _entry.icon, size: vinyl.width),
            ),
          ),
          Positioned(
            left: cardLeft,
            top: origin.top,
            width: origin.width,
            height: origin.height,
            child: AlbumArt(key: const Key('album-opening-card'), file: cover.file, url: cover.url, icon: _entry.icon, size: origin.width, radius: 18),
          ),
        ],
      ),
    );
  }
}

/// Bajo el disco: aleatorio, anterior, siguiente y repetir.
class _PlayerControls extends StatelessWidget {
  const _PlayerControls({required this.player});

  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final idle = c.ink;
    // lo encendido (aleatorio, repetir), con el acento
    ButtonStyle on(bool lit) => IconButton.styleFrom(backgroundColor: lit ? c.accent : null, shape: const CutBorder(cut: 8));
    return Row(
      key: const Key('disc-controls'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          key: const Key('player-shuffle'),
          tooltip: player.shuffle ? 'Aleatorio: activado' : 'Aleatorio: apagado',
          color: player.shuffle ? c.onAccent : idle,
          style: on(player.shuffle),
          iconSize: 22,
          icon: const LcdIcon(Icons.shuffle_rounded),
          onPressed: player.toggleShuffle,
        ),
        const SizedBox(width: 10),
        IconButton(
          key: const Key('disc-previous'),
          tooltip: 'Anterior',
          color: idle,
          iconSize: 30,
          icon: const LcdIcon(Icons.skip_previous_rounded),
          onPressed: player.previous,
        ),
        const SizedBox(width: 10),
        IconButton(
          key: const Key('disc-next'),
          tooltip: 'Siguiente',
          color: idle,
          iconSize: 30,
          icon: const LcdIcon(Icons.skip_next_rounded),
          onPressed: player.next,
        ),
        const SizedBox(width: 10),
        IconButton(
          key: const Key('player-repeat'),
          tooltip: switch (player.repeat) {
            RepeatKind.off => 'Repetir: apagado',
            RepeatKind.all => 'Repetir toda la lista',
            RepeatKind.one => 'Repetir esta canción',
          },
          color: player.repeat == RepeatKind.off ? idle : c.onAccent,
          style: on(player.repeat != RepeatKind.off),
          iconSize: 22,
          icon: LcdIcon(player.repeat == RepeatKind.one ? Icons.repeat_one_rounded : Icons.repeat_rounded),
          onPressed: player.cycleRepeat,
        ),
      ],
    );
  }
}
