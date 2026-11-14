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
import 'package:kyora_chat/ui/widgets/album_stack.dart';
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

  group('la pila de álbumes', () {
    /// El centro de la portada de un álbum de la pila.
    Offset centerOf(WidgetTester tester, String id) => tester.getCenter(card(id));

    testWidgets('las portadas van en una pila vertical: la del centro, grande y delante; las demás, detrás y asomando debajo', (tester) async {
      await home(tester);
      expect(find.byType(AlbumStack), findsOneWidget);
      expect(find.text('Canciones enviadas'), findsOneWidget); // el nombre de la del centro
      final first = tester.getRect(find.descendant(of: card('card-received'), matching: find.byKey(const Key('plate-blank'))));
      expect(first.width, closeTo(first.height, 0.5));
      final deck = tester.getRect(find.byKey(const Key('album-deck')));
      expect(first.center.dx, closeTo(deck.center.dx, 1));
      expect(first.center.dy, closeTo(deck.center.dy, 1));
      // las siguientes asoman por debajo, cada vez más pequeñas
      final root = tester.getRect(card('card-root'));
      final jazz = tester.getRect(card('card-folder-Jazz'));
      expect(root.center.dy, greaterThan(first.center.dy));
      expect(jazz.center.dy, greaterThan(root.center.dy));
      expect(root.width, lessThan(first.width));
      expect(jazz.width, lessThan(root.width));
      // y en cascada: una hacia un lado y la siguiente hacia el otro
      expect((root.center.dx - deck.center.dx).sign, isNot((jazz.center.dx - deck.center.dx).sign));
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
      // y las portadas son grandes: la del centro ocupa buena parte del ancho
      final first = tester.getRect(find.descendant(of: card('card-received'), matching: find.byKey(const Key('plate-blank'))));
      expect(first.width, greaterThan(400 * 0.7));
      expect(find.byType(ClipRRect), findsNothing);
    });

    testWidgets('la etiqueta dice el nombre del álbum del centro y en qué número va', (tester) async {
      await home(tester);
      expect(find.byKey(const Key('deck-title-card-received')), findsOneWidget);
      expect(find.text('01/05'), findsOneWidget);
      await deckTo(tester, 2);
      expect(find.byKey(const Key('deck-title-card-folder-Jazz')), findsOneWidget);
      expect(find.text('03/05'), findsOneWidget);
    });

    testWidgets('se recorren todos arrastrando en vertical, en orden, y siempre queda uno en el centro', (tester) async {
      await home(tester);
      final deck = tester.getRect(find.byKey(const Key('album-deck')));
      final names = {'card-root': 'Mi música', 'card-folder-Jazz': 'Jazz', 'card-folder-Rock': 'Rock', 'card-new-folder': 'Nuevo álbum'};
      var i = 1;
      for (final entry in names.entries) {
        await deckTo(tester, i++);
        expect(centerOf(tester, entry.key).dy, closeTo(deck.center.dy, 1), reason: entry.key);
        expect(find.byKey(Key('deck-title-${entry.key}')), findsOneWidget);
      }
    });

    testWidgets('tiene tope: no se pasa del primero ni del último', (tester) async {
      await home(tester);
      final deck = tester.getRect(find.byKey(const Key('album-deck')));
      await tester.timedDrag(find.byKey(const Key('album-deck')), Offset(0, stackStep(tester) * 3), const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(centerOf(tester, 'card-received').dy, closeTo(deck.center.dy, 1));
      await tester.fling(find.byKey(const Key('album-deck')), const Offset(0, -2000), 5000);
      await tester.pumpAndSettle();
      await tester.fling(find.byKey(const Key('album-deck')), const Offset(0, -2000), 5000);
      await tester.pumpAndSettle();
      expect(centerOf(tester, 'card-new-folder').dy, closeTo(deck.center.dy, 1));
    });

    testWidgets('al soltar sigue un poco por la inercia y se detiene justo en una portada', (tester) async {
      await home(tester);
      final deck = tester.getRect(find.byKey(const Key('album-deck')));
      await tester.fling(find.byKey(const Key('album-deck')), Offset(0, -stackStep(tester) * 0.6), 900);
      await tester.pumpAndSettle();
      final stack = tester.widget<AlbumStack>(find.byType(AlbumStack));
      final front = stack.controller!.current;
      expect(front, greaterThanOrEqualTo(1));
      final id = ['card-received', 'card-root', 'card-folder-Jazz', 'card-folder-Rock', 'card-new-folder'][front];
      expect(centerOf(tester, id).dy, closeTo(deck.center.dy, 1));
    });

    testWidgets('tocar una portada que no está en el centro la trae al centro, sin abrirla', (tester) async {
      await home(tester);
      final deck = tester.getRect(find.byKey(const Key('album-deck')));
      final below = tester.getRect(card('card-root'));
      await tester.tapAt(Offset(below.center.dx, below.center.dy + below.height * 0.25)); // la parte que asoma por debajo
      await tester.pumpAndSettle();
      expect(centerOf(tester, 'card-root').dy, closeTo(deck.center.dy, 1));
      expect(find.byKey(const Key('album-background')), findsNothing);
    });

    testWidgets('las de atrás se oscurecen cuanto más lejos', (tester) async {
      final near = AlbumStack.placeOf(1, 0, const Size(400, 500), 200);
      final far = AlbumStack.placeOf(3, 0, const Size(400, 500), 200);
      final center = AlbumStack.placeOf(0, 0, const Size(400, 500), 200);
      expect(center.shade, 0);
      expect(near.shade, greaterThan(0));
      expect(far.shade, greaterThan(near.shade));
      expect(center.scale, 1);
      expect(far.scale, lessThan(near.scale));
    });

    testWidgets('al salir de la sección no queda ninguna foto a la vista: la pila se funde y recorta en su rectángulo', (tester) async {
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
      expect(find.descendant(of: deck, matching: find.byType(ClipRect)), findsWidgets);
    });

    testWidgets('un álbum sin portada tiene detrás el fondo de la pantalla', (tester) async {
      await home(tester);
      await tester.tap(card('card-received'));
      await settleIo(tester);
      expect(find.byKey(const Key('album-background')), findsOneWidget);
      expect(find.descendant(of: find.byType(AlbumView), matching: find.byKey(const Key('screen-backdrop'))), findsWidgets);
    });

    testWidgets('tocar la del centro abre el álbum', (tester) async {
      await home(tester);
      await deckTo(tester, 1);
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

  group('la sensibilidad', () {
    testWidgets('la pila obedece a la sensibilidad guardada: con menos, el mismo gesto no cambia de álbum', (tester) async {
      store.settings = store.settings.copyWith(deckSpeed: MusicSettings.deckSpeedMin);
      await home(tester);
      expect(tester.widget<AlbumStack>(find.byType(AlbumStack)).speed, MusicSettings.deckSpeedMin);
      final normal = stackStep(tester) * MusicSettings.deckSpeedMin; // lo que haría falta con la normal
      await tester.timedDrag(find.byKey(const Key('album-deck')), Offset(0, -normal * 0.9), const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(tester.widget<AlbumStack>(find.byType(AlbumStack)).controller!.current, 0); // se queda
    });

    testWidgets('con poco arrastre no se cambia de álbum', (tester) async {
      await home(tester);
      await tester.timedDrag(find.byKey(const Key('album-deck')), Offset(0, -stackStep(tester) * 0.3), const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(tester.widget<AlbumStack>(find.byType(AlbumStack)).controller!.current, 0);
    });

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
      expect(songTitle(tester), 'b');
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
      expect(discMid.center.dy, lessThan(disc.center.dy - 20)); // sube hacia su sitio, algo por encima del centro de la pantalla
      // al final: la transición desaparece y el disco de la vista está en el centro
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('album-opening')), findsNothing);
      final resting = tester.getRect(find.byKey(Key('album-disc-${rock.uri}')));
      expect(resting.center, const Offset(200, 357)); // algo por encima del centro de la pantalla
      expect(resting.width, resting.height);
      expect(find.byKey(const Key('vinyl-surface')), findsOneWidget); // es un disco
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
      expect(find.byKey(const Key('album-background')), findsNothing);
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
    testWidgets('el disco algo por encima del centro, debajo el nombre sin fondo, y de fondo la portada nítida con líneas y oscurecida', (tester) async {
      saver.art[song('a.mp3').uri] = '/a.jpg';
      await home(tester);
      await tester.runAsync(pumpEventQueue);
      await openAlbum(tester, 1, 'card-root');
      expect(songTitle(tester), 'a'); // la primera, por orden
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

    testWidgets('mantener el disco abre sus opciones, no la pila de álbumes; tocar fuera las cierra sin cambiar de álbum', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      expect(find.byKey(const Key('focus-panel')), findsNothing);
      await holdDisc(tester);
      expect(find.byKey(const Key('focus-panel')), findsOneWidget);
      expect(find.byKey(const Key('album-picker')), findsNothing);
      expect(find.byType(AlbumStack), findsNothing);
      for (final key in ['album-opt-shuffle', 'album-opt-move', 'album-opt-delete', 'album-rate']) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      await tester.tapAt(const Offset(2, 2)); // fuera del panel
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('focus-panel')), findsNothing);
      expect(tester.widget<Text>(find.byKey(const Key('album-title'))).data, 'Mi música'); // sigue aquí
    });

    testWidgets('en las canciones enviadas solo salen el aleatorio y la velocidad (no se mueven ni se borran de aquí)', (tester) async {
      backend.add('s1', at: DateTime.utc(2026, 9, 1));
      await home(tester);
      await openAlbum(tester, 0, 'card-received');
      await holdDisc(tester);
      expect(find.byKey(const Key('album-opt-shuffle')), findsOneWidget);
      expect(find.byKey(const Key('album-opt-move')), findsNothing);
      expect(find.byKey(const Key('album-opt-delete')), findsNothing);
      expect(find.byKey(const Key('album-rate')), findsOneWidget);
    });

    testWidgets('«Aleatorio del álbum» pone a sonar solo las canciones de ese álbum, con el aleatorio puesto', (tester) async {
      await home(tester);
      await openAlbum(tester, 3, 'card-folder-Rock');
      await holdDisc(tester);
      await tester.tap(find.byKey(const Key('album-opt-shuffle')));
      await settleIo(tester);
      expect(find.byKey(const Key('focus-panel')), findsNothing);
      expect(player.shuffle, isTrue);
      expect(engine.shuffle, isTrue);
      expect(player.playing, isTrue);
      expect(player.queue.map((t) => t.title), ['rock1']); // solo las de Rock, no las de las demás carpetas
    });

    testWidgets('«Borrar álbum» pide confirmación; al cancelar no borra nada y al confirmar borra de verdad sus canciones', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await holdDisc(tester);
      await tester.tap(find.byKey(const Key('album-opt-delete')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('album-delete-text'))).data, contains('3 canciones'));
      expect(tester.widget<Text>(find.byKey(const Key('album-delete-text'))).data, contains('Mi música'));
      await tester.tap(find.byKey(const Key('album-delete-cancel')));
      await tester.pumpAndSettle();
      expect(saver.deletes, isEmpty);
      expect(saver.files, hasLength(3));
      await holdDisc(tester);
      await tester.tap(find.byKey(const Key('album-opt-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('album-delete-confirm')));
      await settleIo(tester);
      expect(saver.deletes, hasLength(1));
      expect(saver.deletes.single, hasLength(3));
      expect(saver.files, isEmpty);
      expect(find.text('Se borraron 3 canciones de «Mi música».'), findsOneWidget);
      expect(find.text('No hay archivos .mp3 en «Mi música».'), findsOneWidget); // el álbum se ve vacío
    });

    testWidgets('si suena una canción del álbum que se borra, primero se para', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await tester.tap(find.byKey(const Key('album-disc-root')));
      await settleIo(tester);
      expect(player.playing, isTrue);
      await holdDisc(tester);
      await tester.tap(find.byKey(const Key('album-opt-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('album-delete-confirm')));
      await settleIo(tester);
      expect(engine.calls, contains('stop'));
      expect(player.current, isNull);
      expect(player.queue, isEmpty);
      expect(saver.files, isEmpty);
    });

    testWidgets('un borrado que falla a medias lo cuenta y deja lo que no se pudo borrar', (tester) async {
      saver.deleteFailures[song('b.mp3').uri] = 'Android no lo borró.';
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await holdDisc(tester);
      await tester.tap(find.byKey(const Key('album-opt-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('album-delete-confirm')));
      await settleIo(tester);
      expect(saver.files.map((f) => f.name), ['b.mp3']);
      expect(find.textContaining('Se borraron 2 canciones de «Mi música».'), findsOneWidget);
      expect(find.textContaining('No se pudo borrar 1: Android no lo borró.'), findsOneWidget);
    });

    testWidgets('«Mover álbum» lleva todas sus canciones a la carpeta que se elija', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await holdDisc(tester);
      await tester.tap(find.byKey(const Key('album-opt-move')));
      await settleIo(tester);
      expect(tester.widget<Text>(find.byKey(const Key('move-title'))).data, 'Mover 3 canciones a…');
      await tester.tap(find.byKey(const Key('move-folder-Jazz')));
      await settleIo(tester);
      await tester.tap(find.byKey(const Key('move-here')));
      await settleIo(tester);
      expect(saver.moves, hasLength(1));
      expect(saver.moves.single.uris, hasLength(3));
      expect(saver.moves.single.to, jazz.uri);
      expect(saver.files, isEmpty);
      expect(saver.dirSongs[jazz.uri], hasLength(3));
      expect(find.text('Se movieron 3 canciones a «Jazz».'), findsOneWidget);
    });

    testWidgets('el medidor cambia la velocidad y el tono a la vez, al instante, y «1×» la devuelve a la normal', (tester) async {
      await home(tester);
      await openAlbum(tester, 1, 'card-root');
      await holdDisc(tester);
      expect(tester.widget<Text>(find.byKey(const Key('album-rate-label'))).data, '1×');
      expect(tester.widget<TextButton>(find.byKey(const Key('album-rate-reset'))).onPressed, isNull); // ya está en 1×
      final slider = tester.widget<Slider>(find.byKey(const Key('album-rate')));
      expect([slider.min, slider.max], [0.5, 1.5]);
      slider.onChanged!(0.85);
      await tester.pump();
      expect(player.rate, 0.85);
      expect(engine.rate, 0.85);
      expect(engine.calls, contains('rate:0.85'));
      expect(tester.widget<Text>(find.byKey(const Key('album-rate-label'))).data, '0,85×');
      await tester.tap(find.byKey(const Key('album-rate-reset')));
      await tester.pump();
      expect(player.rate, 1);
      expect(engine.rate, 1);
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
      expect(songTitle(tester), 'a');
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
      expect(find.byKey(const Key('album-background')), findsNothing);
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
      expect(find.byKey(const Key('album-background')), findsOneWidget); // seguimos en el álbum
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('album-background')), findsNothing);
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
