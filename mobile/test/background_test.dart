
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/background_playback.dart';
import 'package:kyora_chat/models/profile.dart';
import 'package:kyora_chat/state/music_controller.dart';
import 'package:kyora_chat/state/player_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/auth_gate.dart';
import 'package:kyora_chat/ui/settings_sheet.dart';
import 'package:kyora_chat/ui/widgets/sound_rings.dart';

import 'auth_gate_test.dart' show FakeAccount, MemoryRoleCache;
import 'fake_backend.dart';
import 'fake_engine.dart';
import 'music_test.dart' show FakeMusicBackend, FakeSaver, MemoryMusicStore;

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

void main() {
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
        home: SettingsSheet(music: music, role: Role.admin, onSignOut: () async {}, background: background),
      ));
      await tester.pumpAndSettle();
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
        home: SettingsSheet(
          music: MusicController(FakeMusicBackend(), MemoryMusicStore(since: DateTime.utc(2026, 10, 1)), FakeSaver()),
          role: Role.admin,
          onSignOut: () async {},
        ),
      ));
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

    testWidgets('al caducar la sesión se pide entrar otra vez, pero el reproductor sigue vivo', (tester) async {
      await gate(tester);
      expect(engines.length, 1);
      account.expire();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('login-button')), findsOneWidget);
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
      expect(find.byKey(const Key('home-greeting')), findsOneWidget); // otra vez Inicio
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
      await tester.tap(find.byKey(const Key('home-settings'))); // el botón de Inicio abre la configuración
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('settings-sign-out')));
      await tester.tap(find.byKey(const Key('settings-sign-out')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pumpAndSettle();
      expect(account.signedIn, isFalse);
      expect(find.byKey(const Key('login-button')), findsOneWidget);
      expect(engines.single.disposed, isTrue);
    });

    testWidgets('tras cerrar sesión y entrar de nuevo la música empieza de cero', (tester) async {
      await gate(tester);
      await tester.tap(find.byKey(const Key('home-settings'))); // el botón de Inicio abre la configuración
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('settings-sign-out')));
      await tester.tap(find.byKey(const Key('settings-sign-out')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pumpAndSettle();
      account.restore('u2');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pumpAndSettle();
      expect(engines.length, 2);
      expect(engines.first.disposed, isTrue);
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
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: SoundRings(player: player, color: Colors.amber)),
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

extension<T> on T {
  T also(void Function(T) block) {
    block(this);
    return this;
  }
}
