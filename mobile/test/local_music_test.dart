import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/music_store.dart';
import 'package:kyora_chat/models/track.dart';
import 'package:kyora_chat/state/local_music_controller.dart';
import 'package:kyora_chat/state/music_controller.dart';
import 'package:kyora_chat/state/player_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/music_page.dart';

import 'fake_engine.dart';
import 'music_test.dart' show FakeMusicBackend, FakeSaver, MemoryMusicStore;
import 'music_ui.dart';

LocalSong song(String name, {int size = 3 * 1024 * 1024, int at = 1000}) => LocalSong(
  uri: 'content://tree/musica/document/$name',
  name: name,
  sizeBytes: size,
  modified: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
);

void main() {
  late FakeMusicBackend backend;
  late MemoryMusicStore store;
  late FakeSaver saver;
  late MusicController music;
  late LocalMusicController local;

  setUp(() async {
    backend = FakeMusicBackend();
    store = MemoryMusicStore(since: DateTime.utc(2026, 10, 1))..settings = const MusicSettings(auto: false);
    saver = FakeSaver();
    music = MusicController(backend, store, saver);
    local = LocalMusicController(music, saver);
  });

  tearDown(() {
    local.dispose();
    music.dispose();
  });

  Future<void> settle() => pumpEventQueue();

  /// La fila de una canción del teléfono en la lista del álbum.
  Finder songRow(String file) => find.byKey(Key('local-local:content://tree/musica/document/$file'));

  group('modelo', () {
    test('el título es el nombre sin «.mp3» y el archivo se vuelve una canción reproducible', () {
      final s = song('Mi Canción.MP3');
      expect(s.title, 'Mi Canción');
      final track = Track.local(s);
      expect(track.isLocal, isTrue);
      expect(track.localUri, s.uri);
      expect(track.title, 'Mi Canción');
      expect(track.id, 'local:${s.uri}');
      expect(track.coverUrl, isNull);
    });

    test('se lee lo que manda Android', () {
      final s = LocalSong.fromMap({'uri': 'content://x', 'name': 'a.mp3', 'size': 2048, 'modified': 5000});
      expect((s.name, s.sizeBytes, s.modified.millisecondsSinceEpoch), ('a.mp3', 2048, 5000));
      final empty = LocalSong.fromMap({'uri': 'content://y'});
      expect((empty.sizeBytes, empty.name), (0, 'canción.mp3'));
    });
  });

  group('controlador', () {
    test('sin carpeta elegida no lee nada', () async {
      await music.start();
      await local.refresh();
      expect(local.hasFolder, isFalse);
      expect(local.songs, isEmpty);
      expect(saver.listed, isEmpty);
    });

    test('con carpeta elegida lista sus .mp3 por orden alfabético', () async {
      store.settings = const MusicSettings(auto: false).withTree('content://tree/musica', 'Mi música');
      saver.files = [song('zeta.mp3'), song('Alfa.mp3'), song('beta.mp3')];
      await music.start();
      await settle();
      expect(saver.listed, ['content://tree/musica']);
      expect(local.songs.map((t) => t.title), ['Alfa', 'beta', 'zeta']);
      expect(local.folderName, 'Mi música');
      expect(local.error, isNull);
    });

    test('al cambiar de carpeta o quitarla se vuelve a leer', () async {
      store.settings = const MusicSettings(auto: false).withTree('content://tree/a', 'A');
      saver.files = [song('uno.mp3')];
      await music.start();
      await settle();
      expect(local.songs.length, 1);
      saver.files = [song('dos.mp3'), song('tres.mp3')];
      await music.updateSettings(music.settings.withTree('content://tree/b', 'B'));
      await settle();
      expect(saver.listed, ['content://tree/a', 'content://tree/b']);
      expect(local.songs.length, 2);
      await music.updateSettings(music.settings.withoutTree());
      await settle();
      expect(local.songs, isEmpty);
      expect(local.hasFolder, isFalse);
    });

    test('cuando se guarda una canción nueva, la carpeta se vuelve a leer y aparece', () async {
      store.settings = const MusicSettings(auto: false).withTree('content://tree/a', 'A');
      saver.files = [];
      backend.add('n', title: 'Nueva', at: DateTime.utc(2026, 11, 1));
      await music.start();
      await settle();
      expect(local.songs, isEmpty);
      saver.files = [song('Nueva n.mp3')]; // lo que Android ve tras guardarla
      await music.save(music.tracks.single);
      await settle();
      expect(local.songs.map((t) => t.title), ['Nueva n']);
    });

    test('un fallo se explica y, si la carpeta ya no sirve, se marca para elegirla otra vez', () async {
      store.settings = const MusicSettings(auto: false).withTree('content://tree/a', 'A');
      saver.listFails = const TrackSaveException('Android ya no deja leer «A»: elige la carpeta otra vez.', folderLost: true);
      await music.start();
      await settle();
      expect(local.error, contains('elige la carpeta otra vez'));
      expect(local.folderLost, isTrue);
      expect(local.songs, isEmpty);
      saver.listFails = null;
      saver.files = [song('a.mp3')];
      await local.refresh();
      expect(local.error, isNull);
      expect(local.folderLost, isFalse);
      expect(local.songs.length, 1);
    });

    test('dos lecturas seguidas no se pisan: la segunda espera y se hace al terminar la primera', () async {
      store.settings = const MusicSettings(auto: false).withTree('content://tree/a', 'A');
      saver.files = [song('a.mp3')];
      await music.start();
      await settle();
      saver.listed.clear();
      await Future.wait([local.refresh(), local.refresh(), local.refresh()]);
      expect(saver.listed.length, lessThanOrEqualTo(2)); // nunca tres lecturas a la vez
    });
  });

  group('pantalla', () {
    late FakeEngine engine;
    late PlayerController player;

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      engine = FakeEngine();
      player = PlayerController(backend, engine, noteAfter: Duration.zero);
      addTearDown(player.dispose);
      await tester.runAsync(music.start);
      await tester.runAsync(settle);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          // el disco no gira: si no, `pumpAndSettle` no terminaría nunca mientras suene algo
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
          home: MusicPage(controller: music, player: player, local: local),
        ),
      );
      await tester.pump();
    }

    Future<void> openPhoneTab(WidgetTester tester) => openAlbum(tester, 1, 'card-root');

    testWidgets('«Canciones enviadas» es la primera tarjeta y abre su álbum', (tester) async {
      backend.add('r', title: 'Recibida', at: DateTime.utc(2026, 9, 1));
      await open(tester);
      expect(find.byType(TabBar), findsNothing);
      expect(card('card-received'), findsOneWidget);
      expect(find.byKey(const Key('track-r')), findsNothing); // aún no: primero los álbumes
      await tester.tap(card('card-received'));
      await tester.pumpAndSettle();
      expect(songTitle(tester), 'Recibida r'); // la primera, en el disco
      await openList(tester);
      expect(find.byKey(const Key('track-r')), findsOneWidget); // y en la lista
    });

    testWidgets('sin carpeta, la tarjeta «Elegir carpeta» abre los ajustes', (tester) async {
      await open(tester);
      await deckTo(tester, 1);
      await tester.tap(card('card-choose'));
      await tester.pumpAndSettle();
      expect(find.text('Carpeta de las canciones'), findsOneWidget);
    });

    testWidgets('con carpeta enseña sus .mp3 en la lista, con la carpeta como línea de abajo', (tester) async {
      store.settings = const MusicSettings(auto: false).withTree('content://tree/musica', 'Mi música');
      saver.files = [song('Bohemian.mp3', size: 5 * 1024 * 1024), song('Alfa.mp3', size: 1024 * 1024)];
      await open(tester);
      await openPhoneTab(tester);
      expect(songTitle(tester), 'Alfa'); // la que se enseña es la primera
      expect(
        tester.widget<Text>(find.byKey(const Key('album-song-subtitle'))).data,
        'Mi música',
      ); // sin « - » en el nombre: la línea de abajo es la carpeta
      expect(tester.widget<Text>(find.byKey(const Key('album-title'))).data, 'Mi música'); // y el nombre del álbum, arriba
      await openList(tester);
      expect(songRow('Alfa.mp3'), findsOneWidget);
      expect(songRow('Bohemian.mp3'), findsOneWidget);
      // por orden alfabético: Alfa antes que Bohemian (de arriba abajo)
      expect(tester.getTopLeft(songRow('Alfa.mp3')).dy, lessThan(tester.getTopLeft(songRow('Bohemian.mp3')).dy));
    });

    testWidgets('tocar uno de la carpeta lo reproduce, con toda la carpeta como cola', (tester) async {
      store.settings = const MusicSettings(auto: false).withTree('content://tree/musica', 'Mi música');
      saver.files = [song('Alfa.mp3'), song('Beta.mp3'), song('Gamma.mp3')];
      await open(tester);
      await openPhoneTab(tester);
      await openList(tester);
      await playRow(tester, songRow('Beta.mp3'), 'local:content://tree/musica/document/Beta.mp3');
      await tester.runAsync(settle);
      await tester.pumpAndSettle();
      expect(engine.queue.map((q) => q.title), ['Alfa', 'Beta', 'Gamma']);
      expect(engine.startIndex, 1);
      expect(engine.queue[1].url, 'content://tree/musica/document/Beta.mp3'); // directo del archivo, sin internet
      expect(backend.signed, isEmpty); // no pide nada a Supabase
      await openList(tester); // se cierra: debajo del disco, la que suena
      expect(songTitle(tester), 'Beta');
    });

    testWidgets('una carpeta sin .mp3 lo dice', (tester) async {
      store.settings = const MusicSettings(auto: false).withTree('content://tree/musica', 'Vacía');
      await open(tester);
      await openPhoneTab(tester);
      expect(find.text('No hay archivos .mp3 en «Vacía».'), findsOneWidget);
    });

    testWidgets('si la carpeta ya no sirve lo explica y deja elegirla otra vez', (tester) async {
      store.settings = const MusicSettings(auto: false).withTree('content://tree/muerta', 'Vieja');
      saver.listFails = const TrackSaveException('Android ya no deja leer «Vieja»: elige la carpeta otra vez.', folderLost: true);
      await open(tester);
      expect(find.textContaining('Android ya no deja leer «Vieja»'), findsOneWidget);
      expect(find.text('Elegir carpeta'), findsOneWidget);
    });

    testWidgets('lo guardado desde «Recibidas» aparece en el álbum del teléfono', (tester) async {
      store.settings = const MusicSettings(auto: false).withTree('content://tree/musica', 'Mi música');
      backend.add('v', title: 'Vieja', at: DateTime.utc(2026, 9, 1));
      await open(tester);
      saver.files = [song('Vieja v.mp3')];
      await tester.tap(card('card-received'));
      await tester.pumpAndSettle();
      await openList(tester);
      await tester.tap(find.byKey(const Key('more-v')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-v')));
      await tester.runAsync(settle);
      await tester.pumpAndSettle();
      await tester.pageBack(); // cierra la lista
      await tester.pumpAndSettle();
      await tester.pageBack(); // y sale del álbum
      await tester.pumpAndSettle();
      await tester.runAsync(settle);
      await tester.pump();
      await openPhoneTab(tester);
      expect(songTitle(tester), 'Vieja v');
    });
  });
}
