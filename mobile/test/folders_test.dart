import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/favorites_store.dart';
import 'package:kyora_chat/data/music_store.dart';
import 'package:kyora_chat/data/cover_store.dart';
import 'package:kyora_chat/models/track.dart';
import 'package:kyora_chat/state/local_music_controller.dart';
import 'package:kyora_chat/state/music_controller.dart';
import 'package:kyora_chat/state/player_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/music_page.dart';
import 'package:kyora_chat/ui/player_page.dart';
import 'package:kyora_chat/ui/widgets/album_grid.dart';
import 'package:kyora_chat/ui/widgets/app_backdrop.dart';
import 'package:kyora_chat/ui/widgets/cover.dart';
import 'package:kyora_chat/ui/widgets/song_ring.dart';
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

/// El título de la canción de enfrente en la pantalla de un álbum.
String ringTitle(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('ring-title'))).data!;

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
      await tester.runAsync(() => player.play(local.songs.firstWhere((t) => t.title == 'b'), local.songs)); // «b» no trae carátula
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('cover-file-bg')), findsNothing);
      expect(find.byKey(const Key('player-backdrop')), findsOneWidget);
      expect(find.byKey(const Key('disc-dark')), findsOneWidget);
    });
  });

  group('cuadrícula de álbumes', () {
    late FakeEngine engine;
    late PlayerController player;

    Future<void> home(WidgetTester tester, {Future<String?> Function()? pickCover}) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      engine = FakeEngine();
      player = PlayerController(backend, engine, noteAfter: Duration.zero);
      addTearDown(player.dispose);
      await tester.runAsync(music.start);
      await tester.runAsync(pumpEventQueue);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: pickCover == null
              ? MusicPage(controller: music, local: local, player: player)
              : MusicPage(controller: music, local: local, player: player, pickCover: pickCover),
        ),
      );
      await tester.pump();
    }

    Finder card(String key) => find.byKey(ValueKey(key));

    const names = {
      'card-received': 'Canciones enviadas',
      'card-root': 'Mi música',
      'card-folder-Jazz': 'Jazz',
      'card-folder-Rock': 'Rock',
      'card-new-folder': 'Nuevo álbum',
    };

    testWidgets('salen «Canciones enviadas», la carpeta principal, los álbumes y «Nuevo álbum», en cuadrícula de tres en tres', (tester) async {
      backend.add('r', at: DateTime.utc(2026, 9, 1));
      await home(tester);
      expect(find.byKey(const Key('music-grid')), findsOneWidget);
      final ids = names.keys.toList();
      for (final id in ids) {
        expect(card(id), findsOneWidget);
      }
      expect(find.byKey(const Key('view-toggle')), findsNothing); // ya no hay otra vista
      final tops = [for (final id in ids) tester.getTopLeft(card(id))];
      expect(tops[0].dy, tops[1].dy); // la misma fila
      expect(tops[1].dy, tops[2].dy);
      expect(tops[0].dx, lessThan(tops[1].dx));
      expect(tops[1].dx, lessThan(tops[2].dx));
      expect(tops[3].dy, greaterThan(tops[0].dy)); // la cuarta pasa a la fila de abajo
      expect(tops[3].dx, tops[0].dx);
    });

    testWidgets('las casillas son cuadradas, sin esquinas redondeadas, sin nombre ni ▶, y el hueco es el mismo hacia los lados y hacia abajo', (
      tester,
    ) async {
      await home(tester);
      final a = tester.getRect(card('card-received'));
      final b = tester.getRect(card('card-root'));
      final c = tester.getRect(card('card-folder-Jazz'));
      final d = tester.getRect(card('card-folder-Rock'));
      expect(a.width, a.height);
      expect(b.left - a.right, AlbumGrid.gap); // casillas muy pegadas
      expect(c.left - b.right, AlbumGrid.gap);
      expect(d.top - a.bottom, AlbumGrid.gap); // y el mismo hueco entre filas
      expect(a.left, AlbumGrid.gap); // y con el borde de la pantalla
      expect(find.byType(ClipRRect), findsNothing);
      expect(find.byKey(const Key('plate-name')), findsNothing);
      expect(find.text('Rock'), findsNothing);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
      // sigue siendo accesible: el nombre lo lee el lector de pantalla
      expect(find.bySemanticsLabel('Rock'), findsOneWidget);
      // una casilla abre su álbum
      await tester.tap(card('card-folder-Rock'));
      await tester.pumpAndSettle();
      expect(ringTitle(tester), 'rock1');
    });

    testWidgets('mantener pulsado un álbum le pone la imagen elegida, solo en el teléfono; se puede quitar', (tester) async {
      var picks = 0;
      final covers = MemoryCoverStore();
      local.dispose();
      local = LocalMusicController(music, saver, covers: covers);
      await home(tester, pickCover: () async => '/portada${++picks}.jpg');
      await tester.longPress(card('card-folder-Jazz'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('album-cover-clear')), findsNothing); // aún no tiene
      await tester.tap(find.byKey(const Key('album-cover-pick')));
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      expect(picks, 1);
      expect(local.albumCoverOf(jazz.uri), saver.storedCovers.last.path);
      expect(saver.storedCovers.last.keep, isTrue); // vive en la app, no en el .mp3 ni en Supabase
      expect(covers.load().values, contains(saver.storedCovers.last.path)); // y queda recordada
      expect(find.descendant(of: card('card-folder-Jazz'), matching: find.byKey(const Key('plate-blank'))), findsNothing);
      expect(find.descendant(of: card('card-folder-Jazz'), matching: find.byKey(const Key('cover-file'))), findsOneWidget);
      // la de otro álbum no cambió
      expect(local.albumCoverOf(rock.uri), isNull);
      // quitarla
      await tester.longPress(card('card-folder-Jazz'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('album-cover-clear')));
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      expect(local.albumCoverOf(jazz.uri), isNull);
      expect(covers.load(), isEmpty);
      expect(find.descendant(of: card('card-folder-Jazz'), matching: find.byKey(const Key('plate-blank'))), findsOneWidget);
    });

    testWidgets('si se cancela la elección de la imagen, el álbum se queda como estaba', (tester) async {
      await home(tester, pickCover: () async => null);
      await tester.longPress(card('card-root'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('album-cover-pick')));
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      expect(local.albumCoverOf('root'), isNull);
      expect(saver.storedCovers, isEmpty);
    });

    testWidgets('la imagen elegida manda sobre la de las canciones del álbum', (tester) async {
      saver.art[rock.uri] = '/embebida.jpg';
      await home(tester, pickCover: () async => '/mia.jpg');
      await tester.longPress(card('card-root'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('album-cover-pick')));
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      final cover = tester.widget<Cover>(find.descendant(of: card('card-root'), matching: find.byType(Cover)));
      expect(cover.file, saver.storedCovers.last.path);
    });

    testWidgets('en Favoritos no hay cuadrícula', (tester) async {
      await home(tester);
      await tester.tap(find.byKey(const Key('tab-favorites')));
      await tester.pump();
      expect(find.byKey(const Key('music-grid')), findsNothing);
    });

    testWidgets('la píldora cambia entre Álbumes y Favoritos', (tester) async {
      await home(tester);
      expect(find.byKey(const Key('album-tabs')), findsOneWidget);
      expect(find.text('Álbumes'), findsOneWidget);
      expect(find.text('Favoritos'), findsOneWidget);
      expect(card('card-root'), findsOneWidget);
      await tester.tap(find.byKey(const Key('tab-favorites')));
      await tester.pump();
      expect(card('card-root'), findsNothing);
      expect(find.byKey(const Key('favorites-empty')), findsOneWidget);
      await tester.tap(find.byKey(const Key('tab-albums')));
      await tester.pump();
      expect(card('card-root'), findsOneWidget);
    });

    testWidgets('Favoritos enseña las canciones con el corazón, las enviadas y las de los álbumes ya leídos', (tester) async {
      backend.add('r', at: DateTime.utc(2026, 9, 1));
      final favorites = FavoritesController();
      await tester.runAsync(music.start);
      await tester.runAsync(pumpEventQueue);
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(local.refresh);
      await tester.runAsync(pumpEventQueue);
      await favorites.toggle(music.tracks.single.durationKey);
      await favorites.toggle(local.knownTracks().firstWhere((t) => t.title == 'rock1').durationKey);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: MusicPage(controller: music, local: local, favorites: favorites),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('tab-favorites')));
      await tester.pump();
      expect(find.byKey(const Key('favorites-list')), findsOneWidget);
      expect(find.text('rock1'), findsOneWidget);
      expect(find.byKey(Key('track-${music.tracks.single.id}')), findsOneWidget);
      expect(find.text('a'), findsNothing); // sin corazón
      await favorites.toggle(local.knownTracks().firstWhere((t) => t.title == 'rock1').durationKey);
      await tester.pump();
      expect(find.text('rock1'), findsNothing);
    });

    test('conoce las canciones de la raíz y de las subcarpetas leídas por adelantado, sin repetir', () async {
      await start();
      await pumpEventQueue();
      expect(local.knownTracks().map((t) => t.title), ['a', 'b', 'c', 'rock1']);
    });

    testWidgets('una carpeta ya leída se abre al instante: sus canciones ya están en el primer cuadro y la animación del anillo termina sola', (
      tester,
    ) async {
      await home(tester);
      await tester.tap(card('card-folder-Rock'));
      await tester.pump(); // el toque
      await tester.pump(const Duration(milliseconds: 16)); // el cuadro siguiente: Flutter tiene la pantalla nueva oculta en el primero
      expect(ringTitle(tester), 'rock1'); // las canciones ya están, sin esperar a Android
      expect(find.byType(SongRing), findsOneWidget); // y el anillo empieza a abrirse
      await tester.pump(const Duration(milliseconds: 700)); // lo que dura la animación
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('abrir una carpeta enseña sus canciones; «atrás» vuelve a las tarjetas y el controlador a la raíz', (tester) async {
      await home(tester);
      await tester.tap(card('card-folder-Rock'));
      await tester.pumpAndSettle();
      expect(ringTitle(tester), 'rock1');
      expect(find.byKey(const Key('album-title')), findsOneWidget);
      expect(find.byKey(const Key('folder-up')), findsNothing); // se entró aquí: atrás ya es volver a las tarjetas
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      expect(card('card-root'), findsOneWidget);
      expect(local.atRoot, isTrue);
    });

    testWidgets(
      'dentro de un álbum, sus carpetas salen arriba como subálbumes; se abren una encima de otra y «atrás» sube de nivel hasta las placas',
      (tester) async {
        saver.dirFolders[rock.uri] = [const LocalFolder(uri: 'content://tree/musica/document/Rock/Viejo', name: 'Viejo')];
        await home(tester);
        await tester.tap(card('card-folder-Rock'));
        await tester.pumpAndSettle();
        expect(ringTitle(tester), 'rock1');
        expect(find.byKey(const Key('subalbum-strip')), findsOneWidget);
        expect(find.byKey(const Key('subalbum-Viejo')), findsOneWidget);
        expect(find.text('Viejo'), findsOneWidget); // su nombre sale en la tarjeta
        expect(find.byKey(const Key('folder-up')), findsNothing);
        await tester.tap(find.byKey(const Key('subalbum-Viejo')));
        await tester.runAsync(pumpEventQueue);
        await tester.pumpAndSettle();
        expect(local.path.map((f) => f.name), ['Rock', 'Viejo']);
        expect(find.text('No hay archivos .mp3 en «Viejo».'), findsOneWidget);
        await tester.pageBack();
        await tester.runAsync(pumpEventQueue);
        await tester.pumpAndSettle();
        expect(local.path.map((f) => f.name), ['Rock']); // volvió a Rock
        expect(ringTitle(tester), 'rock1');
        await tester.binding.handlePopRoute();
        await tester.runAsync(pumpEventQueue);
        await tester.pumpAndSettle();
        expect(card('card-folder-Rock'), findsOneWidget);
        expect(local.atRoot, isTrue);
      },
    );

    testWidgets('un álbum sin carpetas dentro no enseña la tira de subálbumes', (tester) async {
      await home(tester);
      await tester.tap(card('card-folder-Rock'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('subalbum-strip')), findsNothing);
    });

    testWidgets('en las enviadas, «Recibido» solo está en la fila elegida y pasa a la que se elige', (tester) async {
      backend.add('r1', at: DateTime.utc(2026, 9, 1));
      backend.add('r2', at: DateTime.utc(2026, 9, 2)); // la más nueva sale primera
      await home(tester);
      await tester.tap(card('card-received'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('received-r2')), findsOneWidget);
      expect(find.byKey(const Key('received-r1')), findsNothing);
      expect(find.byKey(const Key('more-r2')), findsOneWidget);
      expect(find.byKey(const Key('more-r1')), findsNothing);
      await tester.tap(find.byKey(const Key('track-r1'))); // elegir la otra: la lleva al centro y la reproduce
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('received-r1')), findsOneWidget);
      expect(find.byKey(const Key('received-r2')), findsNothing);
      expect(engine.queue.map((q) => q.title), contains('Canción r1'));
    });

    testWidgets('«Recibido» desde el disco guarda la canción y avisa a Supabase', (tester) async {
      backend.add('r1', at: DateTime.utc(2026, 9, 1));
      await home(tester);
      await tester.tap(card('card-received'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('received-r1')));
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      expect(backend.confirmed, ['r1']);
      expect(find.byKey(const Key('received-mark-r1')), findsOneWidget);
    });

    testWidgets('«Nuevo álbum» lo crea y aparece como otra placa', (tester) async {
      await home(tester);
      await tester.tap(card('card-new-folder'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('folder-name-field')), 'Pop');
      await tester.tap(find.byKey(const Key('folder-create')));
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      expect(card('card-folder-Pop'), findsOneWidget);
      expect(find.text('Se creó el álbum «Pop».'), findsOneWidget);
      expect(saver.created.single.name, 'Pop');
    });

    testWidgets('sin portada, la placa es un recuadro con icono; con la de una canción enviada, la enseña', (tester) async {
      await home(tester);
      expect(find.descendant(of: card('card-received'), matching: find.byKey(const Key('plate-blank'))), findsOneWidget);
      expect(find.descendant(of: card('card-root'), matching: find.byKey(const Key('plate-blank'))), findsOneWidget);
      backend.add('a', cover: 'https://img.test/a.jpg', at: DateTime.utc(2026, 9, 1));
      await tester.runAsync(music.refresh);
      await tester.pump();
      expect(find.descendant(of: card('card-received'), matching: find.byKey(const Key('plate-blank'))), findsNothing);
      expect(find.descendant(of: card('card-received'), matching: find.byType(Cover)), findsOneWidget);
    });

    testWidgets('el fondo de la app va detrás y las pantallas son transparentes para dejarlo ver', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          builder: (context, child) => AppBackdrop(child: child!),
          home: const Scaffold(body: Text('hola')),
        ),
      );
      expect(find.byKey(const Key('app-backdrop')), findsOneWidget);
      expect(tester.widget<Material>(find.descendant(of: find.byType(Scaffold), matching: find.byType(Material)).first).color, Colors.transparent);
    });
  });

  group('carpetas (pantalla)', () {
    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(music.start);
      await tester.runAsync(pumpEventQueue);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: MusicPage(controller: music, local: local),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('card-root')));
      await tester.pumpAndSettle();
    }

    Future<void> settleIo(WidgetTester tester) async {
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
    }

    String uriKey(String name) => 'local-local:content://tree/musica/document/$name';

    testWidgets('la raíz enseña sus canciones en el anillo por orden, sus carpetas como subálbumes, sin ruta ni numeración', (tester) async {
      await open(tester);
      for (final name in ['a.mp3', 'b.mp3', 'c.mp3']) {
        expect(find.byKey(Key(uriKey(name))), findsOneWidget);
      }
      // de izquierda a derecha: a, b, c (la elegida, la primera, está en el centro)
      final xs = [
        for (final n in ['a.mp3', 'b.mp3', 'c.mp3']) tester.getCenter(find.byKey(Key(uriKey(n)))).dx,
      ];
      expect(xs[0], lessThan(xs[1]));
      expect(xs[1], lessThan(xs[2]));
      expect(ringTitle(tester), 'a');
      expect(find.byKey(const Key('subalbum-Rock')), findsOneWidget);
      expect(find.byKey(const Key('subalbum-Jazz')), findsOneWidget);
      expect(find.byKey(const Key('folder-Rock')), findsNothing);
      expect(find.byKey(const Key('crumb-0')), findsNothing);
      expect(find.byKey(const Key('number-1')), findsNothing);
      expect(tester.widget<Text>(find.byKey(const Key('album-title'))).data, 'Mi música'); // el nombre del álbum arriba
    });

    testWidgets('el anillo se gira arrastrando de lado: lo que pasa de media canción llega a la siguiente y lo demás vuelve', (tester) async {
      await open(tester);
      await tester.drag(find.byType(SongRing), const Offset(-30, 0));
      await tester.pumpAndSettle();
      expect(ringTitle(tester), 'a'); // 30 px no llegan a media canción
      await tester.drag(find.byType(SongRing), const Offset(-100, 0));
      await tester.pumpAndSettle();
      expect(ringTitle(tester), 'b');
      await tester.drag(find.byType(SongRing), const Offset(100, 0));
      await tester.pumpAndSettle();
      expect(ringTitle(tester), 'a');
    });

    testWidgets('mantener pulsada una canción marca, tocar otra suma y «Cancelar» quita todo', (tester) async {
      await open(tester);
      await tester.longPress(find.byKey(Key(uriKey('a.mp3'))));
      await tester.pump();
      expect(find.byKey(const Key('selection-count')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('selection-count'))).data, '1 seleccionada');
      await tester.tap(find.byKey(Key(uriKey('b.mp3'))));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('selection-count'))).data, '2 seleccionadas');
      expect(find.byKey(const Key('row-selected')), findsNWidgets(2));
      expect(find.byKey(const Key('row-unselected')), findsOneWidget);
      await tester.tap(find.byKey(const Key('select-all')));
      await tester.pump();
      expect(find.byKey(const Key('row-selected')), findsNWidgets(3));
      await tester.tap(find.byKey(const Key('cancel-selection')));
      await tester.pump();
      expect(find.byKey(const Key('selection-count')), findsNothing);
      expect(find.byKey(const Key('album-back')), findsOneWidget); // ya sin selección: vuelve la barra con el nombre
    });

    testWidgets('«Mover»: se elige la carpeta, «Mover aquí» y las canciones cambian de carpeta de verdad', (tester) async {
      await open(tester);
      await tester.longPress(find.byKey(Key(uriKey('a.mp3'))));
      await tester.pump();
      await tester.tap(find.byKey(Key(uriKey('b.mp3'))));
      await tester.pump();
      await tester.tap(find.byKey(const Key('move-selected')));
      await settleIo(tester);
      expect(tester.widget<Text>(find.byKey(const Key('move-title'))).data, 'Mover 2 canciones a…');
      expect(tester.widget<FilledButton>(find.byKey(const Key('move-here'))).onPressed, isNull); // están en la raíz: ya están aquí
      await tester.tap(find.byKey(const Key('move-folder-Rock')));
      await settleIo(tester);
      expect(tester.widget<Text>(find.byKey(const Key('move-here-name'))).data, 'En: Rock');
      await tester.tap(find.byKey(const Key('move-here')));
      await settleIo(tester);
      expect(saver.moves.single.to, rock.uri);
      expect(find.text('Se movieron 2 canciones a «Rock».'), findsOneWidget);
      expect(find.byKey(Key(uriKey('a.mp3'))), findsNothing);
      expect(find.byKey(Key(uriKey('c.mp3'))), findsOneWidget);
      expect(find.byKey(const Key('selection-count')), findsNothing);
    });

    testWidgets('en la hoja de mover se puede crear una carpeta nueva y mandar las canciones a ella', (tester) async {
      await open(tester);
      await tester.longPress(find.byKey(Key(uriKey('c.mp3'))));
      await tester.pump();
      await tester.tap(find.byKey(const Key('move-selected')));
      await settleIo(tester);
      expect(tester.widget<Text>(find.byKey(const Key('move-title'))).data, 'Mover 1 canción a…');
      await tester.tap(find.byKey(const Key('move-new-folder')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('folder-name-field')), 'Nuevas');
      await tester.tap(find.byKey(const Key('folder-create')));
      await settleIo(tester);
      expect(saver.created.single, (parent: null, name: 'Nuevas'));
      await tester.tap(find.byKey(const Key('move-folder-Nuevas')));
      await settleIo(tester);
      await tester.tap(find.byKey(const Key('move-here')));
      await settleIo(tester);
      expect(find.text('Se movió 1 canción a «Nuevas».'), findsOneWidget);
      expect(saver.dirSongs['content://tree/musica/document/Nuevas']!.map((s) => s.name), ['c.mp3']);
    });

    testWidgets('si alguna no se pudo mover, el aviso lo dice con el motivo', (tester) async {
      saver.moveFailures['content://tree/musica/document/b.mp3'] = 'No se pudo borrar el original.';
      await open(tester);
      await tester.longPress(find.byKey(Key(uriKey('a.mp3'))));
      await tester.pump();
      await tester.tap(find.byKey(Key(uriKey('b.mp3'))));
      await tester.pump();
      await tester.tap(find.byKey(const Key('move-selected')));
      await settleIo(tester);
      await tester.tap(find.byKey(const Key('move-folder-Jazz')));
      await settleIo(tester);
      await tester.tap(find.byKey(const Key('move-here')));
      await settleIo(tester);
      expect(find.textContaining('Se movió 1 canción a «Jazz».'), findsOneWidget);
      expect(find.textContaining('No se pudo mover 1: No se pudo borrar el original.'), findsOneWidget);
    });
  });
}
