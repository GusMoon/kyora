import 'package:flutter/material.dart';

import '../models/track.dart';
import '../state/player_controller.dart';
import '../theme.dart';
import '../util/cover_color.dart';
import '../util/format.dart';
import 'player_page.dart';
import 'widgets/song_ring.dart';
import 'widgets/subalbum_strip.dart';

/// La pantalla de un álbum: arriba, atrás y el nombre del álbum (o, al marcar canciones, la barra de selección); si el álbum tiene
/// carpetas dentro, sus **subálbumes** en una tira oscura (`SubalbumStrip`); en medio las canciones como un **anillo 3D que se gira**
/// (`SongRing`); y debajo, la canción de enfrente con sus botones. El fondo se tiñe con el color de la portada. Sirve igual para un álbum
/// del teléfono que para las canciones enviadas: quien la abre dice cuáles son las canciones y qué botones lleva cada una.
class AlbumPage extends StatefulWidget {
  const AlbumPage({
    super.key,
    required this.title,
    required this.animation,
    required this.origin,
    required this.tracks,
    required this.artOf,
    required this.onPlay,
    this.actionsOf,
    this.subtitleOf,
    this.subalbums = const [],
    this.coverFile,
    this.coverUrl,
    this.player,
    this.topBar,
    this.banner,
    this.notice,
    this.checked,
    this.onToggle,
    this.onLongPress,
    this.cardKey,
    this.emptyText = 'No hay canciones aquí.',
    this.canPop = true,
    this.onBlockedPop,
  });

  final String title;

  /// La animación de la ruta (0 → 1): las portadas salen de `origin`.
  final Animation<double> animation;
  final Rect origin;
  final List<Track> tracks;

  /// La imagen de cada canción (un archivo del teléfono), si la tiene.
  final String? Function(Track track) artOf;

  /// Se tocó una canción (la de enfrente, o una de los lados, que antes gira al frente): reproducirla.
  final void Function(Track track, int index) onPlay;

  /// Los botones de la canción de enfrente (corazón, menú ⋯, «Recibido»…).
  final Widget? Function(BuildContext context, Track track, int index)? actionsOf;

  /// Lo que va bajo el título de la canción de enfrente (el artista…); `warn` lo pinta como aviso.
  final ({String text, bool warn})? Function(Track track)? subtitleOf;

  /// Las carpetas de dentro del álbum, arriba.
  final List<SubAlbum> subalbums;
  final String? coverFile;
  final String? coverUrl;
  final PlayerController? player;

  /// Sustituye al nombre de arriba (la barra de selección).
  final Widget? topBar;

  /// Una franja bajo la barra de arriba (en las enviadas: cuántas faltan por guardar).
  final Widget? banner;

  /// En vez del anillo: «cargando», un error o «no hay canciones».
  final Widget? notice;

  /// Para marcar varias canciones: ¿está marcada? (`null` fuera de ese modo). Con el modo activo, tocar marca y desmarca.
  final bool Function(Track track)? checked;
  final ValueChanged<Track>? onToggle;
  final ValueChanged<Track>? onLongPress;
  final Key? Function(Track track)? cardKey;

  /// Lo que se dice bajo los subálbumes cuando no hay canciones.
  final String emptyText;

  /// `false` mientras «atrás» tiene que hacer otra cosa antes (quitar la selección); entonces se llama a `onBlockedPop`.
  final bool canPop;
  final VoidCallback? onBlockedPop;

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  Color? _tint;
  int _selected = 0;
  final _ringController = RingController();

  @override
  void initState() {
    super.initState();
    _loadTint();
  }

  @override
  void didUpdateWidget(AlbumPage old) {
    super.didUpdateWidget(old);
    if (old.coverFile != widget.coverFile || old.coverUrl != widget.coverUrl) _loadTint();
    if (_selected >= widget.tracks.length) _selected = widget.tracks.isEmpty ? 0 : widget.tracks.length - 1;
  }

  Future<void> _loadTint() async {
    final file = widget.coverFile;
    final url = widget.coverUrl;
    final found = await coverColor(url: url, file: file);
    if (mounted && file == widget.coverFile && url == widget.coverUrl) setState(() => _tint = found);
  }

  void _tap(Track track, int index) {
    if (widget.checked != null) {
      widget.onToggle?.call(track);
      return;
    }
    if (index != _selected) _ringController.centerOn(index);
    widget.onPlay(track, index);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // sin carátula (o gris), el color de la app con poca fuerza
    final tint = _tint ?? HSLColor.fromColor(c.accent).withSaturation(0.35).toColor();
    return PopScope(
      canPop: widget.canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onBlockedPop?.call();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            Expanded(
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: tint),
                duration: const Duration(milliseconds: 450),
                builder: (context, animated, _) {
                  final color = animated ?? tint;
                  return AnimatedBuilder(
                    animation: widget.animation,
                    builder: (context, child) {
                      final fade = Curves.easeOut.transform(const Interval(0.0, 0.6).transform(widget.animation.value));
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color.lerp(Colors.transparent, Color.lerp(c.background, color, 0.38), fade)!,
                              Color.lerp(Colors.transparent, Color.lerp(Colors.black, color, 0.10), fade)!,
                            ],
                          ),
                        ),
                        child: child,
                      );
                    },
                    child: _content(context, color),
                  );
                },
              ),
            ),
            if (widget.player != null) MiniPlayer(player: widget.player!),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, Color color) {
    final songs = widget.tracks;
    final hasSongs = songs.isNotEmpty && widget.notice == null;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          widget.topBar ?? _TitleBar(title: widget.title),
          if (widget.banner != null) widget.banner!,
          if (widget.subalbums.isNotEmpty) SubalbumStrip(albums: widget.subalbums),
          Expanded(
            child:
                widget.notice ??
                (songs.isEmpty
                    ? (widget.subalbums.isEmpty
                          ? const SizedBox.shrink()
                          : Center(
                              child: Text(widget.emptyText, style: TextStyle(color: context.colors.dim)),
                            ))
                    : _ring(context, color)),
          ),
          // escucha al reproductor: la duración de la canción de enfrente aparece cuando se sabe
          if (hasSongs)
            ListenableBuilder(
              listenable: widget.player ?? const _Never(),
              builder: (context, _) => _panel(context, songs[_selected.clamp(0, songs.length - 1)], _selected.clamp(0, songs.length - 1)),
            ),
        ],
      ),
    );
  }

  Widget _ring(BuildContext context, Color color) {
    final player = widget.player;
    return ListenableBuilder(
      listenable: player ?? const _Never(),
      builder: (context, _) => SongRing(
        tracks: widget.tracks,
        animation: widget.animation,
        origin: widget.origin,
        artOf: widget.artOf,
        controller: _ringController,
        initialIndex: _selected,
        accent: color,
        playingId: player != null && player.playing ? player.current?.id : null,
        cardKey: widget.cardKey,
        checked: widget.checked,
        onSelect: (i) => setState(() => _selected = i),
        onTap: _tap,
        onLongPress: widget.onLongPress,
      ),
    );
  }

  /// La canción de enfrente: su título, lo que va debajo y sus botones.
  Widget _panel(BuildContext context, Track track, int index) {
    final c = context.colors;
    final named = splitArtistTitle(track.title);
    final sub = widget.subtitleOf?.call(track) ?? (text: named.artist ?? '', warn: false);
    final actions = widget.checked == null ? widget.actionsOf?.call(context, track, index) : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  named.title,
                  key: const Key('ring-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                if (sub.text.isNotEmpty)
                  Text(
                    sub.text,
                    key: const Key('ring-subtitle'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, color: sub.warn ? c.warn : c.dim),
                  ),
              ],
            ),
          ),
          ?actions,
        ],
      ),
    );
  }
}

/// Un `Listenable` que nunca avisa (para cuando no hay reproductor al que escuchar).
class _Never implements Listenable {
  const _Never();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
      child: Row(
        children: [
          const BackButton(key: Key('album-back')),
          Expanded(
            child: Text(
              title,
              key: const Key('album-title'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
