import 'dart:async';

import 'package:flutter/material.dart';

import '../data/music_store.dart';
import '../models/track.dart';
import '../state/local_music_controller.dart';
import '../theme.dart';
import 'widgets/pixel_glyph.dart';
import 'widgets/focus_space.dart';

/// Adónde se van a mover las canciones: una carpeta (`uri` `null` = la raíz elegida) y su nombre, para avisar.
class MoveTarget {
  const MoveTarget({required this.uri, required this.name});

  final String? uri;
  final String name;
}

/// Pregunta el nombre de un álbum (carpeta) nuevo. `null` si se cancela.
Future<String?> askFolderName(BuildContext context) => askName(context, title: 'Nuevo álbum', hint: 'Nombre del álbum', confirm: 'Crear');

/// Pregunta un nombre (con `initial` ya escrito, para cambiarlo). `null` si se cancela.
Future<String?> askName(BuildContext context, {required String title, required String hint, required String confirm, String initial = ''}) =>
    showFocusPanel<String>(context, title: title, builder: (context) => _NameDialog(hint: hint, confirm: confirm, initial: initial));

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.hint, required this.confirm, required this.initial});

  final String hint;
  final String confirm;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.initial)..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusDialog(
      content: TextField(
        key: const Key('folder-name-field'),
        controller: _name,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(key: const Key('folder-create'), style: FilledButton.styleFrom(minimumSize: const Size(0, 40)), onPressed: () => Navigator.of(context).pop(_name.text), child: Text(widget.confirm)),
      ],
    );
  }
}

/// «Mover a…»: deja entrar por las carpetas (desde la raíz), crear una nueva ahí y elegir «Mover aquí».
Future<MoveTarget?> showMoveSheet(BuildContext context, LocalMusicController local, {required int count}) => showFocusPanel<MoveTarget>(context, builder: (context) => _MoveSheet(local: local, count: count),
    );

class _MoveSheet extends StatefulWidget {
  const _MoveSheet({required this.local, required this.count});

  final LocalMusicController local;
  final int count;

  @override
  State<_MoveSheet> createState() => _MoveSheetState();
}

class _MoveSheetState extends State<_MoveSheet> {
  /// Por dónde se ha entrado en esta hoja (vacío = la raíz).
  final List<LocalFolder> _trail = [];
  FolderListing? _listing;
  String? _error;
  bool _loading = true;

  String? get _here => _trail.isEmpty ? null : _trail.last.uri;
  String get _hereName => _trail.isEmpty ? widget.local.folderName : _trail.last.name;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final found = await widget.local.browse(_here);
      if (!mounted) return;
      setState(() {
        _listing = found;
        _loading = false;
      });
    } on TrackSaveException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _newFolder() async {
    final name = await askFolderName(context);
    if (name == null || !mounted) return;
    try {
      await widget.local.createFolder(name, parentUri: _here, parentGiven: true);
      await _load();
    } on TrackSaveException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // solo la raíz y sus carpetas de primer nivel: son los álbumes. Una canción movida más adentro desaparecería de la app
    final folders = _trail.isNotEmpty ? const <LocalFolder>[] : ([...?_listing?.folders]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));
    final sameFolder = _here == widget.local.currentUri;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                widget.count == 1 ? 'Mover 1 canción a…' : 'Mover ${widget.count} canciones a…',
                key: const Key('move-title'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('En: $_hereName', key: const Key('move-here-name'), style: TextStyle(color: c.dim)),
            ),
            Flexible(
              child: _loading
                  ? const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)))
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!, key: const Key('move-error'), style: TextStyle(color: c.warn)),
                        )
                      : GridView(
                          key: const Key('move-grid'),
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 6, crossAxisSpacing: 6, childAspectRatio: 1),
                          children: [
                            if (_trail.isNotEmpty)
                              _MoveTile(
                                key: const Key('move-up'),
                                icon: Icons.arrow_upward_rounded,
                                label: 'Subir',
                                onTap: () {
                                  _trail.removeLast();
                                  unawaited(_load());
                                },
                              ),
                            for (final f in folders)
                              _MoveTile(
                                key: Key('move-folder-${f.name}'),
                                icon: Icons.album_rounded,
                                label: f.name,
                                note: f.count == 1 ? '1 canción' : '${f.count} canciones',
                                onTap: () {
                                  _trail.add(f);
                                  unawaited(_load());
                                },
                              ),
                          ],
                        ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const Key('move-new-folder'),
                        style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                        onPressed: _loading || _error != null || _trail.isNotEmpty ? null : _newFolder,
                        icon: const LcdIcon(Icons.create_new_folder_outlined),
                        label: const Text('Nuevo álbum'),
                      ),
                    ),
                  ),
                  FilledButton(
                    key: const Key('move-here'),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: _loading || _error != null || sameFolder ? null : () => Navigator.of(context).pop(MoveTarget(uri: _here, name: _hereName)),
                    child: Text(sameFolder ? 'Ya están aquí' : 'Mover aquí'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un álbum de la cuadrícula de «Mover a…»: un cuadrado con el icono, el nombre (aquí sí hace falta, para saber adónde va) y cuántas canciones
/// tiene; esquinas rectas y el filo del acento, como la cuadrícula de la música.
class _MoveTile extends StatelessWidget {
  const _MoveTile({super.key, required this.icon, required this.label, required this.onTap, this.note});

  final IconData icon;
  final String label;
  final String? note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.07), border: Border.all(color: c.accent.withValues(alpha: 0.6))),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              LcdIcon(icon, size: 30, color: c.accent),
              const SizedBox(height: 4),
              Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.1, color: c.ink)),
              if (note != null) Text(note!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim)),
            ],
          ),
        ),
      ),
    );
  }
}
