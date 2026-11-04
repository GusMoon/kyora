import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/duration_cache.dart';
import 'package:kyora_chat/data/favorites_store.dart';
import 'package:kyora_chat/data/music_store.dart';
import 'package:kyora_chat/models/track.dart';
import 'package:kyora_chat/state/local_music_controller.dart';
import 'package:kyora_chat/state/music_controller.dart';
import 'package:kyora_chat/state/player_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/music_page.dart';
import 'package:kyora_chat/util/format.dart';

import 'fake_engine.dart';
import 'music_test.dart' show FakeMusicBackend, FakeSaver, MemoryMusicStore;
import 'music_ui.dart';

/// La línea de abajo de la canción que se enseña en la vista de un álbum.
String? ringLine(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('album-song-subtitle'))).data;

LocalSong song(String name, {int size = 3 * 1024 * 1024, int at = 1000}) => LocalSong(
  uri: 'content://tree/musica/document/$name',
  name: name,
  sizeBytes: size,
  modified: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
);

void main() {
  group('formato', () {
    test('«Artista - Título» se parte por el primer « - »', () {
      expect(splitArtistTitle('Brambles - To Speak Of Solitude'), (artist: 'Brambles', title: 'To Speak Of Solitude'));
      expect(splitArtistTitle('A - B - C'), (artist: 'A', title: 'B - C'));
      expect(splitArtistTitle('Artista – Título'), (artist: 'Artista', title: 'Título')); // con raya larga también
      expect(splitArtistTitle('  Espacios  -  Sobran  '), (artist: 'Espacios', title: 'Sobran'));
    });

    test('sin separador, o con un lado vacío, todo es el título', () {
      expect(splitArtistTitle('Sin guion'), (artist: null, title: 'Sin guion'));
      expect(splitArtistTitle('Guion-pegado'), (artist: null, title: 'Guion-pegado'));
      expect(splitArtistTitle('- Sin artista'), (artist: null, title: '- Sin artista'));
      expect(splitArtistTitle('Sin título -'), (artist: null, title: 'Sin título -'));
    });

    test('la línea de abajo junta artista y duración con « • » y omite lo que falta', () {
      expect(songLine(artist: 'Brambles', duration: const Duration(minutes: 4, seconds: 21)), 'Brambles • 4:21');
      expect(songLine(artist: 'Brambles'), 'Brambles');
      expect(songLine(duration: const Duration(seconds: 59)), '0:59');
      expect(songLine(artist: '  ', duration: Duration.zero), '');
    });
  });

  group('duraciones', () {
    late FakeMusicBackend backend;
    late MemoryMusicStore store;
    late FakeSaver saver;
    late MusicController music;
    late MemoryDurationCache cache;

    setUp(() {
      backend = FakeMusicBackend();
      store = MemoryMusicStore(since: DateTime.utc(2026, 10, 1))
        ..settings = const MusicSettings(auto: false).withTree('content://tree/musica', 'Mi música');
      saver = FakeSaver();
      music = MusicController(backend, store, saver);
      cache = MemoryDurationCache();
    });

    tearDown(() => music.dispose());

    test('se leen de la carpeta de a 20, la lista avisa en cada tanda y lo leído se recuerda', () async {
      saver.files = [for (var i = 0; i < 45; i++) song('s${i.toString().padLeft(2, '0')}.mp3')];
      for (final f in saver.files) {
        saver.durations[f.uri] = Duration(seconds: 100 + saver.durations.length);
      }
      final local = LocalMusicController(music, saver, durations: cache);
      var told = 0;
      local.addListener(() => told++);
      await music.start();
      await pumpEventQueue();
      expect(saver.durationReads.map((r) => r.length), [20, 20, 5]);
      final first = local.songs.first;
      expect(local.durationOf(first), saver.durations[first.localUri]);
      expect(told, greaterThanOrEqualTo(3));

      // otra lectura de la carpeta: ya se sabe todo, no se le pregunta nada a Android
      saver.durationReads.clear();
      await local.refresh();
      await pumpEventQueue();
      expect(saver.durationReads, isEmpty);
      local.dispose();
    });

    test('un archivo que no se puede leer se queda sin duración, sin molestar a los demás', () async {
      saver.files = [song('a.mp3'), song('rota.mp3'), song('b.mp3')];
      saver.durations
        ..[saver.files[0].uri] = const Duration(minutes: 3)
        ..[saver.files[2].uri] = const Duration(minutes: 5);
      final local = LocalMusicController(music, saver, durations: cache);
      await music.start();
      await pumpEventQueue();
      final byTitle = {for (final t in local.songs) t.title: local.durationOf(t)};
      expect(byTitle, {'a': const Duration(minutes: 3), 'b': const Duration(minutes: 5), 'rota': null});
      local.dispose();
    });

    test('la duración de un archivo cambiado (otro tamaño) se vuelve a leer', () async {
      saver.files = [song('a.mp3', size: 1000)];
      saver.durations[saver.files.first.uri] = const Duration(minutes: 3);
      final local = LocalMusicController(music, saver, durations: cache);
      await music.start();
      await pumpEventQueue();
      saver.files = [song('a.mp3', size: 2000)];
      saver.durations[saver.files.first.uri] = const Duration(minutes: 4);
      await local.refresh();
      await pumpEventQueue();
      expect(local.durationOf(local.songs.single), const Duration(minutes: 4));
      local.dispose();
    });

    test('si lo leído no se puede recordar, la lista queda como estaba', () async {
      saver.files = [song('a.mp3')];
      saver.durations[saver.files.single.uri] = const Duration(minutes: 3);
      final local = LocalMusicController(music, saver, durations: _Failing(cache));
      await music.start();
      await pumpEventQueue();
      expect(local.songs.length, 1);
      expect(local.error, isNull);
      local.dispose();
    });

    test('el reproductor anota lo que dura una recibida cuando suena, y se recuerda', () async {
      backend.add('a');
      final track = backend.tracks.single;
      final engine = FakeEngine();
      final player = PlayerController(backend, engine, durations: cache, noteAfter: Duration.zero);
      expect(player.durationOf(track), isNull);
      await player.play(track, [track]);
      await pumpEventQueue();
      expect(player.durationOf(track), const Duration(minutes: 3));
      expect(cache.of('a'), const Duration(minutes: 3));
      player.dispose();
    });

    test('al cambiar de canción no se anota la duración de una en la otra', () async {
      backend
        ..add('a')
        ..add('b');
      final tracks = List.of(backend.tracks); // b, a
      final engine = FakeEngine();
      final player = PlayerController(backend, engine, durations: cache, noteAfter: const Duration(milliseconds: 40));
      await player.play(tracks[0], tracks); // suena b; el motor dice 3:00 y se espera un poco antes de anotar
      engine.emitIndex(1); // pasa a a…
      engine.emitDuration(const Duration(minutes: 5)); // …y ahora dice que dura 5:00
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(cache.of('b'), isNull); // los 3:00 eran un resto de b mientras ya sonaba a
      expect(cache.of('a'), const Duration(minutes: 5));
      player.dispose();
    });
  });

  group('lista de canciones', () {
    late FakeMusicBackend backend;
    late MemoryMusicStore store;
    late FakeSaver saver;
    late MusicController music;
    late LocalMusicController local;
    late FakeEngine engine;
    late PlayerController player;
    late MemoryDurationCache cache;

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      store = MemoryMusicStore(since: DateTime.utc(2026, 10, 1))..settings = store.settings;
      saver = FakeSaver();
      cache = MemoryDurationCache();
      music = MusicController(backend, store, saver);
      local = LocalMusicController(music, saver, durations: cache);
      engine = FakeEngine();
      player = PlayerController(backend, engine, durations: cache, noteAfter: Duration.zero);
      addTearDown(() {
        player.dispose();
        local.dispose();
        music.dispose();
      });
    }

    /// Abre la música y el álbum de la tarjeta `card` (la número `index` del mazo).
    Future<void> show(WidgetTester tester, {String card = 'card-received', int index = 0}) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(music.start);
      await tester.runAsync(pumpEventQueue);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          // el disco no gira: si no, `pumpAndSettle` no terminaría nunca mientras suene algo
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
          home: MusicPage(controller: music, player: player, local: local),
        ),
      );
      await tester.pump();
      await openAlbum(tester, index, card);
    }

    setUp(() {
      backend = FakeMusicBackend();
      store = MemoryMusicStore()..settings = const MusicSettings(auto: false);
    });

    testWidgets('«Recibidas»: se enseña la primera con su nombre; la lista va de la más nueva a la más antigua', (tester) async {
      backend
        ..add('a', title: 'Brambles - Solitude')
        ..add('b', title: 'Segunda')
        ..add('c', title: 'Tercera');
      await open(tester);
      await show(tester);
      expect(songTitle(tester), 'Tercera c');
      await openList(tester);
      expect(find.text('01'), findsNothing);
      // la lista llega de la más nueva a la más antigua: c, b, a (de arriba abajo)
      final ys = [
        for (final id in ['c', 'b', 'a']) tester.getTopLeft(find.byKey(Key('track-$id'))).dy,
      ];
      expect(ys[0], lessThan(ys[1]));
      expect(ys[1], lessThan(ys[2]));
      await playRow(tester, find.byKey(const Key('track-a')), 'a'); // la tercera
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      await openList(tester); // se cierra
      expect(songTitle(tester), 'Solitude a'); // sin el artista: va en la línea de abajo
      expect(ringLine(tester), startsWith('Brambles'));
    });

    testWidgets('la línea de abajo usa la lista de YouTube cuando el nombre no trae artista', (tester) async {
      backend.add('a', playlist: 'Rock');
      await open(tester);
      await show(tester);
      expect(ringLine(tester), 'Rock');
    });

    testWidgets('la que suena lleva el ecualizador sobre su portada en la lista, y la pausa cuando se para', (tester) async {
      backend
        ..add('a')
        ..add('b');
      await open(tester);
      await show(tester);
      await openList(tester);
      expect(find.byKey(const Key('now-playing')), findsNothing);
      await playRow(tester, find.byKey(const Key('track-a')), 'a'); // es la segunda de la lista
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const Key('track-a')), matching: find.byIcon(Icons.graphic_eq_rounded)), findsOneWidget); // solo la que suena
      expect(find.descendant(of: find.byKey(const Key('track-b')), matching: find.byIcon(Icons.graphic_eq_rounded)), findsNothing);
      await tester.tap(find.byKey(const Key('arc-play-a')));
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      expect(find.descendant(of: find.byKey(const Key('track-a')), matching: find.byIcon(Icons.graphic_eq_rounded)), findsNothing);
      expect(find.descendant(of: find.byKey(const Key('track-a')), matching: find.byKey(const Key('now-playing'))), findsOneWidget); // en pausa
    });

    testWidgets('la duración de una recibida aparece cuando el reproductor la conoce', (tester) async {
      backend.add('a', title: 'Brambles - Solitude');
      await open(tester);
      await show(tester);
      expect(ringLine(tester), 'Brambles'); // aún no se sabe lo que dura
      await tester.tap(find.byKey(const Key('album-disc-received'))); // el disco: suena
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      expect(ringLine(tester), 'Brambles • 3:00'); // y al sonar el reproductor sabe cuánto dura
    });

    testWidgets('guardar está en el menú ⋯: ofrece guardar, enseña la marca al guardarse y luego la deja desactivada', (tester) async {
      backend.add('a');
      await open(tester);
      await show(tester);
      await openList(tester);
      expect(find.byKey(const Key('saved')), findsNothing);
      await tester.tap(find.byKey(const Key('more-a')));
      await tester.pumpAndSettle();
      expect(find.text('Guardar en el teléfono'), findsOneWidget);
      await tester.tap(find.byKey(const Key('save-a')));
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('saved')), findsOneWidget);
      await tester.pump(const Duration(seconds: 6)); // el aviso de abajo tapa el menú un momento
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('more-a')));
      await tester.pumpAndSettle();
      expect(find.text('Guardada en el teléfono'), findsOneWidget);
      expect(tester.widget<PopupMenuItem<String>>(find.byKey(const Key('save-a'))).enabled, isFalse);
    });

    testWidgets('si no se pudo guardar, la línea de abajo da el motivo y el menú dice «Reintentar»', (tester) async {
      backend.add('a');
      await open(tester);
      await show(tester);
      await openList(tester);
      saver.failWith = const TrackSaveException('No hay espacio.');
      await tester.tap(find.byKey(const Key('more-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-a')));
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      expect(find.text('No hay espacio. · toca ⋯ para reintentar'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6)); // el aviso de abajo tapa el menú un momento
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('more-a')));
      await tester.pumpAndSettle();
      expect(find.text('Reintentar'), findsOneWidget);
      saver.failWith = null;
      await tester.tap(find.byKey(const Key('save-a')));
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('saved')), findsOneWidget);
    });

    testWidgets('«En el teléfono» enseña la duración leída de cada archivo', (tester) async {
      store.settings = const MusicSettings(auto: false).withTree('content://tree/musica', 'Mi música');
      await open(tester);
      saver
        ..files = [song('Alfa - Uno.mp3'), song('Beta.mp3')]
        ..durations['content://tree/musica/document/Alfa - Uno.mp3'] = const Duration(minutes: 4, seconds: 21);
      await show(tester, card: 'card-root', index: 1);
      expect(songTitle(tester), 'Uno');
      expect(ringLine(tester), 'Alfa • 4:21');
      await openList(tester);
      final alfa = find.byKey(const Key('local-local:content://tree/musica/document/Alfa - Uno.mp3'));
      final beta = find.byKey(const Key('local-local:content://tree/musica/document/Beta.mp3'));
      expect(find.descendant(of: alfa, matching: find.text('Alfa • 4:21')), findsOneWidget);
      expect(find.descendant(of: beta, matching: find.text('Mi música')), findsOneWidget); // «Beta» no trae artista ni duración: sale la carpeta
      await playRow(tester, beta, 'local:content://tree/musica/document/Beta.mp3');
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      await openList(tester); // se cierra
      expect(songTitle(tester), 'Beta');
      expect(ringLine(tester), startsWith('Mi música')); // y al sonar, su duración
    });
  });

  group('corazones, carátulas y filas compactas', () {
    test('los favoritos se recuerdan en el almacén y se quitan al volver a tocar', () async {
      final store = MemoryFavoritesStore();
      final first = FavoritesController(store);
      await first.toggle('k1');
      await first.toggle('k2');
      await first.toggle('k1');
      expect((first.isFavorite('k1'), first.isFavorite('k2'), first.count), (false, true, 1));
      expect(FavoritesController(store).isFavorite('k2'), isTrue); // al abrir la app otra vez siguen
    });

    test('las carátulas incrustadas se piden una sola vez por archivo y los que no traen no se repiten', () async {
      final backend = FakeMusicBackend();
      final store = MemoryMusicStore(since: DateTime.utc(2026, 10, 1))
        ..settings = const MusicSettings(auto: false).withTree('content://tree/musica', 'Mi música');
      final saver = FakeSaver()
        ..files = [song('Con.mp3'), song('Sin.mp3')]
        ..art['content://tree/musica/document/Con.mp3'] = '/cache/art/con.jpg';
      final music = MusicController(backend, store, saver);
      final local = LocalMusicController(music, saver);
      await music.start();
      await pumpEventQueue();
      final byTitle = {for (final t in local.songs) t.title: local.artOf(t)};
      // la carátula es la del álbum: «Sin» no trae, así que enseña la de la primera que sí (la de «Con»)
      expect(byTitle, {'Con': '/cache/art/con.jpg', 'Sin': '/cache/art/con.jpg'});
      saver.artReads.clear();
      await local.refresh();
      await pumpEventQueue();
      expect(saver.artReads, isEmpty);
      local.dispose();
      music.dispose();
    });

    testWidgets('el corazón de una fila se marca y la fila mide poco (compacta)', (tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final backend = FakeMusicBackend()
        ..add('a', title: 'Dua Lipa - Sweetest Pie')
        ..add('b', title: 'Stay');
      final store = MemoryMusicStore(since: DateTime.utc(2026, 10, 1))..settings = const MusicSettings(auto: false);
      final music = MusicController(backend, store, FakeSaver());
      final favStore = MemoryFavoritesStore();
      final favorites = FavoritesController(favStore);
      addTearDown(music.dispose);
      await tester.runAsync(music.start);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: MusicPage(controller: music, favorites: favorites),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.favorite), findsNothing);
      await tester.tap(find.byKey(const Key('fav-1'))); // la primera de la lista es «Stay» (b, la más nueva)
      await tester.pump();
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(favStore.keys, {'b'});
      await tester.tap(find.byKey(const Key('fav-1')));
      await tester.pump();
      expect(find.byIcon(Icons.favorite), findsNothing);
      expect(favStore.keys, isEmpty);
      expect(tester.getSize(find.byKey(const Key('track-b'))).height, lessThanOrEqualTo(62));
      expect(find.text('Sweetest Pie a'), findsOneWidget);
      expect(find.text('Dua Lipa'), findsOneWidget);
    });
  });
}

/// Un caché que deja leer pero cuyo guardado falla: Android contesta, lo anotado no se puede guardar.
class _Failing implements DurationCache {
  _Failing(this._inner);

  final DurationCache _inner;

  @override
  Duration? of(String key) => _inner.of(key);

  @override
  Future<void> putAll(Map<String, Duration> found) async => throw StateError('sin espacio');
}
