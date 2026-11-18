import 'package:flutter/material.dart';

import '../state/local_music_controller.dart';
import 'album_options.dart' as options;
import 'album_options.dart' show AlbumDeletion;
import 'move_sheet.dart' as sheet;
import 'move_sheet.dart' show MoveTarget;
import 'music_actions.dart';

/// Las preguntas de las acciones de música en KyraAdmin: sus paneles de siempre (`move_sheet.dart`, `album_options.dart`) y los avisos en
/// la barra de abajo.
class AdminMusicDialogs implements MusicDialogs {
  AdminMusicDialogs(this._state) : _messenger = ScaffoldMessenger.maybeOf(_state.context);

  final State _state;
  final ScaffoldMessengerState? _messenger;

  BuildContext get _context => _state.context;

  @override
  bool get alive => _state.mounted;

  @override
  Future<String?> askName({required String title, required String hint, required String confirm, String initial = ''}) =>
      sheet.askName(_context, title: title, hint: hint, confirm: confirm, initial: initial);

  @override
  Future<bool> confirmDeleteSongs({required String title, required int count}) => options.confirmDeleteAlbum(_context, title: title, count: count);

  @override
  Future<bool> confirmDeleteSong({required String title}) => options.confirmDeleteSong(_context, title: title);

  @override
  Future<bool> confirmDeleteEmptyAlbum({required String title}) => options.confirmDeleteEmptyAlbum(_context, title: title);

  @override
  Future<AlbumDeletion?> askDeleteAlbum({required String title, required int count}) => options.askDeleteAlbum(_context, title: title, count: count);

  @override
  Future<MoveTarget?> pickMoveTarget(LocalMusicController local, {required int count}) => sheet.showMoveSheet(_context, local, count: count);

  @override
  void notify(String text) => _messenger?.showSnackBar(SnackBar(content: Text(text)));
}
