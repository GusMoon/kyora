import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/voice_reader.dart';
import 'package:kyora_chat/models/profile.dart';
import 'package:kyora_chat/state/direct_chat_controller.dart';
import 'package:kyora_chat/state/music_controller.dart';
import 'package:kyora_chat/state/voice_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/direct_chats_page.dart';
import 'package:kyora_chat/ui/settings_page.dart';

import 'auth_gate_test.dart' show FakeAccount;
import 'fake_direct.dart';
import 'music_test.dart' show FakeMusicBackend, FakeSaver, MemoryMusicStore;

void main() {
  group('la voz de KyraAdmin', () {
    test('lee la configuración y el permiso; encender y elegir apps se guarda', () async {
      final reader = FakeVoiceReader(granted: true, config: const VoiceConfig(enabled: false, packages: {'com.whatsapp'}));
      final voice = VoiceController(reader);
      addTearDown(voice.dispose);
      await voice.refresh();
      expect(voice.granted, isTrue);
      expect(voice.reads('com.whatsapp'), isTrue);
      await voice.setEnabled(true);
      await voice.toggle(kyraChatPackage);
      await voice.toggle('com.whatsapp');
      expect(reader.config.enabled, isTrue);
      expect(reader.config.packages, {kyraChatPackage});
      await voice.test();
      expect(reader.spoken, hasLength(1));
      await voice.openAccessSettings();
      expect(reader.openedSettings, 1);
    });

    Future<void> openSettings(WidgetTester tester, {VoiceController? voice}) async {
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final music = MusicController(FakeMusicBackend(), MemoryMusicStore(since: DateTime.utc(2026, 10, 1)), FakeSaver());
      addTearDown(music.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: SettingsPage(music: music, role: Role.admin, onSignOut: () async {}, account: FakeAccount(uid: 'u1'), voice: voice),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('la ficha «Voz» sale solo si hay voz (KyraAdmin)', (tester) async {
      await openSettings(tester);
      expect(find.byKey(const Key('mosaic-tile-voice')), findsNothing);
    });

    testWidgets('en la ficha se enciende, se ve si falta el permiso y se elige el chat de Kyra', (tester) async {
      final reader = FakeVoiceReader();
      final voice = VoiceController(reader);
      addTearDown(voice.dispose);
      await openSettings(tester, voice: voice);
      expect(find.byKey(const Key('mosaic-tile-voice')), findsOneWidget);
      await tester.tap(find.byKey(const Key('mosaic-tile-voice')));
      await tester.pumpAndSettle();
      expect(find.text('Dar acceso a notificaciones'), findsOneWidget);
      await tester.tap(find.byKey(const Key('voice-access')));
      await tester.pumpAndSettle();
      expect(reader.openedSettings, 1);
      await tester.tap(find.byKey(const Key('voice-enabled')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('voice-app-kyra')));
      await tester.tap(find.byKey(const Key('voice-app-kyra')));
      await tester.pumpAndSettle();
      expect(reader.config.enabled, isTrue);
      expect(reader.config.packages, {kyraChatPackage});
    });
  });

  group('la sección «Chats» de KyraAdmin', () {
    late FakeDirectBackend backend;
    late DirectChatsController chats;

    setUp(() {
      backend = FakeDirectBackend(uid: 'admin-1');
      chats = DirectChatsController(backend, appInForeground: () => true);
    });
    tearDown(() => chats.dispose());

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(chats.start);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: DirectChatsPage(chats: chats, backend: backend)));
      await tester.pumpAndSettle();
    }

    testWidgets('«Mis chats» enseña las conversaciones del administrador', (tester) async {
      backend.receive('m1', body: 'hola jefe', from: 'user-1');
      await open(tester);
      expect(find.byKey(const Key('dm-thread-ana')), findsOneWidget);
      expect(find.text('hola jefe'), findsOneWidget);
    });

    testWidgets('«Supervisión» enseña todas las conversaciones y borra una de verdad (con confirmación)', (tester) async {
      backend.uid = 'user-1';
      backend.receive('m1', body: 'entre ellos', from: 'user-2'); // una conversación entre ana y luis
      backend.uid = 'admin-1';
      await open(tester);
      await tester.tap(find.byKey(const Key('dm-tab-admin')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      final tile = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('dm-admin-'));
      expect(tile, findsOneWidget);
      await tester.tap(tile);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      expect(find.text('entre ellos'), findsOneWidget); // el administrador lo lee
      await tester.tap(find.byKey(const Key('dm-admin-delete-thread')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dm-confirm-ok')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      expect(backend.server, isEmpty);
      expect(backend.threads, isEmpty);
    });
  });
}
