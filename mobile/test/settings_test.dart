import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/models/profile.dart';
import 'package:kyora_chat/state/music_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/widgets/cut_border.dart';
import 'package:kyora_chat/ui/auth_gate.dart';
import 'package:kyora_chat/ui/settings_page.dart';

import 'auth_gate_test.dart' show FakeAccount, MemoryRoleCache;
import 'fake_backend.dart';
import 'fake_engine.dart';
import 'music_test.dart' show FakeMusicBackend, FakeSaver, MemoryMusicStore;
import 'sections.dart';

void main() {
  group('colores', () {
    test('son un negro limpio, tarjetas gris oscuro, texto claro y un acento de neón', () {
      final c = KyoraColors.classic();
      expect(c.background, const Color(0xFF08090B));
      expect(c.surface, const Color(0xFF14161A));
      expect(c.ink, const Color(0xFFF3F4F6));
      expect(c.accent, const Color(0xFFFF5A1F)); // el naranja de siempre
      expect(c.mine, c.ink); // mis burbujas, claras
      expect(c.onMine, c.background);
      expect(HSLColor.fromColor(c.background).lightness, lessThan(0.05)); // oscuro
      expect(HSLColor.fromColor(c.ink).lightness, greaterThan(0.9)); // claro
    });

    test('el texto se lee de sobra sobre el fondo y sobre las tarjetas, y el de encima del acento sobre el acento', () {
      final c = KyoraColors.classic();
      expect(contrastRatio(c.ink, c.background), greaterThanOrEqualTo(7));
      expect(contrastRatio(c.ink, c.surface), greaterThanOrEqualTo(7));
      expect(contrastRatio(c.onAccent, c.accent), greaterThanOrEqualTo(4.5));
    });

    test('el tema es oscuro, de esquinas cortadas (nada redondo) y sin sombras, y lleva los colores', () {
      final colors = KyoraColors.classic();
      final theme = buildTheme(colors);
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, colors.accent);
      expect(theme.colorScheme.surface, colors.background);
      expect(theme.scaffoldBackgroundColor, Colors.transparent); // el fondo lo pinta la pantalla
      expect(theme.extension<KyoraColors>()!.ink, colors.ink);
      expect((theme.inputDecorationTheme.border! as OutlineInputBorder).borderRadius, BorderRadius.zero);
      expect(theme.dialogTheme.shape, isA<CutBorder>());
      expect(theme.bottomSheetTheme.shape, isA<CutBorder>());
      expect(theme.snackBarTheme.shape, isA<CutBorder>());
      expect(theme.dialogTheme.elevation, 0);
      expect(theme.snackBarTheme.elevation, 0);
    });

    test('al cambiar de paleta los colores se funden, y sin otro tema se queda igual', () {
      final a = KyoraColors.classic();
      final b = a.copyWith(ink: const Color(0xFF000000));
      expect(a.lerp(b, 0).ink, a.ink);
      expect(a.lerp(b, 1).ink, b.ink);
      expect(a.lerp(b, 0.5).ink, isNot(a.ink));
      expect(a.lerp(null, 0.5).ink, a.ink);
    });

    testWidgets('context.colors da los del tema', (tester) async {
      Color? seen;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Builder(builder: (context) {
          seen = context.colors.accent;
          return const SizedBox();
        }),
      ));
      expect(seen, KyoraColors.classic().accent);
    });
  });

  group('pantalla de configuración', () {
    late MusicController music;
    late FakeSaver saver;

    Future<void> open(WidgetTester tester, {Role role = Role.admin, String? username = 'gustavo', Future<void> Function()? signOut}) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      saver = FakeSaver();
      music = MusicController(FakeMusicBackend(), MemoryMusicStore(since: DateTime.utc(2026, 10, 1)), saver);
      addTearDown(music.dispose);
      await tester.runAsync(music.start);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('open'),
                onPressed: () => showSettings(context, SettingsPage(music: music, role: role, username: username, onSignOut: signOut ?? () async {})),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
    }

    testWidgets('el mosaico enseña la carpeta de la música y la cuenta, y ya no los colores', (tester) async {
      await open(tester);
      expect(find.text('CONFIGURACIÓN'), findsOneWidget);
      expect(find.text('Música/Kyora'), findsOneWidget);
      expect(find.text('gustavo'), findsOneWidget);
      expect(find.text('ADMIN'), findsOneWidget);
      expect(find.byKey(const Key('use-wallpaper')), findsNothing);
      expect(find.text('COLORES'), findsNothing);
    });

    testWidgets('«Carpeta de las canciones» abre la hoja de la carpeta', (tester) async {
      await open(tester);
      await openSettingsTile(tester, 'music');
      await tester.tap(find.byKey(const Key('settings-folder')));
      await tester.pumpAndSettle();
      expect(find.text('Carpeta de las canciones'), findsWidgets);
      expect(find.byKey(const Key('pick-folder')), findsOneWidget);
    });

    testWidgets('un pasante se ve como pasante y sin nombre dice «Tu cuenta»', (tester) async {
      await open(tester, role: Role.intern, username: null);
      expect(find.text('PASANTE'), findsOneWidget);
      expect(find.text('Tu cuenta'), findsOneWidget);
      await openSettingsTile(tester, 'account');
      expect(find.text('Pasante'), findsOneWidget);
    });

    testWidgets('cerrar sesión vuelve a la base y avisa', (tester) async {
      var out = 0;
      await open(tester, signOut: () async => out++);
      await revealSignOut(tester);
      await tester.tap(find.byKey(const Key('settings-sign-out')));
      await tester.pumpAndSettle();
      expect(out, 1);
      expect(find.byType(SettingsPage), findsNothing);
    });
  });

  group('la página de Configuración', () {
    late MusicController music;

    Future<void> openPage(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      music = MusicController(FakeMusicBackend(), MemoryMusicStore(since: DateTime.utc(2026, 10, 1)), FakeSaver());
      addTearDown(music.dispose);
      await tester.runAsync(music.start);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: TextButton(key: const Key('open'), onPressed: () => showSettings(context, SettingsPage(music: music, role: Role.admin, onSignOut: () async {})), child: const Text('abrir')),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
    }

    testWidgets('ocupa toda la pantalla: ya no es una hoja del 70 %', (tester) async {
      await openPage(tester);
      expect(tester.getRect(find.byKey(const Key('settings-page'))), const Rect.fromLTWH(0, 0, 400, 850));
      expect(find.byKey(const Key('settings-sheet')), findsNothing);
      expect(find.byKey(const Key('settings-handle')), findsNothing);
    });

    testWidgets('aparece con un fundido y un leve crecimiento, no de golpe', (tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      music = MusicController(FakeMusicBackend(), MemoryMusicStore(since: DateTime.utc(2026, 10, 1)), FakeSaver());
      addTearDown(music.dispose);
      await tester.runAsync(music.start);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (context) => TextButton(key: const Key('open'), onPressed: () => showSettings(context, SettingsPage(music: music, role: Role.admin, onSignOut: () async {})), child: const Text('abrir')),
        ),
      ));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final fade = tester.widgetList<FadeTransition>(find.byType(FadeTransition)).where((f) => f.opacity.value > 0 && f.opacity.value < 1);
      expect(fade, isNotEmpty);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-page')), findsOneWidget);
    });

    testWidgets('lleva un velo oscuro y ningún desenfoque', (tester) async {
      await openPage(tester);
      expect(find.descendant(of: find.byKey(const Key('settings-page')), matching: find.byType(BackdropFilter)), findsNothing);
    });

    testWidgets('se cierra con la X', (tester) async {
      await openPage(tester);
      await tester.tap(find.byKey(const Key('settings-close')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsNothing);
    });

    testWidgets('«atrás» cierra primero la ficha expandida y después la página', (tester) async {
      await openPage(tester);
      await openSettingsTile(tester, 'music');
      expect(find.byKey(const Key('mosaic-detail-music')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget); // la página sigue
      expect(find.byKey(const Key('mosaic-detail-music')), findsNothing); // y volvió el mosaico
      expect(find.byKey(const Key('mosaic-summary-music')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsNothing);
    });

    testWidgets('la X de la ficha expandida vuelve al mosaico sin cerrar la página', (tester) async {
      await openPage(tester);
      await openSettingsTile(tester, 'account');
      await tester.tap(find.byKey(const Key('mosaic-close')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.byKey(const Key('mosaic-summary-account')), findsOneWidget);
    });
  });

  group('desde la app', () {
    late FakeBackend chat;
    late FakeMusicBackend musicBackend;

    Future<void> openGate(WidgetTester tester, FakeAccount account) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      chat = FakeBackend();
      musicBackend = FakeMusicBackend();
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: AuthGate(
          account: account,
          chat: chat,
          music: musicBackend,
          musicStore: MemoryMusicStore(since: DateTime.utc(2026, 10, 1)),
          saver: FakeSaver(),
          roleCache: MemoryRoleCache(),
          engine: FakeEngine.new,
        ),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    }

    testWidgets('el administrador llega a Configuración desde el menú y se abre a pantalla completa con el mosaico', (tester) async {
      await openGate(tester, FakeAccount(uid: 'u1', profile: const Profile(id: 'u1', username: 'gustavo', role: Role.admin)));
      expect(find.byType(SettingsPage), findsNothing);
      await goToSection(tester, 'settings');
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(tester.getRect(find.byKey(const Key('settings-page'))), const Rect.fromLTWH(0, 0, 400, 850));
      expect(find.text('gustavo'), findsOneWidget);
      expect(find.text('ADMIN'), findsOneWidget);
      await openSettingsTile(tester, 'account');
      expect(find.text('Cerrar sesión'), findsOneWidget);
      expect(find.text('Administrador'), findsOneWidget);
    });

    testWidgets('el pasante llega a Configuración desde el menú y cierra sesión desde allí', (tester) async {
      final account = FakeAccount(uid: 'u2', profile: const Profile(id: 'u2', username: 'ana', role: Role.intern));
      await openGate(tester, account);
      await goToSection(tester, 'settings');
      expect(find.text('PASANTE'), findsOneWidget);
      await revealSignOut(tester);
      await tester.tap(find.byKey(const Key('settings-sign-out')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pumpAndSettle();
      expect(account.signedIn, isFalse);
      expect(find.byType(SettingsPage), findsNothing);
      expect(find.byKey(const Key('login-button')), findsOneWidget); // volvió al acceso
    });
  });
}
