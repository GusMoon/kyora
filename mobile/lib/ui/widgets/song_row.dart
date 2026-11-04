
import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../util/format.dart';
import 'cover.dart';

/// Una canción de la lista, compacta: `(carátula ▶) Título / Artista   3:21  ♡  ⋯`. La que suena lleva un ecualizador (o una
/// pausa) sobre la carátula, el título en el color principal y la fila resaltada con un fondo redondeado suave.
class SongRow extends StatelessWidget {
  const SongRow({
    super.key,
    required this.number,
    required this.title,
    required this.line,
    this.coverUrl,
    this.coverFile,
    this.duration,
    this.current = false,
    this.playing = false,
    this.saved = false,
    this.warn = false,
    this.favorite,
    this.onFavorite,
    this.action,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selected,
    this.barColor,
  });

  /// Su lugar en la lista, desde 1. No se escribe en la fila: sirve para reconocerla (por ejemplo, la clave de su corazón).
  final int number;
  final String title;

  /// El artista (o el motivo del fallo, si `warn`).
  final String line;
  final String? coverUrl;
  final String? coverFile;

  /// Lo que dura, si ya se sabe: va en su propia columna.
  final Duration? duration;
  final bool current;
  final bool playing;

  /// Ya está guardada en el teléfono: una marquita junto a la línea de abajo.
  final bool saved;

  /// La línea de abajo es un aviso de error.
  final bool warn;

  /// `null` si no hay corazón; si no, si es favorita.
  final bool? favorite;
  final VoidCallback? onFavorite;

  /// Un botón pequeño entre el título y la duración (en las enviadas, «Recibido»).
  final Widget? action;

  /// A la derecha del corazón: normalmente el menú `⋯`.
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Si va, la fila es la elegida de la rueda del álbum: una barra de ese color a todo el ancho, con el texto y los iconos claros.
  final Color? barColor;

  /// `null` fuera del modo selección; si no, si esta fila está marcada (sustituye a la carátula por una casilla).
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final known = duration != null && duration! > Duration.zero;
    final onBar = barColor != null;
    const light = Color(0xFFF4F4F6);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0.5),
      child: Material(
        color: barColor ?? (current || selected == true ? c.accent.withValues(alpha: 0.14) : Colors.transparent),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 5, 2, 5),
            child: Row(
              children: [
                _Disc(coverUrl: coverUrl, coverFile: coverFile, current: current, playing: playing, selected: selected),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15.5, color: onBar ? light : (current ? c.accent : c.ink), fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 1),
                      Row(
                        children: [
                          if (saved) ...[
                            Icon(Icons.check_circle, key: const Key('saved'), size: 13, color: onBar ? light : c.accent),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              line,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: onBar ? light.withValues(alpha: 0.78) : (warn ? c.warn : c.dim), fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (action != null) Padding(padding: const EdgeInsets.only(left: 6), child: action),
                if (known)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(clock(duration!), style: TextStyle(color: onBar ? light : c.ink, fontSize: 13, fontFeatures: const [FontFeature.tabularFigures()])),
                  ),
                if (favorite != null)
                  IconButton(
                    key: Key('fav-$number'),
                    tooltip: favorite! ? 'Quitar de favoritas' : 'Marcar como favorita',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                    padding: EdgeInsets.zero,
                    icon: Icon(favorite! ? Icons.favorite : Icons.favorite_border, color: onBar ? light : (favorite! ? c.accent : c.dim), size: 22),
                    onPressed: onFavorite,
                  ),
                if (trailing != null) SizedBox(width: 40, height: 40, child: trailing),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// La carátula redonda con su ▶ encima. En la que suena, un ecualizador (o una pausa); en modo selección, una casilla.
class _Disc extends StatelessWidget {
  const _Disc({required this.coverUrl, required this.coverFile, required this.current, required this.playing, required this.selected});

  final String? coverUrl;
  final String? coverFile;
  final bool current;
  final bool playing;
  final bool? selected;

  static const size = 46.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final IconData? icon;
    final Key? key;
    if (selected != null) {
      icon = selected! ? Icons.check_rounded : null;
      key = Key(selected! ? 'row-selected' : 'row-unselected');
    } else if (current) {
      icon = playing ? Icons.graphic_eq_rounded : Icons.pause_rounded;
      key = const Key('now-playing');
    } else {
      icon = Icons.play_arrow_rounded;
      key = const Key('row-play');
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        Cover(url: coverUrl, file: coverFile, size: size, radius: size / 2),
        if (selected == true) Container(width: size, height: size, decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.85), shape: BoxShape.circle)),
        if (selected == false) Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.dim, width: 2))),
        if (icon != null)
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.38), shape: BoxShape.circle),
            child: Icon(icon, key: key, size: 20, color: current ? c.accent : Colors.white),
          ),
        if (icon == null) SizedBox(key: key, width: 1, height: 1),
      ],
    );
  }
}
