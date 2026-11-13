
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/audio_engine.dart';
import 'package:kyora_chat/data/background_playback.dart';
import 'package:kyora_chat/data/just_audio_engine.dart';
import 'package:kyora_chat/models/profile.dart';
import 'package:kyora_chat/state/music_controller.dart';
import 'package:kyora_chat/state/player_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/auth_gate.dart';
import 'package:kyora_chat/ui/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kyora_chat/ui/widgets/sound_circle.dart';

import 'auth_gate_test.dart' show FakeAccount, MemoryRoleCache;
import 'fake_backend.dart';
import 'fake_engine.dart';
import 'music_test.dart' show FakeMusicBackend, FakeSaver, MemoryMusicStore;
import 'sections.dart';

/// Lo que el teléfono mantiene para la música en segundo plano, de mentira: apunta qué se le pidió.
class FakeBackground implements BackgroundPlayback {
  int starts = 0;
  int stops = 0;
  bool unrestricted = false;
  int exemptionAsks = 0;
  bool failStart = false;

  @override
  Future<void> started() async {
    starts++;
    if (failStart) throw StateError('sin permiso');
  }

  @override
  Future<void> stopped() async => stops++;

  @override
  Future<bool> batteryUnrestricted() async => unrestricted;

  @override
  Future<void> requestBatteryExemption() async => exemptionAsks++;
}

/// Unos hooks que tardan en contestar, como un aviso de permisos.
class _SlowHooks implements PlaybackHooks {
  _SlowHooks(this.answer);

  final Future<void> Function() answer;
  int starts = 0;

  @override
  Future<void> started() {
    starts++;
    return answer();
  }

  @override
  Future<void> stopped() async {}
}

void main() {
  notificationTests();

  test('los permisos no chocan: la lectura del sonido espera a que terminen los de la notificación', () async {
    final answer = Completer<void>();
    final levels = FakeLevels();
    final engine = FakeEngine();
    final hooks = _SlowHooks(() => answer.future);
    final backend = FakeMusicBackend()..add('a');
    final player = PlayerController(backend, engine, noteAfter: Duration.zero, levels: levels, hooks: hooks);
    var startedWhenTold = -1;
    // la pantalla reacciona a que suene: como el círculo del disco
    player.addListener(() {
      if (player.playing && startedWhenTold < 0) {
        startedWhenTold = hooks.starts;
        player.listenToSound();
      }
    });
    await player.play(backend.tracks.single, backend.tracks);
    await pumpEventQueue();
    expect(startedWhenTold, 1); // los hooks ya se avisaron cuando la pantalla se enteró
    expect(levels.started, 0); // y el permiso del sonido espera
    answer.complete();
    await pumpEventQueue();
    expect(levels.started, 1);
    player.dispose();
  });

  test('si los permisos fallan, la lectura del sonido sigue', () async {
    final levels = FakeLevels();
    final hooks = _SlowHooks(() => Future<void>.error(StateError('sin permiso')));
    final backend = FakeMusicBackend()..add('a');
    final player = PlayerController(backend, FakeEngine(), noteAfter: Duration.zero, levels: levels, hooks: hooks);
    await player.play(backend.tracks.single, backend.tracks);
    player.listenToSound();
    await pumpEventQueue();
    expect(levels.started, 1);
    player.dispose();
  });

  test('si se deja de escuchar antes de que terminen los permisos, no se enciende', () async {
    final answer = Completer<void>();
    final levels = FakeLevels();
    final backend = FakeMusicBackend()..add('a');
    final player = PlayerController(backend, FakeEngine(), noteAfter: Duration.zero, levels: levels, hooks: _SlowHooks(() => answer.future));
    await player.play(backend.tracks.single, backend.tracks);
    await pumpEventQueue();
    player.listenToSound();
    player.stopListeningToSound();
    answer.complete();
    await pumpEventQueue();
    expect(levels.started, 0);
    player.dispose();
  });

  group('lo que se mantiene despierto mientras suena', () {
    late FakeMusicBackend backend;
    late FakeEngine engine;
    late FakeBackground hooks;
    late PlayerController player;

    setUp(() {
      backend = FakeMusicBackend();
      engine = FakeEngine();
      hooks = FakeBackground();
      player = PlayerController(backend, engine, noteAfter: Duration.zero, hooks: hooks);
    });

    test('al empezar a sonar avisa, y al pausar suelta', () async {
      final a = backend.add('a');
      await player.play(a, [a]);
      await pumpEventQueue();
      expect(hooks.starts, 1);
      expect(hooks.stops, 0);
      await player.toggle(); // pausa
      await pumpEventQueue();
      expect(hooks.stops, 1);
      await player.toggle(); // sigue
      await pumpEventQueue();
      expect(hooks.starts, 2);
      player.dispose();
    });

    test('al soltar el reproductor mientras suena, suelta también lo que mantenía despierto', () async {
      final a = backend.add('a');
      await player.play(a, [a]);
      await pumpEventQueue();
      expect(hooks.stops, 0);
      player.dispose();
      await pumpEventQueue();
      expect(hooks.stops, 1);
    });

    test('si pedir los permisos falla, la música suena igual', () async {
      hooks.failStart = true;
      final a = backend.add('a');
      await player.play(a, [a]);
      await pumpEventQueue();
      expect(hooks.starts, 1);
      expect(player.playing, isTrue);
      expect(player.error, isNull);
      player.dispose();
    });

    test('sin ganchos (las pruebas, otros teléfonos) no pasa nada', () async {
      final plain = PlayerController(backend, FakeEngine(), noteAfter: Duration.zero);
      final a = backend.add('a');
      await plain.play(a, [a]);
      await pumpEventQueue();
      expect(plain.playing, isTrue);
      plain.dispose();
      player.dispose();
    });
  });

  group('Ajustes: música en segundo plano', () {
    late FakeBackground background;
    late MusicController music;

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      background = FakeBackground();
      music = MusicController(FakeMusicBackend(), MemoryMusicStore(since: DateTime.utc(2026, 10, 1)), FakeSaver());
      addTearDown(music.dispose);
      await tester.runAsync(music.start);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: SettingsPage(music: music, role: Role.admin, onSignOut: () async {}, background: background),
      ));
      await tester.pumpAndSettle();
      await openSettingsTile(tester, 'music');
    }

    testWidgets('con restricciones de batería lo dice y deja quitarlas', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('settings-background')), findsOneWidget);
      expect(find.textContaining('Android puede detener la música'), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings-background')));
      await tester.pump();
      expect(background.exemptionAsks, 1);
    });

    testWidgets('al volver del aviso del sistema se vuelve a mirar y, quitadas las restricciones, lo celebra y ya no pide nada', (tester) async {
      await open(tester);
      background.unrestricted = true; // la persona aceptó en el aviso del sistema
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.textContaining('Sin restricciones de batería'), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings-background')));
      await tester.pump();
      expect(background.exemptionAsks, 0);
    });

    testWidgets('sin el servicio no sale la fila', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: SettingsPage(
          music: MusicController(FakeMusicBackend(), MemoryMusicStore(since: DateTime.utc(2026, 10, 1)), FakeSaver()),
          role: Role.admin,
          onSignOut: () async {},
        ),
      ));
      await tester.pumpAndSettle();
      await openSettingsTile(tester, 'music');
      expect(find.byKey(const Key('settings-folder')), findsOneWidget); // la ficha de música sí
      expect(find.byKey(const Key('settings-background')), findsNothing);
    });
  });

  group('una sesión que caduca no corta la música', () {
    late List<FakeEngine> engines;
    late FakeBackground background;
    late FakeAccount account;

    Future<void> gate(WidgetTester tester, {String uid = 'u2'}) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      engines = [];
      background = FakeBackground();
      account = FakeAccount(uid: uid, profile: Profile(id: uid, username: 'ana', role: Role.intern));
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: AuthGate(
          account: account,
          chat: FakeBackend(),
          music: FakeMusicBackend(),
          musicStore: MemoryMusicStore(since: DateTime.utc(2026, 10, 1)),
          saver: FakeSaver(),
          roleCache: MemoryRoleCache(),
          engine: () => FakeEngine().also(engines.add),
          background: background,
        ),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    }

    testWidgets('al caducar la sesión la app sigue abierta (sin pedir el acceso) y el reproductor sigue vivo', (tester) async {
      await gate(tester);
      expect(engines.length, 1);
      account.expire();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('login-button')), findsNothing);
      expect(find.byKey(const Key('home-time')), findsOneWidget);
      expect(engines.single.disposed, isFalse);
    });

    testWidgets('al volver a entrar la misma persona sigue el mismo reproductor (no se crea otro)', (tester) async {
      await gate(tester);
      account.expire();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pumpAndSettle();
      account.restore('u2');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-time')), findsOneWidget); // otra vez Inicio
      expect(engines.length, 1);
      expect(engines.single.disposed, isFalse);
    });

    testWidgets('si entra otra persona no hereda lo de la anterior: el reproductor viejo se suelta y se crea uno nuevo', (tester) async {
      await gate(tester);
      account.expire();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pumpAndSettle();
      account.profile = const Profile(id: 'otro', username: 'luis', role: Role.intern);
      account.restore('otro');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pumpAndSettle();
      expect(engines.length, 2);
      expect(engines.first.disposed, isTrue);
      expect(engines.last.disposed, isFalse);
    });

    testWidgets('«Cerrar sesión» sí para la música', (tester) async {
      await gate(tester);
      await goToSection(tester, 'settings');
      await tester.pumpAndSettle();
      await revealSignOut(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-sign-out')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pumpAndSettle();
      expect(account.signedIn, isFalse);
      expect(find.byKey(const Key('login-button')), findsNothing); // la app sigue abierta, ya sin sesión
      expect(find.byKey(const Key('home-time')), findsOneWidget);
      expect(engines.first.disposed, isTrue); // lo que sonaba se paró (Inicio abre un reproductor nuevo, vacío)
    });

    testWidgets('tras cerrar sesión y entrar de nuevo la música empieza de cero', (tester) async {
      await gate(tester);
      await goToSection(tester, 'settings');
      await tester.pumpAndSettle();
      await revealSignOut(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-sign-out')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pumpAndSettle();
      account.restore('u2');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pumpAndSettle();
      expect(engines.length, 2); // el de antes de cerrar sesión y el de después (la misma persona no estrena otro al volver a entrar)
      expect(engines.first.disposed, isTrue);
      expect(engines.last.disposed, isFalse);
    });
  });

  group('el visualizador del sonido', () {
    testWidgets('se apaga al pasar la app a segundo plano y se enciende al volver', (tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final backend = FakeMusicBackend();
      final levels = FakeLevels();
      final player = PlayerController(backend, FakeEngine(), noteAfter: Duration.zero, levels: levels);
      addTearDown(player.dispose);
      await tester.runAsync(() async {
        backend.add('a');
        await player.play(backend.tracks.single, backend.tracks);
        await pumpEventQueue();
      });
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: SoundCircle(player: player, active: true, size: 100)),
      ));
      await tester.pump();
      expect(levels.started, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(levels.stopped, greaterThanOrEqualTo(1));
      final stops = levels.stopped;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(levels.started, 2);
      expect(levels.stopped, stops);
    });
  });
}

/// Que la app se quede en primer plano con su notificación depende de cosas que no se ven hasta tener el APK: que no se pierdan.
void notificationTests() {
  group('la notificación de lo que suena', () {
    test('el compilador no puede borrar los iconos del reproductor: sin ellos, en Android 13 no sale la notificación y la música se corta', () {
      final keep = File('android/app/src/main/res/raw/keep.xml').readAsStringSync();
      expect(keep, contains('@drawable/audio_service_*'));
      expect(keep, contains('@drawable/ic_kyra_notification'));
      expect(File('android/app/src/main/res/drawable/ic_kyra_notification.xml').existsSync(), isTrue);
    });

    test('main usa ese icono, y el servicio sigue en primer plano también en pausa', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains("androidNotificationIcon: 'drawable/ic_kyra_notification'"));
      expect(main, contains('androidStopForegroundOnPause: false'));
    });

    test('enseña el nombre y el artista por separado, con el mismo reparto que la app', () {
      final item = mediaItemOf(const QueueItem(id: '1', title: 'Flume - Sleepless', url: 'x', subtitle: 'Rock'));
      expect((item.title, item.artist, item.album), ('Sleepless', 'Flume', 'Rock'));
    });

    test('sin artista, la lista de la que viene; y si tampoco, Kyra', () {
      expect(mediaItemOf(const QueueItem(id: '1', title: 'Stay', url: 'x', subtitle: 'Rock')).artist, 'Rock');
      expect(mediaItemOf(const QueueItem(id: '1', title: 'Stay', url: 'x')).artist, 'Kyra');
    });

    test('la portada puede ser de internet o un archivo del teléfono', () {
      expect(mediaItemOf(const QueueItem(id: '1', title: 'a', url: 'x', artUrl: 'https://img.test/a.jpg')).artUri.toString(), 'https://img.test/a.jpg');
      expect(mediaItemOf(const QueueItem(id: '1', title: 'a', url: 'x', artUrl: 'file:///cache/a.jpg')).artUri!.scheme, 'file');
      expect(mediaItemOf(const QueueItem(id: '1', title: 'a', url: 'x')).artUri, isNull);
    });
  });

  group('la restricción de batería', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('kyora/background');
    late List<String> calls;
    late bool free;

    setUp(() {
      calls = [];
      free = false;
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return call.method == 'batteryUnrestricted' ? free : null;
      });
    });

    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    test('la primera vez que suena algo se pide quitarla, y solo esa vez', () async {
      await AndroidBackgroundPlayback().started();
      expect(calls.where((c) => c == 'requestBatteryExemption').length, 1);
      await AndroidBackgroundPlayback().started(); // otra sesión de la app
      expect(calls.where((c) => c == 'requestBatteryExemption').length, 1);
    });

    test('si la app ya no tiene restricción, no se molesta', () async {
      free = true;
      await AndroidBackgroundPlayback().started();
      expect(calls, isNot(contains('requestBatteryExemption')));
    });

    test('el bloqueo de red va primero: no espera a que se contesten los permisos', () async {
      await AndroidBackgroundPlayback().started();
      expect(calls.first, 'wifiLock');
    });
  });
}

extension<T> on T {
  T also(void Function(T) block) {
    block(this);
    return this;
  }
}
