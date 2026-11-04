import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/ui/widgets/section_motion.dart';
import 'package:kyora_chat/data/cover_store.dart';
import 'package:kyora_chat/data/favorites_store.dart';
import 'package:kyora_chat/data/music_store.dart';
import 'package:kyora_chat/models/track.dart';
import 'package:kyora_chat/state/local_music_controller.dart';
import 'package:kyora_chat/state/music_controller.dart';
import 'package:kyora_chat/state/player_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/album_view.dart';
import 'package:kyora_chat/ui/music_page.dart';
import 'package:kyora_chat/ui/player_page.dart';
import 'package:kyora_chat/ui/widgets/album_art.dart';
import 'package:kyora_chat/ui/widgets/album_deck.dart';
import 'package:kyora_chat/ui/widgets/app_backdrop.dart';
import 'package:kyora_chat/ui/widgets/cover.dart';
import 'package:kyora_chat/ui/widgets/disc_player.dart';
import 'package:kyora_chat/ui/widgets/sound_circle.dart';

import 'fake_engine.dart';
import 'music_test.dart' show FakeMusicBackend, FakeSaver, MemoryMusicStore;
import 'music_ui.dart';

const root = 'content://tree/musica';

/// Lo que espera el doble toque a un segundo toque.
const kDoubleTapTimeoutForTests = Duration(milliseconds: 400);

LocalSong song(String name, {String dir = 'musica'}) => LocalSong(
      uri: 'content://tree/$dir/document/$name',
      name: name,
      sizeBytes: 3 * 1024 * 1024,
      modified: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
    );

const rock = LocalFolder(uri: 'content://tree/musica/document/Rock', name: 'Rock', count: 1);
const jazz = LocalFolder(uri: 'content://tree/musica/document/Jazz', name: 'Jazz', count: 0);

/// La pantalla de música nueva: el mazo de álbumes (de uno en uno), sus favoritas y la vista de cada álbum (disco, número, lista).
void main() {
  late FakeMusicBackend backend;
  late MemoryMusicStore store;
  late FakeSaver saver;
  late MusicController music;
  late LocalMusicController local;
  late FakeEngine engine;
  late PlayerController player;

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

  // el orden de la ruleta: enviadas (0), la carpeta (1), Jazz (2), Rock (3), «Nuevo álbum» (4)
  // `moving`: el disco gira de verdad mientras suena (entonces `pumpAndSettle` no terminaría nunca)
  Future<void> home(WidgetTester tester, {Future<String?> Function()? pickCover, FavoritesController? favorites, bool moving = false}) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    engine = FakeEngine();
    player = PlayerController(backend, engine, art: local, noteAfter: Duration.zero);
    addTearDown(player.dispose);
    await tester.runAsync(music.start);
    await tester.runAsync(pumpEventQueue);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        builder: moving ? null : (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
        home: MusicPage(controller: music, local: local, player: player, favorites: favorites, pickCover: pickCover ?? () async => null),
      ),
    );
    await tester.pump();
  }

  Future<void> settleIo(WidgetTester tester) async {
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
  }

  String uriKey(String name) => 'local-local:content://tree/musica/document/$name';

  group('la ruleta de álbumes', () {
    testWidgets('no hay título arriba, y en reposo solo se ve un álbum, grande y centrado', (tester) async {
      await home(tester);
      expect(find.text('Música'), findsNothing);
      expect(find.byKey(const Key('music-title')), findsNothing);
      expect(find.text('Canciones enviadas'), findsOneWidget);
      final first = tester.getRect(find.descendant(of: card('card-received'), matching: find.byKey(const Key('plate-blank'))));
      expect(first.width, first.height);
      expect(first.width, greaterThan(250));
      expect(first.center.dx, closeTo(200, 1));
      // los demás, escondidos detrás
      for (final id in ['card-root', 'card-folder-Jazz', 'card-folder-Rock', 'card-new-folder']) {
        expect(card(id), findsNothing, reason: id);
      }
    });

    testWidgets('se recorren todos, en orden, y siempre queda uno enfrente, centrado', (tester) async {
      await home(tester);
      final names = {'card-root': 'Mi música', 'card-folder-Jazz': 'Jazz', 'card-folder-Rock': 'Rock', 'card-new-folder': 'Nuevo álbum'};
      var i = 1;
      for (final entry in names.entries) {
        await deckTo(tester, i++);
        expect(card(entry.key), findsOneWidget);
        expect(tester.getRect(find.byKey(Key('deck-title-${entry.key}'))).center.dx, closeTo(200, 2));
        expect(find.text(entry.value), findsOneWidget);
      }
    });

    testWidgets('da vueltas sin tope: después del último vuelve el primero, y antes del primero está el último', (tester) async {
      await home(tester);
      await tester.drag(find.byKey(const Key('album-deck')), const Offset(AlbumDeck.pxPerStep, 0));
      await tester.pumpAndSettle();
      expect(card('card-new-folder'), findsOneWidget);
      await tester.drag(find.byKey(const Key('album-deck')), const Offset(-AlbumDeck.pxPerStep, 0));
      await tester.pumpAndSettle();
      expect(card('card-received'), findsOneWidget);
    });

    testWidgets('al girar se abre el anillo y se ven los demás; al soltar se recoge suavemente y queda solo el de enfrente', (tester) async {
      await home(tester);
      final rest = tester.getBottomRight(card('card-received')).dx - tester.getTopLeft(card('card-received')).dx;
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('album-deck'))));
      await gesture.moveBy(const Offset(-30, 0));
      await gesture.moveBy(const Offset(-100, 0));
      await tester.pump();
      await tester.pump(AlbumDeck.openTime);
      // abierto: se ven los otros y encogidos
      expect(card('card-root'), findsOneWidget);
      expect(card('card-new-folder'), findsOneWidget);
      final open = tester.getBottomRight(card('card-folder-Jazz')).dx - tester.getTopLeft(card('card-folder-Jazz')).dx;
      expect(open.abs(), lessThan(rest));
      // mientras no se suelta, sigue abierto
      await tester.pump(const Duration(seconds: 2));
      expect(card('card-root'), findsOneWidget);
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // ya se detuvo y empieza a recogerse
      expect(card('card-folder-Jazz'), findsOneWidget); // no de golpe
      await tester.pumpAndSettle();
      expect(card('card-root'), findsOneWidget); // quedó enfrente
      expect(card('card-received'), findsNothing);
      expect(card('card-folder-Jazz'), findsNothing);
      expect(tester.getBottomRight(card('card-root')).dx - tester.getTopLeft(card('card-root')).dx, closeTo(rest, 0.01));
    });

    testWidgets('si se vuelve a agarrar mientras se detiene, el anillo no se cierra', (tester) async {
      await home(tester);
      await tester.drag(find.byKey(const Key('album-deck')), const Offset(-70, 0));
      await tester.pump(const Duration(milliseconds: 100));
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('album-deck'))));
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(card('card-folder-Jazz'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('nada usa opacidad, ni abierto ni cerrado', (tester) async {
      await home(tester);
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('album-deck'))));
      await gesture.moveBy(const Offset(-60, 0));
      await tester.pump();
      await tester.pump(AlbumDeck.openTime);
      expect(find.descendant(of: find.byKey(const Key('album-deck')), matching: find.byType(Opacity)), findsNothing);
      expect(find.descendant(of: find.byKey(const Key('album-deck')), matching: find.byType(FadeTransition)), findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('al salir de la sección no queda ninguna foto a la vista: la ruleta recorta en su rectángulo', (tester) async {
      await home(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: SectionMotion(animation: const AlwaysStoppedAnimation(1), leaving: true, moving: true, child: MusicPage(controller: music, local: local, player: player, pickCover: () async => null)),
        ),
      );
      await tester.pump();
      final deck = find.byKey(const Key('album-deck'));
      expect(tester.getBottomRight(deck).dx, lessThanOrEqualTo(0));
      expect(find.descendant(of: deck, matching: find.byType(ClipRect)), findsOneWidget);
    });

    testWidgets('un álbum sin portada tiene detrás el efecto completo, no la foto nítida de Inicio', (tester) async {
      await home(tester);
      await tester.tap(card('card-received'));
      await settleIo(tester);
      expect(find.byKey(const Key('album-pages')), findsOneWidget);
      expect(find.byKey(const Key('backdrop-full-veil')), findsOneWidget);
    });

    testWidgets('tocar el de enfrente abre el álbum', (tester) async {
      await home(tester);
      await deckTo(tester, 1);
      expect(find.byKey(const Key('album-pages')), findsNothing);
      await tester.tap(card('card-root'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('album-pages')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('album-title'))).data, 'Mi música');
    });

    testWidgets('sin portada la tarjeta es un recuadro con icono; con la de una canción enviada, la enseña', (tester) async {
      await home(tester);
      expect(find.descendant(of: card('card-received'), matching: find.byKey(const Key('plate-blank'))), findsOneWidget);
      backend.add('a', cover: 'https://img.test/a.jpg', at: DateTime.utc(2026, 9, 1));
      await tester.runAsync(music.refresh);
      await tester.pump();
      expect(find.descendant(of: card('card-received'), matching: find.byKey(const Key('plate-blank'))), findsNothing);
      expect(find.descendant(of: card('card-received'), matching: find.byType(Cover)), findsOneWidget);
    });

    testWidgets('«Nuevo álbum» lo crea y aparece como otra tarjeta', (tester) async {
      await home(tester);
      await deckTo(tester, 4);
      await tester.tap(card('card-new-folder'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('folder-name-field')), 'Pop');
      await tester.tap(find.byKey(const Key('folder-create')));
      await settleIo(tester);
      expect(find.text('Se creó el álbum «Pop».'), findsOneWidget);
      expect(saver.created.single.name, 'Pop');
      await deckTo(tester, 3); // Pop va entre Jazz y Rock
      expect(card('card-folder-Pop'), findsOneWidget);
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

  group('las favoritas, debajo', () {
    testWidgets('sin ninguna dice cómo marcarlas', (tester) async {
      await home(tester, favorites: FavoritesController());
      await tester.drag(find.byKey(const Key('music-scroll')), const Offset(0, -300));
      await tester.pump();
      expect(find.byKey(const Key('favorites-title')), findsOneWidget);
      expect(find.byKey(const Key('favorites-empty')), findsOneWidget);
    });

    testWidgets('salen las enviadas y las de los álbumes ya leídos, cada una con el corazón puesto; al quitarlo se van', (tester) async {
      backend.add('r', at: DateTime.utc(2026, 9, 1));
      final favorites = FavoritesController();
      await tester.runAsync(music.start);
      await tester.runAsync(pumpEventQueue);
      await favorites.toggle(music.tracks.single.durationKey);
      await favorites.toggle(Track.local(song('rock1.mp3', dir: 'rock')).durationKey);
      await home(tester, favorites: favorites);
      await tester.drag(find.byKey(const Key('music-scroll')), const Offset(0, -400));
      await tester.pump();
      expect(find.byKey(const Key('favorites-list')), findsOneWidget);
      expect(find.text('rock1'), findsOneWidget);
      expect(find.byKey(Key('track-${music.tracks.single.id}')), findsOneWidget);
      expect(find.text('a'), findsNothing); // sin corazón
      await favorites.toggle(Track.local(song('rock1.mp3', dir: 'rock')).durationKey);
      await tester.pump();
      expect(find.text('rock1'), findsNothing);
    });

    testWidgets('cada favorita lleva la portada de su álbum (la que se le puso al álbum), no una suya', (tester) async {
      final favorites = FavoritesController();
      saver.art[song('a.mp3').uri] = '/embebida-de-a.jpg';
      saver.art[song('b.mp3').uri] = '/embebida-de-b.jpg';
      await tester.runAsync(music.start);
      await tester.runAsync(pumpEventQueue);
      await favorites.toggle(Track.local(song('b.mp3')).durationKey);
      await home(tester, favorites: favorites);
      await tester.runAsync(pumpEventQueue);
      await tester.drag(find.byKey(const Key('music-scroll')), const Offset(0, -400));
      await tester.pump();
      // «b» no trae la suya a la vista: sale la del álbum (la de su primera canción con imagen, «a»)
      final cover = tester.widget<Cover>(find.descendant(of: find.byKey(Key(uriKey('b.mp3'))), matching: find.byType(Cover)));
      expect(cover.file, '/embebida-de-a.jpg');
      // y si el álbum tiene portada elegida, esa
      await tester.runAsync(() => local.setAlbumCover('root', '/mia.jpg'));
      await tester.pump();
      expect(tester.widget<Cover>(find.descendant(of: find.byKey(Key(uriKey('b.mp3'))), matching: find.byType(Cover))).file, saver.storedCovers.last.path);
    });

    testWidgets('tocar una favorita la reproduce con todas las favoritas como cola', (tester) async {
      final favorites = FavoritesController();
      await tester.runAsync(music.start);
      await tester.runAsync(pumpEventQueue);
      await favorites.toggle(Track.local(song('a.mp3')).durationKey);
      await favorites.toggle(Track.local(song('c.mp3')).durationKey);
      await home(tester, favorites: favorites);
      await tester.drag(find.byKey(const Key('music-scroll')), const Offset(0, -400));
      await tester.pump();
      await tester.tap(find.byKey(Key(uriKey('c.mp3'))));
      await settleIo(tester);
      expect(player.current?.title, 'c');
      expect(engine.queue.map((q) => q.title), ['a', 'c']);
    });
  });

  group('al abrir un álbum: el disco sale de la tarjeta', () {
    testWidgets('al empezar el disco y la tarjeta están en el mismo sitio; la tarjeta se va a la izquierda y el disco llega al centro', (tester) async {
      await home(tester);
      await deckTo(tester, 3);
      final cardRect = tester.getRect(find.descendant(of: card('card-folder-Rock'), matching: find.byKey(const Key('plate-blank'))));
      await tester.tap(card('card-folder-Rock'));
      await tester.pump(); // construye la ruta
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byKey(const Key('album-opening')), findsOneWidget);
      final ghost = tester.getRect(find.byKey(const Key('album-opening-card')));
      final disc = tester.getRect(find.byKey(const Key('album-opening-disc')));
      expect(ghost.center.dx, closeTo(cardRect.center.dx, 6)); // la tarjeta, donde estaba
      expect(ghost.width, closeTo(cardRect.width, 1));
      expect(disc.center.dx, closeTo(cardRect.center.dx, 12)); // y el disco, detrás de ella
      expect(disc.center.dy, closeTo(cardRect.center.dy, 12));
      // a mitad: la tarjeta ya se fue hacia la izquierda y el disco viaja al centro
      await tester.pump(const Duration(milliseconds: 220));
      final ghostMid = tester.getRect(find.byKey(const Key('album-opening-card')));
      final discMid = tester.getRect(find.byKey(const Key('album-opening-disc')));
      expect(ghostMid.left, lessThan(ghost.left - 40));
      expect(discMid.center.dy, greaterThan(disc.center.dy + 50)); // baja hacia el centro de la pantalla
      expect(discMid.width, greaterThan(disc.width)); // y crece
      // al final: la transición desaparece y el disco de la vista está en el centro
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('album-opening')), findsNothing);
      final resting = tester.getRect(find.byKey(Key('album-disc-${rock.uri}')));
      expect(resting.center, const Offset(200, 425)); // en el centro de la pantalla
      expect(resting.width, resting.height);
      expect(resting.width, greaterThan(cardRect.width)); // más grande que la tarjeta
      expect(find.byKey(const Key('disc-hole')), findsOneWidget); // es un disco
    });

    testWidgets('al volver hace el camino inverso y, al terminar, la tarjeta vuelve a estar en la ruleta', (tester) async {
      await home(tester);
      await deckTo(tester, 3);
      final cardRect = tester.getRect(find.descendant(of: card('card-folder-Rock'), matching: find.byKey(const Key('plate-blank'))));
      await tester.tap(card('card-folder-Rock'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pump(); // empieza a volver
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('album-opening')), findsOneWidget); // el disco vuelve a la tarjeta
      await tester.pumpAndSettle();
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      expect(find.byKey(const Key('album-pages')), findsNothing);
      final back = tester.getRect(find.descendant(of: card('card-folder-Rock'), matching: find.byKey(const Key('plate-blank'))));
      expect(back.center, cardRect.center);
      expect(local.atRoot, isTrue);
    });

    testWidgets('la transición no usa opacidad sobre nada con cristal ni deja la pantalla a medias (sin errores en todo el recorrido)', (tester) async {
      await home(tester);
      await tester.tap(card('card-received'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('la vista del álbum', () {
    testWidgets('el disco en el centro de la pantalla, debajo el nombre sin fondo, y de fondo la portada borrosa', (tester) async {
      saver.art[song('a.mp3').uri] = '/a.jpg';
      await home(tester);
      await tester.runAsync(pumpEventQueue);
      await openAlbum(tester, 1, 'card-root');
      expect(songTitle(tester), 'a'); // la primera, por orden
      expect(tester.widget<Text>(find.byKey(const Key('album-title'))).data, 'Mi música');
      // el disco, en el centro y redondo, con la portada del álbum en la etiqueta
      final disc = tester.getRect(find.byKey(const Key('album-disc-root')));
      expect(disc.center, const Offset(200, 425));
      expect(disc.width, disc.height);
      expect(tester.widget<Image>(find.descendant(of: find.byType(DiscPlayer), matching: find.byKey(const Key('art-file')))).image, isA<ResizeImage>());
      // el nombre va debajo del disco
      expect(tester.getTopLeft(find.byKey(const Key('album-song-title'))).dy, greaterThan(disc.bottom));
      // el fondo es la misma portada, pequeñísima y estirada (borrosa)
      final backdrop = find.descendant(of: find.byKey(const Key('album-backdrop')), matching: find.byType(Image));
      expect(backdrop, findsOneWidget);
      expect((tester.widget<Image>(backdrop).image as ResizeImage).width, 48);
      expect(tester.getSize(find.byKey(const Key('album-backdrop'))), const Size(400, 850));
    });

    testWidgets('ya no hay panel oscuro ni mini-barra, aunque suene algo', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await tester.tap(find.byKey(const Key('album-disc-root')));
      await settleIo(tester);
      expect(player.playing, isTrue);
      expect(find.byKey(const Key('album-sheet')), findsNothing);
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(find.byType(MiniPlayer), findsNothing);
      expect(find.byKey(const Key('album-number')), findsNothing);
    });

    testWidgets('deslizando a un lado o al otro se pasa de álbum sin parar la canción que suena', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await tester.tap(find.byKey(const Key('album-disc-root')));
      await settleIo(tester);
      expect(player.playing, isTrue);
      engine.calls.clear();
      await swipeAlbum(tester); // la carpeta → Jazz
      await settleIo(tester);
      expect(tester.widget<Text>(find.byKey(const Key('album-title'))).data, 'Jazz');
      await swipeAlbum(tester); // → Rock
      await settleIo(tester);
      expect(tester.widget<Text>(find.byKey(const Key('album-title'))).data, 'Rock');
      expect(songTitle(tester), 'rock1');
      await swipeAlbum(tester, next: false);
      await swipeAlbum(tester, next: false);
      await settleIo(tester);
      expect(tester.widget<Text>(find.byKey(const Key('album-title'))).data, 'Mi música');
      // la canción seguía sonando todo el rato
      expect(player.current?.title, 'a');
      expect(player.playing, isTrue);
      expect(engine.calls, isNot(contains('stop')));
      expect(engine.calls, isNot(contains('pause')));
    });

    testWidgets('el disco se desplaza con el dedo al pasar de álbum, y los dos se ven a la vez', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      final gesture = await tester.startGesture(const Offset(200, 820));
      await gesture.moveBy(const Offset(-40, 0));
      await gesture.moveBy(const Offset(-100, 0));
      await tester.pump();
      expect(tester.getCenter(find.byKey(const Key('album-disc-root'))).dx, lessThan(200));
      expect(find.byKey(Key('album-disc-${jazz.uri}')), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('pasar de álbum no deja de leer su carpeta: la del álbum que se ve es la que el controlador tiene abierta', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      expect(local.atRoot, isTrue);
      await swipeAlbum(tester); // Jazz
      await settleIo(tester);
      expect(local.currentUri, jazz.uri);
      await swipeAlbum(tester); // Rock
      await settleIo(tester);
      expect(local.path.map((f) => f.name), ['Rock']);
      expect(songTitle(tester), 'rock1');
    });

    testWidgets('al llegar al último álbum no hay más: se queda ahí', (tester) async {
      await home(tester);
      await openAlbum(tester, 3, 'card-folder-Rock');
      await swipeAlbum(tester);
      expect(tester.widget<Text>(find.byKey(const Key('album-title'))).data, 'Rock');
    });

    testWidgets('al volver, la ruleta está en el último álbum que se vio', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await swipeAlbum(tester);
      await swipeAlbum(tester); // Rock
      await settleIo(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      expect(find.byKey(const Key('album-pages')), findsNothing);
      expect(tester.getRect(find.descendant(of: card('card-folder-Rock'), matching: find.byKey(const Key('plate-blank')))).center.dx, closeTo(200, 1));
    });

    testWidgets('«atrás» vuelve a la ruleta y el controlador a la raíz', (tester) async {
      await home(tester);
      await openAlbum(tester, 3, 'card-folder-Rock');
      expect(songTitle(tester), 'rock1');
      expect(find.byKey(const Key('album-title')), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      expect(card('card-folder-Rock'), findsOneWidget);
      expect(local.atRoot, isTrue);
    });

    testWidgets('un álbum solo enseña sus canciones: las subcarpetas no salen, ni sus canciones', (tester) async {
      const old = LocalFolder(uri: 'content://tree/musica/document/Rock/Viejo', name: 'Viejo', count: 1);
      saver.dirFolders[rock.uri] = [old];
      saver.dirSongs[old.uri] = [song('vieja.mp3', dir: 'viejo')];
      await home(tester);
      await openAlbum(tester, 3, 'card-folder-Rock');
      await openList(tester);
      expect(find.byKey(Key('local-local:${song('rock1.mp3', dir: 'rock').uri}')), findsOneWidget);
      expect(find.text('Viejo'), findsNothing);
      expect(find.text('vieja'), findsNothing);
      expect(find.byKey(const Key('album-subalbums')), findsNothing);
      expect(local.path.map((f) => f.name), ['Rock']);
    });

    testWidgets('un álbum con solo subcarpetas se ve vacío', (tester) async {
      saver.dirFolders[jazz.uri] = [const LocalFolder(uri: 'content://tree/musica/document/Jazz/Viejo', name: 'Viejo', count: 1)];
      await home(tester);
      await openAlbum(tester, 2, 'card-folder-Jazz');
      expect(find.text('No hay archivos .mp3 en «Jazz».'), findsOneWidget);
    });

    testWidgets('un álbum vacío lo dice debajo del disco, y el doble toque no abre nada', (tester) async {
      await home(tester);
      await openAlbum(tester, 2, 'card-folder-Jazz');
      expect(find.text('No hay archivos .mp3 en «Jazz».'), findsOneWidget);
      expect(tester.getTopLeft(find.text('No hay archivos .mp3 en «Jazz».')).dy, greaterThan(tester.getRect(find.byKey(Key('album-disc-${jazz.uri}'))).bottom));
      await openList(tester);
      expect(find.byKey(const Key('arc-list')), findsNothing);
    });
  });

  group('el disco', () {
    Matrix4 turnOf(WidgetTester tester) => tester.widget<Transform>(find.ancestor(of: find.byKey(const Key('vinyl-surface')), matching: find.byType(Transform)).first).transform;

    double progress(WidgetTester tester) => (tester.widget<CustomPaint>(find.byKey(const Key('disc-progress'))).painter! as ProgressRingPainter).fraction.value;

    /// Abre la carpeta y pone a sonar la primera canción (dura 3 minutos en el motor de mentira).
    Future<void> sounding(WidgetTester tester, {bool moving = false}) async {
      await home(tester, moving: moving);
      await openAlbum(tester, 1, 'card-root');
      await tester.tap(find.byKey(const Key('album-disc-root')));
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
    }

    testWidgets('un toque reproduce, sin esperar a ver si hay otro, y el siguiente pausa', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await tester.tap(find.byKey(const Key('album-disc-root')));
      expect(player.current?.title, 'a'); // al instante
      await settleIo(tester);
      expect(engine.queue.map((q) => q.title), ['a', 'b', 'c']); // toda la carpeta como cola
      expect(player.playing, isTrue);
      await tester.tap(find.byKey(const Key('album-disc-root')));
      await settleIo(tester);
      expect(player.playing, isFalse);
    });

    testWidgets('gira solo mientras suena, y al pausar se detiene poco a poco', (tester) async {
      await home(tester, moving: true);
      await openAlbum(tester, 1, 'card-root');
      final still = turnOf(tester).clone();
      await tester.pump(const Duration(seconds: 1));
      expect(turnOf(tester), still); // aún sin sonar, quieto
      await tester.tap(find.byKey(const Key('album-disc-root')));
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      final first = turnOf(tester).clone();
      expect(first, isNot(still));
      await tester.pump(const Duration(milliseconds: 100));
      expect(turnOf(tester), isNot(first));
      // pausa: todavía gira un momento y luego para
      await tester.tap(find.byKey(const Key('album-disc-root')));
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      final braking = turnOf(tester).clone();
      await tester.pump(const Duration(milliseconds: 100));
      expect(turnOf(tester), isNot(braking));
      await tester.pumpAndSettle(); // sin nada más que animar: se detuvo
      final stopped = turnOf(tester).clone();
      await tester.pump(const Duration(seconds: 1));
      expect(turnOf(tester), stopped);
    });

    testWidgets('el disco de otro álbum no avanza aunque suene algo', (tester) async {
      await sounding(tester);
      player.position = const Duration(seconds: 90);
      await tester.pump();
      expect(progress(tester), closeTo(0.5, 0.01));
      await swipeAlbum(tester);
      await settleIo(tester);
      expect(tester.widget<Text>(find.byKey(const Key('album-title'))).data, 'Jazz');
      expect(progress(tester), 0);
    });

    testWidgets('la línea blanca avanza con la canción', (tester) async {
      await sounding(tester);
      expect(progress(tester), 0);
      player.position = const Duration(seconds: 45);
      await tester.pump();
      expect(progress(tester), closeTo(0.25, 0.001));
      player.position = const Duration(seconds: 90);
      await tester.pump();
      expect(progress(tester), closeTo(0.5, 0.001));
    });

    testWidgets('girarlo con el dedo adelanta; al revés, retrocede; el salto se hace al soltar', (tester) async {
      await sounding(tester);
      player.position = const Duration(seconds: 60);
      await tester.pump();
      final disc = tester.getCenter(find.byKey(const Key('album-disc-root')));
      const r = 110.0;
      Offset at(double degrees) => disc + Offset.fromDirection(degrees * math.pi / 180, r);

      // un cuarto de vuelta en el sentido del reloj, desde arriba hacia la derecha
      var gesture = await tester.startGesture(at(-90));
      for (var d = -80.0; d <= 0; d += 10) {
        await gesture.moveTo(at(d));
        await tester.pump();
      }
      expect(tester.widget<Text>(find.byKey(const Key('disc-time'))).data, '1:07 / 3:00');
      expect(progress(tester), closeTo(67.5 / 180, 0.001)); // la línea ya va adonde caerá
      expect(engine.seeks, isEmpty); // todavía no salta
      await gesture.up();
      await tester.pump();
      expect(engine.seeks.single, const Duration(seconds: 67, milliseconds: 500));
      expect(find.byKey(const Key('disc-time')), findsNothing);
      expect(player.playing, isTrue);
      expect(player.current?.title, 'a'); // no fue un toque

      // medio cuarto al revés
      engine.seeks.clear();
      gesture = await tester.startGesture(at(0));
      for (var d = -10.0; d >= -90; d -= 10) {
        await gesture.moveTo(at(d));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();
      expect(engine.seeks.single, const Duration(seconds: 60));
    });

    testWidgets('girar cruzando el lado izquierdo no da un salto de una vuelta', (tester) async {
      await sounding(tester);
      player.position = const Duration(seconds: 60);
      await tester.pump();
      final disc = tester.getCenter(find.byKey(const Key('album-disc-root')));
      Offset at(double degrees) => disc + Offset.fromDirection(degrees * math.pi / 180, 110);
      final gesture = await tester.startGesture(at(150));
      for (var d = 160.0; d <= 210; d += 10) {
        await gesture.moveTo(at(d));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();
      expect(engine.seeks.single.inMilliseconds, closeTo(60000 + 5000, 5));
    });

    testWidgets('no se sale de la canción al girar mucho hacia atrás', (tester) async {
      await sounding(tester);
      player.position = const Duration(seconds: 5);
      await tester.pump();
      final disc = tester.getCenter(find.byKey(const Key('album-disc-root')));
      Offset at(double degrees) => disc + Offset.fromDirection(degrees * math.pi / 180, 110);
      final gesture = await tester.startGesture(at(0));
      for (var d = -10.0; d >= -350; d -= 10) {
        await gesture.moveTo(at(d));
      }
      await gesture.up();
      await tester.pump();
      expect(engine.seeks.single, Duration.zero);
    });

    testWidgets('sin ninguna canción de este álbum sonando, girarlo no mueve nada ni arranca nada', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      final disc = tester.getCenter(find.byKey(const Key('album-disc-root')));
      Offset at(double degrees) => disc + Offset.fromDirection(degrees * math.pi / 180, 110);
      final gesture = await tester.startGesture(at(-90));
      for (var d = -80.0; d <= 0; d += 10) {
        await gesture.moveTo(at(d));
        await tester.pump();
      }
      expect(find.byKey(const Key('disc-time')), findsNothing);
      await gesture.up();
      await tester.pump();
      expect(engine.seeks, isEmpty);
      expect(player.current, isNull);
    });

    testWidgets('fuera del círculo los toques no son del disco, aunque caigan en su cuadrado', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      final disc = tester.getRect(find.byKey(const Key('album-disc-root')));
      await tester.tapAt(disc.topLeft + const Offset(4, 4));
      await tester.pump(kDoubleTapTimeoutForTests);
      expect(player.current, isNull);
    });

    testWidgets('el círculo del centro escucha el sonido solo desde que suena algo, y al salir lo suelta', (tester) async {
      final levels = FakeLevels();
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      engine = FakeEngine();
      player = PlayerController(backend, engine, art: local, noteAfter: Duration.zero, levels: levels);
      addTearDown(player.dispose);
      await tester.runAsync(music.start);
      await tester.runAsync(pumpEventQueue);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: AlbumView(
            albums: const [AlbumEntry(id: 'root', title: 'Mi música', icon: Icons.smartphone_rounded)],
            initial: 0,
            animation: kAlwaysCompleteAnimation,
            originOf: (_) => Rect.zero,
            music: music,
            local: local,
            player: player,
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(SoundCircle), findsOneWidget);
      expect(levels.started, 0); // no pide el permiso solo por abrir el álbum
      await tester.tap(find.byKey(const Key('album-disc-root')));
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(levels.started, 1);
      // al salir, se apaga la lectura
      await tester.pumpWidget(const SizedBox());
      expect(levels.stopped, 1);
    });
  });

  group('la lista de canciones', () {
    testWidgets('doble toque fuera del disco la abre; otro la cierra', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      expect(find.byKey(const Key('arc-list')), findsNothing);
      await openList(tester);
      expect(find.byKey(const Key('arc-list')), findsOneWidget);
      for (final name in ['a.mp3', 'b.mp3', 'c.mp3']) {
        expect(find.byKey(Key(uriKey(name))), findsOneWidget);
      }
      await openList(tester);
      expect(find.byKey(const Key('arc-list')), findsNothing);
      expect(find.byKey(const Key('album-disc-root')), findsOneWidget);
    });

    testWidgets('doble toque en el disco no la abre: son dos toques de reproducir', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await tester.tap(find.byKey(const Key('album-disc-root')));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.byKey(const Key('album-disc-root')));
      await settleIo(tester);
      expect(find.byKey(const Key('arc-list')), findsNothing);
      expect(player.current?.title, 'a');
    });

    testWidgets('dos toques separados fuera del disco no la abren', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await tester.tapAt(const Offset(30, 820));
      await tester.pump(const Duration(seconds: 1));
      await tester.tapAt(const Offset(30, 820));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('arc-list')), findsNothing);
    });

    testWidgets('«atrás» la cierra antes de salir del álbum', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await openList(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('arc-list')), findsNothing);
      expect(find.byKey(const Key('album-pages')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('album-pages')), findsNothing);
    });

    testWidgets('al abrirse el disco encoge hacia la fila del centro y las filas llegan por la derecha', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      final rest = tester.getCenter(find.byKey(const Key('album-disc-root')));
      await tester.tapAt(const Offset(30, 820));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(const Offset(30, 820));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 230));
      final middle = tester.getCenter(find.byKey(const Key('album-disc-root')));
      expect(middle.dx, lessThan(rest.dx - 20));
      await tester.pumpAndSettle();
      // ya abierta, el disco grande no se ve
      expect(find.byKey(const Key('album-disc-root')), findsNothing);
    });

    testWidgets('la fila del centro lleva la píldora con el botón; tocar otra la trae al centro sin ponerla a sonar', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await openList(tester);
      String playId(String name) => 'arc-play-local:content://tree/musica/document/$name';
      expect(find.byKey(Key(playId('a.mp3'))), findsOneWidget);
      expect(find.byKey(Key(playId('b.mp3'))), findsNothing);
      await tester.tap(find.byKey(Key(uriKey('b.mp3'))));
      await tester.pumpAndSettle();
      expect(find.byKey(Key(playId('a.mp3'))), findsNothing);
      expect(find.byKey(Key(playId('b.mp3'))), findsOneWidget);
      expect(player.current, isNull);
      // y el botón la pone a sonar, sin cerrar la lista
      await tester.tap(find.byKey(Key(playId('b.mp3'))));
      await settleIo(tester);
      expect(player.current?.title, 'b');
      expect(engine.queue.map((q) => q.title), ['a', 'b', 'c']);
      expect(find.byKey(const Key('arc-list')), findsOneWidget);
      // otra vez: pausa
      await tester.tap(find.byKey(Key(playId('b.mp3'))));
      await settleIo(tester);
      expect(player.playing, isFalse);
    });

    testWidgets('las filas van en curva: la del centro más a la izquierda que las demás', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await openList(tester);
      await tester.tap(find.byKey(Key(uriKey('b.mp3'))));
      await tester.pumpAndSettle();
      double leftOf(String name) => tester.getTopLeft(find.byKey(Key(uriKey(name)))).dx;
      expect(leftOf('b.mp3'), lessThan(leftOf('a.mp3')));
      expect(leftOf('b.mp3'), lessThan(leftOf('c.mp3')));
    });

    testWidgets('al cerrarla, debajo del disco queda la canción que quedó en el centro', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await openList(tester);
      await tester.tap(find.byKey(Key(uriKey('c.mp3'))));
      await tester.pumpAndSettle();
      await openList(tester);
      expect(songTitle(tester), 'c');
    });

    testWidgets('si pasa a sonar otra canción, la lista va hasta ella', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await tester.tap(find.byKey(const Key('album-disc-root')));
      await settleIo(tester);
      await openList(tester);
      expect(find.byKey(const Key('arc-play-local:content://tree/musica/document/a.mp3')), findsOneWidget);
      await tester.runAsync(player.next);
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('arc-play-local:content://tree/musica/document/b.mp3')), findsOneWidget);
    });

    testWidgets('el corazón de la píldora marca la canción como favorita', (tester) async {
      final favorites = FavoritesController();
      await home(tester, favorites: favorites);
      await openAlbum(tester, 1, 'card-root');
      await openList(tester);
      await tester.tap(find.byKey(const Key('fav-1')));
      await settleIo(tester);
      expect(favorites.isFavorite(Track.local(song('a.mp3')).durationKey), isTrue);
    });

    testWidgets('un doble toque sobre el botón de la píldora no cierra la lista', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await openList(tester);
      const play = Key('arc-play-local:content://tree/musica/document/a.mp3');
      await tester.tap(find.byKey(play));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.byKey(play));
      await settleIo(tester);
      expect(find.byKey(const Key('arc-list')), findsOneWidget);
    });
  });

  group('cambiar la portada, dentro del álbum', () {
    testWidgets('el botón del álbum pone la imagen elegida a todo el álbum: el disco, la tarjeta y sus canciones; solo en el teléfono', (tester) async {
      var picks = 0;
      final covers = MemoryCoverStore();
      local.dispose();
      local = LocalMusicController(music, saver, covers: covers);
      await home(tester, pickCover: () async => '/portada${++picks}.jpg');
      await openAlbum(tester, 2, 'card-folder-Jazz');
      await tester.tap(find.byKey(const Key('album-cover')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('album-cover-clear')), findsNothing); // aún no tiene
      await tester.tap(find.byKey(const Key('album-cover-pick')));
      await settleIo(tester);
      expect(picks, 1);
      expect(local.albumCoverOf(jazz.uri), saver.storedCovers.last.path);
      expect(saver.storedCovers.last.keep, isTrue); // vive en la app, no en el .mp3 ni en Supabase
      expect(covers.load().values, contains(saver.storedCovers.last.path)); // y queda recordada
      // el disco ya la enseña
      expect(find.descendant(of: find.byType(DiscPlayer), matching: find.byKey(const Key('art-file'))), findsOneWidget);
      // la de otro álbum no cambió
      expect(local.albumCoverOf(rock.uri), isNull);
      // y la tarjeta de la ruleta, al volver
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      expect(find.descendant(of: card('card-folder-Jazz'), matching: find.byKey(const Key('plate-blank'))), findsNothing);
      // quitarla
      await tester.tap(card('card-folder-Jazz'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('album-cover')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('album-cover-clear')));
      await settleIo(tester);
      expect(local.albumCoverOf(jazz.uri), isNull);
      expect(covers.load(), isEmpty);
    });

    testWidgets('mantener pulsada la tarjeta ya no abre nada: la portada se cambia dentro del álbum', (tester) async {
      await home(tester);
      await tester.longPress(card('card-received'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('album-cover-pick')), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('si se cancela la elección de la imagen, el álbum se queda como estaba', (tester) async {
      await home(tester, pickCover: () async => null);
      await openAlbum(tester, 1, 'card-root');
      await tester.tap(find.byKey(const Key('album-cover')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('album-cover-pick')));
      await settleIo(tester);
      expect(local.albumCoverOf('root'), isNull);
      expect(saver.storedCovers, isEmpty);
    });

    testWidgets('la imagen elegida manda sobre la de las canciones del álbum, y todas sus canciones la tienen', (tester) async {
      saver.art[song('a.mp3').uri] = '/embebida.jpg';
      await home(tester, pickCover: () async => '/mia.jpg');
      await tester.runAsync(pumpEventQueue);
      await openAlbum(tester, 1, 'card-root');
      await tester.tap(find.byKey(const Key('album-cover')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('album-cover-pick')));
      await settleIo(tester);
      final chosen = saver.storedCovers.last.path;
      for (final name in ['a.mp3', 'b.mp3', 'c.mp3']) {
        expect(local.artOf(Track.local(song(name))), chosen, reason: name);
      }
      await openList(tester);
      expect(tester.widget<AlbumArt>(find.descendant(of: find.byKey(Key(uriKey('c.mp3'))), matching: find.byType(AlbumArt))).file, chosen);
      // el reproductor y la mini-barra también usan la del álbum
      await playRow(tester, find.byKey(Key(uriKey('c.mp3'))), 'local:${song('c.mp3').uri}');
      await settleIo(tester);
      expect(player.coverFileOf(player.current), chosen);
    });

    testWidgets('en las canciones enviadas también: la portada del álbum es la de todas', (tester) async {
      backend.add('r', cover: 'https://img.test/r.jpg', at: DateTime.utc(2026, 9, 1));
      await home(tester, pickCover: () async => '/mia.jpg');
      await openAlbum(tester, 0, 'card-received');
      await tester.tap(find.byKey(const Key('album-cover')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('album-cover-pick')));
      await settleIo(tester);
      expect(local.albumCoverOf('received'), saver.storedCovers.last.path);
      expect(local.artOf(music.tracks.single), saver.storedCovers.last.path);
      expect(saver.written, isEmpty); // no se toca ningún archivo
    });
  });

  group('marcar y mover canciones', () {
    Future<void> openRoot(WidgetTester tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await openList(tester);
    }

    testWidgets('mantener pulsada una canción marca, tocar otra suma y «Cancelar» quita todo', (tester) async {
      await openRoot(tester);
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

    testWidgets('con canciones marcadas «atrás» primero quita la marca, luego cierra la lista y luego sale del álbum', (tester) async {
      await openRoot(tester);
      await tester.longPress(find.byKey(Key(uriKey('a.mp3'))));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('selection-count')), findsNothing);
      expect(find.byKey(const Key('arc-list')), findsOneWidget); // seguimos en la lista
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('arc-list')), findsNothing);
      expect(find.byKey(const Key('album-pages')), findsOneWidget); // seguimos en el álbum
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('album-pages')), findsNothing);
    });

    testWidgets('«Mover»: se elige la carpeta, «Mover aquí» y las canciones cambian de carpeta de verdad', (tester) async {
      await openRoot(tester);
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
      await openRoot(tester);
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

    testWidgets('la hoja de mover solo ofrece los álbumes: dentro de uno no se ven sus subcarpetas ni se pueden crear', (tester) async {
      saver.dirFolders[rock.uri] = [const LocalFolder(uri: 'content://tree/musica/document/Rock/Viejo', name: 'Viejo', count: 0)];
      await openRoot(tester);
      await tester.longPress(find.byKey(Key(uriKey('a.mp3'))));
      await tester.pump();
      await tester.tap(find.byKey(const Key('move-selected')));
      await settleIo(tester);
      await tester.tap(find.byKey(const Key('move-folder-Rock')));
      await settleIo(tester);
      expect(find.byKey(const Key('move-folder-Viejo')), findsNothing);
      expect(tester.widget<TextButton>(find.byKey(const Key('move-new-folder'))).onPressed, isNull);
      expect(tester.widget<FilledButton>(find.byKey(const Key('move-here'))).onPressed, isNotNull); // pero sí se puede mover aquí
    });

    testWidgets('si alguna no se pudo mover, el aviso lo dice con el motivo', (tester) async {
      saver.moveFailures['content://tree/musica/document/b.mp3'] = 'No se pudo borrar el original.';
      await openRoot(tester);
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

  group('canciones enviadas', () {
    testWidgets('«Recibido» y el menú ⋯ salen en la píldora de la fila del centro, y al sonar otra se enseña debajo del disco', (tester) async {
      backend.add('r1', at: DateTime.utc(2026, 9, 1));
      backend.add('r2', at: DateTime.utc(2026, 9, 2)); // la más nueva sale primera
      await home(tester);
      await openAlbum(tester, 0, 'card-received');
      expect(songTitle(tester), 'Canción r2');
      await openList(tester);
      expect(find.byKey(const Key('received-r2')), findsOneWidget);
      expect(find.byKey(const Key('more-r2')), findsOneWidget);
      expect(find.byKey(const Key('received-r1')), findsNothing);
      await playRow(tester, find.byKey(const Key('track-r1')), 'r1');
      await settleIo(tester);
      expect(find.byKey(const Key('received-r1')), findsOneWidget);
      expect(engine.queue.map((q) => q.title), contains('Canción r1'));
      await openList(tester);
      expect(songTitle(tester), 'Canción r1');
    });

    testWidgets('«Recibido» guarda la canción y avisa a Supabase', (tester) async {
      backend.add('r1', at: DateTime.utc(2026, 9, 1));
      await home(tester);
      await openAlbum(tester, 0, 'card-received');
      await openList(tester);
      await tester.tap(find.byKey(const Key('received-r1')));
      await settleIo(tester);
      expect(backend.confirmed, ['r1']);
      expect(find.byKey(const Key('received-mark-r1')), findsOneWidget);
    });

    testWidgets('sin canciones lo dice debajo del disco', (tester) async {
      await home(tester);
      await openAlbum(tester, 0, 'card-received');
      expect(find.text('Aún no hay canciones.\nLas que te manden desde la PC aparecen aquí.'), findsOneWidget);
    });

    testWidgets('el menú ⋯ ya no ofrece cambiar la imagen de una canción: solo guardarla', (tester) async {
      backend.add('r1', at: DateTime.utc(2026, 9, 1));
      await home(tester);
      await openAlbum(tester, 0, 'card-received');
      await openList(tester);
      await tester.tap(find.byKey(const Key('more-r1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('save-r1')), findsOneWidget);
      expect(find.byKey(const Key('cover-r1')), findsNothing);
      expect(find.text('Cambiar imagen'), findsNothing);
    });
  });

  testWidgets('la vista del álbum se puede abrir sola, sin la pantalla de música (una sola página, sin transición)', (tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(music.start);
    await tester.runAsync(pumpEventQueue);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: AlbumView(
          albums: const [AlbumEntry(id: 'root', title: 'Mi música', icon: Icons.smartphone_rounded)],
          initial: 0,
          animation: kAlwaysCompleteAnimation,
          originOf: (_) => Rect.zero,
          music: music,
          local: local,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(songTitle(tester), 'a');
    expect(find.byKey(const Key('album-opening')), findsNothing);
  });
}
