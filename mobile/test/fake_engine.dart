import 'dart:async';

import 'package:kyora_chat/data/audio_engine.dart';
import 'package:kyora_chat/data/audio_levels.dart';

/// La fuerza del sonido de mentira: las pruebas dicen cuánto suena.
class FakeLevels implements AudioLevels {
  final _levels = StreamController<double>.broadcast();
  final _frames = StreamController<SoundFrame>.broadcast();
  int started = 0;
  int stopped = 0;

  void emit(double value) {
    _levels.add(value);
    _frames.add(SoundFrame(level: value));
  }

  /// Un trozo de sonido completo: fuerza, bajos y onda.
  void emitFrame(SoundFrame frame) {
    _levels.add(frame.level);
    _frames.add(frame);
  }

  @override
  Stream<double> get levels => _levels.stream;

  @override
  Stream<SoundFrame> get frames => _frames.stream;

  @override
  Future<bool> start() async {
    started++;
    return true;
  }

  @override
  Future<void> stop() async => stopped++;
}

/// Un motor de audio de mentira: guarda lo que se le pide y deja a las pruebas simular lo que haría el real.
class FakeEngine implements AudioEngine {
  final _index = StreamController<int?>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration?>.broadcast();
  final _status = StreamController<EngineStatus>.broadcast();
  final _errors = StreamController<String>.broadcast();

  List<QueueItem> queue = const [];
  int startIndex = -1;
  int at = -1;
  bool isPlaying = false;
  bool shuffle = false;
  RepeatKind repeat = RepeatKind.off;
  bool disposed = false;
  final List<Duration> seeks = [];
  final List<String> calls = [];

  @override
  Stream<int?> get index => _index.stream;
  @override
  Stream<bool> get playing => _playing.stream;
  @override
  Stream<Duration> get position => _position.stream;
  @override
  Stream<Duration?> get duration => _duration.stream;
  @override
  Stream<EngineStatus> get status => _status.stream;
  @override
  Stream<String> get errors => _errors.stream;

  @override
  Future<void> setQueue(List<QueueItem> items, int start) async {
    calls.add('setQueue:$start');
    queue = items;
    startIndex = start;
    at = start;
    _index.add(start);
    _status.add(EngineStatus.ready);
    _duration.add(const Duration(minutes: 3));
  }

  @override
  Future<void> play() async {
    calls.add('play');
    isPlaying = true;
    _playing.add(true);
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    isPlaying = false;
    _playing.add(false);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    isPlaying = false;
    _playing.add(false);
  }

  @override
  Future<void> next() async {
    calls.add('next');
    if (at + 1 < queue.length) {
      at++;
      _index.add(at);
    }
  }

  @override
  Future<bool> previous() async {
    calls.add('previous');
    if (at <= 0) return false;
    at--;
    _index.add(at);
    return true;
  }

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek');
    seeks.add(position);
  }

  @override
  Future<void> setShuffle(bool on) async {
    calls.add('shuffle:$on');
    shuffle = on;
  }

  @override
  Future<void> setRepeat(RepeatKind mode) async {
    calls.add('repeat:${mode.name}');
    repeat = mode;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  // ---------- lo que haría el motor real ----------

  void emitPosition(Duration value) => _position.add(value);
  void emitStatus(EngineStatus value) => _status.add(value);
  void emitError(String message) => _errors.add(message);
  void emitDuration(Duration? value) => _duration.add(value);
  void emitIndex(int value) {
    at = value;
    _index.add(value);
  }
}
