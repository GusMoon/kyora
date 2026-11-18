import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/music_store.dart';
import '../../models/track.dart';
import '../../state/local_music_controller.dart';
import '../album_options.dart' show AlbumDeletion;
import '../move_sheet.dart' show MoveTarget;
import '../music_actions.dart';
import 'neo_dialogs.dart';
import 'neo_theme.dart';
import 'neo_widgets.dart';

/// Las preguntas de las acciones de música en KyraFamily, con los cuadros y hojas del diseño cyber-brutalista.
class NeoMusicDialogs implements MusicDialogs {
  NeoMusicDialogs(this._state) : _messenger = ScaffoldMessenger.maybeOf(_state.context);

  final State _state;
  final ScaffoldMessengerState? _messenger;

  BuildContext get _context => _state.context;

  @override
  bool get alive => _state.mounted;

  @override
  Future<String?> askName({required String title, required String hint, required String confirm, String initial = ''}) =>
      neoAskText(_context, title: title, hint: hint, confirm: confirm, initial: initial);

  @override
  Future<bool> confirmDeleteSongs({required String title, required int count}) => neoConfirm(
        _context,
        title: 'Borrar canciones',
        text: '¿Borrar ${count == 1 ? 'la canción' : 'las $count canciones'} de «$title» del teléfono? No se puede deshacer.',
        confirm: 'Borrar',
      );

  @override
  Future<bool> confirmDeleteSong({required String title}) =>
      neoConfirm(_context, title: 'Borrar canción', text: '¿Borrar «$title» del teléfono? No se puede deshacer.', confirm: 'Borrar');

  @override
  Future<bool> confirmDeleteEmptyAlbum({required String title}) =>
      neoConfirm(_context, title: 'Borrar álbum', text: '¿Borrar el álbum «$title»? No se puede deshacer.', confirm: 'Borrar');

  @override
  Future<AlbumDeletion?> askDeleteAlbum({required String title, required int count}) => showDialog<AlbumDeletion>(
        context: _context,
        builder: (context) => NeoDialog(
          title: 'Borrar álbum',
          actions: [
            NeoButton(
              key: const Key('neo-album-move-first'),
              label: 'Pasarlas a otro álbum',
              icon: Icons.drive_file_move_outlined,
              onTap: () => Navigator.of(context).pop(AlbumDeletion.moveFirst),
            ),
            NeoButton(
              key: const Key('neo-album-delete-all'),
              label: 'Borrar todo',
              danger: true,
              icon: Icons.delete_outline_rounded,
              onTap: () => Navigator.of(context).pop(AlbumDeletion.deleteAll),
            ),
            NeoButton(key: const Key('neo-cancel'), label: 'Cancelar', icon: Icons.close_rounded, color: context.neo.paper, onTap: () => Navigator.of(context).pop()),
          ],
          child: Text(
            '«$title» tiene ${count == 1 ? '1 canción' : '$count canciones'}. Pásalas a otro álbum; si no, se borrarán junto con el álbum y no se puede deshacer.',
            style: neoBody(color: context.neo.ink),
          ),
        ),
      );

  @override
  Future<MoveTarget?> pickMoveTarget(LocalMusicController local, {required int count}) => showModalBottomSheet<MoveTarget>(
        context: _context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => _NeoMoveSheet(local: local, count: count),
      );

  @override
  void notify(String text) {
    _messenger?.hideCurrentSnackBar();
    _messenger?.showSnackBar(SnackBar(content: Text(text)));
  }
}

/// Elegir adónde mover: se recorren las carpetas (entrar, volver) y se puede crear una nueva ahí; «Mover aquí» elige la carpeta en que se está.
class _NeoMoveSheet extends StatefulWidget {
  const _NeoMoveSheet({required this.local, required this.count});

  final LocalMusicController local;
  final int count;

  @override
  State<_NeoMoveSheet> createState() => _NeoMoveSheetState();
}

class _NeoMoveSheetState extends State<_NeoMoveSheet> {
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
      if (mounted) {
        setState(() {
          _listing = found;
          _loading = false;
        });
      }
    } on TrackSaveException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  Future<void> _newFolder() async {
    final name = await neoAskText(context, title: 'Nuevo álbum', hint: 'Nombre del álbum', confirm: 'Crear');
    if (name == null || !mounted) return;
    try {
      await widget.local.createFolder(name, parentUri: _here, parentGiven: true);
      await _load();
    } on TrackSaveException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.neo;
    final folders = _listing?.folders ?? const <LocalFolder>[];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'MOVER ${widget.count == 1 ? '1 CANCIÓN' : '${widget.count} CANCIONES'} A…',
                style: neoLabel(size: 12, color: s.dim),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (_trail.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: NeoIconButton(
                        key: const Key('neo-move-up'),
                        icon: Icons.arrow_back_rounded,
                        size: 36,
                        tooltip: 'Volver',
                        onTap: () {
                          _trail.removeLast();
                          unawaited(_load());
                        },
                      ),
                    ),
                  Expanded(child: Text(_hereName.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: neoHeading(size: 22, color: s.ink))),
                ],
              ),
              const SizedBox(height: 10),
              if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: NeoNotice(_error!)),
              Flexible(
                child: _loading
                    ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 3)))
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final f in folders)
                            InkWell(
                              key: Key('neo-move-folder-${f.name}'),
                              onTap: () {
                                _trail.add(f);
                                unawaited(_load());
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                decoration: BoxDecoration(border: Border(top: BorderSide(color: s.line, width: Neo.border))),
                                child: Row(
                                  children: [
                                    Icon(Icons.folder_outlined, size: 20, color: s.ink),
                                    const SizedBox(width: 12),
                                    Expanded(child: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: neoBody(color: s.ink, weight: FontWeight.w700))),
                                    Icon(Icons.chevron_right_rounded, color: s.dim),
                                  ],
                                ),
                              ),
                            ),
                          if (folders.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('Aquí no hay más carpetas.', style: neoBody(color: s.dim))),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              NeoButton(key: const Key('neo-move-new'), label: 'Nuevo álbum aquí', icon: Icons.create_new_folder_outlined, color: s.paper, onTap: () => unawaited(_newFolder())),
              const SizedBox(height: 10),
              NeoButton(
                key: const Key('neo-move-here'),
                label: 'Mover aquí',
                icon: Icons.drive_file_move_outlined,
                onTap: () => Navigator.of(context).pop(MoveTarget(uri: _here, name: _hereName)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
