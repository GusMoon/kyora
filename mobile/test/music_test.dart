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
import 'package:kyora_chat/ui/music_page.dart';

class FakeMusicBackend implements MusicBackend {
  final List<Track> tracks = [];
  final _changes = StreamController<void>.broadcast();
  final List<String> downloads = [];
  ChatException? listError;
  ChatException? downloadError;

  Track add(String id, {String title = 'Canción', DateTime? at, String? playlist}) {
    final track = Track(
      id: id,
      title: '$title $id',
      fileName: '$id.mp3',
      storagePath: 'u/music/$id/$id.mp3',
      sizeBytes: 2 * 1024 * 1024,
      createdAt: at ?? DateTime.now().toUtc(),
      playlist: playlist,
    );
    tracks.insert(0, track);
    return track;
  }

  void announce() => _changes.add(null);

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
  final List<({String name, MusicBase base, String folder, int bytes})> saved = [];
  TrackSaveException? failWith;

  @override
  Future<String> save({required String fileName, required Uint8List bytes, required MusicBase base, required String folder}) async {
    if (failWith != null) throw failWith!;
    saved.add((name: fileName, base: base, folder: folder, bytes: bytes.length));
    return folder.isEmpty ? base.label : '${base.label}/$folder';
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
    Future<MusicController> open(WidgetTester tester, {MusicController? controller}) async {
      final c = controller ?? make();
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
      expect(find.text('Rock · 2,0 MB'), findsOneWidget);
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

    testWidgets('elegir otra carpeta en los ajustes la recuerda', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('music-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('base-download')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('folder-field')), 'Rock');
      await tester.tap(find.byKey(const Key('settings-save')));
      await tester.pumpAndSettle();
      expect(store.settings.base, MusicBase.download);
      expect(store.settings.folder, 'Rock');
      expect(find.text('Todo guardado en Descargas/Rock.'), findsOneWidget);
    });

    testWidgets('un error de la lista se explica y se puede reintentar', (tester) async {
      backend.listError = const ChatException('Falta crear la base de datos: ejecuta supabase/schema.sql en Supabase.');
      await open(tester);
      expect(find.textContaining('ejecuta supabase/schema.sql'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });
  });
}
