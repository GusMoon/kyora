import 'package:flutter/material.dart';

import '../../theme.dart';
import 'cover.dart';

/// Un álbum de la cuadrícula: su portada (la que le pusiste, o la de su primera canción, o un recuadro con un icono). Sin textos: el nombre
/// solo lo leen los lectores de pantalla (`Semantics`).
class AlbumPlate {
  const AlbumPlate({required this.id, required this.title, required this.icon, required this.onTap, this.coverFile, this.coverUrl, this.onLongPress});

  /// Con esta clave se encuentra la casilla (`card-root`, `card-folder-Rock`…).
  final String id;
  final String title;
  final IconData icon;

  /// Se llama con el rectángulo que ocupa la casilla en la pantalla: de ahí «sale» el disco al abrir el álbum.
  final void Function(Rect origin) onTap;

  /// Mantener pulsada la casilla (para cambiarle la portada). Sin esto, la casilla no responde a la pulsación larga.
  final VoidCallback? onLongPress;

  final String? coverFile;
  final String? coverUrl;
}

/// Lo que ocupa en la pantalla el widget de `context` (para que el disco del álbum salga de ahí).
Rect rectOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return Rect.zero;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Los álbumes en cuadrícula: casillas cuadradas, de tres en tres, solo con su portada: sin bordes redondeados, sin nombre y sin botones.
/// El mismo espacio entre casillas (y con el borde de la pantalla), muy pequeño.
class AlbumGrid extends StatelessWidget {
  const AlbumGrid({super.key, required this.plates, required this.onRefresh, this.header});

  final List<AlbumPlate> plates;
  final Future<void> Function() onRefresh;
  final Widget? header;

  /// El hueco entre casillas y con el borde.
  static const gap = 3.0;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        key: const Key('music-grid'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (header != null) SliverToBoxAdapter(child: header),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(gap, gap, gap, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: gap, crossAxisSpacing: gap),
              delegate: SliverChildBuilderDelegate((context, i) => _Tile(plate: plates[i]), childCount: plates.length),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.plate});

  final AlbumPlate plate;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: plate.title,
      button: true,
      onLongPress: plate.onLongPress,
      child: GestureDetector(
        key: ValueKey(plate.id),
        behavior: HitTestBehavior.opaque,
        onTap: () => plate.onTap(rectOf(context)),
        onLongPress: plate.onLongPress,
        child: LayoutBuilder(builder: (context, box) => PlateArt(plate: plate, side: box.maxWidth)),
      ),
    );
  }
}

/// La cara de la casilla: la portada, o un recuadro con el icono. Cuadrada y sin esquinas redondeadas.
class PlateArt extends StatelessWidget {
  const PlateArt({super.key, required this.plate, required this.side});

  final AlbumPlate plate;
  final double side;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (plate.coverFile != null || plate.coverUrl != null) {
      return Cover(url: plate.coverUrl, file: plate.coverFile, size: side, radius: 0);
    }
    return DecoratedBox(
      key: const Key('plate-blank'),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c.pick, c.plate]),
      ),
      child: Center(child: Icon(plate.icon, size: side * 0.32, color: c.dim)),
    );
  }
}

/// La píldora de arriba para cambiar entre «Álbumes» y «Favoritos».
class AlbumTabs extends StatelessWidget {
  const AlbumTabs({super.key, required this.favorites, required this.onChanged});

  /// `true` = «Favoritos»; `false` = «Álbumes».
  final bool favorites;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget tab(Key key, String text, bool selected, VoidCallback onTap) => Expanded(
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.pick : Colors.transparent,
            borderRadius: BorderRadius.circular(17),
            border: selected ? Border.all(color: c.edge) : null,
          ),
          child: Text(
            text,
            style: TextStyle(color: selected ? c.ink : c.dim, fontSize: 14, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
          ),
        ),
      ),
    );
    return Container(
      key: const Key('album-tabs'),
      width: 210,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.field,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.edge),
      ),
      child: Row(
        children: [
          tab(const Key('tab-albums'), 'Álbumes', !favorites, () => onChanged(false)),
          tab(const Key('tab-favorites'), 'Favoritos', favorites, () => onChanged(true)),
        ],
      ),
    );
  }
}
