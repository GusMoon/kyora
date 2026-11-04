import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/chat_backend.dart';
import '../data/music_backend.dart';
import '../data/music_store.dart';
import '../models/track.dart';

enum TrackState { pending, saving, saved, failed }

/// La música que llega de la PC: la lista de canciones, cuáles ya están en el teléfono y su guardado.
///
/// Con la app abierta escucha a Supabase (Realtime): cuando la PC sube una canción nueva y `auto` está encendido, la baja y la
/// deja en la carpeta elegida sin que hagas nada. Las canciones anteriores a la primera vez que se abrió la app (o a
/// encender `auto`) quedan pendientes: se guardan a mano, una por una o todas juntas.
class MusicController extends ChangeNotifier {
  MusicController(this._backend, this._store, this._saver);

  final MusicBackend _backend;
  final MusicStore _store;
  final TrackSaver _saver;

  List<Track> tracks = const [];
  MusicSettings settings = const MusicSettings();
  String? error;
  bool loading = true;

  final Set<String> _saved = {};
  final Set<String> _saving = {};
  final Set<String> _confirming = {};
  final Map<String, String> _failed = {};
  DateTime? _autoSince;
  StreamSubscription<void>? _changes;
  bool _refreshing = false;
  bool _disposed = false;
  final _notices = StreamController<String>.broadcast();

  /// Avisos cortos (por ejemplo, «Guardada en Música/Kyora: …»): salen como una barra inferior.
  Stream<String> get notices => _notices.stream;

  Future<void> start() async {
    settings = await _store.loadSettings();
    _saved.addAll(await _store.loadSaved());
    _autoSince = await _store.autoSince();
    _changes = _backend.trackChanges().listen((_) => unawaited(refresh()), onError: (Object e) {
      error = e.toString();
      _tell();
    });
    await refresh();
  }

  TrackState stateOf(Track track) {
    if (_saving.contains(track.id)) return TrackState.saving;
    if (_saved.contains(track.id)) return TrackState.saved;
    if (_failed.containsKey(track.id)) return TrackState.failed;
    return TrackState.pending;
  }

  String? failureOf(Track track) => _failed[track.id];

  /// Cuántas canciones ya están guardadas en el teléfono.
  int get savedCount => _saved.length;

  int get pendingCount => tracks.where((t) => stateOf(t) == TrackState.pending || stateOf(t) == TrackState.failed).length;

  /// Vuelve a pedir la lista y, si toca, guarda solas las canciones nuevas.
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      tracks = await _backend.listTracks();
      error = null;
    } on ChatException catch (e) {
      error = e.message;
    } finally {
      _refreshing = false;
      loading = false;
      _tell();
    }
    if (settings.auto && error == null) await _saveNew();
  }

  Future<void> _saveNew() async {
    final since = _autoSince;
    for (final track in tracks) {
      if (_disposed) return;
      final fresh = since == null || !track.createdAt.isBefore(since);
      if (fresh && stateOf(track) == TrackState.pending) await save(track, quiet: true);
    }
  }

  /// Baja una canción y la deja en la carpeta elegida.
  /// Lo que se le hace a una canción antes de dejarla en el teléfono (ponerle la imagen que le hayas elegido).
  Future<Uint8List> Function(Track track, Uint8List bytes)? prepareForSaving;

  Future<void> save(Track track, {bool quiet = false}) async {
    if (_saving.contains(track.id) || _saved.contains(track.id)) return;
    _saving.add(track.id);
    _failed.remove(track.id);
    _tell();
    try {
      final downloaded = await _backend.downloadTrack(track.storagePath);
      final bytes = await prepareForSaving?.call(track, downloaded) ?? downloaded;
      final where = await _saver.save(
        fileName: track.fileName,
        bytes: bytes,
        base: settings.base,
        folder: settings.folder,
        treeUri: settings.treeUri,
      );
      _saved.add(track.id);
      await _store.markSaved(track.id);
      if (!_disposed) _notices.add('Guardada en $where: ${track.title}');
    } on ChatException catch (e) {
      _failed[track.id] = e.message;
      if (!quiet && !_disposed) _notices.add(e.message);
    } on TrackSaveException catch (e) {
      _failed[track.id] = e.message;
      if (!quiet && !_disposed) _notices.add(e.message);
    } finally {
      _saving.remove(track.id);
      _tell();
    }
  }

  /// ¿Ya confirmaste con «Recibido» esta canción?
  bool isReceived(Track track) => track.receivedAt != null;

  /// ¿Se está confirmando ahora mismo?
  bool isConfirming(Track track) => _confirming.contains(track.id);

  /// «Recibido»: avisa a Supabase de que la canción ya está guardada en este teléfono. Si todavía no lo está, la guarda primero; y
  /// si no se puede guardar, **no** avisa (Supabase no borra nada sin esta confirmación). `true` si quedó confirmada.
  Future<bool> confirmReceived(Track track) async {
    if (isReceived(track)) return true;
    if (_confirming.contains(track.id)) return false;
    _confirming.add(track.id);
    _tell();
    try {
      if (stateOf(track) == TrackState.saving) {
        if (!_disposed) _notices.add('Espera a que termine de guardarse.');
        return false;
      }
      if (stateOf(track) != TrackState.saved) await save(track);
      if (stateOf(track) != TrackState.saved) return false; // no se pudo guardar: el motivo ya salió como aviso
      await _backend.confirmReceived(track.id);
      final at = DateTime.now().toUtc();
      tracks = [for (final t in tracks) t.id == track.id ? t.withReceived(at) : t];
      if (!_disposed) _notices.add('Recibida: ${track.title}');
      return true;
    } on ChatException catch (e) {
      if (!_disposed) _notices.add(e.message);
      return false;
    } finally {
      _confirming.remove(track.id);
      _tell();
    }
  }

  /// «Guardar todas»: las pendientes y las que fallaron, una detrás de otra.
  Future<void> saveAll() async {
    for (final track in List.of(tracks)) {
      if (_disposed) return;
      final state = stateOf(track);
      if (state == TrackState.pending || state == TrackState.failed) await save(track);
    }
  }

  /// Abre el selector de carpetas de Android (lo usa la hoja de ajustes). `null` si no se eligió ninguna.
  Future<PickedFolder?> pickFolder() => _saver.pickFolder();

  Future<void> updateSettings(MusicSettings next) async {
    final turnedOn = next.auto && !settings.auto;
    settings = next;
    await _store.saveSettings(next);
    if (turnedOn) _autoSince = DateTime.now().toUtc(); // encender «guardar solas»: cuenta desde ahora, no toda la biblioteca
    _tell();
    if (turnedOn && error == null) await _saveNew();
  }

  void _tell() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_changes?.cancel());
    unawaited(_notices.close());
    super.dispose();
  }
}
