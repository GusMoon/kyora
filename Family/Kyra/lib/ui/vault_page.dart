import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/vault_source.dart';
import '../state/vault_controller.dart';
import '../theme.dart';
import '../util/format.dart';
import 'widgets/app_backdrop.dart';
import 'widgets/cyber_panel.dart';
import 'widgets/hack_text.dart';
import 'widgets/section_motion.dart';

/// El **Vault**: una carpeta de tu almacenamiento (la eliges la primera vez) para ver sus carpetas, archivos e imágenes. Las **imágenes se ven
/// tal como son**, sin ningún efecto. Se recorre entrando en las carpetas (con el camino arriba para volver) o, cambiando de modo, como un
/// **árbol** de carpetas que se abren en su sitio. Tocar una imagen la abre a pantalla completa, con zoom y pasando a las demás; un archivo
/// de otro tipo se abre con la app del teléfono que sepa verlo.
class VaultPage extends StatefulWidget {
  const VaultPage({super.key, required this.controller});

  final VaultController controller;

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.controller.root != null) unawaited(widget.controller.refresh());
    });
  }

  VaultController get _c => widget.controller;

  Future<void> _tap(VaultEntry entry, {List<VaultEntry>? among}) async {
    if (entry.isDir) {
      if (_c.view == VaultView.tree) {
        await _c.toggle(entry);
      } else {
        await _c.enter(entry);
      }
      return;
    }
    if (entry.canShow) {
      final images = among ?? _c.images;
      final index = images.indexWhere((e) => e.uri == entry.uri);
      await Navigator.of(context).push(QuickPageRoute<void>(builder: (_) => VaultViewerPage(controller: _c, images: images, index: index < 0 ? 0 : index)));
      return;
    }
    final opened = await _c.open(entry);
    if (!opened && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay ninguna app que abra este archivo.')));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final back = _c.root != null && _c.view == VaultView.grid && _c.canGoUp;
        return PopScope(
          // «atrás» sube de carpeta antes de salir
          canPop: !back,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) unawaited(_c.up());
          },
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: _c.root == null ? _Empty(controller: _c) : _Browser(controller: _c, onTap: _tap),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Sin carpeta elegida: invita a elegir una.
class _Empty extends StatelessWidget {
  const _Empty({required this.controller});

  final VaultController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: FlyIn(
        edge: MotionEdge.bottom,
        child: CyberPanel(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inventory_2_outlined, size: 56, color: c.accent),
                const SizedBox(height: 14),
                HackText('VAULT', style: TextStyle(fontFamily: monoFont, fontSize: 20, letterSpacing: 2, fontWeight: FontWeight.w600, color: c.accent)),
                const SizedBox(height: 10),
                Text('> elige una carpeta de tu almacenamiento para verla aquí: carpetas, archivos e imágenes', textAlign: TextAlign.center, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim)),
                if (controller.error != null) ...[
                  const SizedBox(height: 10),
                  Text('> ${controller.error}', key: const Key('vault-error'), textAlign: TextAlign.center, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.warn)),
                ],
                const SizedBox(height: 18),
                OutlinedButton(key: const Key('vault-pick'), onPressed: () => unawaited(controller.pick()), child: const Text('ELEGIR CARPETA')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Con carpeta: la cabecera con los botones, el camino y lo de dentro.
class _Browser extends StatelessWidget {
  const _Browser({required this.controller, required this.onTap});

  final VaultController controller;
  final Future<void> Function(VaultEntry entry, {List<VaultEntry>? among}) onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ctrl = controller;
    final tree = ctrl.view == VaultView.tree;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FlyIn(
          edge: MotionEdge.top,
          order: 0,
          child: CyberPanel(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
              child: Row(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 24, color: c.accent),
                  const SizedBox(width: 10),
                  Expanded(child: HackText(ctrl.root!.name.toUpperCase(), textKey: const Key('vault-name'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: monoFont, fontSize: 17, letterSpacing: 1.4, fontWeight: FontWeight.w600, color: c.accent))),
                  _Tool(key: const Key('vault-view'), icon: tree ? Icons.grid_view_rounded : Icons.account_tree_outlined, label: tree ? 'Ver en cuadrícula' : 'Ver como árbol', onTap: () => unawaited(ctrl.toggleView())),
                  _Tool(key: const Key('vault-refresh'), icon: Icons.refresh_rounded, label: 'Actualizar', onTap: () => unawaited(ctrl.refresh())),
                  _Tool(key: const Key('vault-change'), icon: Icons.folder_open_rounded, label: 'Cambiar de carpeta', onTap: () => unawaited(ctrl.pick())),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (!tree)
          FlyIn(
            edge: MotionEdge.left,
            order: 1,
            child: _Crumbs(controller: ctrl),
          ),
        Expanded(
          child: FlyIn(
            edge: MotionEdge.bottom,
            order: 2,
            child: CyberPanel(child: _content(context, ctrl, tree)),
          ),
        ),
      ],
    );
  }

  Widget _content(BuildContext context, VaultController ctrl, bool tree) {
    final c = context.colors;
    Widget message(String text, {Color? color, List<Widget> actions = const []}) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, key: const Key('vault-message'), textAlign: TextAlign.center, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: color ?? c.dim)),
            if (actions.isNotEmpty) ...[const SizedBox(height: 14), ...actions],
          ],
        ),
      ),
    );

    if (ctrl.loading && (tree ? ctrl.rows.isEmpty : ctrl.entries.isEmpty)) {
      return const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(key: Key('vault-loading'), strokeWidth: 2.4)));
    }
    if (ctrl.error != null && (tree ? ctrl.rows.isEmpty : ctrl.entries.isEmpty)) {
      return message(
        '> ${ctrl.error}',
        color: c.warn,
        actions: [
          if (ctrl.lost) OutlinedButton(key: const Key('vault-repick'), onPressed: () => unawaited(ctrl.pick()), child: const Text('ELEGIR OTRA CARPETA')) else OutlinedButton(key: const Key('vault-retry'), onPressed: () => unawaited(ctrl.refresh()), child: const Text('REINTENTAR')),
        ],
      );
    }
    if (tree) {
      final rows = ctrl.rows;
      if (rows.isEmpty) return message('> carpeta vacía');
      final images = [for (final r in rows) if (r.entry.canShow) r.entry];
      return ListView.builder(
        key: const Key('vault-tree'),
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: rows.length,
        itemBuilder: (context, i) => _TreeRow(row: rows[i], controller: ctrl, onTap: () => onTap(rows[i].entry, among: images)),
      );
    }
    final entries = ctrl.entries;
    if (entries.isEmpty) return message('> carpeta vacía');
    return GridView.builder(
      key: const Key('vault-grid'),
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.8),
      itemCount: entries.length,
      itemBuilder: (context, i) => _Tile(entry: entries[i], controller: ctrl, onTap: () => onTap(entries[i])),
    );
  }
}

/// Un botón cuadrado de la cabecera.
class _Tool extends StatelessWidget {
  const _Tool({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox.square(dimension: 44, child: Icon(icon, size: 24, color: context.colors.ink)),
    ),
  );
}

/// El camino hasta la carpeta de ahora: `RAÍZ / fotos / 2026`, cada trozo se toca para volver ahí.
class _Crumbs extends StatelessWidget {
  const _Crumbs({required this.controller});

  final VaultController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final trail = controller.trail;
    Widget crumb(int depth, String text) {
      final last = depth == trail.length;
      return GestureDetector(
        key: Key('crumb-$depth'),
        behavior: HitTestBehavior.opaque,
        onTap: last ? null : () => unawaited(controller.goTo(depth)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
          child: Text(text, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: last ? c.accent : c.ink, fontWeight: last ? FontWeight.w600 : FontWeight.w400)),
        ),
      );
    }

    return Container(
      height: 44,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), border: Border.all(color: c.edge)),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          key: const Key('vault-crumbs'),
          scrollDirection: Axis.horizontal,
          reverse: true, // la carpeta de ahora siempre a la vista
          child: Row(
            children: [
              Text('~ ', style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim)),
              crumb(0, 'RAÍZ'),
              for (var i = 0; i < trail.length; i++) ...[
                Text(' / ', style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim)),
                crumb(i + 1, trail[i].name),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// La imagen reducida de un archivo, tal cual (sin ningún efecto). Mientras llega, una caja vacía; si falla, un icono de imagen rota.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.entry, required this.controller, this.side});

  final VaultEntry entry;
  final VaultController controller;

  /// El lado en px si es un cuadrito (en el árbol).
  final double? side;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FutureBuilder<Uint8List>(
      future: controller.thumb(entry),
      builder: (context, snapshot) {
        if (snapshot.hasData) return Image.memory(snapshot.data!, key: Key('vault-image-${entry.name}'), fit: BoxFit.cover, width: side, height: side, gaplessPlayback: true, errorBuilder: (_, _, _) => Icon(Icons.broken_image_outlined, color: c.dim));
        if (snapshot.hasError) return Center(child: Icon(Icons.broken_image_outlined, size: side == null ? 32 : side! * 0.6, color: c.dim));
        return const SizedBox.expand();
      },
    );
  }
}

IconData _iconFor(VaultEntry e) {
  if (e.isDir) return Icons.folder_rounded;
  final m = e.mime;
  final x = e.extension;
  if (m.startsWith('audio/') || const {'mp3', 'wav', 'flac', 'm4a', 'ogg', 'aac'}.contains(x)) return Icons.music_note_rounded;
  if (m.startsWith('video/') || const {'mp4', 'mkv', 'mov', 'avi', 'webm', '3gp'}.contains(x)) return Icons.videocam_rounded;
  if (x == 'pdf' || m == 'application/pdf') return Icons.picture_as_pdf_rounded;
  if (const {'zip', 'rar', '7z', 'tar', 'gz'}.contains(x)) return Icons.folder_zip_rounded;
  if (e.isImage) return Icons.image_rounded;
  return Icons.insert_drive_file_rounded;
}

/// Una casilla de la cuadrícula: una carpeta, una imagen (en grande, tal cual) o un archivo.
class _Tile extends StatelessWidget {
  const _Tile({required this.entry, required this.controller, required this.onTap});

  final VaultEntry entry;
  final VaultController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final showImage = entry.canShow;
    return GestureDetector(
      key: Key('vault-entry-${entry.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(color: showImage ? null : Colors.black.withValues(alpha: 0.35), border: Border.all(color: entry.isDir ? c.accent.withValues(alpha: 0.7) : c.edge)),
        child: showImage
            ? _Thumb(entry: entry, controller: controller)
            : Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_iconFor(entry), size: 30, color: entry.isDir ? c.accent : c.ink),
                    const SizedBox(height: 4),
                    Flexible(child: Text(entry.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontFamily: appFont, fontSize: 15, height: 1.15, color: c.ink))),
                    if (!entry.isDir && entry.size > 0) Text(humanSize(entry.size), style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim)),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Una fila del árbol: sangrada según su profundidad, con la flecha de las carpetas y el icono (o la imagen pequeña).
class _TreeRow extends StatelessWidget {
  const _TreeRow({required this.row, required this.controller, required this.onTap});

  final VaultRow row;
  final VaultController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = row.entry;
    return GestureDetector(
      key: Key('vault-row-${e.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(10 + row.depth * 18.0, 4, 10, 4),
        child: SizedBox(
          height: 40,
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: e.isDir
                    ? (row.loading ? const Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))) : Icon(row.expanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded, size: 22, color: c.accent))
                    : null,
              ),
              const SizedBox(width: 4),
              if (e.canShow)
                SizedBox.square(dimension: 36, child: _Thumb(entry: e, controller: controller, side: 36))
              else
                SizedBox.square(dimension: 36, child: Icon(row.expanded ? Icons.folder_open_rounded : _iconFor(e), size: 24, color: e.isDir ? c.accent : c.ink)),
              const SizedBox(width: 10),
              Expanded(child: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: appFont, fontSize: 16, color: c.ink))),
              if (!e.isDir && e.size > 0) Text(humanSize(e.size), style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Una imagen a pantalla completa, **tal como es** (el archivo entero, sin efectos), con zoom y pasando a las demás de la carpeta.
class VaultViewerPage extends StatefulWidget {
  const VaultViewerPage({super.key, required this.controller, required this.images, required this.index});

  final VaultController controller;
  final List<VaultEntry> images;
  final int index;

  @override
  State<VaultViewerPage> createState() => _VaultViewerPageState();
}

class _VaultViewerPageState extends State<VaultViewerPage> {
  late final PageController _pages = PageController(initialPage: widget.index);
  late int _current = widget.index;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final entry = widget.images[_current];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(entry.name, key: const Key('viewer-title'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: appFont, fontSize: 16, color: c.ink)),
        actions: [
          Center(child: Padding(padding: const EdgeInsets.only(right: 16), child: Text('${_current + 1}/${widget.images.length}', key: const Key('viewer-count'), style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim)))),
        ],
      ),
      body: PageView.builder(
        key: const Key('viewer-pages'),
        controller: _pages,
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (context, i) => _FullImage(controller: widget.controller, entry: widget.images[i]),
      ),
    );
  }
}

class _FullImage extends StatelessWidget {
  const _FullImage({required this.controller, required this.entry});

  final VaultController controller;
  final VaultEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FutureBuilder<Uint8List>(
      future: controller.read(entry),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.broken_image_outlined, size: 56, color: c.dim), const SizedBox(height: 8), Text('No se pudo abrir esta imagen', style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.warn))]));
        }
        if (!snapshot.hasData) return const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.4)));
        return InteractiveViewer(
          maxScale: 6,
          child: Center(child: Image.memory(snapshot.data!, key: Key('viewer-image-${entry.name}'), fit: BoxFit.contain, gaplessPlayback: true, errorBuilder: (_, _, _) => Icon(Icons.broken_image_outlined, size: 56, color: c.dim))),
        );
      },
    );
  }
}
