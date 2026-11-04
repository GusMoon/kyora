import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/art_source.dart';
import '../data/audio_engine.dart';
import '../data/audio_levels.dart';
import '../data/background_playback.dart';
import '../data/chat_backend.dart';
import '../data/duration_cache.dart';
import '../data/music_backend.dart';
import '../models/track.dart';

/// El reproductor: la canción que suena, si está sonando, su avance, el aleatorio, y los movimientos básicos (pausa, anterior,
/// siguiente, adelantar). La cola es la lista de canciones de la pantalla de música; se reproducen por internet (con
/// direcciones firmadas de Supabase, válidas 24 h) y siguen sonando con la pantalla apagada.
class PlayerController extends ChangeNotifier {
  PlayerController(
    this._backend,
    this._engine, {
    DateTime Function()? clock,
    DurationCache? durations,
    this.noteAfter = const Duration(seconds: 2),
    ArtSource? art,
    this.levels,
    this.hooks,
  })  : _clock = clock ?? DateTime.now,
        _durations = durations ?? MemoryDurationCache(),
        _art = art // ignore: prefer_initializing_formals
  {
    _art?.addListener(_tell);
    _subscriptions.addAll([
      _engine.index.listen(_onIndex),
      _engine.playing.listen((value) {
        _playing = value;
        _tell();
        _notifyHooks(value);
      }),
      _engine.position.listen((value) {
        position = value;
        _tell();
      }),
      _engine.duration.listen((value) {
        duration = value ?? Duration.zero;
        _tell();
        _scheduleNote();
      }),
      _engine.status.listen(_onStatus),
      _engine.errors.listen((message) {
        error = message;
        loading = false;
        _tell();
      }),
    ]);
  }

  /// Cuánto avanzado tiene que ir una canción para que «anterior» la reinicie en vez de ir a la anterior.
  static const restartAfter = Duration(seconds: 3);

  /// Lo que duran las direcciones firmadas que se piden (y cuánto antes de caducar se vuelven a pedir).
  static const urlLife = Duration(hours: 24);
  static const urlRenewBefore = Duration(hours: 2);

  /// Cuánto espera, después de que el motor diga cuánto dura, para anotarlo: al cambiar de canción el motor puede avisar de la
  /// duración un instante antes que de la canción, y no se debe anotar la de una en la otra.
  final Duration noteAfter;

  /// De dónde se lee qué tan fuerte suena, para los aros del reproductor. Sin esto laten sin más.
  final AudioLevels? levels;

  /// Lo que se mantiene despierto (la red) mientras suena, y el permiso de las notificaciones la primera vez.
  final PlaybackHooks? hooks;

  void _notifyHooks(bool playing) {
    final h = hooks;
    if (h == null) return;
    unawaited((playing ? h.started() : h.stopped()).catchError((Object _) {}));
  }

  final MusicBackend _backend;
  final AudioEngine _engine;
  final DateTime Function() _clock;
  final DurationCache _durations;
  final ArtSource? _art;
  Timer? _noteTimer;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  List<Track> queue = const [];
  Track? current;
  bool _playing = false;
  EngineStatus _status = EngineStatus.idle;
  bool loading = false;
  bool shuffle = false;
  RepeatKind repeat = RepeatKind.off;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  String? error;
  bool _disposed = false;

  final Map<String, String> _urls = {};
  DateTime? _urlsAt;

  /// Suena de verdad: el motor está en marcha y no ha llegado al final de la cola.
  bool get playing => _playing && _status != EngineStatus.completed;

  bool get hasCurrent => current != null;

  /// La carátula de una canción del teléfono (la imagen incrustada en su .mp3), si ya se leyó.
  String? coverFileOf(Track? track) => track == null ? null : _art?.artOf(track);

  /// Pone a sonar `track` con `all` (la lista que se está viendo) como cola.
  Future<void> play(Track track, List<Track> all) async {
    error = null;
    loading = true;
    current = track;
    position = Duration.zero;
    duration = Duration.zero;
    _tell();
    _loadArtAround(track);
    try {
      final remote = [for (final t in all) if (!t.isLocal) t];
      final signed = remote.isEmpty ? const <String, String>{} : await _signedUrls(remote);
      String? addressOf(Track t) => t.isLocal ? t.localUri : signed[t.storagePath];
      final playable = [for (final t in all) if (addressOf(t) != null) t];
      final start = playable.indexWhere((t) => t.id == track.id);
      if (start < 0) throw const ChatException('No se encontró el archivo de esa canción.');
      queue = playable;
      _loadArtAround(track);
      await _engine.setQueue(_items(playable, addressOf), start);
      if (shuffle) await _engine.setShuffle(true);
      if (repeat != RepeatKind.off) await _engine.setRepeat(repeat);
      await _engine.play();
    } on ChatException catch (e) {
      error = e.message;
    } finally {
      loading = false;
      _tell();
    }
  }

  List<QueueItem> _items(List<Track> tracks, String? Function(Track) addressOf) => [
        for (final t in tracks) QueueItem(id: t.id, title: t.title, url: addressOf(t)!, subtitle: t.playlist, artUrl: t.coverUrl),
      ];

  /// Hace `work`, que reescribe el archivo de `track`, sin que el motor lo esté leyendo a la vez: si es la que suena o la que va a sonar,
  /// lo suelta y después sigue por donde iba. Si no, el motor ni se entera.
  Future<T> whileRewriting<T>(Track track, Future<T> Function() work) async {
    final at = queue.indexWhere((t) => t.id == track.id);
    final now = queue.indexWhere((t) => t.id == current?.id);
    if (!track.isLocal || at < 0 || (at != now && at != now + 1 && !shuffle)) return work();
    final wasPlaying = playing;
    final resumeAt = position;
    await _engine.stop();
    try {
      return await work();
    } finally {
      final remote = [for (final t in queue) if (!t.isLocal) t];
      final signed = remote.isEmpty ? const <String, String>{} : await _signedUrls(remote);
      await _engine.setQueue(_items(queue, (t) => t.isLocal ? t.localUri : signed[t.storagePath]), now < 0 ? 0 : now);
      if (shuffle) await _engine.setShuffle(true);
      if (repeat != RepeatKind.off) await _engine.setRepeat(repeat);
      await seek(resumeAt);
      if (wasPlaying) await _engine.play();
    }
  }

  Future<void> toggle() => _playing && _status != EngineStatus.completed ? _engine.pause() : _engine.play();

  /// La siguiente de la cola.
  Future<void> next() => _engine.next();

  /// Si ya sonaron unos segundos (o es la primera), vuelve al principio de esta; si no, la anterior.
  Future<void> previous() async {
    if (position > restartAfter || !await _engine.previous()) await seek(Duration.zero);
  }

  Future<void> seek(Duration to) {
    final limit = duration > Duration.zero && to > duration ? duration : to;
    position = limit < Duration.zero ? Duration.zero : limit;
    _tell();
    return _engine.seek(position);
  }

  Future<void> toggleShuffle() async {
    shuffle = !shuffle;
    _tell();
    if (queue.isNotEmpty) await _engine.setShuffle(shuffle);
  }

  /// Pasa de «sin repetir» a «repetir toda la cola», a «repetir esta» y otra vez a «sin repetir».
  Future<void> cycleRepeat() async {
    repeat = RepeatKind.values[(repeat.index + 1) % RepeatKind.values.length];
    _tell();
    if (queue.isNotEmpty) await _engine.setRepeat(repeat);
  }

  /// Lee la carátula de esta canción y de sus vecinas, para que al pasar a otra ya esté lista.
  void _loadArtAround(Track track) {
    unawaited(_art?.load(track));
    final i = queue.indexWhere((t) => t.id == track.id);
    if (i < 0) return;
    if (i + 1 < queue.length) unawaited(_art?.load(queue[i + 1]));
    if (i > 0) unawaited(_art?.load(queue[i - 1]));
  }

  // ---------- lo que cuenta el motor ----------

  void _onIndex(int? index) {
    if (index != null && index >= 0 && index < queue.length) {
      current = queue[index];
      position = Duration.zero;
      _tell();
      _loadArtAround(current!);
    }
  }

  void _onStatus(EngineStatus status) {
    _status = status;
    if (status == EngineStatus.ready || status == EngineStatus.completed) loading = false;
    _tell();
    // al terminar la cola se queda en pausa, lista para empezar otra vez
    if (status == EngineStatus.completed) unawaited(_engine.pause());
  }

  // ---------- cuánto dura cada canción ----------

  /// Lo que dura una canción, si ya se sabe (la leyó Android de su archivo o la oyó este reproductor).
  Duration? durationOf(Track track) => _durations.of(track.durationKey);

  void _scheduleNote() {
    _noteTimer?.cancel();
    if (duration <= Duration.zero) return;
    if (noteAfter == Duration.zero) {
      unawaited(_note());
    } else {
      _noteTimer = Timer(noteAfter, () => unawaited(_note()));
    }
  }

  Future<void> _note() async {
    final track = current;
    if (track == null || duration <= Duration.zero || _durations.of(track.durationKey) == duration) return;
    await _durations.putAll({track.durationKey: duration});
    _tell(); // las filas de la lista ya pueden enseñarla
  }

  // ---------- direcciones de los archivos ----------

  Future<Map<String, String>> _signedUrls(List<Track> tracks) async {
    final paths = {for (final t in tracks) t.storagePath};
    final at = _urlsAt;
    final fresh = at != null && _clock().difference(at) < urlLife - urlRenewBefore;
    if (!fresh || !paths.every(_urls.containsKey)) {
      final got = await _backend.signedUrls(paths.toList(), urlLife.inSeconds);
      _urls
        ..clear()
        ..addAll(got);
      _urlsAt = _clock();
    }
    return _urls;
  }

  void _tell() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _noteTimer?.cancel();
    _art?.removeListener(_tell);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    if (_playing) _notifyHooks(false); // al soltar el reproductor, lo que mantenía despierto también se suelta
    unawaited(_engine.dispose());
    super.dispose();
  }
}
