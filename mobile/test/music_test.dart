import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/chat_backend.dart';
import 'package:kyora_chat/data/music_backend.dart';
import 'package:kyora_chat/data/music_store.dart';
import 'package:kyora_chat/models/track.dart';
import 'package:kyora_chat/state/music_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/folder_settings.dart';
import 'package:kyora_chat/ui/music_page.dart';

class FakeMusicBackend implements MusicBackend {
  final List<Track> tracks = [];
  final _changes = StreamController<void>.broadcast();
  final List<String> downloads = [];
  final List<List<String>> signed = [];
  ChatException? listError;
  ChatException? signError;
  ChatException? downloadError;
  ChatException? confirmError;

  /// Las canciones que se confirmaron como recibidas, en orden.
  final List<String> confirmed = [];

  Track add(String id, {String title = 'Canción', DateTime? at, String? playlist, String? cover}) {
    final track = Track(
      id: id,
      title: '$title $id',
      fileName: '$id.mp3',
      storagePath: 'u/music/$id/$id.mp3',
      sizeBytes: 2 * 1024 * 1024,
      createdAt: at ?? DateTime.now().toUtc(),
      playlist: playlist,
      coverUrl: cover,
    );
    tracks.insert(0, track);
    return track;
  }

  void announce() => _changes.add(null);

  @override
  Future<Map<String, String>> signedUrls(List<String> storagePaths, int expiresIn) async {
    if (signError != null) throw signError!;
    signed.add(storagePaths);
    return {for (final path in storagePaths) path: 'https://files.test/$path?exp=$expiresIn'};
  }

  @override
  Future<List<Track>> listTracks({int limit = 200}) async {
    if (listError != null) throw listError!;
    return List.of(tracks);
  }

  @override
  Future<Uint8List> downloadTrack(String storagePath) async {
    if (downloadError != null) throw downloadError!;
    downloads.add(storagePath);
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<void> confirmReceived(String trackId) async {
    if (confirmError != null) throw confirmError!;
    confirmed.add(trackId);
    // como Supabase: la fila guarda la hora, y las siguientes listas la traen
    tracks.replaceRange(0, tracks.length, [for (final t in tracks) t.id == trackId ? t.withReceived(DateTime.now().toUtc()) : t]);
  }

  @override
  Stream<void> trackChanges() => _changes.stream;
}

class MemoryMusicStore implements MusicStore {
  MemoryMusicStore({this.since});

  MusicSettings settings = const MusicSettings();
  final Set<String> saved = {};
  DateTime? since;

  @override
  Future<MusicSettings> loadSettings() async => settings;

  @override
  Future<void> saveSettings(MusicSettings value) async => settings = value;

  @override
  Future<Set<String>> loadSaved() async => Set.of(saved);

  @override
  Future<void> markSaved(String trackId) async => saved.add(trackId);

  @override
  Future<DateTime> autoSince() async => since ??= DateTime.now().toUtc();
}

class FakeSaver implements TrackSaver {
  final List<({String name, MusicBase base, String folder, int bytes, String? tree})> saved = [];
  TrackSaveException? failWith;

  /// Lo que "elige" la persona en el selector de carpetas (`null` = lo cierra sin elegir).
  PickedFolder? picks;
  TrackSaveException? pickFails;
  int picked = 0;

  @override
  Future<String> save({
    required String fileName,
    required Uint8List bytes,
    required MusicBase base,
    required String folder,
    String? treeUri,
  }) async {
    if (failWith != null) throw failWith!;
    saved.add((name: fileName, base: base, folder: folder, bytes: bytes.length, tree: treeUri));
    if (treeUri != null && treeUri.isNotEmpty) return 'Mis canciones';
    return folder.isEmpty ? base.label : '${base.label}/$folder';
  }

  /// Lo que "hay" en la carpeta elegida: los .mp3 de la raíz (`files`), sus subcarpetas (`rootFolders`) y, por dirección de carpeta,
  /// lo de cada subcarpeta (`dirSongs`, `dirFolders`).
  List<LocalSong> files = [];
  List<LocalFolder> rootFolders = [];
  final Map<String, List<LocalSong>> dirSongs = {};
  final Map<String, List<LocalFolder>> dirFolders = {};
  TrackSaveException? listFails;
  TrackSaveException? createFails;
  TrackSaveException? moveFails;

  /// Canciones (por dirección) que fallan al moverse, con su motivo.
  final Map<String, String> moveFailures = {};
  final List<String> listed = [];
  final List<({List<String> uris, String? from, String? to})> moves = [];
  final List<({String? parent, String name})> created = [];

  List<LocalSong> _songsIn(String? dir) => dir == null ? files : (dirSongs[dir] ??= []);

  /// Si hay, la lectura de la raíz se queda esperando esto (como un Android lento).
  Future<void>? holdRoot;

  @override
  Future<FolderListing> listDir(String treeUri, {String? dirUri}) async {
    listed.add(dirUri ?? treeUri);
    if (dirUri == null && holdRoot != null) await holdRoot;
    if (listFails != null) throw listFails!;
    if (dirUri == null) return FolderListing(folders: List.of(rootFolders), songs: List.of(files));
    return FolderListing(folders: List.of(dirFolders[dirUri] ?? const []), songs: List.of(dirSongs[dirUri] ?? const []));
  }

  @override
  Future<LocalFolder> createFolder(String treeUri, {String? parentUri, required String name}) async {
    if (createFails != null) throw createFails!;
    created.add((parent: parentUri, name: name));
    final folder = LocalFolder(uri: '${parentUri ?? 'content://tree/musica/document'}/$name', name: name);
    if (parentUri == null) {
      rootFolders = [...rootFolders, folder];
    } else {
      dirFolders[parentUri] = [...(dirFolders[parentUri] ?? const []), folder];
    }
    dirSongs[folder.uri] = [];
    return folder;
  }

  @override
  Future<MoveResult> moveSongs(String treeUri, {required List<String> uris, String? fromUri, String? toUri}) async {
    moves.add((uris: List.of(uris), from: fromUri, to: toUri));
    if (moveFails != null) throw moveFails!;
    var moved = 0;
    final failures = <String, String>{};
    for (final uri in uris) {
      if (moveFailures.containsKey(uri)) {
        failures[uri] = moveFailures[uri]!;
        continue;
      }
      final from = _songsIn(fromUri);
      final i = from.indexWhere((x) => x.uri == uri);
      if (i < 0) continue;
      _songsIn(toUri).add(from.removeAt(i));
      moved++;
    }
    return MoveResult(moved: moved, failures: failures);
  }

  /// Lo que "dura" cada archivo según Android (los que no estén aquí no se pueden leer) y los grupos en que se pidió.
  final Map<String, Duration> durations = {};
  final List<List<String>> durationReads = [];

  @override
  Future<Map<String, Duration>> readDurations(List<String> uris) async {
    durationReads.add(uris);
    return {for (final uri in uris) if (durations[uri] != null) uri: durations[uri]!};
  }

  /// Las carátulas incrustadas que "tiene" cada archivo (ruta de la imagen).
  final Map<String, String> art = {};
  final List<List<String>> artReads = [];

  @override
  Future<Map<String, String>> readArt(List<String> uris) async {
    artReads.add(uris);
    return {for (final uri in uris) if (art[uri] != null) uri: art[uri]!};
  }

  /// El contenido de cada archivo, por dirección; lo que se escribió y las imágenes guardadas.
  final Map<String, Uint8List> contents = {};
  final List<String> written = [];
  final List<({String key, bool keep, String path})> storedCovers = [];
  TrackSaveException? prepareFails;
  TrackSaveException? writeFails;

  @override
  Future<Uint8List> prepareCover(String path) async {
    if (prepareFails != null) throw prepareFails!;
    return Uint8List.fromList([0xFF, 0xD8, 0xFF, ...path.codeUnits]);
  }

  @override
  Future<String> storeCover(String key, Uint8List bytes, {required bool keep}) async {
    final path = '/covers/${storedCovers.length}.jpg';
    storedCovers.add((key: key, keep: keep, path: path));
    return path;
  }

  @override
  Future<Uint8List> readFile(String uri) async => contents[uri] ?? Uint8List.fromList(List.filled(40, 0xFF));

  @override
  Future<void> writeFile(String uri, Uint8List bytes) async {
    if (writeFails != null) throw writeFails!;
    contents[uri] = bytes;
    written.add(uri);
    // como en Android: el archivo cambia de tamaño y de fecha
    final at = files.indexWhere((f) => f.uri == uri);
    if (at >= 0) {
      files[at] = LocalSong(uri: uri, name: files[at].name, sizeBytes: bytes.length, modified: files[at].modified.add(const Duration(seconds: 1)));
    }
  }

  @override
  Future<PickedFolder?> pickFolder() async {
    picked++;
    if (pickFails != null) throw pickFails!;
    return picks;
  }
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late FakeMusicBackend backend;
  late MemoryMusicStore store;
  late FakeSaver saver;

  setUp(() {
    backend = FakeMusicBackend();
    store = MemoryMusicStore(since: DateTime.utc(2026, 10, 1));
    saver = FakeSaver();
  });

  MusicController make() => MusicController(backend, store, saver);

  group('controlador', () {
    test('una canción nueva que sube la PC se guarda sola en la carpeta elegida', () async {
      final c = make();
      await c.start();
      expect(c.tracks, isEmpty);
      backend.add('a', at: DateTime.utc(2026, 11, 1));
      backend.announce();
      await settle();
      expect(saver.saved.single.name, 'a.mp3');
      expect(saver.saved.single.base, MusicBase.music);
      expect(saver.saved.single.folder, 'Kyora');
      expect(c.stateOf(c.tracks.single), TrackState.saved);
      expect(store.saved, {'a'});
      c.dispose();
    });

    test('las canciones anteriores a la primera vez quedan pendientes y se guardan a mano', () async {
      backend.add('vieja', at: DateTime.utc(2026, 9, 1));
      final c = make();
      await c.start();
      expect(saver.saved, isEmpty);
      expect(c.stateOf(c.tracks.single), TrackState.pending);
      expect(c.pendingCount, 1);
      await c.saveAll();
      expect(saver.saved.map((s) => s.name), ['vieja.mp3']);
      expect(c.pendingCount, 0);
      c.dispose();
    });

    test('una canción ya guardada no se vuelve a bajar', () async {
      store.saved.add('a');
      backend.add('a', at: DateTime.utc(2026, 11, 1));
      final c = make();
      await c.start();
      backend.announce();
      await settle();
      expect(saver.saved, isEmpty);
      expect(backend.downloads, isEmpty);
      c.dispose();
    });

    test('con «guardar solas» apagado nada se baja hasta que lo pides', () async {
      store.settings = const MusicSettings(auto: false);
      final c = make();
      await c.start();
      backend.add('a', at: DateTime.utc(2026, 11, 1));
      backend.announce();
      await settle();
      expect(saver.saved, isEmpty);
      expect(c.pendingCount, 1);
      await c.save(c.tracks.single);
      expect(saver.saved.length, 1);
      c.dispose();
    });

    test('encender «guardar solas» cuenta desde ahora: no baja la biblioteca vieja', () async {
      store.settings = const MusicSettings(auto: false);
      backend.add('vieja', at: DateTime.utc(2026, 10, 15));
      final c = make();
      await c.start();
      await c.updateSettings(c.settings.copyWith(auto: true));
      expect(saver.saved, isEmpty);
      expect(c.stateOf(c.tracks.single), TrackState.pending);
      c.dispose();
    });

    test('cambiar la carpeta se recuerda y la siguiente canción va a la nueva', () async {
      final c = make();
      await c.start();
      await c.updateSettings(const MusicSettings(base: MusicBase.download, folder: 'Mis canciones'));
      expect(store.settings.base, MusicBase.download);
      expect(store.settings.where, 'Descargas/Mis canciones');
      backend.add('a', at: DateTime.utc(2026, 11, 1));
      backend.announce();
      await settle();
      expect(saver.saved.single.base, MusicBase.download);
      expect(saver.saved.single.folder, 'Mis canciones');
      c.dispose();
    });

    test('con una carpeta elegida con el selector, las canciones van a ella y se dice su nombre', () async {
      store.settings = const MusicSettings().withTree('content://tree/musica', 'Mis canciones');
      final c = make();
      await c.start();
      expect(c.settings.where, 'Mis canciones');
      backend.add('a', at: DateTime.utc(2026, 11, 1));
      backend.announce();
      final notice = c.notices.first;
      await settle();
      expect(saver.saved.single.tree, 'content://tree/musica');
      expect(await notice, 'Guardada en Mis canciones: Canción a');
      c.dispose();
    });

    test('quitar la carpeta elegida vuelve a Música/Kyora y se recuerda', () async {
      final c = make();
      await c.start();
      await c.updateSettings(c.settings.withTree('content://tree/x', 'X'));
      expect(store.settings.hasTree, isTrue);
      await c.updateSettings(c.settings.withoutTree());
      expect(store.settings.hasTree, isFalse);
      expect(store.settings.where, 'Música/Kyora');
      c.dispose();
    });

    test('elegir otras opciones (subcarpeta, guardar solas) no pierde la carpeta elegida', () {
      final tree = const MusicSettings().withTree('content://tree/x', 'X');
      final changed = tree.copyWith(folder: 'Otra', auto: false, base: MusicBase.download);
      expect(changed.treeUri, 'content://tree/x');
      expect(changed.where, 'X');
    });

    test('si la carpeta elegida ya no sirve, la canción queda en error con el motivo', () async {
      store.settings = const MusicSettings().withTree('content://tree/muerta', 'Vieja');
      saver.failWith = const TrackSaveException('Android ya no deja escribir en «Vieja»: elige la carpeta otra vez.', folderLost: true);
      final c = make();
      await c.start();
      backend.add('a', at: DateTime.utc(2026, 11, 1));
      backend.announce();
      await settle();
      expect(c.stateOf(c.tracks.single), TrackState.failed);
      expect(c.failureOf(c.tracks.single), contains('elige la carpeta otra vez'));
      c.dispose();
    });

    test('si el teléfono no puede guardar, la canción queda en error y se reintenta', () async {
      saver.failWith = const TrackSaveException('No hay espacio.');
      final c = make();
      await c.start();
      backend.add('a', at: DateTime.utc(2026, 11, 1));
      backend.announce();
      await settle();
      final track = c.tracks.single;
      expect(c.stateOf(track), TrackState.failed);
      expect(c.failureOf(track), 'No hay espacio.');
      expect(store.saved, isEmpty);
      saver.failWith = null;
      await c.save(track);
      expect(c.stateOf(track), TrackState.saved);
      c.dispose();
    });

    test('«Recibido» en una canción que ya está en el teléfono avisa a Supabase sin volver a guardarla', () async {
      backend.add('a', at: DateTime.utc(2026, 11, 1));
      final c = make();
      await c.start();
      final track = c.tracks.single;
      expect(c.stateOf(track), TrackState.saved); // la guardó sola
      expect(c.isReceived(track), isFalse);
      expect(await c.confirmReceived(track), isTrue);
      expect(backend.confirmed, ['a']);
      expect(saver.saved.length, 1);
      expect(c.isReceived(c.tracks.single), isTrue);
      await c.refresh(); // la lista que vuelve de Supabase ya trae la confirmación
      expect(c.isReceived(c.tracks.single), isTrue);
      expect(await c.confirmReceived(c.tracks.single), isTrue); // repetir no vuelve a avisar
      expect(backend.confirmed, ['a']);
      c.dispose();
    });

    test('«Recibido» en una pendiente la guarda primero y solo entonces confirma', () async {
      backend.add('vieja', at: DateTime.utc(2026, 9, 1));
      final c = make();
      await c.start();
      final track = c.tracks.single;
      expect(c.stateOf(track), TrackState.pending);
      final order = <String>[];
      c.addListener(() {
        if (c.stateOf(track) == TrackState.saved && !order.contains('guardada')) order.add('guardada');
      });
      expect(await c.confirmReceived(track), isTrue);
      expect(order, ['guardada']);
      expect(saver.saved.single.name, 'vieja.mp3');
      expect(store.saved, {'vieja'});
      expect(backend.confirmed, ['vieja']);
      c.dispose();
    });

    test('si no se puede guardar, «Recibido» no confirma nada', () async {
      backend.add('vieja', at: DateTime.utc(2026, 9, 1));
      saver.failWith = const TrackSaveException('No hay espacio.');
      final c = make();
      await c.start();
      final avisos = <String>[];
      final sub = c.notices.listen(avisos.add);
      expect(await c.confirmReceived(c.tracks.single), isFalse);
      await settle();
      expect(backend.confirmed, isEmpty);
      expect(c.isReceived(c.tracks.single), isFalse);
      expect(c.stateOf(c.tracks.single), TrackState.failed);
      expect(avisos, ['No hay espacio.']);
      await sub.cancel();
      c.dispose();
    });

    test('si Supabase no recibe la confirmación, la canción queda guardada pero sin confirmar y se puede reintentar', () async {
      backend.add('vieja', at: DateTime.utc(2026, 9, 1));
      backend.confirmError = const ChatException('Sin conexión con Supabase', retryable: true);
      final c = make();
      await c.start();
      final avisos = <String>[];
      final sub = c.notices.listen(avisos.add);
      expect(await c.confirmReceived(c.tracks.single), isFalse);
      await settle();
      expect(c.stateOf(c.tracks.single), TrackState.saved);
      expect(c.isReceived(c.tracks.single), isFalse);
      expect(avisos.last, 'Sin conexión con Supabase');
      backend.confirmError = null;
      expect(await c.confirmReceived(c.tracks.single), isTrue);
      expect(saver.saved.length, 1); // no se vuelve a guardar
      expect(backend.confirmed, ['vieja']);
      await sub.cancel();
      c.dispose();
    });

    test('guardar solas no confirma: sin pulsar «Recibido» nada se avisa a Supabase', () async {
      backend.add('a', at: DateTime.utc(2026, 11, 1));
      final c = make();
      await c.start();
      backend.announce();
      await settle();
      expect(c.stateOf(c.tracks.single), TrackState.saved);
      expect(backend.confirmed, isEmpty);
      c.dispose();
    });

    test('sin conexión la lista da su error y no revienta', () async {
      backend.listError = const ChatException('Sin conexión con Supabase', retryable: true);
      final c = make();
      await c.start();
      expect(c.error, 'Sin conexión con Supabase');
      expect(c.loading, isFalse);
      backend.listError = null;
      backend.add('a', at: DateTime.utc(2026, 11, 1));
      await c.refresh();
      expect(c.error, isNull);
      expect(c.tracks.length, 1);
      c.dispose();
    });
  });

  group('pantalla', () {
    late MusicController shown;

    /// Abre la hoja de la carpeta de las canciones, que ahora se alcanza desde Ajustes (o la placa «Elegir carpeta»).
    Future<void> openFolderSheet(WidgetTester tester) async {
      unawaited(showFolderSettings(tester.element(find.byType(MusicPage)), shown));
      await tester.pumpAndSettle();
    }

    Future<MusicController> open(WidgetTester tester, {MusicController? controller}) async {
      final c = controller ?? make();
      shown = c;
      await tester.runAsync(c.start);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: MusicPage(controller: c)));
      await tester.pump();
      return c;
    }

    testWidgets('sin canciones explica dónde aparecerán', (tester) async {
      await open(tester);
      expect(find.textContaining('Aún no hay canciones'), findsOneWidget);
      expect(find.text('Todo guardado en Música/Kyora.'), findsOneWidget);
    });

    testWidgets('enseña las canciones, cuáles están guardadas y deja guardar las pendientes', (tester) async {
      backend.add('vieja', title: 'Pendiente', at: DateTime.utc(2026, 9, 1), playlist: 'Rock');
      backend.add('nueva', title: 'Guardada', at: DateTime.utc(2026, 11, 1));
      store.saved.add('nueva');
      await open(tester);
      expect(find.text('Pendiente vieja'), findsOneWidget);
      expect(find.text('Rock'), findsOneWidget);
      expect(find.byKey(const Key('saved')), findsOneWidget);
      expect(find.text('1 por guardar en Música/Kyora.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('save-all')));
      await tester.runAsync(settle);
      await tester.pump();
      expect(saver.saved.map((s) => s.name), ['vieja.mp3']);
      expect(find.byKey(const Key('saved')), findsNWidgets(2));
      expect(find.byKey(const Key('save-all')), findsNothing);
    });

    testWidgets('tocar una pendiente la guarda y avisa dónde quedó', (tester) async {
      backend.add('vieja', title: 'Pendiente', at: DateTime.utc(2026, 9, 1));
      await open(tester);
      await tester.tap(find.byKey(const Key('track-vieja')));
      await tester.runAsync(settle);
      await tester.pump();
      expect(find.textContaining('Guardada en Música/Kyora'), findsOneWidget);
    });

    testWidgets('cada canción enviada tiene su botón «Recibido»; al pulsarlo guarda, confirma y queda la marca', (tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      backend.add('vieja', title: 'Pendiente', at: DateTime.utc(2026, 9, 1));
      await open(tester);
      expect(find.byKey(const Key('received-vieja')), findsOneWidget);
      expect(find.text('Recibido'), findsOneWidget);
      expect(find.byKey(const Key('received-mark-vieja')), findsNothing);
      await tester.tap(find.byKey(const Key('received-vieja')));
      await tester.runAsync(settle);
      await tester.pump();
      expect(saver.saved.map((s) => s.name), ['vieja.mp3']);
      expect(backend.confirmed, ['vieja']);
      expect(find.byKey(const Key('received-vieja')), findsNothing);
      expect(find.byKey(const Key('received-mark-vieja')), findsOneWidget);
      expect(find.textContaining('Guardada en Música/Kyora'), findsOneWidget); // los avisos salen de uno en uno: primero este, luego «Recibida»
    });

    testWidgets('si no se pudo guardar, el botón «Recibido» sigue ahí y no se confirma', (tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      saver.failWith = const TrackSaveException('No hay espacio.');
      backend.add('vieja', title: 'Pendiente', at: DateTime.utc(2026, 9, 1));
      await open(tester);
      await tester.tap(find.byKey(const Key('received-vieja')));
      await tester.runAsync(settle);
      await tester.pump();
      expect(backend.confirmed, isEmpty);
      expect(find.byKey(const Key('received-vieja')), findsOneWidget);
      expect(find.text('No hay espacio.'), findsWidgets);
    });

    testWidgets('elegir otra carpeta en los ajustes la recuerda', (tester) async {
      await open(tester);
      await openFolderSheet(tester);
      await tester.tap(find.byKey(const Key('base-download')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('folder-field')), 'Rock');
      await tester.tap(find.byKey(const Key('settings-save')));
      await tester.pumpAndSettle();
      expect(store.settings.base, MusicBase.download);
      expect(store.settings.folder, 'Rock');
      expect(find.text('Todo guardado en Descargas/Rock.'), findsOneWidget);
    });

    testWidgets('«Elegir carpeta» abre el selector de Android, enseña su nombre y se recuerda', (tester) async {
      saver.picks = const PickedFolder(uri: 'content://tree/musica', name: 'Mis canciones');
      await open(tester);
      await openFolderSheet(tester);
      expect(find.text('Elegir carpeta'), findsOneWidget);
      expect(find.byKey(const Key('folder-field')), findsOneWidget);
      await tester.tap(find.byKey(const Key('pick-folder')));
      await tester.pumpAndSettle();
      expect(saver.picked, 1);
      expect(find.text('Cambiar carpeta'), findsOneWidget);
      expect(find.text('Se guardan en Mis canciones.'), findsOneWidget);
      expect(find.byKey(const Key('folder-field')), findsNothing); // con carpeta elegida no hace falta la subcarpeta
      await tester.tap(find.byKey(const Key('settings-save')));
      await tester.pumpAndSettle();
      expect(store.settings.treeUri, 'content://tree/musica');
      expect(find.text('Todo guardado en Mis canciones.'), findsOneWidget);
    });

    testWidgets('cerrar el selector sin elegir no cambia nada', (tester) async {
      await open(tester);
      await openFolderSheet(tester);
      await tester.tap(find.byKey(const Key('pick-folder')));
      await tester.pumpAndSettle();
      expect(find.text('Elegir carpeta'), findsOneWidget);
      expect(find.text('Se guardan en Música/Kyora.'), findsOneWidget);
    });

    testWidgets('si el selector no se puede abrir lo explica', (tester) async {
      saver.pickFails = const TrackSaveException('Este teléfono no tiene selector de carpetas.');
      await open(tester);
      await openFolderSheet(tester);
      await tester.tap(find.byKey(const Key('pick-folder')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pick-error')), findsOneWidget);
      expect(find.text('Este teléfono no tiene selector de carpetas.'), findsOneWidget);
    });

    testWidgets('«Usar Música/Descargas otra vez» quita la carpeta elegida', (tester) async {
      store.settings = const MusicSettings().withTree('content://tree/x', 'Mis canciones');
      await open(tester);
      await openFolderSheet(tester);
      await tester.tap(find.byKey(const Key('use-default-folder')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('folder-field')), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings-save')));
      await tester.pumpAndSettle();
      expect(store.settings.hasTree, isFalse);
      expect(find.text('Todo guardado en Música/Kyora.'), findsOneWidget);
    });

    testWidgets('un error de la lista se explica y se puede reintentar', (tester) async {
      backend.listError = const ChatException('Falta crear la base de datos: ejecuta supabase/schema.sql en Supabase.');
      await open(tester);
      expect(find.textContaining('ejecuta supabase/schema.sql'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });
  });
}
