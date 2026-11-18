import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/audio_engine.dart';
import 'package:kyora_chat/data/audio_levels.dart';
import 'package:kyora_chat/data/favorites_store.dart';
import 'package:kyora_chat/models/track.dart';
import 'package:kyora_chat/state/player_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/home_page.dart';
import 'package:kyora_chat/ui/section_host.dart';
import 'package:kyora_chat/ui/widgets/app_section.dart';
import 'package:kyora_chat/ui/widgets/home_player.dart';
import 'package:kyora_chat/ui/widgets/marble_texture.dart';
import 'package:kyora_chat/ui/widgets/vinyl_disc.dart';
import 'package:kyora_chat/util/cover_tint.dart';
import 'package:kyora_chat/util/pixel_art.dart';
import 'package:kyora_chat/util/wallpaper_color.dart';

import 'fake_engine.dart';
import 'music_test.dart' show FakeMusicBackend;

/// Unos píxeles RGBA: `parts` son (color, cuántos).
Uint8List pixels(List<(Color, int)> parts) {
  final out = <int>[];
  for (final (color, count) in parts) {
    for (var i = 0; i < count; i++) {
      out.addAll([(color.r * 255).round(), (color.g * 255).round(), (color.b * 255).round(), 255]);
    }
  }
  return Uint8List.fromList(out);
}

void main() {
  group('el reproductor de Inicio', () {
    late FakeMusicBackend backend;
    late FakeEngine engine;
    late FakeLevels levels;
    late PlayerController player;
    late FavoritesController favorites;
    late List<Track> tracks;
    final opened = <String>[];

    setUp(() {
      backend = FakeMusicBackend();
      engine = FakeEngine();
      levels = FakeLevels();
      player = PlayerController(backend, engine, noteAfter: Duration.zero, levels: levels);
      favorites = FavoritesController();
      backend
        ..add('a', title: 'Queen - Bohemian Rhapsody')
        ..add('b', title: 'Otra');
      tracks = List.of(backend.tracks);
      opened.clear();
    });

    tearDown(() {
      player.dispose();
      favorites.dispose();
    });

    Future<void> show(WidgetTester tester, {bool withFavorites = true, Size size = const Size(400, 850)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: SingleChildScrollView(child: HomePlayer(player: player, favorites: withFavorites ? favorites : null, onOpenMusic: () => opened.add('music'))),
        ),
      ));
      await tester.pump();
    }

    Future<void> play(WidgetTester tester, [int i = 1]) async {
      await tester.runAsync(() => player.play(tracks[i], tracks));
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
    }

    testWidgets('sin canción cargada no sale nada', (tester) async {
      await show(tester);
      expect(find.byKey(const Key('home-player')), findsNothing);
    });

    testWidgets('con una canción: portada, título, artista, barra con los tiempos y los controles', (tester) async {
      await show(tester);
      await play(tester, 1);
      expect(find.byKey(const Key('home-player')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('home-player-title'))).data, startsWith('Bohemian Rhapsody'));
      expect(tester.widget<Text>(find.byKey(const Key('home-player-artist'))).data, 'QUEEN');
      expect(find.byKey(const Key('home-player-bar')), findsOneWidget);
      expect(find.byKey(const Key('home-player-position')), findsOneWidget);
      expect(find.byKey(const Key('home-player-duration')), findsOneWidget);
      expect(find.byKey(const Key('home-player-eq')), findsOneWidget);
      for (final k in ['hp-repeat', 'hp-shuffle', 'hp-prev', 'hp-toggle', 'hp-next', 'hp-open', 'hp-heart']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
    });

    testWidgets('a todo lo ancho (el ancho de la pantalla menos los márgenes de la página)', (tester) async {
      await show(tester);
      await play(tester);
      expect(tester.getSize(find.byKey(const Key('home-player'))).width, 400);
    });

    testWidgets('el principal hace pausa y reproducir; siguiente y anterior; aleatorio y repetir se encienden', (tester) async {
      await show(tester);
      await play(tester);
      expect(player.playing, isTrue);
      await tester.tap(find.byKey(const Key('hp-toggle')));
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      expect(player.playing, isFalse);
      await tester.tap(find.byKey(const Key('hp-shuffle')));
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      expect(player.shuffle, isTrue);
      await tester.tap(find.byKey(const Key('hp-repeat')));
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      expect(player.repeat, RepeatKind.all);
      await tester.tap(find.byKey(const Key('hp-repeat')));
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      expect(player.repeat, RepeatKind.one);
      expect(find.byIcon(Icons.repeat_one_rounded), findsOneWidget);
    });

    testWidgets('«Detener» para la canción y el reproductor desaparece de Inicio', (tester) async {
      await show(tester);
      await play(tester);
      expect(find.byKey(const Key('home-player')), findsOneWidget);
      await tester.tap(find.byKey(const Key('hp-stop')));
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      expect(player.current, isNull);
      expect(player.playing, isFalse);
      expect(find.byKey(const Key('home-player')), findsNothing);
    });

    testWidgets('el corazón marca y desmarca la favorita, y «abrir la música» avisa', (tester) async {
      await show(tester);
      await play(tester);
      final key = tracks[1].durationKey;
      expect(favorites.isFavorite(key), isFalse);
      await tester.tap(find.byKey(const Key('hp-heart')));
      await tester.pump();
      expect(favorites.isFavorite(key), isTrue);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      await tester.tap(find.byKey(const Key('hp-heart')));
      await tester.pump();
      expect(favorites.isFavorite(key), isFalse);
      await tester.tap(find.byKey(const Key('hp-open')));
      expect(opened, ['music']);
    });

    testWidgets('sin favoritas no hay corazón', (tester) async {
      await show(tester, withFavorites: false);
      await play(tester);
      expect(find.byKey(const Key('hp-heart')), findsNothing);
    });

    testWidgets('tocar la barra adelanta la canción a ese punto', (tester) async {
      await show(tester);
      await play(tester);
      engine.emitDuration(const Duration(minutes: 4));
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('home-player-duration'))).data, '4:00');
      expect(tester.getSize(find.byKey(const Key('home-player-bar'))).width, greaterThan(300)); // la barra ocupa todo el ancho
      await tester.tap(find.byKey(const Key('home-player-bar')));
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      expect(player.position.inSeconds, closeTo(120, 2));
    });

    testWidgets('el ecualizador escucha el sonido mientras suena y lo suelta en pausa', (tester) async {
      await show(tester);
      await play(tester);
      expect(levels.started, greaterThan(0));
      levels.emitFrame(SoundFrame(level: 0.8, wave: List.filled(48, 0.7)));
      await tester.pump();
      await tester.runAsync(() => player.toggle());
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      expect(levels.stopped, greaterThan(0));
    });

    testWidgets('en una pantalla estrecha no se desborda', (tester) async {
      await show(tester, size: const Size(320, 600));
      await play(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('en Inicio sale debajo del tablero y «abrir la música» lleva a esa sección', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: SectionHost(sections: [
          AppSection(id: 'home', icon: Icons.home_outlined, label: 'Inicio', builder: (_) => HomePage(onOpenSettings: () {}, player: player, favorites: favorites, now: () => DateTime(2026, 11, 9, 9, 30))),
          AppSection(id: 'music', icon: Icons.music_note_outlined, label: 'Música', builder: (_) => const Text('Pantalla música')),
        ]),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-player')), findsNothing);
      await play(tester);
      await tester.pumpAndSettle();
      final grid = tester.getRect(find.byKey(const Key('home-grid')));
      final card = tester.getRect(find.byKey(const Key('home-player')));
      expect(card.top, greaterThanOrEqualTo(grid.bottom));
      expect(card.width, closeTo(grid.width, 1));
      await tester.tap(find.byKey(const Key('hp-open')));
      await tester.pumpAndSettle();
      expect(find.text('Pantalla música'), findsOneWidget);
    });
  });

  group('los colores de una portada para su vinilo', () {
    test('un solo color: el segundo tono es vecino y el fondo, casi negro', () {
      final palette = paletteOf(pixels([(const Color(0xFFE02020), 200)]))!;
      expect(HSVColor.fromColor(palette.main).hue, closeTo(0, 6));
      final second = HSVColor.fromColor(palette.second).hue;
      expect(second, inInclusiveRange(25, 50)); // un tono vecino
      expect(palette.deep.computeLuminance(), lessThan(0.05));
    });

    test('con dos colores de la portada, el segundo tono sale de ella', () {
      final palette = paletteOf(pixels([(const Color(0xFFE02020), 300), (const Color(0xFF2060FF), 200), (const Color(0xFF101010), 100)]))!;
      expect(HSVColor.fromColor(palette.main).hue, closeTo(0, 8)); // el rojo pesa más
      expect(HSVColor.fromColor(palette.second).hue, closeTo(225, 12)); // el azul de la portada
    });

    test('una portada gris no tiene paleta', () {
      expect(paletteOf(pixels([(const Color(0xFF808080), 100), (const Color(0xFF202020), 50)])), isNull);
    });

    test('desde un solo color (sin portada) también sale una paleta', () {
      final p = CoverPalette.fromColor(const Color(0xFF22DD66));
      expect(p.main, const Color(0xFF22DD66));
      expect(p.second, isNot(p.main));
    });

    test('las portadas guardan su paleta y avisan al saberla', () {
      addTearDown(CoverTints.clear);
      CoverTints.clear();
      expect(CoverTints.watchPalette('x').value, isNull);
      final art = PixelArt(10, 10, pixels([(const Color(0xFFE02020), 100)]));
      CoverTints.learn('x', art);
      expect(CoverTints.watchPalette('x').value?.main, isNotNull);
      expect(CoverTints.watchPalette(null).value, isNull);
    });
  });

  group('el vinilo jaspeado', () {
    const palette = CoverPalette(main: Color(0xFFE02020), second: Color(0xFFFF7A30), deep: Color(0xFF140404));

    test('se pinta una textura por portada, siempre igual para la misma y distinta entre portadas', () {
      final a = MarbleTexture.of(palette, MarbleTexture.seedOf('portada-a'));
      final again = MarbleTexture.of(palette, MarbleTexture.seedOf('portada-a'));
      final b = MarbleTexture.of(palette, MarbleTexture.seedOf('portada-b'));
      expect(a, isNotNull);
      expect(identical(a, again), isTrue); // se guarda
      expect(identical(a, b), isFalse);
      expect(a!.width, MarbleTexture.side);
      expect(MarbleTexture.seedOf('portada-a'), MarbleTexture.seedOf('portada-a'));
      expect(MarbleTexture.seedOf('portada-a'), isNot(MarbleTexture.seedOf('portada-b')));
    });

    test('el disco se pinta con la textura sin fallar (y sin ella, con las vetas de siempre)', () {
      final texture = MarbleTexture.of(palette, 7)!;
      for (final marble in <ui.Image?>[texture, null]) {
        final recorder = ui.PictureRecorder();
        VinylPainter(angle: ValueNotifier(0.5), label: null, ink: palette.main, marble: marble).paint(Canvas(recorder), const Size(300, 300));
        expect(recorder.endRecording(), isNotNull);
      }
      expect(VinylPainter(angle: null, label: null, ink: palette.main, marble: texture).shouldRepaint(VinylPainter(angle: null, label: null, ink: palette.main)), isTrue);
    });

    testWidgets('el disco usa los colores de la portada (su paleta) y, sin ella, los del acento', (tester) async {
      addTearDown(CoverTints.clear);
      CoverTints.setPalette('https://img.test/a.jpg', palette);
      CoverTints.set('https://img.test/a.jpg', palette.main);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: const Scaffold(body: Center(child: VinylDisc(id: 'a', file: null, url: 'https://img.test/a.jpg', icon: Icons.album, size: 200)))));
      final painter = tester.widget<CustomPaint>(find.byKey(const Key('vinyl-surface'))).painter! as VinylPainter;
      expect(painter.marble, isNotNull);
      expect(painter.ink, palette.main);
    });
  });
}
