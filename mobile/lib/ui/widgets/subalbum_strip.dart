import 'package:flutter/material.dart';

import 'album_grid.dart' show rectOf;
import 'cover.dart';

/// Una carpeta dentro de un álbum (un «subálbum»): su portada y su nombre.
class SubAlbum {
  const SubAlbum({required this.id, required this.title, required this.onOpen, this.subtitle, this.coverFile, this.coverUrl});

  /// Con esto se encuentra su tarjeta (`subalbum-<id>`).
  final String id;
  final String title;

  /// Debajo del nombre (por ejemplo, cuántas canciones tiene).
  final String? subtitle;
  final String? coverFile;
  final String? coverUrl;

  /// Se llama con lo que ocupa su tarjeta en la pantalla (de ahí sale el álbum al abrirlo).
  final void Function(Rect origin) onOpen;
}

/// Los subálbumes de un álbum, arriba, en una tira oscura de esquinas redondeadas: la tarjeta del centro grande, con su nombre, y las de los
/// lados inclinadas y más pequeñas, como una galería que se recorre de lado. Tocar la del centro la abre; tocar una de los lados la
/// lleva al centro.
class SubalbumStrip extends StatefulWidget {
  const SubalbumStrip({super.key, required this.albums, this.height = 176});

  final List<SubAlbum> albums;
  final double height;

  @override
  State<SubalbumStrip> createState() => _SubalbumStripState();
}

class _SubalbumStripState extends State<SubalbumStrip> {
  late final PageController _controller = PageController(viewportFraction: 0.38);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _page => _controller.hasClients && _controller.position.haveDimensions ? (_controller.page ?? 0) : 0;

  @override
  Widget build(BuildContext context) {
    final card = widget.height * 0.66;
    return Container(
      key: const Key('subalbum-strip'),
      height: widget.height,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF14110F), Color(0xFF050505)]),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 14, offset: Offset(0, 6))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: PageView.builder(
          controller: _controller,
          itemCount: widget.albums.length,
          itemBuilder: (context, i) => AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final d = (i - _page).clamp(-2.0, 2.0);
              final near = (1 - d.abs()).clamp(0.0, 1.0); // 1 = en el centro
              return Center(
                child: Opacity(
                  opacity: 0.45 + 0.55 * near,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0014)
                      ..rotateY(-d * 0.55)
                      ..scaleByDouble(0.78 + 0.22 * near, 0.78 + 0.22 * near, 1.0, 1.0),
                    child: _SubCard(album: widget.albums[i], size: card, near: near, onTap: () => _tap(context, i)),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _tap(BuildContext context, int i) {
    if ((i - _page).abs() < 0.5) {
      widget.albums[i].onOpen(rectOf(context));
    } else {
      _controller.animateToPage(i, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    }
  }
}

class _SubCard extends StatelessWidget {
  const _SubCard({required this.album, required this.size, required this.near, required this.onTap});

  final SubAlbum album;
  final double size;
  final double near;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: album.title,
      button: true,
      child: GestureDetector(
        key: Key('subalbum-${album.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Cover(url: album.coverUrl, file: album.coverFile, size: size, radius: 0),
                // el nombre abajo, sobre un velo; en las de los lados se desvanece
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xCC000000)])),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                      child: Opacity(
                        opacity: near,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(album.title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                            if (album.subtitle != null) Text(album.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 11.5)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
