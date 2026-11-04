import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'audio_engine.dart';

/// El motor real: `just_audio`, con la notificación y los controles de la pantalla de bloqueo (`just_audio_background`).
class JustAudioEngine implements AudioEngine {
  JustAudioEngine()
      : _player = AudioPlayer(
          // Más búfer por delante: con la pantalla apagada la red puede quedarse un rato sin dar datos y la canción no se corta.
          audioLoadConfiguration: const AudioLoadConfiguration(
            androidLoadControl: AndroidLoadControl(
              minBufferDuration: Duration(seconds: 60),
              maxBufferDuration: Duration(seconds: 180),
              bufferForPlaybackAfterRebufferDuration: Duration(seconds: 6),
            ),
          ),
        );

  final AudioPlayer _player;
  final _errors = StreamController<String>.broadcast();

  @override
  Stream<int?> get index => _player.currentIndexStream;

  @override
  Stream<bool> get playing => _player.playingStream;

  @override
  Stream<Duration> get position => _player.positionStream;

  @override
  Stream<Duration?> get duration => _player.durationStream;

  @override
  Stream<EngineStatus> get status => _player.processingStateStream.map((state) => switch (state) {
        ProcessingState.idle => EngineStatus.idle,
        ProcessingState.loading => EngineStatus.loading,
        ProcessingState.buffering => EngineStatus.buffering,
        ProcessingState.ready => EngineStatus.ready,
        ProcessingState.completed => EngineStatus.completed,
      });

  @override
  Stream<String> get errors => _errors.stream;

  @override
  Future<void> setQueue(List<QueueItem> items, int startIndex) async {
    try {
      await _player.setAudioSources(
        [
          for (final item in items)
            AudioSource.uri(
              Uri.parse(item.url),
              tag: MediaItem(
                id: item.id,
                title: item.title,
                album: item.subtitle,
                artUri: item.artUrl == null ? null : Uri.tryParse(item.artUrl!),
              ),
            ),
        ],
        initialIndex: startIndex,
      );
    } on PlayerInterruptedException {
      // otra canción se pidió mientras esta cargaba: la última manda
    } on PlayerException catch (e) {
      _errors.add(_explain(e));
    }
  }

  @override
  Future<void> play() async {
    try {
      await _player.play();
    } on PlayerException catch (e) {
      _errors.add(_explain(e));
    }
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> next() => _player.seekToNext();

  @override
  Future<bool> previous() async {
    if (!_player.hasPrevious) return false;
    await _player.seekToPrevious();
    return true;
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setShuffle(bool on) async {
    await _player.setShuffleModeEnabled(on);
    if (on) await _player.shuffle();
  }

  @override
  Future<void> setRepeat(RepeatKind mode) => _player.setLoopMode(switch (mode) {
        RepeatKind.off => LoopMode.off,
        RepeatKind.all => LoopMode.all,
        RepeatKind.one => LoopMode.one,
      });

  @override
  Future<void> dispose() async {
    await _player.dispose();
    await _errors.close();
  }

  String _explain(PlayerException e) {
    final text = (e.message ?? '').toLowerCase();
    if (text.contains('403') || text.contains('expired') || text.contains('forbidden')) {
      return 'El enlace de la canción caducó: vuelve a tocarla.';
    }
    if (text.contains('source error') || text.contains('unable to connect') || text.contains('timeout')) {
      return 'No se pudo reproducir: revisa tu conexión.';
    }
    return 'No se pudo reproducir esta canción.';
  }
}
