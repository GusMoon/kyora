import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/wallpaper_store.dart';
import 'package:kyora_chat/models/track.dart';
import 'package:kyora_chat/state/now_playing_backdrop.dart';
import 'package:kyora_chat/state/player_controller.dart';
import 'package:kyora_chat/state/wallpaper_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/util/cover_tint.dart';
import 'package:kyora_chat/ui/section_host.dart';
import 'package:kyora_chat/ui/widgets/app_backdrop.dart';
import 'package:kyora_chat/ui/widgets/app_section.dart';
import 'package:kyora_chat/ui/widgets/cover_backdrop.dart';

import 'fake_engine.dart';
import 'music_test.dart' show FakeMusicBackend;

/// El fondo y los colores de toda la app mientras suena algo: su portada (nítida, con líneas y oscurecida) y su color; al pausar o parar, lo de siempre.
void main() {
  late FakeMusicBackend backend;
  late FakeEngine engine;
  late PlayerController player;
  late NowPlayingBackdrop nowPlaying;
  late List<Track> tracks;

  setUp(() {
    backend = FakeMusicBackend();
    engine = FakeEngine();
    player = PlayerController(backend, engine, noteAfter: Duration.zero);
    nowPlaying = NowPlayingBackdrop();
    // «a» trae portada de internet; «b» no
    backend
      ..add('a', cover: 'https://img.test/a.jpg')
      ..add('b');
    tracks = List.of(backend.tracks); // b, a
  });

  tearDown(() {
    nowPlaying.dispose();
    player.dispose();
  });

  group('lo que se sabe de lo que suena', () {
    test('sin reproductor o sin nada sonando no hay portada', () async {
      expect(nowPlaying.source, isNull);
      nowPlaying.attach(player);
      await pumpEventQueue();
      expect(nowPlaying.source, isNull);
    });

    test('al sonar una canción con portada, la tiene; al pausar, la suelta; al reanudar, vuelve', () async {
      nowPlaying.attach(player);
      var notified = 0;
      nowPlaying.addListener(() => notified++);
      await player.play(tracks[1], tracks); // «a»
      await pumpEventQueue();
      expect(nowPlaying.source, (file: null, url: 'https://img.test/a.jpg'));
      expect(notified, 1);
      await player.toggle(); // pausa
      await pumpEventQueue();
      expect(nowPlaying.source, isNull);
      await player.toggle(); // sigue
      await pumpEventQueue();
      expect(nowPlaying.source?.url, 'https://img.test/a.jpg');
    });

    test('el color de la app mientras suena es el de la portada, y al pausar se suelta', () async {
      CoverTints.set('https://img.test/a.jpg', const Color(0xFF22DD66));
      addTearDown(CoverTints.clear);
      nowPlaying.attach(player);
      expect(nowPlaying.accent, isNull);
      await player.play(tracks[1], tracks); // «a»
      await pumpEventQueue();
      expect(nowPlaying.accent, const Color(0xFF22DD66));
      await player.toggle();
      await pumpEventQueue();
      expect(nowPlaying.accent, isNull);
    });

    test('si el color de la portada se conoce después (al terminar de leerla), avisa', () async {
      addTearDown(CoverTints.clear);
      nowPlaying.attach(player);
      await player.play(tracks[1], tracks);
      await pumpEventQueue();
      expect(nowPlaying.accent, isNull); // aún no se sabe
      var notified = 0;
      nowPlaying.addListener(() => notified++);
      CoverTints.set('https://img.test/a.jpg', const Color(0xFFFF8A3D));
      expect(nowPlaying.accent, const Color(0xFFFF8A3D));
      expect(notified, 1);
    });

    test('una canción sin portada no cambia el fondo', () async {
      nowPlaying.attach(player);
      await player.play(tracks[0], tracks); // «b», sin portada
      await pumpEventQueue();
      expect(player.playing, isTrue);
      expect(nowPlaying.source, isNull);
    });

    test('si se suelta el reproductor (cerrar sesión), el fondo vuelve a lo normal', () async {
      nowPlaying.attach(player);
      await player.play(tracks[1], tracks);
      await pumpEventQueue();
      expect(nowPlaying.source, isNotNull);
      nowPlaying.attach(null);
      await pumpEventQueue();
      expect(nowPlaying.source, isNull);
    });

    test('al pasar a otra canción con otra portada, cambia', () async {
      backend.add('c', cover: 'https://img.test/c.jpg');
      final all = List.of(backend.tracks); // c, b, a
      nowPlaying.attach(player);
      await player.play(all[2], all); // «a»
      await pumpEventQueue();
      expect(nowPlaying.source?.url, 'https://img.test/a.jpg');
      engine.emitIndex(0); // «c»
      await pumpEventQueue();
      expect(nowPlaying.source?.url, 'https://img.test/c.jpg');
    });
  });

  group('el fondo de toda la app', () {
    late WallpaperController wallpaper;

    setUp(() => wallpaper = WallpaperController(MemoryWallpaperStore(), lookup: (_) async => null));
    tearDown(() => wallpaper.dispose());

    Widget page(String id, String next) => Builder(
          builder: (context) => Center(child: TextButton(key: Key('go-$id'), onPressed: () => SectionHost.goTo(context, next), child: Text('Pantalla $id'))),
        );

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        builder: (context, child) => AppBackdrop(wallpaper: wallpaper, nowPlaying: nowPlaying, child: child!),
        home: SectionHost(sections: [
          AppSection(id: 'home', icon: Icons.circle_outlined, label: 'home', builder: (_) => page('home', 'chat')),
          AppSection(id: 'chat', icon: Icons.circle_outlined, label: 'chat', builder: (_) => page('chat', 'home')),
        ]),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> playSong(WidgetTester tester) async {
      nowPlaying.attach(player);
      await tester.runAsync(() => player.play(tracks[1], tracks));
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
    }

    testWidgets('sin nada sonando es el de siempre: sin portada', (tester) async {
      await open(tester);
      expect(find.byType(CoverBackdrop), findsNothing);
    });

    testWidgets('al sonar una canción con portada el fondo pasa a ser la portada, nítida, con líneas de barrido y oscurecida, y no es cristal', (tester) async {
      await open(tester);
      await playSong(tester);
      await tester.pumpAndSettle();
      expect(find.byType(CoverBackdrop), findsOneWidget);
      expect(find.byType(ImageFiltered), findsNothing); // sin desenfoque
      expect(find.byKey(const Key('backdrop-lines')), findsOneWidget); // las líneas, como en los componentes de Configuración
      expect(find.byKey(const Key('backdrop-dim')), findsOneWidget); // el oscurecimiento que da profundidad
      expect(find.byKey(const Key('backdrop-tint')), findsOneWidget); // teñida con el color de la portada
      expect(find.byType(BackdropFilter), findsNothing);
      expect(tester.getSize(find.byType(CoverBackdrop)), const Size(400, 800));
    });

    testWidgets('sigue ahí al cambiar de sección, sin importar dónde se navegue', (tester) async {
      await open(tester);
      await playSong(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('go-home')));
      await tester.pumpAndSettle();
      expect(find.text('Pantalla chat'), findsOneWidget);
      expect(find.byType(CoverBackdrop), findsOneWidget);
    });

    testWidgets('al pausar se funde y vuelve el fondo original; al reanudar vuelve la portada', (tester) async {
      await open(tester);
      await playSong(tester);
      await tester.pumpAndSettle();
      expect(find.byType(CoverBackdrop), findsOneWidget);
      await tester.runAsync(player.toggle);
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
      await tester.pump(BackdropLayers.coverFade ~/ 2);
      expect(find.byType(CoverBackdrop), findsOneWidget); // todavía se está yendo
      await tester.pumpAndSettle();
      expect(find.byType(CoverBackdrop), findsNothing);
      expect(tester.widget<ColoredBox>(find.byKey(const Key('screen-backdrop'))).color, KyoraColors.classic().background);
      await tester.runAsync(player.toggle);
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      expect(find.byType(CoverBackdrop), findsOneWidget);
    });

    testWidgets('con un fondo de pantalla puesto, la portada lo cubre mientras suena y al pausar vuelve el fondo de pantalla', (tester) async {
      await tester.runAsync(() => wallpaper.set('C:/fondo.jpg'));
      await open(tester);
      expect(find.byKey(const Key('backdrop-dim')), findsOneWidget);
      await playSong(tester);
      await tester.pumpAndSettle();
      expect(find.byType(CoverBackdrop), findsOneWidget);
      expect(find.byKey(const Key('backdrop-dim')), findsOneWidget); // el oscurecido de la app sigue encima
      await tester.runAsync(player.toggle);
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      expect(find.byType(CoverBackdrop), findsNothing);
      expect(find.byKey(const Key('backdrop-dim')), findsOneWidget);
    });
  });
}
