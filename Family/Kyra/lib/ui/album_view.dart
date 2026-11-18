import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/audio_engine.dart';
import '../data/favorites_store.dart';
import '../models/track.dart';
import '../state/local_music_controller.dart';
import '../state/music_controller.dart';
import '../state/player_controller.dart';
import '../theme.dart';
import '../util/format.dart';
import '../util/picker.dart';
import '../util/track_search.dart';
import 'admin_music_dialogs.dart';
import 'album_options.dart';
import 'cover_picker.dart';
import 'folder_settings.dart';
import 'music_actions.dart';
import 'widgets/cut_border.dart';
import 'widgets/app_backdrop.dart';
import 'widgets/cover_backdrop.dart';
import 'widgets/disc_player.dart';
import 'widgets/mini_player.dart';
import 'widgets/music_rows.dart';
import 'widgets/song_arc_list.dart';
import 'widgets/pixel_glyph.dart';
import 'widgets/lcd_box.dart';
import 'widgets/options_reactor.dart';
import 'widgets/hack_text.dart';
import 'widgets/focus_space.dart';
import 'widgets/section_motion.dart';

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

/// La ruta del álbum: se abre y se cierra con el **efecto de holograma** de la app (la pantalla se materializa con saltos, parpadeo y franjas
/// de interferencia; al volver, se deshace igual), sin más animación: ya no sale un disco de la tarjeta. Mientras se anima se sigue viendo la
/// música debajo.
///
/// Con [hologram] en `false` la entrada es inmediata (se usa cuando ya hay un holograma en marcha, como el del cambio de sección al venir de
/// Inicio: dos seguidos serían lentos); al volver siempre se deshace con el holograma.
PageRoute<T> albumOpenRoute<T>({required WidgetBuilder builder, bool hologram = true}) => PageRouteBuilder<T>(
  opaque: true, // mientras dura la animación se ve la música debajo; al terminar ya no hace falta
  transitionDuration: hologram ? const Duration(milliseconds: 360) : Duration.zero,
  reverseTransitionDuration: const Duration(milliseconds: 280),
  pageBuilder: (context, animation, secondaryAnimation) => builder(context),
  transitionsBuilder: (context, animation, secondaryAnimation, child) => HologramReveal(animation: animation, child: child),
);

/// La vista de un álbum. De fondo, **la portada** nítida, con líneas de barrido y oscurecida; en el centro, algo más arriba que el medio,
/// el **disco de vinilo** (`DiscPlayer`): un toque reproduce o pausa y girarlo mueve la canción. Debajo, sin ningún fondo, el nombre de la
/// canción y, si suena una de este álbum, aleatorio, anterior, siguiente y repetir; si suena una de otro, abajo sale su tarjeta, que lleva a su disco.
///
/// **Mantener presionado el disco** abre sus opciones: aleatorio del álbum, mover, borrar y el medidor de velocidad y tono. (Ya no sirve para
/// cambiar de álbum: se vuelve a la pila y se elige otro.)
/// **Doble toque en cualquier parte menos en el disco** abre la lista de canciones (`SongArcList`): el disco encoge hasta la fila del centro y
/// las demás llegan por la curva. Otro doble toque o «atrás» la cierran. No hay deslizamientos de lado ni de arriba abajo.
///
/// Un álbum solo enseña sus canciones: lo que tenga en subcarpetas no se muestra.
///
/// Se abre y se cierra con el efecto de holograma de `albumOpenRoute`.
class AlbumView extends StatefulWidget {
  const AlbumView({
    super.key,
    required this.albums,
    required this.initial,
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

  /// Lo que se oscurece la portada con la lista abierta (por encima del oscurecido de siempre): lo justo para leer las filas sin perder la imagen.
  static const listDim = 0.5;

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

  /// Los Ã¡lbumes cuyo disco ya se tocÃ³ por el centro: hasta entonces solo se ven el disco y el fondo.
  final Set<String> _started = {};

  /// Dónde está el disco en pantalla: de ahí nace el reactor de opciones.
  final GlobalKey _discKey = GlobalKey();

  /// La bÃºsqueda de canciones del Ã¡lbum: abierta o no, y lo escrito.
  bool _searching = false;
  final TextEditingController _query = TextEditingController();

  /// La canción que se enseña de cada álbum cuando no suena ninguna de él (la que quedó en el centro de la lista).
  final Map<String, int> _picked = {};

  /// La canción que sonaba la última vez que se miró: si pasa a sonar una de otro álbum (el aleatorio entre todo), se pasa solo a ese álbum.
  String? _lastCurrent;

  /// Ya no hay animación propia de entrada (la ruta pinta el holograma): el fondo y la barra están siempre del todo a la vista.
  final Animation<double> _backgroundIn = kAlwaysCompleteAnimation;
  final Animation<double> _barIn = kAlwaysCompleteAnimation;

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
    _listFade.dispose();
    _list.dispose();
    _query.dispose();
    super.dispose();
  }

  void _onListStatus(AnimationStatus status) {
    // cerrada del todo, la lista deja de construirse
    if (status == AnimationStatus.dismissed && mounted) setState(() {});
  }

  /// «Seleccionar»: empieza a marcar canciones por la que está en el centro de la lista (después, un toque marca o desmarca cada una).
  void _startSelecting() {
    final e = _entry;
    final songs = _songs(e);
    final local = widget.local;
    if (songs == null || songs.isEmpty || local == null || !_canEdit(e)) return;
    final shown = searchTracks(_query.text, songs);
    final base = shown.isEmpty ? songs : shown;
    local.toggleSelect(base[_focus(e, base)]);
  }

  /// Las acciones de música (las mismas que en KyraFamily), con los paneles de KyraAdmin.
  MusicActions? _actions() {
    final local = widget.local;
    return local == null ? null : MusicActions(local: local, player: widget.player, dialogs: AdminMusicDialogs(this));
  }

  /// Borra las canciones marcadas (con confirmación).
  Future<void> _deleteSelected() async => _actions()?.deleteSelected(albumTitle: _entry.title);

  /// Abre la búsqueda: enseña la lista de canciones y, arriba, el campo para escribir.
  void _startSearch() {
    final songs = _songs(_entry);
    if (songs == null || songs.isEmpty) return;
    setState(() {
      _searching = true;
    });
    if (!_listOpen) _openList();
  }

  /// Cierra la búsqueda: se borra lo escrito y la lista vuelve a enseñar todas las canciones.
  void _stopSearch() {
    _query.clear();
    setState(() => _searching = false);
  }

  void _openList() {
    final songs = _songs(_entry);
    if (songs == null || songs.isEmpty) return;
    setState(() {
      _listOpen = true;
    });
    unawaited(_list.forward());
  }

  void _closeList() {
    _query.clear();
    setState(() {
      _listOpen = false;
      _searching = false;
    });
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
    setState(() {
      _shown = i;
    });
    widget.onShown?.call(widget.albums[i]);
  }

  /// ¿Ya se tocó el disco por el centro (o ya suena una canción de este álbum)? Hasta entonces solo se ven el disco y el fondo.
  bool _armed(AlbumEntry e) => _started.contains(e.id) || _isActive(e);

  /// ¿Se pueden mover, borrar y renombrar las canciones de este álbum? Solo en los del teléfono que el controlador tiene abiertos.
  bool _canEdit(AlbumEntry e) => !e.received && widget.local != null && _isOpenIn(e);

  /// Mantener presionado el disco: abre el reactor de opciones de la canción que se enseña (la que suena), sobre un velo oscuro.
  void _openOptions() {
    final e = _entry;
    if (_listOpen || _marking(e) || !_armed(e)) return;
    final songs = _songs(e);
    if (songs == null || songs.isEmpty) return;
    unawaited(HapticFeedback.mediumImpact().catchError((Object _) {}));
    final box = _discKey.currentContext?.findRenderObject() as RenderBox?;
    final center = box == null || !box.hasSize ? MediaQuery.sizeOf(context).center(Offset.zero) : box.localToGlobal(box.size.center(Offset.zero));
    unawaited(showOptionsReactor(context, center: center, options: _discOptions(e, songs[_focus(e, songs)]), listenable: widget.player));
  }

  /// Las opciones de la canción `track`: mover, borrar, velocidad y tono, y cambiar el nombre. Mover, borrar y renombrar solo en los álbumes
  /// del teléfono; en las enviadas queda la velocidad y el tono.
  List<DiscOption> _discOptions(AlbumEntry e, Track track) {
    final player = widget.player;
    final edit = _canEdit(e);
    void run(Future<void> Function() action) => unawaited(action());

    return [
      if (edit) DiscOption(id: 'move', icon: Icons.drive_file_move_outlined, label: 'Mover a otro álbum', onTap: () => run(() => _moveTrack(track))),
      if (edit) DiscOption(id: 'delete', icon: Icons.delete_outline_rounded, label: 'Borrar canción', warn: true, onTap: () => run(() => _deleteTrack(track))),
      if (player != null)
        DiscOption(
          id: 'speed',
          icon: Icons.speed_rounded,
          label: 'Velocidad y tono',
          // el propio reactor pasa a ser un dial: se gira el dedo por el aro para ajustar
          dials: [
            ReactorDial(id: 'rate', icon: Icons.speed_rounded, label: 'Velocidad', min: PlayerController.minRate, max: PlayerController.maxRate, step: RateMeter.step, value: () => player.rate, onChanged: (v) => unawaited(player.setRate(v)), format: RateMeter.label, neutral: 1),
            ReactorDial(id: 'pitch', icon: Icons.graphic_eq_rounded, label: 'Tono', min: PlayerController.minPitch, max: PlayerController.maxPitch, step: RateMeter.step, value: () => player.pitch, onChanged: (v) => unawaited(player.setPitch(v)), format: RateMeter.label, neutral: 1),
          ],
        ),
      if (edit) DiscOption(id: 'rename', icon: Icons.edit_outlined, label: 'Cambiar nombre', onTap: () => run(() => _renameTrack(track))),
    ];
  }

  /// El menú de una canción de la lista (mantenerla presionada): mover o borrar.
  Future<void> _songMenu(Track track) async {
    unawaited(HapticFeedback.mediumImpact().catchError((Object _) {}));
    final choice = await showFocusPanel<String>(
      context,
      title: splitArtistTitle(track.title).title,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('song-opt-move'),
              leading: const LcdIcon(Icons.drive_file_move_outlined),
              title: const Text('Mover'),
              onTap: () => Navigator.pop(context, 'move'),
            ),
            ListTile(
              key: const Key('song-opt-delete'),
              leading: LcdIcon(Icons.delete_outline_rounded, color: context.colors.warn),
              title: Text('Borrar', style: TextStyle(color: context.colors.warn)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'move') await _moveTrack(track);
    if (choice == 'delete') await _deleteTrack(track);
  }

  Future<void> _moveTrack(Track track) async => _actions()?.moveTrack(track);

  Future<void> _deleteTrack(Track track) async => _actions()?.deleteTrack(track, title: splitArtistTitle(track.title).title);

  Future<void> _renameTrack(Track track) async => _actions()?.renameTrack(track);

  /// ¿La canción que suena es de este álbum?
  bool _isActive(AlbumEntry e) {
    final current = widget.player?.current;
    if (current == null) return false;
    return _songs(e)?.any((t) => t.id == current.id) ?? false;
  }

  /// Tocar el centro del disco: reproduce (o pausa) la canción que se enseña. La primera vez se destapan el nombre y los controles.
  void _toggle(AlbumEntry e) {
    final songs = _songs(e);
    if (songs == null || songs.isEmpty) return;
    if (_started.add(e.id)) setState(() {});
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
    await changeAlbumCover(context, local: local, albumId: e.id, title: e.title, pickCover: widget.pickCover);
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
        // «atrás» primero quita la marca de las canciones o la búsqueda y, con la lista abierta, la cierra
        canPop: !_marking(_entry) && !_searching && !_listOpen,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_marking(_entry)) {
            local?.clearSelection();
          } else if (_searching) {
            _stopSearch();
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
        // con la lista abierta, lo de debajo se oscurece con una trama de tinta y, al acabar de abrirse, con un velo plano: la portada del álbum
        // se sigue viendo, más oscura (sin portada, el color de la pantalla de siempre)
        AnimatedBuilder(
          animation: _list,
          builder: (context, _) {
            final cover = _coverOf(_entry);
            final hasCover = cover.file != null || cover.url != null;
            return KeyedSubtree(
              key: const Key('album-dark'),
              child: _list.value < 0.05
                  ? const SizedBox.expand()
                  : _list.value < 0.6
                  ? const LcdDither(density: 0.25)
                  : ColoredBox(
                      key: const Key('album-list-dim'),
                      color: hasCover ? Colors.black.withValues(alpha: AlbumView.listDim) : context.colors.background,
                    ),
            );
          },
        ),
        // el doble toque: va debajo del disco, no por encima. Así el disco tiene sus gestos para él y un toque en él no espera a ver si llega un segundo
        GestureDetector(key: const Key('album-background'), behavior: HitTestBehavior.opaque, onDoubleTap: _openList, child: const SizedBox.expand()),
        // el disco del álbum que se ve
        AnimatedBuilder(animation: _list, builder: (context, _) => _discs(size, disc)),
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
                  ? SelectionBar(local: local!, onMove: widget.onMove ?? () {}, onDelete: () => unawaited(_deleteSelected()))
                  : _searching
                  ? Row(
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: BackButton(key: Key('album-back')),
                        ),
                        Expanded(
                          child: TextField(
                            key: const Key('album-search-field'),
                            controller: _query,
                            autofocus: true,
                            textInputAction: TextInputAction.search,
                            decoration: const InputDecoration(hintText: 'Buscar una canción', border: InputBorder.none),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        IconButton(
                          key: const Key('album-search-close'),
                          tooltip: 'Cerrar la búsqueda',
                          icon: const LcdIcon(Icons.close_rounded),
                          onPressed: _stopSearch,
                        ),
                        const SizedBox(width: 4),
                      ],
                    )
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
                        if (_songs(_entry)?.isNotEmpty ?? false)
                          IconButton(
                            key: const Key('album-search'),
                            tooltip: 'Buscar una canción',
                            icon: const LcdIcon(Icons.search_rounded),
                            onPressed: _startSearch,
                          ),
                        if (_listOpen && _canEdit(_entry))
                          IconButton(
                            key: const Key('album-select'),
                            tooltip: 'Seleccionar canciones',
                            icon: const LcdIcon(Icons.checklist_rounded),
                            onPressed: _startSelecting,
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
    final hidden = fade == 0;
    // oculto, no gira ni lee el sonido (su reloj y el del círculo se apagan): con la lista abierta solo gastaría batería y cuadros
    return TickerMode(
      enabled: !hidden,
      child: Offstage(
        offstage: hidden,
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
                  child: Transform.scale(
                    scale: scale,
                    child: Opacity(opacity: fade, child: _disc(_entry, disc)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _disc(AlbumEntry e, Rect disc) {
    final art = _coverOf(e);
    final songs = _songs(e);
    final hasSongs = songs != null && songs.isNotEmpty;
    return Stack(
      alignment: Alignment.center,
      children: [
        DiscPlayer(
          key: e.id == _entry.id ? _discKey : null,
          id: e.id,
          file: art.file,
          url: art.url,
          icon: e.icon,
          size: disc.width,
          active: _isActive(e),
          player: widget.player,
          touchKey: Key('album-disc-${e.id}'),
          playHint: hasSongs && !_armed(e),
          onTap: () => _toggle(e),
          onLongPress: _openOptions,
        ),
      ],
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
    } else if (!_armed(e)) {
      // al entrar solo se ven el disco y el fondo: el nombre y los controles aparecen al tocar el centro del disco
      return const SizedBox.shrink();
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
  Widget _backdrop(({String? file, String? url}) cover) => cover.file == null && cover.url == null
      ? const BackdropLayers()
      : Stack(
          fit: StackFit.expand,
          children: [
            CoverBackdrop(file: cover.file, url: cover.url),
            const HackerScreen(),
          ],
        );

  /// La lista de canciones, por encima del disco mientras está abierta.
  Widget _listLayer(BuildContext context) {
    final e = _entry;
    final local = widget.local;
    final player = widget.player;
    final favorites = widget.favorites;
    final all = _songs(e) ?? const <Track>[];
    if (all.isEmpty) return const SizedBox.shrink();
    // con la búsqueda abierta, solo las que coinciden; al tocar una suena con todo el álbum como cola
    final songs = searchTracks(_query.text, all);
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
            if (songs.isNotEmpty)
              SongArcList(
                key: ValueKey('album-list-${e.id}-${_query.text}'),
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
                onPlay: (t) => _playOrPause(e, t, all),
                onFocus: (i) => setState(() => _picked[e.id] = i),
                onDoubleTap: _closeList,
                selectedOf: marking ? (t) => local!.isSelected(t) : null,
                onHold: _canEdit(e) ? (t) => unawaited(_songMenu(t)) : null,
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
                            icon: LcdIcon(favorite ? Icons.favorite : Icons.favorite_border, color: context.colors.ink, size: 22),
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
            if (songs.isEmpty)
              Center(
                child: Text(
                  'Ninguna canción coincide.',
                  key: const Key('album-search-empty'),
                  style: TextStyle(color: context.colors.dim, fontSize: 16),
                ),
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
    return Wrap(
      key: const Key('disc-controls'),
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
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
        // la velocidad, mientras no sea la normal: tocarla la devuelve a 1×
        if (player.rate != 1) ...[
          const SizedBox(width: 6),
          TextButton(
            key: const Key('player-rate'),
            style: TextButton.styleFrom(minimumSize: const Size(52, 44), padding: const EdgeInsets.symmetric(horizontal: 8)),
            onPressed: () => unawaited(player.setRate(1)),
            child: Text(
              RateMeter.label(player.rate),
              style: TextStyle(color: c.accent, fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ],
        // y el tono, si no es el normal
        if (player.pitch != 1) ...[
          const SizedBox(width: 6),
          TextButton(
            key: const Key('player-pitch'),
            style: TextButton.styleFrom(minimumSize: const Size(52, 44), padding: const EdgeInsets.symmetric(horizontal: 8)),
            onPressed: () => unawaited(player.setPitch(1)),
            child: Text(
              '♪${RateMeter.label(player.pitch)}',
              style: TextStyle(color: c.accent, fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ],
    );
  }
}
