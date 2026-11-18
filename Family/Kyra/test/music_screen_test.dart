import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/ui/widgets/vinyl_disc.dart';
import 'package:kyora_chat/ui/widgets/section_motion.dart';
import 'package:kyora_chat/data/audio_engine.dart';
import 'package:kyora_chat/data/cover_store.dart';
import 'package:kyora_chat/data/favorites_store.dart';
import 'package:kyora_chat/data/music_store.dart';
import 'package:kyora_chat/models/track.dart';
import 'package:kyora_chat/state/local_music_controller.dart';
import 'package:kyora_chat/state/music_controller.dart';
import 'package:kyora_chat/state/player_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/util/pixel_art.dart';
import 'package:kyora_chat/util/cover_tint.dart';
import 'package:kyora_chat/ui/album_view.dart';
import 'package:kyora_chat/ui/music_page.dart';
import 'package:kyora_chat/ui/widgets/album_art.dart';
import 'package:kyora_chat/ui/widgets/album_grid.dart';
import 'package:kyora_chat/ui/widgets/options_reactor.dart';
import 'package:kyora_chat/ui/widgets/app_backdrop.dart';
import 'package:kyora_chat/ui/widgets/cover.dart';
import 'package:kyora_chat/ui/widgets/disc_player.dart';
import 'package:kyora_chat/ui/widgets/mini_player.dart';
import 'package:kyora_chat/ui/widgets/sound_circle.dart';

import 'fake_engine.dart';
import 'music_test.dart' show FakeMusicBackend, FakeSaver, MemoryMusicStore;
import 'music_ui.dart';
import 'sections.dart';

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
  Future<void> home(WidgetTester tester, {Future<String?> Function()? pickCover, FavoritesController? favorites, bool moving = false, ValueNotifier<String?>? openAlbum}) async {
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
        home: MusicPage(controller: music, local: local, player: player, favorites: favorites, openAlbum: openAlbum, pickCover: pickCover ?? () async => null),
      ),
    );
    await tester.pump();
  }

  Future<void> settleIo(WidgetTester tester) async {
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
  }

  String uriKey(String name) => 'local-local:content://tree/musica/document/$name';

  group('la cuadrícula de álbumes', () {
    testWidgets('los álbumes van en cuadrícula, tres por fila, todos del mismo tamaño y pegados (con un margen muy pequeño e igual), sin nombre', (tester) async {
      await home(tester);
      expect(find.byType(AlbumGrid), findsOneWidget);
      final rects = [for (final id in ['card-received', 'card-root', 'card-folder-Jazz', 'card-folder-Rock', 'card-new-folder']) tester.getRect(find.descendant(of: card(id), matching: find.byType(SizedBox)).first)];
      // la primera fila: tres, a la misma altura y de izquierda a derecha
      expect(rects[1].top, closeTo(rects[0].top, 0.5));
      expect(rects[2].top, closeTo(rects[0].top, 0.5));
      expect(rects[1].left, greaterThan(rects[0].right));
      expect(rects[2].left, greaterThan(rects[1].right));
      // la segunda fila empieza debajo, a la izquierda, con la misma separación
      expect(rects[3].top, greaterThan(rects[0].bottom));
      expect(rects[3].left, closeTo(rects[0].left, 0.5));
      expect(rects[4].top, closeTo(rects[3].top, 0.5));
      // cuadradas, del mismo lado, y un lado de la tercera parte del ancho
      for (final r in rects) {
        expect(r.width, closeTo(r.height, 0.5));
        expect(r.width, closeTo(AlbumGrid.sideFor(400), 0.5));
      }
      // pegados: el mismo margen pequeño entre uno y otro, en horizontal y en vertical, y al borde de la pantalla
      expect(rects[1].left - rects[0].right, closeTo(AlbumGrid.gap, 0.5));
      expect(rects[2].left - rects[1].right, closeTo(AlbumGrid.gap, 0.5));
      expect(rects[3].top - rects[0].bottom, closeTo(AlbumGrid.gap, 0.5));
      expect(rects[0].left, closeTo(AlbumGrid.margin, 0.5));
      expect(AlbumGrid.gap, lessThanOrEqualTo(6));
      expect(AlbumGrid.gap, AlbumGrid.margin);
      // y no se ve ningún nombre
      expect(find.text('Canciones enviadas'), findsNothing);
      expect(find.text('Jazz'), findsNothing);
      expect(find.text('Mi música'), findsNothing);
      expect(find.byKey(const Key('deck-title-card-received')), findsNothing);
    });

    testWidgets('la pantalla solo enseña los álbumes: sin el texto «Música», sin favoritas y sin la tarjeta de lo que suena', (tester) async {
      final favorites = FavoritesController();
      await favorites.toggle(Track.local(song('a.mp3')).durationKey);
      await home(tester, favorites: favorites);
      await tester.runAsync(() => player.play(Track.local(song('a.mp3')), [Track.local(song('a.mp3'))]));
      await tester.pump();
      expect(find.textContaining('MÚSICA'), findsNothing);
      expect(find.textContaining('Música'), findsNothing);
      expect(find.byKey(const Key('favorites-title')), findsNothing);
      expect(find.byKey(const Key('favorites-empty')), findsNothing);
      expect(find.byType(MiniPlayer), findsNothing);
      expect(find.byType(ClipRRect), findsNothing);
    });

    testWidgets('la etiqueta de arriba dice cuántos álbumes hay', (tester) async {
      await home(tester);
      expect(find.text('ÁLBUMES'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('deck-count'))).data, '05');
    });

    testWidgets('ya no hay pila: nada se desliza hacia los lados ni se superpone, y las portadas no se oscurecen', (tester) async {
      await home(tester);
      final a = tester.getRect(card('card-received'));
      final b = tester.getRect(card('card-root'));
      expect(a.overlaps(b), isFalse);
      expect(find.byKey(const Key('deck-index')), findsNothing);
    });

    testWidgets('al salir de la sección no queda ninguna foto a la vista: la cuadrícula se funde', (tester) async {
      await home(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: SectionMotion(animation: const AlwaysStoppedAnimation(1), leaving: true, moving: true, child: MusicPage(controller: music, local: local, player: player, pickCover: () async => null)),
        ),
      );
      await tester.pump();
      final deck = find.byKey(const Key('album-deck'));
      // la sección que se va se funde del todo: no queda ninguna portada a la vista
      final opacity = tester.widget<Opacity>(find.ancestor(of: deck, matching: find.byType(Opacity)).first).opacity;
      expect(opacity, 0);
    });

    testWidgets('un álbum sin portada tiene detrás el fondo de la pantalla', (tester) async {
      await home(tester);
      await tester.tap(card('card-received'));
      await settleIo(tester);
      expect(find.byKey(const Key('album-background')), findsOneWidget);
      expect(find.descendant(of: find.byType(AlbumView), matching: find.byKey(const Key('screen-backdrop'))), findsWidgets);
    });

    testWidgets('tocar un álbum lo abre', (tester) async {
      await home(tester);
      expect(find.byKey(const Key('album-background')), findsNothing);
      await tester.tap(card('card-root'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('album-background')), findsOneWidget);
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

  group('la sensibilidad (la de las favoritas)', () {
    test('se guarda con los demás ajustes y no se pierde al elegir o quitar la carpeta', () {
      const settings = MusicSettings(deckSpeed: 0.75);
      expect(settings.copyWith(auto: false).deckSpeed, 0.75);
      expect(settings.withTree('content://x', 'x').deckSpeed, 0.75);
      expect(settings.withTree('content://x', 'x').withoutTree().deckSpeed, 0.75);
      expect(const MusicSettings().deckSpeed, 1);
    });
  });

  group('la tarjeta de lo que suena', () {
    Future<void> sounding(WidgetTester tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await tester.tap(find.byKey(const Key('album-disc-root')));
      await settleIo(tester);
    }

    testWidgets('sin nada sonando no sale', (tester) async {
      await home(tester);
      expect(find.byKey(const Key('mini-player')), findsNothing);
    });

    testWidgets('en la pantalla principal no sale, suene lo que suene', (tester) async {
      await sounding(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(MiniPlayer), findsNothing);
      expect(find.byKey(const Key('mini-player')), findsNothing);
    });

    testWidgets('en el álbum de la canción no sale: ahí está el disco', (tester) async {
      await sounding(tester);
      expect(find.byType(MiniPlayer), findsNothing);
    });

    testWidgets('al pasar a otro álbum sale; y al tocarla desliza hasta el disco de la canción', (tester) async {
      await sounding(tester);
      await swipeAlbum(tester); // la carpeta → Jazz
      await settleIo(tester);
      expect(tester.widget<Text>(find.byKey(const Key('album-title'))).data, 'Jazz');
      expect(find.byType(MiniPlayer), findsOneWidget);
      await tester.tap(find.byKey(const Key('mini-player')));
      await settleIo(tester);
      expect(tester.widget<Text>(find.byKey(const Key('album-title'))).data, 'Mi música');
      expect(find.byType(MiniPlayer), findsNothing);
    });

    testWidgets('con la lista abierta no sale', (tester) async {
      await home(tester);
      await openAlbum(tester, 3, 'card-folder-Rock');
      await tester.tap(find.byKey(Key('album-disc-${rock.uri}')));
      await settleIo(tester);
      await swipeAlbum(tester, next: false); // Jazz
      await swipeAlbum(tester, next: false); // la carpeta, que sí tiene canciones
      await settleIo(tester);
      expect(find.byType(MiniPlayer), findsOneWidget);
      await openList(tester);
      expect(find.byType(MiniPlayer), findsNothing);
    });

    testWidgets('en otro álbum pausa y pasa a la siguiente', (tester) async {
      await sounding(tester);
      await swipeAlbum(tester); // Jazz
      await settleIo(tester);
      await tester.tap(find.byKey(const Key('mini-toggle')));
      await settleIo(tester);
      expect(player.playing, isFalse);
      await tester.tap(find.byKey(const Key('mini-next')));
      await settleIo(tester);
      expect(player.current?.title, 'b');
      // la nueva canción es de «Mi música»: la vista pasa sola a ese álbum y ya no hace falta la tarjeta
      expect(tester.widget<Text>(find.byKey(const Key('album-title'))).data, 'Mi música');
      expect(find.byType(MiniPlayer), findsNothing);
    });
  });

  group('los controles bajo el disco', () {
    Future<void> sounding(WidgetTester tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await tester.tap(find.byKey(const Key('album-disc-root')));
      await settleIo(tester);
    }

    testWidgets('no salen hasta que suena una canción del álbum, y van debajo del nombre', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      expect(find.byKey(const Key('disc-controls')), findsNothing);
      await tester.tap(find.byKey(const Key('album-disc-root')));
      await settleIo(tester);
      expect(find.byKey(const Key('disc-controls')), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(const Key('disc-controls'))).dy, greaterThan(tester.getBottomLeft(find.byKey(const Key('album-song-title'))).dy));
    });

    testWidgets('en otro álbum no salen', (tester) async {
      await sounding(tester);
      await swipeAlbum(tester);
      await settleIo(tester);
      expect(find.byKey(const Key('disc-controls')), findsNothing);
    });

    testWidgets('siguiente y anterior cambian de canción, y el nombre con ellas', (tester) async {
      await sounding(tester);
      await tester.tap(find.byKey(const Key('disc-next')));
      await settleIo(tester);
      expect(player.current?.title, 'b');
      expect(await songTitle(tester), 'b');
      await tester.tap(find.byKey(const Key('disc-previous')));
      await settleIo(tester);
      expect(player.current?.title, 'a');
    });

    testWidgets('aleatorio se enciende y se apaga', (tester) async {
      await sounding(tester);
      await tester.tap(find.byKey(const Key('player-shuffle')));
      await settleIo(tester);
      expect(player.shuffle, isTrue);
      expect(engine.shuffle, isTrue);
      expect(tester.widget<IconButton>(find.byKey(const Key('player-shuffle'))).tooltip, 'Aleatorio: activado');
    });

    testWidgets('repetir pasa de apagado a toda la lista, a esta canción y otra vez a apagado', (tester) async {
      await sounding(tester);
      for (final (kind, icon) in [(RepeatKind.all, Icons.repeat_rounded), (RepeatKind.one, Icons.repeat_one_rounded), (RepeatKind.off, Icons.repeat_rounded)]) {
        await tester.tap(find.byKey(const Key('player-repeat')));
        await settleIo(tester);
        expect(player.repeat, kind);
        expect(engine.repeat, kind);
        expect(find.descendant(of: find.byKey(const Key('player-repeat')), matching: findIcon(icon)), findsOneWidget);
      }
    });

    testWidgets('un error de reproducción sale bajo el disco', (tester) async {
      await sounding(tester);
      engine.emitError('El enlace de la canción caducó: vuelve a tocarla.');
      await settleIo(tester);
      expect(find.byKey(const Key('player-error')), findsOneWidget);
    });
  });

  group('al abrir un álbum: efecto de holograma, sin disco que viaje', () {
    testWidgets('al abrir, la pantalla del álbum se materializa con el holograma (parpadea y se ve nítida al terminar); no sale ningún disco de la tarjeta', (tester) async {
      await home(tester);
      await deckTo(tester, 3);
      await tester.tap(card('card-folder-Rock'));
      await tester.pump(); // construye la ruta
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.byKey(const Key('album-opening')), findsNothing); // ya no hay disco ni tarjeta que viajen
      expect(find.byKey(const Key('album-opening-disc')), findsNothing);
      expect(find.byType(HologramReveal), findsWidgets);
      // al empezar casi no se ve (con parpadeo), y al terminar está entero y nítido
      final reveal = find.ancestor(of: find.byType(AlbumView), matching: find.byType(HologramReveal)).first;
      double opacity() => tester.widget<Opacity>(find.descendant(of: reveal, matching: find.byType(Opacity)).first).opacity;
      expect(opacity(), lessThan(1));
      await tester.pumpAndSettle();
      expect(opacity(), 1);
      final resting = tester.getRect(find.byKey(Key('album-disc-${rock.uri}')));
      expect(resting.center, const Offset(200, 357)); // el disco, en su sitio de siempre
      expect(resting.width, resting.height);
      expect(find.byKey(const Key('vinyl-surface')), findsOneWidget); // es un disco
    });

    testWidgets('abrir es corto (no se alarga): el holograma dura menos de medio segundo', (tester) async {
      await home(tester);
      await tester.tap(card('card-root'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(); // un cuadro más para que cierre
      expect(find.byType(AlbumView), findsOneWidget);
      final reveal = find.ancestor(of: find.byType(AlbumView), matching: find.byType(HologramReveal)).first;
      expect(tester.widget<HologramReveal>(reveal).animation.value, 1);
    });

    testWidgets('al volver se deshace con el mismo holograma y, al terminar, la cuadrícula sigue donde estaba', (tester) async {
      await home(tester);
      await deckTo(tester, 3);
      final cardRect = tester.getRect(card('card-folder-Rock'));
      await tester.tap(card('card-folder-Rock'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pump(); // empieza a volver
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('album-opening')), findsNothing);
      await tester.pumpAndSettle();
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      expect(find.byKey(const Key('album-background')), findsNothing);
      expect(tester.getRect(card('card-folder-Rock')), cardRect);
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
    testWidgets('otra pantalla (el botón del álbum del reproductor de Inicio) puede pedir abrir un álbum: se abre solo y la petición se vacía', (tester) async {
      final request = ValueNotifier<String?>(null);
      addTearDown(request.dispose);
      await home(tester, openAlbum: request);
      expect(find.byKey(const Key('album-back')), findsNothing);
      request.value = rock.uri;
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('album-title'))).data, 'Rock');
      expect(request.value, isNull);
      // una petición que ya estaba puesta al entrar a Música también se atiende
      await tester.pageBack();
      await tester.pumpAndSettle();
      request.value = 'root';
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('album-title'))).data, 'Mi música');
    });

    testWidgets('el disco algo por encima del centro, debajo el nombre sin fondo, y de fondo la portada nítida con líneas y oscurecida', (tester) async {
      saver.art[song('a.mp3').uri] = '/a.jpg';
      await home(tester);
      await tester.runAsync(pumpEventQueue);
      await openAlbum(tester, 1, 'card-root');
      expect(await songTitle(tester), 'a'); // la primera, por orden
      expect(tester.widget<Text>(find.byKey(const Key('album-title'))).data, 'Mi música');
      // el disco, en el centro y redondo, con la portada del álbum en la etiqueta
      final disc = tester.getRect(find.byKey(const Key('album-disc-root')));
      expect(disc.center, const Offset(200, 357)); // un poco por encima del centro
      expect(disc.width, disc.height);
      // la portada, en la etiqueta del disco (en pixel art, pintada en celdas)
      expect(tester.widget<VinylDisc>(find.byType(VinylDisc)).file, '/a.jpg');
      // el nombre va debajo del disco
      expect(tester.getTopLeft(find.byKey(const Key('album-song-title'))).dy, greaterThan(disc.bottom));
      // el fondo es la portada del álbum tal cual (nítida), con líneas de barrido y oscurecida (con un color mate debajo mientras carga)
      expect(find.descendant(of: find.byKey(const Key('album-backdrop')), matching: find.byKey(const Key('backdrop-cover'))), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('album-backdrop')), matching: find.byKey(const Key('backdrop-lines'))), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('album-backdrop')), matching: find.byKey(const Key('backdrop-dim'))), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('album-backdrop')), matching: find.byType(ImageFiltered)), findsNothing); // sin desenfoque
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.descendant(of: find.byKey(const Key('album-backdrop')), matching: find.byKey(const Key('matte-backdrop'))), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('album-backdrop'))), const Size(400, 850));
    });

    testWidgets('ya no hay panel oscuro, y en su propio álbum tampoco la tarjeta de lo que suena', (tester) async {
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

    testWidgets('volviendo a la pila se abre otro álbum sin parar la canción que suena', (tester) async {
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
      expect(find.byKey(const Key('album-song-title')), findsNothing); // sin tocar el centro del disco, solo el disco y el fondo
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

    testWidgets('al entrar solo se ven el disco y el fondo: el nombre y los controles esperan a que se toque el centro del disco, y ahí empieza a sonar', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      expect(find.byKey(const Key('album-song-title')), findsNothing);
      expect(find.byKey(const Key('disc-controls')), findsNothing);
      expect(find.byKey(const Key('disc-play-hint')), findsOneWidget);
      expect(player.current, isNull);
      // un toque en el borde del disco (fuera del centro) no reproduce
      final disc = tester.getRect(find.byKey(const Key('album-disc-root')));
      await tester.tapAt(disc.center + Offset(disc.width * 0.35, 0));
      await settleIo(tester);
      expect(player.current, isNull);
      // mantener presionado sin haber empezado no abre nada
      await tester.longPress(find.byType(DiscPlayer));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('options-disc')), findsNothing);
      // el centro: reproduce y destapa el nombre y los controles
      await tester.tap(find.byKey(const Key('album-disc-root')));
      await settleIo(tester);
      expect(player.playing, isTrue);
      expect(find.byKey(const Key('album-song-title')), findsOneWidget);
      expect(find.byKey(const Key('disc-controls')), findsOneWidget);
      expect(find.byKey(const Key('disc-play-hint')), findsNothing);
    });

    testWidgets('mantener el disco abre el reactor de opciones sobre un velo oscuro, solo con iconos; el centro lo cierra sin cambiar de álbum', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      expect(find.byKey(const Key('options-disc')), findsNothing);
      await holdDisc(tester);
      expect(find.byKey(const Key('options-disc')), findsOneWidget);
      expect(find.byKey(const Key('focus-panel')), findsNothing);
      expect(find.byType(AlbumGrid), findsNothing);
      // lo de atrás queda oscurecido: el panel es el protagonista
      expect(find.byKey(const Key('focus-veil')), findsOneWidget);
      for (final id in ['move', 'delete', 'speed', 'rename']) {
        expect(find.byKey(Key('disc-option-$id')), findsOneWidget, reason: id);
      }
      // las opciones están dentro del reactor y no llevan texto
      final reactor = tester.getRect(find.byKey(const Key('options-disc')));
      for (final id in ['move', 'delete', 'speed', 'rename']) {
        expect(reactor.inflate(1).contains(tester.getCenter(find.byKey(Key('disc-option-$id')))), isTrue, reason: id);
        expect(find.descendant(of: find.byKey(Key('disc-option-$id')), matching: find.byType(Text)), findsNothing, reason: id);
      }
      await tester.tap(find.byKey(const Key('disc-options-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('options-disc')), findsNothing);
      expect(find.byKey(const Key('focus-veil')), findsNothing);
      expect(tester.widget<Text>(find.byKey(const Key('album-title'))).data, 'Mi música'); // sigue aquí
    });

    testWidgets('tocar fuera del reactor lo cierra', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await holdDisc(tester);
      expect(find.byKey(const Key('options-disc')), findsOneWidget);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('options-disc')), findsNothing);
    });

    testWidgets('en las canciones enviadas solo sale la velocidad y el tono (no se mueven, borran ni renombran desde aquí)', (tester) async {
      backend.add('s1', at: DateTime.utc(2026, 9, 1));
      await home(tester);
      await openAlbum(tester, 0, 'card-received');
      await holdDisc(tester);
      expect(find.byKey(const Key('disc-option-speed')), findsOneWidget);
      for (final id in ['move', 'delete', 'rename']) {
        expect(find.byKey(Key('disc-option-$id')), findsNothing, reason: id);
      }
    });

    testWidgets('«Borrar canción» pide confirmación; al cancelar no borra nada y al confirmar borra de verdad solo esa, parando antes lo que suena', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await holdDisc(tester);
      expect(player.playing, isTrue);
      await tester.tap(find.byKey(const Key('disc-option-delete')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('song-delete-text'))).data, contains('a'));
      await tester.tap(find.byKey(const Key('song-delete-cancel')));
      await tester.pumpAndSettle();
      expect(saver.deletes, isEmpty);
      expect(saver.files, hasLength(3));
      await holdDisc(tester);
      await tester.tap(find.byKey(const Key('disc-option-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('song-delete-confirm')));
      await settleIo(tester);
      expect(saver.deletes.single, [song('a.mp3').uri]);
      expect(saver.files.map((f) => f.name), ['b.mp3', 'c.mp3']);
      expect(engine.calls, contains('stop'));
      expect(player.current, isNull);
      expect(find.text('Se borró la canción.'), findsOneWidget);
    });

    testWidgets('un borrado que falla lo cuenta con el motivo y deja la canción', (tester) async {
      saver.deleteFailures[song('a.mp3').uri] = 'Android no lo borró.';
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await holdDisc(tester);
      await tester.tap(find.byKey(const Key('disc-option-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('song-delete-confirm')));
      await settleIo(tester);
      expect(saver.files, hasLength(3));
      expect(find.textContaining('No se pudo borrar: Android no lo borró.'), findsOneWidget);
    });

    testWidgets('«Mover a otro álbum» lleva solo esa canción a la carpeta que se elija', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await holdDisc(tester);
      await tester.tap(find.byKey(const Key('disc-option-move')));
      await settleIo(tester);
      expect(tester.widget<Text>(find.byKey(const Key('move-title'))).data, 'Mover 1 canción a…');
      await tester.tap(find.byKey(const Key('move-folder-Jazz')));
      await settleIo(tester);
      await tester.tap(find.byKey(const Key('move-here')));
      await settleIo(tester);
      expect(saver.moves.single.uris, [song('a.mp3').uri]);
      expect(saver.moves.single.to, jazz.uri);
      expect(saver.files.map((f) => f.name), ['b.mp3', 'c.mp3']);
      expect(saver.dirSongs[jazz.uri], hasLength(1));
      expect(find.text('Se movió a «Jazz».'), findsOneWidget);
    });

    testWidgets('«Cambiar nombre» renombra el archivo de la canción (con su «.mp3») y para lo que suena', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await holdDisc(tester);
      await tester.tap(find.byKey(const Key('disc-option-rename')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('folder-name-field'))).controller!.text, 'a'); // con el nombre de ahora
      await tester.enterText(find.byKey(const Key('folder-name-field')), 'Zeta');
      await tester.tap(find.byKey(const Key('folder-create')));
      await settleIo(tester);
      expect(saver.renames.single, (uri: song('a.mp3').uri, name: 'Zeta.mp3'));
      expect(engine.calls, contains('stop'));
      expect(local.songs.map((t) => t.title), contains('Zeta'));
    });

    testWidgets('«Velocidad y tono»: el propio reactor pasa a ser un dial; girando el dedo por el aro se ajusta, cada cosa por separado, y «restablecer» las devuelve a 1×', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await holdDisc(tester);
      await tester.tap(find.byKey(const Key('disc-option-speed')));
      await tester.pumpAndSettle();
      // sigue siendo el mismo reactor (no se abre otro panel ni salen deslizadores)
      expect(find.byKey(const Key('options-disc')), findsOneWidget);
      expect(find.byKey(const Key('focus-panel')), findsNothing);
      expect(find.byType(Slider), findsNothing);
      expect(tester.widget<Text>(find.byKey(const Key('reactor-value'))).data, '1×');
      final box = tester.getRect(find.byKey(const Key('options-disc')));
      Offset at(double fraction) {
        final angle = OptionsReactor.gaugeStart + OptionsReactor.gaugeSweep * fraction;
        return box.center + Offset.fromDirection(angle, box.width / 2 * 0.7);
      }

      Future<void> turn(double from, double to) async {
        final g = await tester.startGesture(at(from));
        await g.moveTo(at((from + to) / 2));
        await g.moveTo(at(to));
        await g.up();
        await tester.pump();
      }

      await turn(0.2, 0.35); // la velocidad: de 0,5× a 1,5× en 270°
      expect(player.rate, 0.85);
      expect(engine.rate, 0.85);
      expect(player.pitch, 1); // el tono no se movió
      expect(engine.calls, contains('rate:0.85'));
      expect(tester.widget<Text>(find.byKey(const Key('reactor-value'))).data, '0,85×');
      // el tono, aparte
      await tester.tap(find.byKey(const Key('reactor-dial-pitch')));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('reactor-value'))).data, '1×');
      await turn(0.5, 0.7);
      expect(player.pitch, 1.2);
      expect(engine.pitch, 1.2);
      expect(player.rate, 0.85); // ni la velocidad
      expect(engine.calls, contains('pitch:1.2'));
      expect(tester.widget<Text>(find.byKey(const Key('reactor-value'))).data, '1,2×');
      // restablecer devuelve a 1× el ajuste que se está girando
      await tester.tap(find.byKey(const Key('reactor-reset')));
      await tester.pump();
      expect([player.rate, player.pitch], [0.85, 1]);
      await tester.tap(find.byKey(const Key('reactor-dial-rate')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('reactor-reset')));
      await tester.pump();
      expect([player.rate, player.pitch, engine.rate, engine.pitch], [1, 1, 1, 1]);
      // el núcleo vuelve a las opciones
      await tester.tap(find.byKey(const Key('reactor-back')));
      await tester.pump();
      expect(find.byKey(const Key('disc-option-speed')), findsOneWidget);
    });

    testWidgets('el dial no se sale de los extremos: más allá del arco se queda en el mínimo o el máximo', (tester) async {
      expect(OptionsReactor.fractionAt(OptionsReactor.gaugeStart), 0);
      expect(OptionsReactor.fractionAt(OptionsReactor.gaugeStart + OptionsReactor.gaugeSweep), closeTo(1, 1e-9));
      expect(OptionsReactor.fractionAt(OptionsReactor.gaugeStart + OptionsReactor.gaugeSweep / 2), closeTo(0.5, 1e-9));
      expect(OptionsReactor.fractionAt(math.pi / 2 + 0.1), 0); // abajo, algo a la izquierda del hueco: el mínimo
      expect(OptionsReactor.fractionAt(math.pi / 2 - 0.1), 1); // abajo, algo a la derecha: el máximo
    });

    testWidgets('la velocidad se queda entre canciones y la pastilla del disco la muestra y la devuelve a 1×', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await tester.tap(find.byKey(const Key('album-disc-root')));
      await settleIo(tester);
      expect(find.byKey(const Key('player-rate')), findsNothing);
      await player.setRate(1.25);
      await tester.pump();
      expect(tester.widget<TextButton>(find.byKey(const Key('player-rate'))).child, isA<Text>());
      expect(find.text('1,25×'), findsOneWidget);
      await tester.tap(find.byKey(const Key('disc-next')));
      await settleIo(tester);
      expect(player.rate, 1.25);
      await tester.tap(find.byKey(const Key('player-rate')));
      await settleIo(tester);
      expect(player.rate, 1);
      expect(find.byKey(const Key('player-rate')), findsNothing);
    });

    testWidgets('con el disco quieto un toque corto no abre las opciones, y deslizar de lado o en vertical ya no cambia nada', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await tester.tap(find.byKey(const Key('album-disc-root')));
      await settleIo(tester);
      expect(find.byKey(const Key('focus-panel')), findsNothing);
      final stage = tester.getRect(find.byKey(const Key('album-background')));
      await tester.flingFrom(Offset(stage.center.dx, stage.top + 120), const Offset(-300, 0), 1500);
      await tester.pumpAndSettle();
      await tester.flingFrom(Offset(stage.center.dx, stage.top + 120), const Offset(0, -300), 1500);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('album-title'))).data, 'Mi música');
      expect(await songTitle(tester), 'a');
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
      expect(await songTitle(tester), 'rock1');
    });

    testWidgets('al volver, la cuadrícula sigue ahí y la portada del último álbum que se vio vuelve a pintarse', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await swipeAlbum(tester);
      await swipeAlbum(tester); // Rock
      await settleIo(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      expect(find.byKey(const Key('album-background')), findsNothing);
      expect(card('card-folder-Rock'), findsOneWidget);
      expect(find.byKey(const Key('deck-hidden')), findsNothing);
      expect(find.descendant(of: card('card-folder-Rock'), matching: find.byKey(const Key('plate-blank'))), findsOneWidget);
    });

    testWidgets('«atrás» vuelve a la cuadrícula y el controlador a la raíz', (tester) async {
      await home(tester);
      await openAlbum(tester, 3, 'card-folder-Rock');
      expect(await songTitle(tester), 'rock1');
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
    /// Cuánto está girado el disco: el ángulo con que se pinta (la cuadrícula no se mueve, gira el dibujo).
    double turnOf(WidgetTester tester) => (tester.widget<CustomPaint>(find.byKey(const Key('vinyl-surface'))).painter! as VinylPainter).angle!.value;

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
      final still = turnOf(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(turnOf(tester), still); // aún sin sonar, quieto
      await tester.tap(find.byKey(const Key('album-disc-root')));
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      final first = turnOf(tester);
      expect(first, isNot(still));
      await tester.pump(const Duration(milliseconds: 100));
      expect(turnOf(tester), isNot(first));
      // pausa: todavía gira un momento y luego para
      await tester.tap(find.byKey(const Key('album-disc-root')));
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      final braking = turnOf(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(turnOf(tester), isNot(braking));
      await tester.pumpAndSettle(); // sin nada más que animar: se detuvo
      final stopped = turnOf(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(turnOf(tester), stopped);
    });

    /// Cuánto gira el disco en un segundo (ya a toda velocidad), con la velocidad de la canción en `rate`.
    Future<double> spinPerSecond(WidgetTester tester, double rate) async {
      await home(tester, moving: true);
      await player.setRate(rate);
      await openAlbum(tester, 1, 'card-root');
      await tester.tap(find.byKey(const Key('album-disc-root')));
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100)); // 4 s: la inercia (0,35 s) ya pasó
      }
      final before = turnOf(tester);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      return turnOf(tester) - before;
    }

    testWidgets('a velocidad normal gira a 33⅓ vueltas por minuto', (tester) async {
      expect(await spinPerSecond(tester, 1), closeTo(DiscPlayer.spinFor(1), 0.1));
    });

    testWidgets('con más velocidad el disco gira más rápido, y con menos, más lento', (tester) async {
      expect(await spinPerSecond(tester, 1.5), closeTo(DiscPlayer.spinFor(1) * 1.5, 0.15));
    });

    testWidgets('el disco lento gira a la mitad', (tester) async {
      expect(await spinPerSecond(tester, 0.5), closeTo(DiscPlayer.spinFor(1) * 0.5, 0.1));
    });

    test('lo que gira es proporcional a la velocidad', () {
      expect(DiscPlayer.spinFor(1), DiscPlayer.speed);
      expect(DiscPlayer.spinFor(2), DiscPlayer.speed * 2);
      expect(DiscPlayer.spinFor(0.5), DiscPlayer.speed / 2);
    });

    testWidgets('con la lista abierta el disco oculto no gira ni lee el sonido', (tester) async {
      await home(tester, moving: true);
      await openAlbum(tester, 1, 'card-root');
      await tester.tap(find.byKey(const Key('album-disc-root')));
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await openList(tester);
      double hiddenTurn() => (tester.widget<CustomPaint>(find.byKey(const Key('vinyl-surface'), skipOffstage: false)).painter! as VinylPainter).angle!.value;
      final stopped = hiddenTurn();
      await tester.pump(const Duration(seconds: 1));
      expect(hiddenTurn(), stopped); // el reloj del disco está apagado mientras no se ve
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

    testWidgets('con la lista abierta el fondo sigue siendo la portada, oscurecida con un velo plano (no un fondo liso)', (tester) async {
      saver.art[song('a.mp3').uri] = '/a.jpg';
      await home(tester);
      await tester.runAsync(pumpEventQueue);
      await openAlbum(tester, 1, 'card-root');
      await openList(tester);
      expect(find.descendant(of: find.byKey(const Key('album-backdrop')), matching: find.byKey(const Key('backdrop-cover'))), findsOneWidget);
      final dim = tester.widget<ColoredBox>(find.byKey(const Key('album-list-dim')));
      expect(dim.color, Colors.black.withValues(alpha: AlbumView.listDim)); // translúcido: deja ver la portada
      expect(AlbumView.listDim, inInclusiveRange(0.4, 0.75));
      expect(find.byType(BackdropFilter), findsNothing);
      await openList(tester);
      expect(find.byKey(const Key('album-list-dim')), findsNothing);
    });

    testWidgets('sin portada la lista abierta tapa con el color de la pantalla, como siempre', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await openList(tester);
      expect(tester.widget<ColoredBox>(find.byKey(const Key('album-list-dim'))).color.a, 1);
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
      expect(find.byKey(const Key('album-background')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('album-background')), findsNothing);
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
      expect(await songTitle(tester), 'c');
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
      expect(tester.widget<VinylDisc>(find.byType(VinylDisc)).file, saver.storedCovers.last.path);
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

    testWidgets('mantener pulsado un álbum abre el menú de consola: cambiar nombre, borrar álbum y cambiar foto', (tester) async {
      await home(tester);
      await deckTo(tester, 2); // Jazz
      expect(find.byKey(const Key('deck-menu-card-folder-Jazz')), findsNothing);
      await tester.longPress(card('card-folder-Jazz'));
      await tester.pumpAndSettle();
      final menu = find.byKey(const Key('deck-menu-card-folder-Jazz'));
      expect(menu, findsOneWidget);
      expect(find.byKey(const Key('deck-action-rename')), findsOneWidget);
      expect(find.byKey(const Key('deck-action-delete')), findsOneWidget);
      expect(find.byKey(const Key('deck-action-cover')), findsOneWidget);
      expect(find.text('CAMBIAR NOMBRE'), findsOneWidget);
      expect(find.text('BORRAR ÁLBUM'), findsOneWidget);
      expect(find.text('CAMBIAR FOTO'), findsOneWidget);
      expect(find.byType(AlbumGrid), findsOneWidget); // no se abrió el álbum
      // la «x» cierra el menú sin abrir el álbum
      await tester.tap(find.byKey(const Key('deck-menu-close')));
      await tester.pumpAndSettle();
      expect(menu, findsNothing);
      expect(find.byType(AlbumGrid), findsOneWidget);
    });

    testWidgets('en «Canciones enviadas» y en la carpeta elegida el menú solo ofrece cambiar la foto', (tester) async {
      await home(tester);
      await tester.longPress(card('card-received'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deck-action-cover')), findsOneWidget);
      expect(find.byKey(const Key('deck-action-rename')), findsNothing);
      expect(find.byKey(const Key('deck-action-delete')), findsNothing);
      await tester.tap(find.byKey(const Key('deck-action-cover')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('album-cover-pick')), findsOneWidget);
    });

    testWidgets('«Cambiar nombre» pide el nombre (con el de ahora) y renombra la carpeta', (tester) async {
      await home(tester);
      await deckTo(tester, 3); // Rock
      await tester.longPress(card('card-folder-Rock'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deck-action-rename')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('folder-name-field'))).controller!.text, 'Rock');
      await tester.enterText(find.byKey(const Key('folder-name-field')), 'Metal');
      await tester.tap(find.byKey(const Key('folder-create')));
      await settleIo(tester);
      expect(saver.renames.single, (uri: rock.uri, name: 'Metal'));
      expect(find.text('El álbum ahora se llama «Metal».'), findsOneWidget);
      expect(find.byKey(const Key('card-folder-Metal')), findsOneWidget);
    });

    testWidgets('«Borrar álbum» vacío pide confirmación y borra la carpeta', (tester) async {
      await home(tester);
      await deckTo(tester, 2); // Jazz: sin canciones
      await tester.longPress(card('card-folder-Jazz'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deck-action-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('album-delete-cancel')));
      await settleIo(tester);
      expect(saver.folderDeletes, isEmpty);
      await tester.longPress(card('card-folder-Jazz'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deck-action-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('album-delete-confirm')));
      await settleIo(tester);
      expect(saver.folderDeletes, [jazz.uri]);
      expect(find.byKey(const Key('card-folder-Jazz')), findsNothing);
    });

    testWidgets('«Borrar álbum» con canciones avisa de que deben pasarse a otro álbum o se borrarán con él; «Borrar todo» borra la carpeta entera', (tester) async {
      await home(tester);
      await deckTo(tester, 3); // Rock: 1 canción
      await tester.longPress(card('card-folder-Rock'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deck-action-delete')));
      await tester.pumpAndSettle();
      final warning = tester.widget<Text>(find.byKey(const Key('album-delete-warning'))).data!;
      expect(warning, contains('Rock'));
      expect(warning, contains('1 canción'));
      expect(warning, contains('otro álbum'));
      expect(warning, contains('se borrarán'));
      await tester.tap(find.byKey(const Key('album-delete-cancel'))); // cancelar no toca nada
      await settleIo(tester);
      expect(saver.folderDeletes, isEmpty);
      expect(saver.moves, isEmpty);
      await tester.longPress(card('card-folder-Rock'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deck-action-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('album-delete-all')));
      await settleIo(tester);
      expect(saver.folderDeletes, [rock.uri]);
      expect(saver.moves, isEmpty);
      expect(find.byKey(const Key('card-folder-Rock')), findsNothing);
    });

    testWidgets('«Pasarlas a otro álbum» mueve todas las canciones al destino y después borra la carpeta; sin destino no se borra nada', (tester) async {
      await home(tester);
      await deckTo(tester, 3); // Rock
      await tester.longPress(card('card-folder-Rock'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deck-action-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('album-delete-move')));
      await settleIo(tester);
      expect(tester.widget<Text>(find.byKey(const Key('move-title'))).data, 'Mover 1 canción a…');
      // se cierra la hoja sin elegir: nada se mueve ni se borra
      await tester.tapAt(const Offset(2, 2));
      await settleIo(tester);
      expect(saver.moves, isEmpty);
      expect(saver.folderDeletes, isEmpty);
      // ahora sí: a Jazz
      await tester.longPress(card('card-folder-Rock'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deck-action-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('album-delete-move')));
      await settleIo(tester);
      await tester.tap(find.byKey(const Key('move-folder-Jazz')));
      await settleIo(tester);
      await tester.tap(find.byKey(const Key('move-here')));
      await settleIo(tester);
      expect(saver.moves.single.uris, [song('rock1.mp3', dir: 'rock').uri]);
      expect(saver.moves.single.to, jazz.uri);
      expect(saver.folderDeletes, [rock.uri]);
      expect(saver.dirSongs[jazz.uri], hasLength(1));
      expect(find.byKey(const Key('card-folder-Rock')), findsNothing);
    });

    testWidgets('si alguna canción no se pudo pasar, el álbum no se borra', (tester) async {
      saver.moveFailures[song('rock1.mp3', dir: 'rock').uri] = 'No se pudo borrar el original.';
      await home(tester);
      await deckTo(tester, 3); // Rock
      await tester.longPress(card('card-folder-Rock'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deck-action-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('album-delete-move')));
      await settleIo(tester);
      await tester.tap(find.byKey(const Key('move-folder-Jazz')));
      await settleIo(tester);
      await tester.tap(find.byKey(const Key('move-here')));
      await settleIo(tester);
      expect(saver.folderDeletes, isEmpty);
      expect(find.textContaining('no se borró'), findsOneWidget);
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

    /// Entra en el modo selección con el botón «Seleccionar» (marca la canción del centro de la lista, `a.mp3`) y deja marcadas justo `names`.
    Future<void> mark(WidgetTester tester, List<String> names) async {
      await tester.tap(find.byKey(const Key('album-select')));
      await tester.pump();
      for (final n in names) {
        if (n == 'a.mp3') continue;
        await tester.tap(find.byKey(Key(uriKey(n))));
        await tester.pump();
      }
      if (!names.contains('a.mp3')) {
        await tester.tap(find.byKey(Key(uriKey('a.mp3'))));
        await tester.pump();
      }
    }

    testWidgets('«Seleccionar» marca la canción del centro, tocar otra suma y «Cancelar» quita todo', (tester) async {
      await openRoot(tester);
      await mark(tester, ['a.mp3']);
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
      await mark(tester, ['a.mp3']);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('selection-count')), findsNothing);
      expect(find.byKey(const Key('arc-list')), findsOneWidget); // seguimos en la lista
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('arc-list')), findsNothing);
      expect(find.byKey(const Key('album-background')), findsOneWidget); // seguimos en el álbum
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('album-background')), findsNothing);
    });

    testWidgets('«Mover»: se elige la carpeta, «Mover aquí» y las canciones cambian de carpeta de verdad', (tester) async {
      await openRoot(tester);
      await mark(tester, ['a.mp3']);
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
      await mark(tester, ['c.mp3']);
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

    testWidgets('la hoja de mover enseña los álbumes en cuadrícula (cuadrados, tres por fila), no en lista', (tester) async {
      await openRoot(tester);
      await mark(tester, ['a.mp3']);
      await tester.tap(find.byKey(const Key('move-selected')));
      await settleIo(tester);
      expect(find.byKey(const Key('move-grid')), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
      final rock = tester.getRect(find.byKey(const Key('move-folder-Rock')));
      final jazz = tester.getRect(find.byKey(const Key('move-folder-Jazz')));
      expect(rock.width, closeTo(rock.height, 1)); // cuadrados
      expect(rock.width, jazz.width);
      expect(rock.top, jazz.top); // en la misma fila
    });

    testWidgets('la hoja de mover solo ofrece los álbumes: dentro de uno no se ven sus subcarpetas ni se pueden crear', (tester) async {
      saver.dirFolders[rock.uri] = [const LocalFolder(uri: 'content://tree/musica/document/Rock/Viejo', name: 'Viejo', count: 0)];
      await openRoot(tester);
      await mark(tester, ['a.mp3']);
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
      await mark(tester, ['a.mp3']);
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
    testWidgets('mantener pulsada una canción abre su menú con «Mover» y «Borrar» (ya no la marca)', (tester) async {
      await openRoot(tester);
      await tester.longPress(find.byKey(Key(uriKey('b.mp3'))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('song-opt-move')), findsOneWidget);
      expect(find.byKey(const Key('song-opt-delete')), findsOneWidget);
      expect(find.byKey(const Key('selection-count')), findsNothing);
      await tester.tap(find.byKey(const Key('song-opt-move')));
      await settleIo(tester);
      expect(tester.widget<Text>(find.byKey(const Key('move-title'))).data, 'Mover 1 canción a…');
      await tester.tap(find.byKey(const Key('move-folder-Jazz')));
      await settleIo(tester);
      await tester.tap(find.byKey(const Key('move-here')));
      await settleIo(tester);
      expect(saver.moves.single.uris, [song('b.mp3').uri]);
      expect(find.byKey(Key(uriKey('b.mp3'))), findsNothing);
    });

    testWidgets('«Borrar» del menú de una canción pide confirmación y borra solo esa', (tester) async {
      await openRoot(tester);
      await tester.longPress(find.byKey(Key(uriKey('c.mp3'))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('song-opt-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('song-delete-confirm')));
      await settleIo(tester);
      expect(saver.deletes.single, [song('c.mp3').uri]);
      expect(find.byKey(Key(uriKey('c.mp3'))), findsNothing);
      expect(find.byKey(Key(uriKey('a.mp3'))), findsOneWidget);
    });

    testWidgets('con canciones marcadas, el botón de borrar pide confirmación y borra todas las marcadas', (tester) async {
      await openRoot(tester);
      await mark(tester, ['a.mp3', 'b.mp3']);
      await tester.tap(find.byKey(const Key('delete-selected')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('album-delete-text'))).data, contains('2 canciones'));
      await tester.tap(find.byKey(const Key('album-delete-confirm')));
      await settleIo(tester);
      expect(saver.deletes.single, hasLength(2));
      expect(saver.files.map((f) => f.name), ['c.mp3']);
    });

    testWidgets('el buscador del álbum filtra la lista por lo que se escribe (sin importar mayúsculas ni acentos) y al cerrarlo vuelven todas', (tester) async {
      saver.files = [song('Álvaro - Mar.mp3'), song('Beta.mp3'), song('Gamma - Mar azul.mp3')];
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await tester.tap(find.byKey(const Key('album-search')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('album-search-field')), findsOneWidget);
      expect(find.byKey(Key(uriKey('Beta.mp3'))), findsOneWidget); // sin escribir, todas
      await tester.enterText(find.byKey(const Key('album-search-field')), 'ALVARO');
      await tester.pumpAndSettle();
      expect(find.byKey(Key(uriKey('Álvaro - Mar.mp3'))), findsOneWidget);
      expect(find.byKey(Key(uriKey('Beta.mp3'))), findsNothing);
      await tester.enterText(find.byKey(const Key('album-search-field')), 'mar');
      await tester.pumpAndSettle();
      expect(find.byKey(Key(uriKey('Álvaro - Mar.mp3'))), findsOneWidget);
      expect(find.byKey(Key(uriKey('Gamma - Mar azul.mp3'))), findsOneWidget);
      expect(find.byKey(Key(uriKey('Beta.mp3'))), findsNothing);
      await tester.enterText(find.byKey(const Key('album-search-field')), 'zzz');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('album-search-empty')), findsOneWidget);
      await tester.tap(find.byKey(const Key('album-search-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('album-search-field')), findsNothing);
      expect(find.byKey(Key(uriKey('Beta.mp3'))), findsOneWidget);
    });

    testWidgets('tocar una canción encontrada la reproduce con todo el álbum como cola', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await tester.tap(find.byKey(const Key('album-search')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('album-search-field')), 'c');
      await tester.pumpAndSettle();
      await playRow(tester, find.byKey(Key(uriKey('c.mp3'))), 'local:${song('c.mp3').uri}');
      await settleIo(tester);
      expect(player.current?.title, 'c');
      expect(player.queue.map((t) => t.title), ['a', 'b', 'c']);
    });

  });

  group('canciones enviadas', () {
    testWidgets('«Recibido» y el menú ⋯ salen en la píldora de la fila del centro, y al sonar otra se enseña debajo del disco', (tester) async {
      backend.add('r1', at: DateTime.utc(2026, 9, 1));
      backend.add('r2', at: DateTime.utc(2026, 9, 2)); // la más nueva sale primera
      await home(tester);
      await openAlbum(tester, 0, 'card-received');
      expect(await songTitle(tester), 'Canción r2');
      await openList(tester);
      expect(find.byKey(const Key('received-r2')), findsOneWidget);
      expect(find.byKey(const Key('more-r2')), findsOneWidget);
      expect(find.byKey(const Key('received-r1')), findsNothing);
      await playRow(tester, find.byKey(const Key('track-r1')), 'r1');
      await settleIo(tester);
      expect(find.byKey(const Key('received-r1')), findsOneWidget);
      expect(engine.queue.map((q) => q.title), contains('Canción r1'));
      await openList(tester);
      expect(await songTitle(tester), 'Canción r1');
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
          music: music,
          local: local,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(await songTitle(tester), 'a');
    expect(find.byKey(const Key('album-opening')), findsNothing);
  });
  group('el aleatorio entre todos los álbumes', () {
    testWidgets('sin la opción, arriba sale el botón «Aleatorio»; con ella, no', (tester) async {
      await home(tester);
      expect(find.byKey(const Key('music-shuffle-all')), findsOneWidget);
      await tester.runAsync(() => music.updateSettings(music.settings.copyWith(autoShuffle: true)));
      await tester.pump();
      expect(find.byKey(const Key('music-shuffle-all')), findsNothing);
    });

    testWidgets('el botón pone a sonar una canción cualquiera con las de todos los álbumes en la cola y el aleatorio puesto', (tester) async {
      await home(tester);
      await tester.tap(find.byKey(const Key('music-shuffle-all')));
      await settleIo(tester);
      expect(player.current, isNotNull);
      expect(player.shuffle, isTrue);
      expect(engine.shuffle, isTrue);
      final titles = engine.queue.map((q) => q.title).toSet();
      // las de la carpeta y las de Rock: de varios álbumes
      expect(titles, containsAll(['a', 'b', 'c', 'rock1']));
      expect(engine.isPlaying, isTrue);
    });

    testWidgets('con la opción puesta, al abrir Música empieza a sonar sola en aleatorio', (tester) async {
      store.settings = store.settings.copyWith(autoShuffle: true);
      await home(tester);
      await settleIo(tester);
      expect(player.current, isNotNull);
      expect(player.shuffle, isTrue);
      expect(engine.queue.map((q) => q.title), contains('rock1'));
      expect(find.byKey(const Key('music-shuffle-all')), findsNothing);
    });

    testWidgets('sin canciones lo dice y no falla', (tester) async {
      saver
        ..files = []
        ..rootFolders = [];
      await home(tester);
      await tester.tap(find.byKey(const Key('music-shuffle-all')));
      await settleIo(tester);
      expect(player.current, isNull);
      expect(find.text('Aún no hay canciones para el aleatorio.'), findsOneWidget);
    });

    test('playShuffled elige una al azar, activa el aleatorio y pone todas en la cola', () async {
      final engine = FakeEngine();
      final player = PlayerController(FakeMusicBackend(), engine, noteAfter: Duration.zero);
      addTearDown(player.dispose);
      final all = [for (final n in ['x.mp3', 'y.mp3', 'z.mp3']) Track.local(song(n))];
      await player.playShuffled(all, random: math.Random(3));
      expect(player.shuffle, isTrue);
      expect(engine.shuffle, isTrue);
      expect(engine.queue, hasLength(3));
      expect(all.map((t) => t.id), contains(player.current!.id));
      await player.playShuffled(const []);
      expect(engine.queue, hasLength(3)); // sin canciones no hace nada
    });

    test('allTracks lee todas las carpetas, también las que no se habían leído', () async {
      await music.start();
      final all = await local.allTracks();
      expect(all.map((t) => t.title), containsAll(['a', 'b', 'c', 'rock1']));
    });

    test('la opción se guarda con los demás ajustes y no se pierde al elegir o quitar la carpeta', () {
      const settings = MusicSettings(autoShuffle: true);
      expect(settings.copyWith(auto: false).autoShuffle, isTrue);
      expect(settings.withTree('content://x', 'x').autoShuffle, isTrue);
      expect(settings.withTree('content://x', 'x').withoutTree().autoShuffle, isTrue);
      expect(const MusicSettings().autoShuffle, isFalse);
    });

    testWidgets('la vista del álbum va sola al disco del álbum de la canción que empieza a sonar', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await settleIo(tester);
      expect(tester.widget<Text>(find.byKey(const Key('album-title'))).data, 'Mi música');
      final rock1 = Track.local(song('rock1.mp3', dir: 'rock'));
      await tester.runAsync(() => player.play(rock1, [rock1]));
      await settleIo(tester);
      expect(tester.widget<Text>(find.byKey(const Key('album-title'))).data, 'Rock');
    });
  });

  group('el disco, del color de su portada', () {
    tearDown(CoverTints.clear);

    testWidgets('el plástico, el anillo de avance y la línea del sonido van del color de la portada', (tester) async {
      saver.art[song('a.mp3').uri] = '/a.jpg';
      CoverTints.set('/a.jpg', const Color(0xFF22DD66));
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      final disc = tester.widget<CustomPaint>(find.byKey(const Key('vinyl-surface')));
      expect((disc.painter! as VinylPainter).ink, const Color(0xFF22DD66));
      final ring = tester.widget<CustomPaint>(find.byKey(const Key('disc-progress')));
      expect((ring.painter! as ProgressRingPainter).ink, const Color(0xFF22DD66));
      expect(tester.widget<SoundCircle>(find.byType(SoundCircle)).color, const Color(0xFF22DD66));
    });

    testWidgets('sin color (portada gris o sin portada) va en el acento de la app', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      final disc = tester.widget<CustomPaint>(find.byKey(const Key('vinyl-surface')));
      expect((disc.painter! as VinylPainter).ink, KyoraColors.classic().accent);
    });

    test('el color de un pixel art es su tono con más presencia, vivo y brillante', () {
      final rgba = Uint8List.fromList([for (var i = 0; i < 20; i++) ...[230, 120, 20, 255]]);
      final tint = tintOf(PixelArt(5, 4, rgba))!;
      final hsv = HSVColor.fromColor(tint);
      expect(hsv.hue, inInclusiveRange(20, 40)); // naranja
      expect(hsv.value, greaterThan(0.95));
      expect(tintOf(PixelArt(1, 1, Uint8List.fromList([128, 128, 128, 255]))), isNull); // gris: sin color
    });
  });
}
