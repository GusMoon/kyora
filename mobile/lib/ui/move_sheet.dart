import 'dart:async';

import 'package:flutter/material.dart';

import '../data/music_store.dart';
import '../models/track.dart';
import '../state/local_music_controller.dart';
import '../theme.dart';

/// Adónde se van a mover las canciones: una carpeta (`uri` `null` = la raíz elegida) y su nombre, para avisar.
class MoveTarget {
  const MoveTarget({required this.uri, required this.name});

  final String? uri;
  final String name;
}

/// Pregunta el nombre de un álbum (carpeta) nuevo. `null` si se cancela.
Future<String?> askFolderName(BuildContext context) => showDialog<String>(
      context: context,
      builder: (context) => const _FolderNameDialog(),
    );

class _FolderNameDialog extends StatefulWidget {
  const _FolderNameDialog();

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo álbum'),
      content: TextField(
        key: const Key('folder-name-field'),
        controller: _name,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Nombre del álbum'),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(key: const Key('folder-create'), style: FilledButton.styleFrom(minimumSize: const Size(0, 40)), onPressed: () => Navigator.of(context).pop(_name.text), child: const Text('Crear')),
      ],
    );
  }
}

/// «Mover a…»: deja entrar por las carpetas (desde la raíz), crear una nueva ahí y elegir «Mover aquí».
Future<MoveTarget?> showMoveSheet(BuildContext context, LocalMusicController local, {required int count}) => showModalBottomSheet<MoveTarget>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _MoveSheet(local: local, count: count),
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
    final folders = [...?_listing?.folders]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            if (_trail.isNotEmpty)
                              ListTile(
                                key: const Key('move-up'),
                                leading: const Icon(Icons.arrow_upward_rounded),
                                title: const Text('Subir'),
                                onTap: () {
                                  _trail.removeLast();
                                  unawaited(_load());
                                },
                              ),
                            for (final f in folders)
                              ListTile(
                                key: Key('move-folder-${f.name}'),
                                leading: Icon(Icons.folder_rounded, color: c.accent),
                                title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(f.count == 1 ? '1 canción' : '${f.count} canciones', style: TextStyle(color: c.dim)),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  _trail.add(f);
                                  unawaited(_load());
                                },
                              ),
                            if (folders.isEmpty && _trail.isNotEmpty)
                              Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 8), child: Text('No hay más álbumes aquí.', style: TextStyle(color: c.dim))),
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
                        onPressed: _loading || _error != null ? null : _newFolder,
                        icon: const Icon(Icons.create_new_folder_outlined),
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
