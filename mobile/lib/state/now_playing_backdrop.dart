import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../util/cover_tint.dart';

import 'player_controller.dart';

/// La portada de lo que **suena**, para vestir con ella toda la app: mientras una canción suena el fondo pasa a ser su portada y **los colores de la
/// app** (el acento) pasan a ser los de la portada; al pausar o parar vuelve todo a lo de siempre. `source` y `accent` son `null` cuando no hay
/// que cambiar nada.
class NowPlayingBackdrop extends ChangeNotifier {
  PlayerController? _player;
  ({String? file, String? url})? _source;
  bool _disposed = false;

  /// La portada que suena ahora, o `null` si no suena nada (o lo que suena no tiene portada).
  ({String? file, String? url})? get source => _source;

  ValueListenable<Color?>? _tint;

  /// El color de la portada que suena (el acento de la app mientras suena), o `null` si no suena nada o la portada es casi gris.
  Color? get accent => _tint?.value;

  /// Se queda mirando a `player` (o a ninguno). No avisa a quien escucha en el acto: puede llamarse mientras se construye la pantalla.
  void attach(PlayerController? player) {
    if (identical(player, _player)) return;
    _player?.removeListener(_sync);
    _player = player;
    player?.addListener(_sync);
    scheduleMicrotask(_sync);
  }

  void _sync() {
    if (_disposed) return;
    final player = _player;
    final track = player?.current;
    ({String? file, String? url})? next;
    if (player != null && track != null && player.playing) {
      final file = player.coverFileOf(track);
      final url = track.coverUrl;
      if (file != null || url != null) next = (file: file, url: url);
    }
    final old = _source;
    if (old?.file == next?.file && old?.url == next?.url) return;
    _source = next;
    _watchTint(next == null ? null : (next.file ?? next.url));
    notifyListeners();
  }

  /// Escucha el color de la portada (se sabe cuando la portada termina de leerse).
  void _watchTint(String? key) {
    _tint?.removeListener(_tintChanged);
    _tint = key == null ? null : CoverTints.watch(key);
    _tint?.addListener(_tintChanged);
  }

  void _tintChanged() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _tint?.removeListener(_tintChanged);
    _tint = null;
    _player?.removeListener(_sync);
    _player = null;
    super.dispose();
  }
}
