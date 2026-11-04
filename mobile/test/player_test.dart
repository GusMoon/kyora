import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/audio_engine.dart';
import 'package:kyora_chat/data/chat_backend.dart';
import 'package:kyora_chat/data/music_store.dart';
import 'package:kyora_chat/models/track.dart';
import 'package:kyora_chat/state/music_controller.dart';
import 'package:kyora_chat/state/player_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/music_page.dart';
import 'package:kyora_chat/ui/player_page.dart';
import 'package:kyora_chat/ui/widgets/sound_rings.dart';

import 'fake_engine.dart';
import 'music_test.dart' show FakeMusicBackend, FakeSaver, MemoryMusicStore;

void main() {
  late FakeMusicBackend backend;
  late FakeEngine engine;
  late DateTime now;
  late PlayerController player;
  late List<Track> tracks;

  setUp(() {
    backend = FakeMusicBackend();
    engine = FakeEngine();
    now = DateTime.utc(2026, 11, 1, 10);
    player = PlayerController(backend, engine, clock: () => now, noteAfter: Duration.zero);
    // la lista llega de la más nueva a la más antigua: c, b, a
    backend
      ..add('a', cover: 'https://img.test/a.jpg', playlist: 'Rock')
      ..add('b')
      ..add('c');
    tracks = List.of(backend.tracks);
  });

  tearDown(() => player.dispose());

  Future<void> settle() => pumpEventQueue();

  group('controlador', () {
    test('al tocar una canción carga toda la lista como cola, empieza por ella y suena', () async {
      await player.play(tracks[1], tracks);
      await settle();
      expect(backend.signed.single, tracks.map((t) => t.storagePath).toList());
      expect(engine.queue.map((q) => q.id), ['c', 'b', 'a']);
      expect(engine.startIndex, 1);
      expect(engine.queue.first.url, 'https://files.test/u/music/c/c.mp3?exp=86400'); // direcciones válidas 24 h
      expect(engine.queue.last.artUrl, 'https://img.test/a.jpg');
      expect(engine.queue.last.subtitle, 'Rock');
      expect(engine.calls, ['setQueue:1', 'play']);
      expect(player.current?.id, 'b');
      expect(player.playing, isTrue);
      expect(player.loading, isFalse);
      expect(player.error, isNull);
    });

    test('las direcciones firmadas se reutilizan y se piden de nuevo antes de caducar o si llega una canción nueva', () async {
      await player.play(tracks[0], tracks);
      await player.play(tracks[2], tracks);
      expect(backend.signed.length, 1);
      backend.add('d');
      final more = List.of(backend.tracks);
      await player.play(more[0], more);
      expect(backend.signed.length, 2); // hay una ruta que no estaba
      now = now.add(const Duration(hours: 23));
      await player.play(more[0], more);
      expect(backend.signed.length, 3); // a punto de caducar
    });

    test('lo que cuenta el motor se refleja: posición, duración y cambio de canción', () async {
      await player.play(tracks[0], tracks);
      await settle();
      expect(player.duration, const Duration(minutes: 3));
      engine.emitPosition(const Duration(seconds: 42));
      await settle();
      expect(player.position, const Duration(seconds: 42));
      engine.emitIndex(2); // pasó sola a la siguiente
      await settle();
      expect(player.current?.id, 'a');
      expect(player.position, Duration.zero);
    });

    test('el avance avisa por su propio canal: el reproductor no notifica a todos a cada tick (unas 5 veces por segundo)', () async {
      await player.play(tracks[0], tracks);
      await settle();
      var whole = 0, progress = 0;
      player.addListener(() => whole++);
      player.positionListenable.addListener(() => progress++);
      for (var i = 1; i <= 20; i++) {
        engine.emitPosition(Duration(milliseconds: 200 * i));
      }
      await settle();
      expect(progress, 20); // la barra de avance sí se entera de todos
      expect(whole, 0); // las listas, el anillo y el fondo no se reconstruyen por esto
      expect(player.position, const Duration(seconds: 4));
      // y lo demás sigue avisando a todos
      await player.toggle();
      await settle();
      expect(whole, greaterThan(0));
    });

    test('pausa y reanuda', () async {
      await player.play(tracks[0], tracks);
      await settle();
      await player.toggle();
      await settle();
      expect(player.playing, isFalse);
      await player.toggle();
      await settle();
      expect(player.playing, isTrue);
    });

    test('siguiente pasa a la siguiente de la cola', () async {
      await player.play(tracks[0], tracks);
      await settle();
      await player.next();
      await settle();
      expect(player.current?.id, 'b');
    });

    test('anterior: con la canción ya avanzada vuelve al principio; al principio va a la anterior; en la primera, reinicia', () async {
      await player.play(tracks[1], tracks);
      await settle();
      engine.emitPosition(const Duration(seconds: 20));
      await settle();
      await player.previous();
      expect(engine.seeks, [Duration.zero]);
      expect(player.current?.id, 'b');

      engine.emitPosition(const Duration(seconds: 1));
      await settle();
      await player.previous();
      await settle();
      expect(player.current?.id, 'c');

      engine.emitPosition(const Duration(seconds: 1));
      await settle();
      await player.previous(); // ya es la primera: no hay anterior
      expect(engine.seeks.last, Duration.zero);
      expect(player.current?.id, 'c');
    });

    test('adelantar y retroceder con la barra mueve el motor, sin pasarse de la duración', () async {
      await player.play(tracks[0], tracks);
      await settle();
      await player.seek(const Duration(seconds: 90));
      expect(engine.seeks.last, const Duration(seconds: 90));
      expect(player.position, const Duration(seconds: 90));
      await player.seek(const Duration(minutes: 10));
      expect(engine.seeks.last, const Duration(minutes: 3));
      await player.seek(const Duration(seconds: -5));
      expect(engine.seeks.last, Duration.zero);
    });

    test('el aleatorio se activa y desactiva, y se mantiene al tocar otra canción', () async {
      await player.play(tracks[0], tracks);
      await player.toggleShuffle();
      expect(player.shuffle, isTrue);
      expect(engine.shuffle, isTrue);
      await player.play(tracks[1], tracks);
      expect(engine.calls.last, 'play');
      expect(engine.calls, contains('shuffle:true'));
      expect(engine.calls.indexOf('shuffle:true'), lessThan(engine.calls.lastIndexOf('play')));
      await player.toggleShuffle();
      expect(player.shuffle, isFalse);
      expect(engine.shuffle, isFalse);
    });

    test('activar el aleatorio antes de tocar nada lo deja listo para cuando empiece', () async {
      await player.toggleShuffle();
      expect(engine.calls, isEmpty); // sin cola, no hay nada que mezclar todavía
      await player.play(tracks[0], tracks);
      expect(engine.shuffle, isTrue);
    });

    test('al terminar la cola se queda en pausa, lista para empezar otra vez', () async {
      await player.play(tracks[2], tracks);
      await settle();
      engine.emitStatus(EngineStatus.completed);
      await settle();
      expect(player.playing, isFalse);
      expect(engine.calls.last, 'pause');
    });

    test('un fallo del motor se enseña y deja de decir «cargando»', () async {
      await player.play(tracks[0], tracks);
      engine.emitError('No se pudo reproducir: revisa tu conexión.');
      await settle();
      expect(player.error, 'No se pudo reproducir: revisa tu conexión.');
      expect(player.loading, isFalse);
    });

    test('si Supabase no da las direcciones, lo dice y no toca el motor', () async {
      backend.signError = const ChatException('Sin conexión con Supabase', retryable: true, code: 'offline');
      await player.play(tracks[0], tracks);
      expect(player.error, 'Sin conexión con Supabase');
      expect(engine.calls, isEmpty);
      expect(player.loading, isFalse);
      backend.signError = null;
      await player.play(tracks[0], tracks);
      expect(player.error, isNull);
      expect(engine.calls, ['setQueue:0', 'play']);
    });

    test('una canción sin archivo en la nube se salta, y si es la tocada, da error', () async {
      final ghost = Track(id: 'x', title: 'X', fileName: 'x.mp3', storagePath: 'nada', sizeBytes: 1, createdAt: DateTime.utc(2026));
      final noFile = _MissingFiles(backend, {'nada'});
      final p = PlayerController(noFile, FakeEngine(), clock: () => now);
      addTearDown(p.dispose);
      await p.play(tracks[0], [ghost, ...tracks]);
      expect(p.queue.map((t) => t.id), ['c', 'b', 'a']);
      await p.play(ghost, [ghost, ...tracks]);
      expect(p.error, 'No se encontró el archivo de esa canción.');
    });

    test('al cerrarlo, el motor se libera', () async {
      final own = FakeEngine();
      PlayerController(backend, own).dispose();
      await settle();
      expect(own.disposed, isTrue);
    });
  });

  test('la hora se escribe como minutos:segundos', () {
    expect(clock(Duration.zero), '0:00');
    expect(clock(const Duration(seconds: 7)), '0:07');
    expect(clock(const Duration(minutes: 3, seconds: 42)), '3:42');
    expect(clock(const Duration(hours: 1, minutes: 2, seconds: 10)), '1:02:10');
    expect(clock(const Duration(seconds: -4)), '0:00');
  });

  group('controlador: repetir', () {
    test('cambia el motor en cada pulsación y se mantiene al cargar otra lista', () async {
      await player.play(tracks[0], tracks);
      expect(player.repeat, RepeatKind.off);
      await player.cycleRepeat();
      expect((player.repeat, engine.repeat), (RepeatKind.all, RepeatKind.all));
      await player.cycleRepeat();
      expect(engine.repeat, RepeatKind.one);
      await player.play(tracks[1], tracks);
      expect(engine.calls.last, 'play');
      expect(engine.calls.where((c) => c == 'repeat:one').length, 2); // al pulsar y al cargar la nueva lista
      await player.cycleRepeat();
      expect((player.repeat, engine.repeat), (RepeatKind.off, RepeatKind.off));
    });

    test('sin nada cargado solo se recuerda', () async {
      await player.cycleRepeat();
      expect(player.repeat, RepeatKind.all);
      expect(engine.calls, isEmpty);
    });
  });

  group('pantallas', () {
    late MusicController music;

    Future<void> open(WidgetTester tester) async {
      // como un teléfono (más alto que el de las pruebas por defecto) y sin guardado automático
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // el disco no gira con las animaciones desactivadas: así «pumpAndSettle» termina
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      music = MusicController(backend, MemoryMusicStore(since: DateTime.utc(2026, 10, 1))..settings = const MusicSettings(auto: false), FakeSaver());
      addTearDown(music.dispose);
      await tester.runAsync(music.start);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: MusicPage(controller: music, player: player)));
      await tester.pump();
    }

    testWidgets('sin nada sonando no hay barra de reproducción', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('mini-player')), findsNothing);
      expect(find.byKey(const Key('track-c')), findsOneWidget);
      expect(find.byKey(const Key('number-1')), findsNothing); // sin numeración
    });

    testWidgets('tocar una canción la reproduce, la marca y saca la barra de abajo', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('track-b')));
      await tester.runAsync(settle);
      await tester.pump();
      expect(engine.startIndex, 1);
      expect(find.byKey(const Key('mini-player')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('mini-player')), matching: find.text('Canción b')), findsOneWidget);
      expect(find.byKey(const Key('now-playing')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('mini-player')), matching: find.byIcon(Icons.pause_rounded)), findsOneWidget);
    });

    testWidgets('tocar una canción no la guarda: guardar está en su menú ⋯', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('track-b')));
      await tester.runAsync(settle);
      await tester.pump();
      expect(find.byKey(const Key('saved')), findsNothing);
      await tester.tap(find.byKey(const Key('more-b')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-b')));
      await tester.runAsync(settle);
      await tester.pump();
      expect(find.byKey(const Key('saved')), findsOneWidget);
      expect(backend.downloads, ['u/music/b/b.mp3']);
    });

    testWidgets('la barra de abajo pausa y pasa a la siguiente', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('track-c')));
      await tester.runAsync(settle);
      await tester.pump();
      await tester.tap(find.byKey(const Key('mini-toggle')));
      await tester.runAsync(settle);
      await tester.pump();
      expect(engine.isPlaying, isFalse);
      expect(find.descendant(of: find.byKey(const Key('mini-player')), matching: find.byIcon(Icons.play_arrow_rounded)), findsOneWidget);
      await tester.tap(find.byKey(const Key('mini-next')));
      await tester.runAsync(settle);
      await tester.pump();
      expect(find.byKey(const Key('mini-title')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('mini-title'))).data, 'Canción b');
    });

    testWidgets('el reproductor completo enseña título, tiempos, carátula y los controles', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('track-a')));
      await tester.runAsync(settle);
      await tester.pump();
      engine.emitPosition(const Duration(seconds: 65));
      await tester.runAsync(settle);
      await tester.pump();
      await tester.tap(find.byKey(const Key('mini-player')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('player-title')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('player-title'))).data, 'Canción a');
      expect(find.text('Rock'), findsWidgets);
      expect(tester.widget<Text>(find.byKey(const Key('player-position'))).data, '1:05');
      expect(tester.widget<Text>(find.byKey(const Key('player-duration'))).data, '3:00');
      expect(find.byKey(const Key('cover-image')), findsWidgets); // esta canción trae carátula (la etiqueta del vinilo)
      for (final key in ['player-shuffle', 'player-previous', 'player-toggle', 'player-next', 'player-repeat', 'player-seek', 'player-disc']) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
    });

    testWidgets('en el reproductor: anterior, pausa, siguiente, aleatorio y la barra funcionan', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('track-b')));
      await tester.runAsync(settle);
      await tester.pump();
      await tester.tap(find.byKey(const Key('mini-player')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('player-toggle')));
      await tester.runAsync(settle);
      await tester.pump();
      expect(engine.isPlaying, isFalse);

      await tester.tap(find.byKey(const Key('player-next')));
      await tester.runAsync(settle);
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('player-title'))).data, 'Canción a');

      await tester.tap(find.byKey(const Key('player-previous')));
      await tester.runAsync(settle);
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('player-title'))).data, 'Canción b');

      await tester.tap(find.byKey(const Key('player-shuffle')));
      await tester.runAsync(settle);
      await tester.pump();
      expect(engine.shuffle, isTrue);
      expect(tester.widget<IconButton>(find.byKey(const Key('player-shuffle'))).color, KyoraColors.classic().accent);

      // arrastrar la barra desde la mitad hacia la derecha adelanta la canción
      await tester.drag(find.byKey(const Key('player-seek')), const Offset(120, 0));
      await tester.runAsync(settle);
      await tester.pump();
      expect(engine.seeks, isNotEmpty);
      expect(engine.seeks.last, greaterThan(const Duration(seconds: 90))); // la mitad de 3:00 es 1:30; más arriba, más adelante
    });

    Future<void> openPlayer(WidgetTester tester, String id) async {
      await open(tester);
      await tester.tap(find.byKey(Key('track-$id')));
      await tester.runAsync(settle);
      await tester.pump();
      await tester.tap(find.byKey(const Key('mini-player')));
      await tester.pumpAndSettle();
    }

    testWidgets('solo se ve la canción actual: nada de la cola alrededor del disco', (tester) async {
      await openPlayer(tester, 'b'); // la cola es c, b, a
      expect(find.byKey(const Key('player-disc')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('player-title'))).data, 'Canción b');
      expect(find.byKey(const Key('queue-a')), findsNothing);
      expect(find.byKey(const Key('queue-c')), findsNothing);
      expect(find.text('Canción a'), findsNothing);
      expect(find.text('Canción c'), findsNothing);
    });

    testWidgets('deslizar la parte de arriba del disco pasa a la siguiente o a la anterior', (tester) async {
      await openPlayer(tester, 'b');
      await tester.fling(find.byKey(const Key('disc-swipe')), const Offset(-120, 0), 1000);
      await tester.runAsync(settle);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('player-title'))).data, 'Canción a');
      await tester.fling(find.byKey(const Key('disc-swipe')), const Offset(120, 0), 1000);
      await tester.runAsync(settle);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('player-title'))).data, 'Canción b');
    });

    testWidgets('el disco ya no gira', (tester) async {
      await openPlayer(tester, 'b');
      expect(find.byKey(const Key('disc-spin')), findsNothing);
      expect(find.descendant(of: find.byKey(const Key('player-seek')), matching: find.byType(RotationTransition)), findsNothing);
    });

    test('la lectura del sonido se comparte: solo se apaga cuando la suelta la última pantalla', () async {
      final levels = FakeLevels();
      final own = PlayerController(backend, engine, clock: () => now, noteAfter: Duration.zero, levels: levels);
      own.listenToSound(); // el disco
      own.listenToSound(); // y los aros del reproductor, encima
      expect(levels.started, 1);
      own.stopListeningToSound(); // se cierra el reproductor
      expect(levels.stopped, 0); // el disco sigue leyendo
      own.pauseSound(); // la app pasa a segundo plano
      expect(levels.stopped, 1);
      own.resumeSound(); // y vuelve
      expect(levels.started, 2);
      own.stopListeningToSound();
      expect(levels.stopped, 2);
      own.stopListeningToSound(); // de más: no hace nada
      own.resumeSound(); // sin nadie leyendo: tampoco
      expect(levels.stopped, 2);
      expect(levels.started, 2);
    });

    group('aros que siguen al sonido', () {
      late FakeLevels levels;
      late PlayerController own;

      Future<void> show(WidgetTester tester) async {
        tester.view.physicalSize = const Size(400, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        levels = FakeLevels();
        own = PlayerController(backend, engine, clock: () => now, noteAfter: Duration.zero, levels: levels);
        addTearDown(own.dispose);
        await tester.runAsync(() async {
          await own.play(tracks[1], tracks);
          await settle();
        });
        await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: PlayerPage(player: own)));
        await tester.pump();
      }

      double ring(WidgetTester tester) => (tester.widget<CustomPaint>(find.byKey(const Key('sound-rings'))).painter! as SoundRingsPainter).level.value;

      Future<void> run(WidgetTester tester, {int frames = 20}) async {
        for (var i = 0; i < frames; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      Future<void> pause(WidgetTester tester) async {
        await tester.tap(find.byKey(const Key('player-toggle')));
        await tester.runAsync(settle);
        await run(tester, frames: 120);
      }

      testWidgets('se abren con el sonido fuerte y se recogen con el silencio', (tester) async {
        await show(tester);
        expect(levels.started, 1);
        levels.emit(0.4);
        await run(tester);
        final loud = ring(tester);
        expect(loud, greaterThan(0.8));
        levels.emit(0.02);
        await run(tester, frames: 40);
        expect(ring(tester), lessThan(loud * 0.5));
        await pause(tester);
      });

      testWidgets('una canción suave también los mueve: se mide contra lo más fuerte reciente', (tester) async {
        await show(tester);
        levels.emit(0.08);
        await run(tester);
        expect(ring(tester), greaterThan(0.8));
        await pause(tester);
      });

      testWidgets('al pausar se apagan y se dejan de animar', (tester) async {
        await show(tester);
        levels.emit(0.4);
        await run(tester);
        await pause(tester);
        expect(ring(tester), 0);
        expect(tester.binding.hasScheduledFrame, isFalse);
      });

      testWidgets('si no llega sonido que leer, laten suavemente mientras suena', (tester) async {
        await show(tester);
        await run(tester, frames: 60);
        expect(ring(tester), inInclusiveRange(0.05, 0.5));
        levels.emit(0); // el teléfono da ceros: tampoco cuenta como sonido
        await run(tester, frames: 60);
        expect(ring(tester), inInclusiveRange(0.05, 0.5));
        await pause(tester);
      });

      testWidgets('al salir del reproductor se deja de escuchar', (tester) async {
        await show(tester);
        await pause(tester);
        await tester.pumpWidget(const SizedBox());
        expect(levels.stopped, 1);
      });

      testWidgets('con las animaciones del teléfono desactivadas se quedan quietos', (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
        await show(tester);
        levels.emit(0.4);
        await run(tester);
        expect(ring(tester), 0);
      });
    });

    testWidgets('cerrar, aleatorio y repetir van sobre círculos de vidrio; los del disco no', (tester) async {
      await openPlayer(tester, 'b');
      for (final key in ['player-close', 'player-shuffle', 'player-repeat']) {
        expect(find.ancestor(of: find.byKey(Key(key)), matching: find.byType(BackdropFilter)), findsOneWidget, reason: key);
      }
      for (final key in ['player-previous', 'player-next', 'player-toggle']) {
        expect(find.ancestor(of: find.byKey(Key(key)), matching: find.byType(BackdropFilter)), findsNothing, reason: key);
      }
      await tester.tap(find.byKey(const Key('player-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('player-disc')), findsNothing); // cerrar sigue funcionando
    });

    testWidgets('repetir pasa de apagado a toda la lista, a esta canción y otra vez a apagado', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('track-b')));
      await tester.runAsync(settle);
      await tester.pump();
      await tester.tap(find.byKey(const Key('mini-player')));
      await tester.pumpAndSettle();
      Future<void> press() async {
        await tester.tap(find.byKey(const Key('player-repeat')));
        await tester.runAsync(settle);
        await tester.pump();
      }

      expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
      await press();
      expect(engine.repeat, RepeatKind.all);
      expect(tester.widget<IconButton>(find.byKey(const Key('player-repeat'))).color, KyoraColors.classic().accent);
      await press();
      expect(engine.repeat, RepeatKind.one);
      expect(find.byIcon(Icons.repeat_one_rounded), findsOneWidget);
      await press();
      expect(engine.repeat, RepeatKind.off);
      expect(tester.widget<IconButton>(find.byKey(const Key('player-repeat'))).color, Colors.white);
    });

    testWidgets('«Artista - Título» sale con el título grande y el artista debajo', (tester) async {
      backend.add('z', title: 'Brambles - Solitude');
      tracks = List.of(backend.tracks);
      await open(tester);
      await tester.tap(find.byKey(const Key('track-z')));
      await tester.runAsync(settle);
      await tester.pump();
      await tester.tap(find.byKey(const Key('mini-player')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('player-title'))).data, 'Solitude z');
      expect(find.text('Brambles'), findsWidgets);
    });

    testWidgets('un error de reproducción sale en el reproductor', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('track-b')));
      await tester.runAsync(settle);
      await tester.pump();
      engine.emitError('El enlace de la canción caducó: vuelve a tocarla.');
      await tester.runAsync(settle);
      await tester.pump();
      await tester.tap(find.byKey(const Key('mini-player')));
      await tester.pumpAndSettle();
      expect(find.text('El enlace de la canción caducó: vuelve a tocarla.'), findsOneWidget);
    });
  });
}

/// Un backend al que le faltan ciertos archivos en la nube (no da dirección para esas rutas).
class _MissingFiles extends FakeMusicBackend {
  _MissingFiles(FakeMusicBackend base, this.missing) {
    tracks.addAll(base.tracks);
  }

  final Set<String> missing;

  @override
  Future<Map<String, String>> signedUrls(List<String> storagePaths, int expiresIn) =>
      super.signedUrls([for (final p in storagePaths) if (!missing.contains(p)) p], expiresIn);
}
