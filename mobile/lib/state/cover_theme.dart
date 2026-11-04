import 'dart:async';

import 'package:flutter/material.dart';

import '../util/cover_color.dart';
import 'player_controller.dart';

/// Cómo se saca el color de una carátula (en las pruebas, uno falso: analizar una imagen de verdad lleva tiempo).
typedef CoverLookup = Future<Color?> Function({String? url, String? file});

/// El color de la carátula de la canción que suena, para que **toda la app** se vista con él (`buildCoverTheme`). `null` mientras nada
/// ha sonado: los colores de siempre. Cuando cambia la canción (o llega su carátula, que en las del teléfono se lee después) se recalcula;
/// una canción sin carátula deja el color de la anterior, y al cerrar sesión se vuelve a los de siempre.
class CoverTheme extends ValueNotifier<Color?> {
  CoverTheme({CoverLookup lookup = coverColor}) : _lookup = lookup, super(null); // ignore: prefer_initializing_formals

  final CoverLookup _lookup;
  PlayerController? _player;
  String? _key;

  /// Empieza a seguir a ese reproductor.
  void attach(PlayerController player) {
    _player?.removeListener(_onPlayer);
    _player = player;
    _key = null;
    player.addListener(_onPlayer);
    unawaited(_onPlayer());
  }

  /// Deja de seguirlo y vuelve a los colores de siempre. Se puede llamar durante una construcción (el cambio se hace justo después).
  void detach() {
    _player?.removeListener(_onPlayer);
    _player = null;
    _key = null;
    if (value != null) scheduleMicrotask(() => value = null);
  }

  Future<void> _onPlayer() async {
    final player = _player;
    final track = player?.current;
    if (player == null || track == null) return;
    final file = player.coverFileOf(track);
    final url = track.coverUrl;
    if (file == null && url == null) return; // sin carátula (todavía): se queda lo que había
    final key = '${track.id}|$file|$url';
    if (key == _key) return;
    _key = key;
    final color = await _lookup(url: url, file: file);
    if (key == _key && _player == player) value = color;
  }

  @override
  void dispose() {
    _player?.removeListener(_onPlayer);
    _player = null;
    super.dispose();
  }
}
