import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/art_source.dart';
import '../data/cover_store.dart';
import '../data/duration_cache.dart';
import '../data/music_store.dart';
import '../models/track.dart';
import 'music_controller.dart';

/// Los .mp3 y las subcarpetas que hay en la carpeta que elegiste en el teléfono, para verlos, reproducirlos y organizarlos: se entra
/// en las subcarpetas, se crean carpetas nuevas y se mueven canciones (una o varias) de verdad en el almacenamiento. Se vuelve a leer
/// sola cuando cambias de carpeta o cuando se guarda una canción nueva, y a mano con «tirar para actualizar».
class LocalMusicController extends ChangeNotifier implements ArtSource {
  LocalMusicController(this._music, this._saver, {DurationCache? durations, CoverStore? covers})
      : _durations = durations ?? MemoryDurationCache(),
        _coverStore = covers ?? MemoryCoverStore(),
        _covers = (covers ?? MemoryCoverStore()).load() {
    _music.addListener(_onMusicChanged);
    _signature = _signatureNow();
  }

  /// Cuántos archivos se le preguntan a Android de una vez: la lista va apareciendo con sus duraciones sin esperar a todas.
  static const durationBatch = 20;

  final MusicController _music;
  final TrackSaver _saver;
  final DurationCache _durations;
  final CoverStore _coverStore;

  /// La imagen elegida para cada álbum (`album:<id>`), recordada en este teléfono.
  final Map<String, String> _covers;

  /// Las canciones y las subcarpetas de la carpeta en que se está (la raíz elegida o una de las que se entró).
  List<Track> songs = const [];
  List<LocalFolder> folders = const [];
  bool loading = false;

  /// Lo que hay en la raíz, para las tarjetas (no cambia al entrar en una subcarpeta).
  List<LocalFolder> rootFolders = const [];
  int rootSongCount = 0;

  /// Las subcarpetas por las que se entró desde la raíz (vacío = se está en la raíz).
  final List<LocalFolder> path = [];
  final Set<String> _selected = {};

  /// Lo que ya se leyó de cada carpeta (por su dirección; la raíz es ''). Al entrar en una carpeta ya leída se enseña al instante y
  /// se vuelve a leer en silencio por si cambió; las subcarpetas de la que se mira se leen por adelantado.
  final Map<String, FolderListing> _listings = {};
  String? _shown;
  int _prefetchRound = 0;

  /// Cuántas subcarpetas se leen por adelantado.
  static const prefetchLimit = 40;

  /// El motivo por el que no se pudo leer la carpeta (ya explicado en español), o `null`.
  String? error;

  /// `true` si el error es que la carpeta ya no sirve y hay que elegirla otra vez.
  bool folderLost = false;

  String? _tree;
  late String _signature;

  /// Las carpetas que se están leyendo ahora mismo. Cada una va por su lado: la que acabas de tocar no espera a las demás.
  final Set<String> _reading = {};
  bool _again = false;
  bool _disposed = false;
  int _round = 0;
  final Map<String, String> _art = {};

  /// A qué álbum pertenece cada .mp3 leído (por su dirección) y la imagen de cada álbum ya calculada (se borra con cada cambio).
  final Map<String, String> _albumByUri = {};
  final Map<String, String?> _albumArt = {};

  bool get hasFolder => _music.settings.hasTree;

  bool get atRoot => path.isEmpty;

  /// La dirección de la carpeta en que se está, o `null` si es la raíz.
  String? get currentUri => path.isEmpty ? null : path.last.uri;

  /// Hay canciones marcadas (modo selección).
  bool get selecting => _selected.isNotEmpty;
  int get selectedCount => _selected.length;
  bool isSelected(Track track) => _selected.contains(track.localUri);
  List<Track> get selectedSongs => [for (final t in songs) if (_selected.contains(t.localUri)) t];

  /// El nombre de la carpeta elegida, para enseñarlo.
  String get folderName => _music.settings.where;

  String _signatureNow() => '${_music.settings.treeUri}|${_music.savedCount}';

  void _onMusicChanged() {
    final now = _signatureNow();
    if (now == _signature) return;
    _signature = now;
    if (_tree != _music.settings.treeUri) {
      _tree = _music.settings.treeUri;
      path.clear(); // otra carpeta elegida: se vuelve a la raíz
      _selected.clear();
      _listings.clear();
      _albumByUri.clear();
      _shown = null;
      rootFolders = const [];
      rootSongCount = 0;
    } else {
      _listings.remove(''); // se guardó una canción: va a la raíz
    }
    _present();
    unawaited(refresh());
  }

  // ---------- moverse y marcar ----------

  /// Entra en una subcarpeta.
  Future<void> open(LocalFolder folder) {
    path.add(folder);
    _selected.clear();
    _present();
    return refresh();
  }

  /// Vuelve a la carpeta de antes (si se estaba en una subcarpeta).
  Future<void> up() {
    if (path.isEmpty) return Future.value();
    path.removeLast();
    _selected.clear();
    _present();
    return refresh();
  }

  /// Vuelve a la carpeta del lugar `depth` de la ruta (0 = la raíz).
  Future<void> goTo(int depth) {
    if (depth >= path.length) return Future.value();
    path.removeRange(depth, path.length);
    _selected.clear();
    _present();
    return refresh();
  }

  /// El botón «atrás»: primero quita la selección y luego sube de carpeta. `false` si no había nada que deshacer.
  bool back() {
    if (selecting) {
      clearSelection();
      return true;
    }
    if (path.isNotEmpty) {
      unawaited(up());
      return true;
    }
    return false;
  }

  void toggleSelect(Track track) {
    final uri = track.localUri;
    if (uri == null) return;
    if (!_selected.remove(uri)) _selected.add(uri);
    _tell();
  }

  void selectAll() {
    _selected
      ..clear()
      ..addAll([for (final t in songs) t.localUri!]);
    _tell();
  }

  void clearSelection() {
    if (_selected.isEmpty) return;
    _selected.clear();
    _tell();
  }

  // ---------- crear y mover (cambios reales en el almacenamiento) ----------

  /// Lo que hay dentro de otra carpeta (para elegir adónde mover), sin cambiar en la que se está. `dirUri` `null` = la raíz.
  Future<FolderListing> browse(String? dirUri) {
    final tree = _music.settings.treeUri;
    if (tree == null || tree.isEmpty) throw const TrackSaveException('Primero elige una carpeta.');
    return _saver.listDir(tree, dirUri: dirUri);
  }

  /// Crea una carpeta nueva dentro de `parentUri` (sin él, la carpeta en que se está). Lanza `TrackSaveException` con el motivo.
  Future<LocalFolder> createFolder(String name, {String? parentUri, bool parentGiven = false}) async {
    final tree = _music.settings.treeUri;
    if (tree == null || tree.isEmpty) throw const TrackSaveException('Primero elige una carpeta.');
    final clean = name.trim();
    if (clean.isEmpty) throw const TrackSaveException('Escribe un nombre para la carpeta.');
    if (clean.contains('/') || clean.contains('\\')) throw const TrackSaveException('El nombre no puede llevar «/» ni «\\».');
    final parent = parentGiven ? parentUri : currentUri;
    final created = await _saver.createFolder(tree, parentUri: parent, name: clean);
    _listings.remove(parent ?? '');
    _prefetchRound++;
    if (parent == currentUri) await refresh();
    return created;
  }

  /// Mueve las canciones marcadas a `toUri` (`null` = la raíz). Quita la selección y vuelve a leer la carpeta.
  Future<MoveResult> moveSelected({required String? toUri}) => move(selectedSongs, toUri: toUri);

  Future<MoveResult> move(List<Track> songsToMove, {required String? toUri}) async {
    final tree = _music.settings.treeUri;
    if (tree == null || tree.isEmpty) throw const TrackSaveException('Primero elige una carpeta.');
    if (toUri == currentUri) throw const TrackSaveException('Ya están en esa carpeta.');
    if (songsToMove.isEmpty) return const MoveResult(moved: 0);
    try {
      return await _saver.moveSongs(tree, uris: [for (final t in songsToMove) t.localUri!], fromUri: currentUri, toUri: toUri);
    } finally {
      _selected.clear();
      _listings
        ..remove(currentUri ?? '')
        ..remove(toUri ?? '');
      _prefetchRound++;
      await refresh(); // se vea lo que quedó, haya salido bien o a medias
    }
  }

  /// Vuelve a leer la carpeta. Sin carpeta elegida no hay nada que leer.
  Future<void> refresh() async {
    final tree = _music.settings.treeUri;
    _tree = tree;
    if (tree == null || tree.isEmpty) {
      songs = const [];
      folders = const [];
      path.clear();
      _selected.clear();
      _listings.clear();
      _albumByUri.clear();
      _shown = null;
      rootFolders = const [];
      rootSongCount = 0;
      error = null;
      folderLost = false;
      loading = false;
      _tell();
      return;
    }
    final key = currentUri ?? '';
    _present();
    if (!_reading.add(key)) {
      _again = true; // ya se está leyendo esta misma: se lee de nuevo al terminar
      return;
    }
    if (_shown != key || (songs.isEmpty && folders.isEmpty)) loading = true; // sin nada que enseñar todavía: se nota que carga
    _tell();
    FolderListing? found;
    try {
      found = await _saver.listDir(tree, dirUri: currentUri);
      _store(key, found);
      if (key == (currentUri ?? '')) {
        _apply(found, key);
        error = null;
        folderLost = false;
      }
    } on TrackSaveException catch (e) {
      if (key == (currentUri ?? '')) {
        songs = const [];
        folders = const [];
        _shown = key;
        error = e.message;
        folderLost = e.folderLost;
      }
    } finally {
      _reading.remove(key);
      if (key == (currentUri ?? '')) loading = false;
      _tell();
    }
    if (key != (currentUri ?? '')) return; // ya se está en otra carpeta, que tiene su propia lectura
    if (_again) {
      _again = false;
      await refresh(); // mientras leía se pidió volver a leerla
    } else {
      unawaited(_fillDurations());
      if (found != null) unawaited(_prefetch(tree, found.folders));
    }
  }

  /// Guarda lo leído de una carpeta y recuerda a qué álbum pertenece cada una de sus canciones.
  void _store(String key, FolderListing listing) {
    _listings[key] = listing;
    final album = key.isEmpty ? 'root' : key;
    for (final song in listing.songs) {
      _albumByUri[song.uri] = album;
    }
  }

  /// Enseña ya lo que se sabe de la carpeta actual (lo leído antes) o, si no se sabe nada, la deja vacía mientras carga: así al
  /// navegar nunca se ve la lista de la carpeta anterior.
  void _present() {
    final key = currentUri ?? '';
    if (_shown == key) return;
    final cached = _listings[key];
    if (cached != null) {
      _apply(cached, key);
    } else {
      songs = const [];
      folders = const [];
      _shown = key;
      loading = true;
    }
    error = null;
    folderLost = false;
    _tell();
  }

  void _apply(FolderListing listing, String key) {
    songs = [for (final song in listing.songs) Track.local(song)]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    folders = [...listing.folders]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _selected.removeWhere((uri) => !songs.any((t) => t.localUri == uri)); // lo marcado que ya no está ahí
    _shown = key;
    if (key.isEmpty) {
      rootFolders = folders;
      rootSongCount = songs.length;
    }
  }

  /// Las canciones de una carpeta (`null` = la raíz) si ya se leyó, en orden. Para poder reproducirla sin entrar en ella.
  List<Track>? tracksIn(String? dirUri) {
    final listing = _listings[dirUri ?? ''];
    if (listing == null) return null;
    return [for (final song in listing.songs) Track.local(song)]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  /// Las subcarpetas de una carpeta (`null` = la raíz) si ya se leyó, por orden alfabético. Las de «subálbumes» de un álbum.
  List<LocalFolder>? foldersIn(String? dirUri) {
    final listing = _listings[dirUri ?? ''];
    if (listing == null) return null;
    return [...listing.folders]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Todas las canciones de las carpetas que ya se leyeron (la raíz y las subcarpetas leídas por adelantado), sin repetir y por orden
  /// alfabético. Para «Favoritos»: solo salen las de álbumes ya leídos.
  List<Track> knownTracks() {
    final seen = <String>{};
    final all = <Track>[];
    for (final listing in _listings.values) {
      for (final song in listing.songs) {
        final track = Track.local(song);
        if (seen.add(track.id)) all.add(track);
      }
    }
    return all..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  /// Lee por adelantado, de a una y en silencio, las subcarpetas de la que se mira: al entrar ya están.
  Future<void> _prefetch(String tree, List<LocalFolder> subs) async {
    final token = ++_prefetchRound;
    for (final f in subs.take(prefetchLimit)) {
      if (_disposed || token != _prefetchRound || tree != _music.settings.treeUri) return;
      if (_listings.containsKey(f.uri)) continue;
      try {
        final read = await _saver.listDir(tree, dirUri: f.uri);
        if (token != _prefetchRound) return;
        _store(f.uri, read);
      } catch (_) {
        return;
      }
    }
  }

  /// La carátula que se ve en una canción: **la de su álbum** (ya no hay una por canción). Es la imagen que elegiste para el álbum o, si
  /// no le pusiste ninguna, la incrustada de la primera de sus canciones que la traiga. `null` si el álbum no tiene ninguna (las canciones
  /// enviadas entonces enseñan la suya de internet).
  @override
  String? artOf(Track track) {
    final album = albumArt(albumIdOf(track));
    if (album != null || !track.isLocal) return album;
    final own = _art[track.localUri]; // el álbum aún no se leyó: la suya
    return own == null || own.isEmpty ? null : own;
  }

  /// El álbum al que pertenece una canción: `received` (las enviadas), `root` (la carpeta elegida) o la dirección de su carpeta.
  String albumIdOf(Track track) {
    if (!track.isLocal) return 'received';
    return _albumByUri[track.localUri] ?? 'root';
  }

  /// La imagen de un álbum (ver [artOf]); `albumId` es `received`, `root` o la dirección de la carpeta.
  String? albumArt(String albumId) {
    if (_albumArt.containsKey(albumId)) return _albumArt[albumId];
    final own = albumCoverOf(albumId);
    String? found = own;
    if (found == null && albumId != 'received') {
      for (final song in tracksIn(albumId == 'root' ? null : albumId) ?? const <Track>[]) {
        final art = _art[song.localUri];
        if (art != null && art.isNotEmpty) {
          found = art;
          break;
        }
      }
    }
    return _albumArt[albumId] = found;
  }

  // ---------- la portada de un álbum (solo en este teléfono) ----------

  static String _albumKey(String albumId) => 'album:$albumId';

  /// La imagen que elegiste para un álbum (`albumId`: la dirección de su carpeta, `root` o `received`), o `null` si no le pusiste ninguna.
  String? albumCoverOf(String albumId) => _covers[_albumKey(albumId)];

  /// Le pone al álbum la imagen de `imagePath`. Se copia dentro de la app y se recuerda aquí, en el teléfono: no se sube a ningún sitio,
  /// así cada quien personaliza los suyos. Lanza `TrackSaveException` con el motivo; entonces el álbum se queda como estaba.
  Future<void> setAlbumCover(String albumId, String imagePath) async {
    final image = await _saver.prepareCover(imagePath);
    _covers[_albumKey(albumId)] = await _saver.storeCover(_albumKey(albumId), image, keep: true);
    await _rememberCovers();
    _tell();
  }

  /// Quita la imagen elegida: el álbum vuelve a enseñar la de su primera canción.
  Future<void> clearAlbumCover(String albumId) async {
    final path = _covers.remove(_albumKey(albumId));
    if (path == null) return;
    await _rememberCovers();
    try {
      await File(path).delete();
    } on FileSystemException {
      // ya no estaba
    }
    _tell();
  }

  Future<void> _rememberCovers() async {
    try {
      await _coverStore.save(_covers);
    } catch (_) {
      // sin poder recordarla, la imagen vale mientras la app siga abierta
    }
  }

  /// Lee ya la carátula de esa canción (la que va a sonar) si todavía no se había leído.
  @override
  Future<void> load(Track track) async {
    final uri = track.localUri;
    if (uri == null || _art.containsKey(uri)) return;
    final Map<String, String> read;
    try {
      read = await _saver.readArt([uri]);
    } catch (_) {
      return;
    }
    _art[uri] = read[uri] ?? '';
    if (read.isNotEmpty) _tell();
  }

  /// Lo que dura una canción de la carpeta, si ya se leyó.
  Duration? durationOf(Track track) => _durations.of(track.durationKey);

  /// Pregunta a Android lo que duran las canciones que aún no se sabe, de a pocas, y avisa a cada tanda. Si la carpeta se vuelve
  /// a leer mientras tanto, esta pasada se deja: la nueva ya cuenta con lo que se haya sabido.
  Future<void> _fillDurations() async {
    final round = ++_round;
    final missing = [for (final song in songs) if (_durations.of(song.durationKey) == null) song];
    for (var i = 0; i < missing.length; i += durationBatch) {
      final batch = missing.sublist(i, i + durationBatch > missing.length ? missing.length : i + durationBatch);
      final Map<String, Duration> read;
      try {
        read = await _saver.readDurations([for (final song in batch) song.localUri!]);
      } catch (_) {
        return; // la duración es un adorno: si falla, la lista se queda como está
      }
      if (_disposed || round != _round) return;
      final found = {
        for (final song in batch)
          if (read[song.localUri] != null) song.durationKey: read[song.localUri]!,
      };
      if (found.isEmpty) continue;
      try {
        await _durations.putAll(found);
      } catch (_) {
        return; // no se pudo recordar: la lista sigue sin duraciones y se vuelven a pedir la próxima vez
      }
      _tell();
    }
    await _fillArt(round);
  }

  /// Lo mismo con las carátulas incrustadas: de a pocas y avisando en cada tanda.
  Future<void> _fillArt(int round) async {
    final wanted = [for (final song in songs) if (!_art.containsKey(song.localUri)) song.localUri!];
    for (var i = 0; i < wanted.length; i += durationBatch) {
      final batch = wanted.sublist(i, i + durationBatch > wanted.length ? wanted.length : i + durationBatch);
      final Map<String, String> read;
      try {
        read = await _saver.readArt(batch);
      } catch (_) {
        return;
      }
      if (_disposed || round != _round) return;
      for (final uri in batch) {
        _art[uri] = read[uri] ?? ''; // '' = sin carátula: no se vuelve a preguntar
      }
      if (read.isNotEmpty) _tell();
    }
  }

  void _tell() {
    _albumArt.clear();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _music.removeListener(_onMusicChanged);
    super.dispose();
  }
}
