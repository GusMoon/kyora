import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/music_store.dart';
import 'package:kyora_chat/models/track.dart';
import 'package:kyora_chat/state/local_music_controller.dart';
import 'package:kyora_chat/state/music_controller.dart';
import 'package:kyora_chat/state/player_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/player_page.dart';
import 'package:kyora_chat/ui/widgets/queue_disc.dart';
import 'package:kyora_chat/util/cover_color.dart';

import 'fake_engine.dart';
import 'music_test.dart' show FakeMusicBackend, FakeSaver, MemoryMusicStore;

const root = 'content://tree/musica';

LocalSong song(String name, {String dir = 'musica'}) => LocalSong(
  uri: 'content://tree/$dir/document/$name',
  name: name,
  sizeBytes: 3 * 1024 * 1024,
  modified: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
);

const rock = LocalFolder(uri: 'content://tree/musica/document/Rock', name: 'Rock', count: 1);
const jazz = LocalFolder(uri: 'content://tree/musica/document/Jazz', name: 'Jazz', count: 0);

void main() {
  late FakeMusicBackend backend;
  late MemoryMusicStore store;
  late FakeSaver saver;
  late MusicController music;
  late LocalMusicController local;

  setUp(() {
    backend = FakeMusicBackend();
    store = MemoryMusicStore(since: DateTime.utc(2026, 10, 1))..settings = const MusicSettings(auto: false).withTree(root, 'Mi música');
    saver = FakeSaver()
      ..files = [song('b.mp3'), song('a.mp3'), song('c.mp3')]
      ..rootFolders = [rock, jazz]
      ..dirSongs[rock.uri] = [song('rock1.mp3', dir: 'rock')];
    music = MusicController(backend, store, saver);
    local = LocalMusicController(music, saver);
  });

  tearDown(() {
    local.dispose();
    music.dispose();
  });

  Future<void> start() async {
    await music.start();
    await pumpEventQueue();
  }

  group('carpetas (controlador)', () {
    test('la raíz enseña sus subcarpetas (ordenadas) y sus canciones', () async {
      await start();
      expect(local.folders.map((f) => f.name), ['Jazz', 'Rock']);
      expect(local.songs.map((t) => t.title), ['a', 'b', 'c']);
      expect(local.atRoot, isTrue);
      expect(local.currentUri, isNull);
    });

    test('entrar en una carpeta lee solo esa, subir y volver a un tramo de la ruta funcionan', () async {
      saver.dirFolders[rock.uri] = [const LocalFolder(uri: 'content://tree/musica/document/Rock/Viejo', name: 'Viejo')];
      await start();
      await local.open(rock);
      expect(saver.listed, contains(rock.uri));
      expect(local.songs.map((t) => t.title), ['rock1']);
      expect(local.path.map((f) => f.name), ['Rock']);
      expect(local.currentUri, rock.uri);
      await local.open(local.folders.single);
      expect(local.path.map((f) => f.name), ['Rock', 'Viejo']);
      await local.goTo(1);
      expect(local.path.map((f) => f.name), ['Rock']);
      await local.up();
      expect(local.atRoot, isTrue);
      expect(local.songs.length, 3);
      await local.up(); // en la raíz no hace nada
      expect(local.atRoot, isTrue);
    });

    test('cambiar de carpeta elegida vuelve a la raíz', () async {
      await start();
      await local.open(rock);
      await music.updateSettings(music.settings.withTree('content://tree/otra', 'Otra'));
      await pumpEventQueue();
      expect(local.atRoot, isTrue);
      expect(saver.listed, contains('content://tree/otra'));
    });

    test('marcar: tocar marca y desmarca, «todas» marca todas y «atrás» primero quita la marca', () async {
      await start();
      local.toggleSelect(local.songs[0]);
      local.toggleSelect(local.songs[1]);
      expect((local.selecting, local.selectedCount), (true, 2));
      local.toggleSelect(local.songs[0]);
      expect(local.selectedSongs.map((t) => t.title), ['b']);
      local.selectAll();
      expect(local.selectedCount, 3);
      expect(local.back(), isTrue); // quita la selección
      expect(local.selecting, isFalse);
      await local.open(rock);
      expect(local.back(), isTrue); // sube a la raíz
      await pumpEventQueue();
      expect(local.atRoot, isTrue);
      expect(local.back(), isFalse); // no hay nada más que deshacer
    });

    test('crear una carpeta la hace de verdad en la carpeta actual y aparece', () async {
      await start();
      final made = await local.createFolder('  Pop  ');
      expect(made.name, 'Pop');
      expect(saver.created.single, (parent: null, name: 'Pop'));
      expect(local.folders.map((f) => f.name), contains('Pop'));
      await local.open(rock);
      await local.createFolder('Lento');
      expect(saver.created.last, (parent: rock.uri, name: 'Lento'));
      expect(local.folders.map((f) => f.name), ['Lento']);
    });

    test('un nombre vacío o con barras se rechaza sin tocar nada', () async {
      await start();
      for (final bad in ['', '   ', 'a/b', r'a\b']) {
        await expectLater(local.createFolder(bad), throwsA(isA<TrackSaveException>()));
      }
      expect(saver.created, isEmpty);
    });

    test('si no se pudo crear, el motivo llega tal cual', () async {
      saver.createFails = const TrackSaveException('Android no dejó crear la carpeta «X».');
      await start();
      await expectLater(local.createFolder('X'), throwsA(isA<TrackSaveException>().having((e) => e.message, 'message', contains('Android no dejó'))));
    });

    test('mover las marcadas: salen de la carpeta de origen, entran en la de destino y se quita la selección', () async {
      await start();
      local.toggleSelect(local.songs[0]); // a
      local.toggleSelect(local.songs[2]); // c
      final result = await local.moveSelected(toUri: rock.uri);
      expect(result.moved, 2);
      expect(saver.moves.single.from, isNull);
      expect(saver.moves.single.to, rock.uri);
      expect(saver.moves.single.uris, ['content://tree/musica/document/a.mp3', 'content://tree/musica/document/c.mp3']);
      expect(local.songs.map((t) => t.title), ['b']); // lo que queda en la raíz
      expect(local.selecting, isFalse);
      await local.open(rock);
      expect(local.songs.map((t) => t.title), ['a', 'c', 'rock1']);
    });

    test('mover desde una subcarpeta a la raíz', () async {
      await start();
      await local.open(rock);
      local.selectAll();
      await local.moveSelected(toUri: null);
      expect(saver.moves.single.from, rock.uri);
      expect(local.songs, isEmpty);
      await local.up();
      expect(local.songs.map((t) => t.title), ['a', 'b', 'c', 'rock1']);
    });

    test('a la misma carpeta no se mueve y no se pide nada', () async {
      await start();
      local.selectAll();
      await expectLater(local.moveSelected(toUri: null), throwsA(isA<TrackSaveException>()));
      expect(saver.moves, isEmpty);
    });

    test('las que no se pudieron mover se cuentan con su motivo y se quedan donde estaban', () async {
      saver.moveFailures['content://tree/musica/document/b.mp3'] = 'No se pudo borrar el original.';
      await start();
      local.selectAll();
      final result = await local.moveSelected(toUri: jazz.uri);
      expect(result.moved, 2);
      expect(result.failures, {'content://tree/musica/document/b.mp3': 'No se pudo borrar el original.'});
      expect(local.songs.map((t) => t.title), ['b']);
    });

    test('si Android rechaza todo el movimiento, el error sale y la lista se vuelve a leer igual', () async {
      saver.moveFails = const TrackSaveException('Android ya no deja escribir en «Mi música»: elige la carpeta otra vez.', folderLost: true);
      await start();
      local.selectAll();
      await expectLater(local.moveSelected(toUri: rock.uri), throwsA(isA<TrackSaveException>()));
      expect(local.selecting, isFalse);
      expect(local.songs.length, 3);
    });
  });

  group('navegar sin esperas', () {
    test('una carpeta ya leída (por adelantado) se enseña al instante, sin esperar a Android', () async {
      await start(); // al leer la raíz se leen en silencio sus subcarpetas
      expect(saver.listed, containsAll([rock.uri, jazz.uri]));
      final entering = local.open(rock);
      // sin esperar nada: ya están sus canciones y no hay «cargando»
      expect(local.songs.map((t) => t.title), ['rock1']);
      expect(local.loading, isFalse);
      await entering;
    });

    test('al volver a la raíz también sale al instante', () async {
      await start();
      await local.open(rock);
      final back = local.up();
      expect(local.songs.map((t) => t.title), ['a', 'b', 'c']);
      expect(local.folders.map((f) => f.name), ['Jazz', 'Rock']);
      await back;
    });

    test('una carpeta que no se había leído nunca deja la lista vacía y «cargando», nunca la de la carpeta anterior', () async {
      saver.rootFolders = [
        for (var i = 0; i < 50; i++) LocalFolder(uri: 'content://tree/musica/document/F$i', name: 'F${i.toString().padLeft(2, '0')}'),
      ];
      saver.dirSongs['content://tree/musica/document/F49'] = [song('lejana.mp3', dir: 'f49')];
      await start();
      expect(saver.listed.contains('content://tree/musica/document/F49'), isFalse); // más allá de las que se leen por adelantado
      final entering = local.open(local.folders.last);
      expect(local.songs, isEmpty); // no queda la lista de la raíz
      expect(local.folders, isEmpty);
      expect(local.loading, isTrue);
      await entering;
      expect(local.songs.map((t) => t.title), ['lejana']);
      expect(local.loading, isFalse);
    });

    test('la carpeta que tocas no espera a que termine otra lectura lenta, y esa lectura no pisa lo que se ve', () async {
      saver.rootFolders = [
        for (var i = 0; i < 50; i++) LocalFolder(uri: 'content://tree/musica/document/F$i', name: 'F${i.toString().padLeft(2, '0')}'),
      ];
      saver.dirSongs['content://tree/musica/document/F49'] = [song('lejana.mp3', dir: 'f49')];
      await start();
      final slow = Completer<void>();
      saver.holdRoot = slow.future;
      final rereading = local.refresh(); // la raíz se relee, lenta
      await pumpEventQueue();
      await local.open(local.folders.last); // termina sin que la raíz haya acabado
      expect(local.songs.map((t) => t.title), ['lejana']);
      expect(local.loading, isFalse);
      slow.complete();
      await rereading;
      await pumpEventQueue();
      expect(local.songs.map((t) => t.title), ['lejana']); // lo viejo de la raíz no aparece aquí
      expect(local.rootSongCount, 3); // pero sí queda al día para las tarjetas
    });

    test('si mientras se leía una carpeta se pasó a otra, el resultado viejo no pisa lo que se ve', () async {
      await start();
      final first = local.open(rock); // empieza a leer Rock…
      final second = local.up(); // …y ya se volvió a la raíz
      await Future.wait([first, second]);
      await pumpEventQueue();
      expect(local.atRoot, isTrue);
      expect(local.songs.map((t) => t.title), ['a', 'b', 'c']);
    });

    test('lo que se movió o creó se vuelve a leer: la copia vieja de la carpeta no se enseña', () async {
      await start();
      local.toggleSelect(local.songs.first);
      await local.moveSelected(toUri: rock.uri);
      final entering = local.open(rock);
      await entering;
      expect(local.songs.map((t) => t.title), ['a', 'rock1']);
    });
  });

  group('carátula del teléfono', () {
    test('se lee la de la canción que va a sonar aunque la lista no la hubiera leído todavía', () async {
      saver.art['content://tree/musica/document/a.mp3'] = '/cache/art/a-600.jpg';
      final track = Track.local(song('a.mp3'));
      expect(local.artOf(track), isNull);
      await local.load(track);
      expect(local.artOf(track), '/cache/art/a-600.jpg');
    });

    test('el reproductor la da para el fondo y se actualiza cuando aparece', () async {
      saver.art['content://tree/musica/document/a.mp3'] = '/cache/art/a-600.jpg';
      final track = Track.local(song('a.mp3'));
      final engine = FakeEngine();
      final player = PlayerController(backend, engine, art: local, noteAfter: Duration.zero);
      var told = 0;
      player.addListener(() => told++);
      expect(player.coverFileOf(track), isNull);
      await player.play(track, [track]); // al empezar pide su carátula
      await pumpEventQueue();
      expect(player.coverFileOf(track), '/cache/art/a-600.jpg');
      expect(told, greaterThan(0));
      expect(player.coverFileOf(null), isNull);
      player.dispose();
    });
  });

  group('fondo del reproductor', () {
    test('donde termina la carátula es justo donde el disco toca los lados de la pantalla', () {
      const width = 400.0;
      final r = width * QueueDisc.radiusFactor;
      final discTop = 850 - QueueDisc.heightFor(width, 0) + QueueDisc.band;
      final y = 850 - QueueDisc.coverBottomFor(width, 0);
      // el punto (borde de la pantalla, y) cae sobre el círculo del disco
      expect(Offset(width / 2, y - (discTop + r)).distance, closeTo(r, 0.01));
    });

    test('el color de la carátula es el que más se ve, y lo vivo pesa más', () {
      Uint8List pixels(List<List<int>> rgb) => Uint8List.fromList([
        for (final c in rgb) ...[...c, 255],
      ]);
      final red = dominantColor(
        pixels([
          for (var i = 0; i < 90; i++) [200, 20, 20],
          for (var i = 0; i < 10; i++) [20, 20, 200],
        ]),
      )!;
      expect(HSVColor.fromColor(red).hue, anyOf(lessThan(15), greaterThan(345)));
      // mucho gris y poco color: gana el color
      final blue = dominantColor(
        pixels([
          for (var i = 0; i < 80; i++) [120, 120, 120],
          for (var i = 0; i < 20; i++) [10, 40, 220],
        ]),
      )!;
      expect(HSVColor.fromColor(blue).hue, inInclusiveRange(210, 240));
      // todo gris: no hay color que dar
      expect(
        dominantColor(
          pixels([
            for (var i = 0; i < 50; i++) [90, 90, 90],
          ]),
        ),
        isNull,
      );
      expect(dominantColor(Uint8List(0)), isNull);
    });

    test('la carátula de YouTube se pide en grande; las demás direcciones no cambian', () {
      expect(sharperCover('https://i.ytimg.com/vi/abc/hqdefault.jpg'), 'https://i.ytimg.com/vi/abc/maxresdefault.jpg');
      expect(sharperCover('https://img.test/a.jpg'), 'https://img.test/a.jpg');
    });

    testWidgets('con una canción del teléfono, el fondo es su carátula; sin ella, solo el degradado', (tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      saver.art['content://tree/musica/document/a.mp3'] = '/cache/art/a-600.jpg';
      final engine = FakeEngine();
      final player = PlayerController(backend, engine, art: local, noteAfter: Duration.zero);
      addTearDown(player.dispose);
      await tester.runAsync(() async {
        await music.start();
        await pumpEventQueue();
        await player.play(local.songs.firstWhere((t) => t.title == 'a'), local.songs);
        await pumpEventQueue();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: PlayerPage(player: player),
        ),
      );
      await tester.pump(const Duration(seconds: 6)); // el análisis de color de la carátula espera su tiempo de gracia
      expect(find.byKey(const Key('cover-file-bg')), findsOneWidget);
      // la carátula ocupa solo lo que se ve por encima del disco, no toda la pantalla
      final cover = tester.getRect(find.byKey(const Key('cover-file-bg')));
      expect(cover.top, 0);
      expect(cover.width, 400);
      expect(cover.bottom, closeTo(850 - QueueDisc.coverBottomFor(400, 0), 0.01));
      expect(cover.bottom, lessThan(850 * 0.8));
      expect(find.byKey(const Key('disc-blur')), findsNothing); // ya no hay borroso, solo una sombra leve
      expect(find.byKey(const Key('disc-dark')), findsOneWidget);
      // «b» no trae carátula, pero la del álbum es de todas sus canciones: el fondo sigue siendo esa
      await tester.runAsync(() => player.play(local.songs.firstWhere((t) => t.title == 'b'), local.songs));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('cover-file-bg')), findsOneWidget);
      // una de otro álbum, sin carátula en ninguna de sus canciones: solo el degradado
      final other = Track.local(song('rock1.mp3', dir: 'rock'));
      await tester.runAsync(() => player.play(other, [other]));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('cover-file-bg')), findsNothing);
      expect(find.byKey(const Key('player-backdrop')), findsOneWidget);
      expect(find.byKey(const Key('disc-dark')), findsOneWidget);
    });
  });
}
