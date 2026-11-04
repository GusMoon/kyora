import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/models/profile.dart';
import 'package:kyora_chat/state/music_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/widgets/app_backdrop.dart';
import 'package:kyora_chat/ui/auth_gate.dart';
import 'package:kyora_chat/ui/settings_sheet.dart';

import 'auth_gate_test.dart' show FakeAccount, MemoryRoleCache;
import 'fake_backend.dart';
import 'fake_engine.dart';
import 'music_test.dart' show FakeMusicBackend, FakeSaver, MemoryMusicStore;

void main() {
  group('colores', () {
    test('son el dorado de Kyora sobre gris oscuro', () {
      final c = KyoraColors.classic();
      expect(c.accent, const Color(0xFFE3B25A));
      expect(c.background, const Color(0xFF1F2023));
      expect(c.mine, c.pick);
    });

    test('el fondo es un gris neutro', () {
      final grey = HSLColor.fromColor(KyoraColors.classic().background);
      expect(grey.saturation, lessThan(0.1)); // gris de verdad, sin tinte
      expect(grey.lightness, inInclusiveRange(0.1, 0.2)); // oscuro, pero sin llegar a negro
    });

    test('todos los textos se leen bien sobre el gris más claro del fondo', () {
      final (lightest, _) = backdropGreys(KyoraColors.classic().background);
      double contrast(Color a, Color b) {
        final (x, y) = (a.computeLuminance(), b.computeLuminance());
        return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
      }

      final c = KyoraColors.classic();
      expect(contrast(c.ink, lightest), greaterThanOrEqualTo(7));
      expect(contrast(c.dim, lightest), greaterThanOrEqualTo(4.5));
      expect(contrast(c.accent, lightest), greaterThanOrEqualTo(4.5));
    });

    test('el tema es siempre oscuro y lleva los colores', () {
      final colors = KyoraColors.classic();
      final theme = buildTheme(colors);
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, colors.accent);
      expect(theme.scaffoldBackgroundColor, Colors.transparent); // el fondo lo pinta `AppBackdrop`
      expect(theme.extension<KyoraColors>()!.accent, colors.accent);
    });

    test('mezclar dos juegos de colores da lo de en medio', () {
      final a = KyoraColors.classic();
      final b = a.copyWith(accent: const Color(0xFF1B998B));
      expect(a.lerp(b, 0).accent, a.accent);
      expect(a.lerp(b, 1).accent, b.accent);
      expect(a.lerp(null, 0.5).accent, a.accent);
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
                onPressed: () => showSettingsSheet(context, SettingsSheet(music: music, role: role, username: username, onSignOut: signOut ?? () async {})),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
    }

    testWidgets('enseña la carpeta y la cuenta, y ya no los colores del fondo de pantalla', (tester) async {
      await open(tester);
      expect(find.text('Configuración'), findsOneWidget);
      expect(find.text('Música/Kyora'), findsOneWidget);
      expect(find.text('gustavo'), findsOneWidget);
      expect(find.text('Administrador'), findsOneWidget);
      expect(find.byKey(const Key('use-wallpaper')), findsNothing);
      expect(find.text('Colores'), findsNothing);
    });

    testWidgets('«Carpeta de las canciones» abre la hoja de la carpeta', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('settings-folder')));
      await tester.pumpAndSettle();
      expect(find.text('Carpeta de las canciones'), findsWidgets);
      expect(find.byKey(const Key('pick-folder')), findsOneWidget);
    });

    testWidgets('un pasante se ve como pasante y sin nombre dice «Tu cuenta»', (tester) async {
      await open(tester, role: Role.intern, username: null);
      expect(find.text('Pasante'), findsOneWidget);
      expect(find.text('Tu cuenta'), findsOneWidget);
    });

    testWidgets('cerrar sesión vuelve a la base y avisa', (tester) async {
      var out = 0;
      await open(tester, signOut: () async => out++);
      await tester.ensureVisible(find.byKey(const Key('settings-sign-out')));
      await tester.tap(find.byKey(const Key('settings-sign-out')));
      await tester.pumpAndSettle();
      expect(out, 1);
      expect(find.byType(SettingsSheet), findsNothing);
    });
  });

  group('la hoja de Configuración', () {
    late MusicController music;

    Future<void> openSheet(WidgetTester tester) async {
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
            body: Stack(
              children: [
                const Align(alignment: Alignment.topCenter, child: Padding(padding: EdgeInsets.only(top: 80), child: Text('lo de arriba', key: Key('behind')))),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: TextButton(key: const Key('open'), onPressed: () => showSettingsSheet(context, SettingsSheet(music: music, role: Role.admin, onSignOut: () async {})), child: const Text('abrir')),
                ),
              ],
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
    }

    testWidgets('sube desde el borde de abajo y llega al 70 % de la pantalla, dejando ver lo de arriba', (tester) async {
      await openSheet(tester);
      final rect = tester.getRect(find.byKey(const Key('settings-sheet')));
      expect(rect.bottom, 850);
      expect(rect.height, closeTo(850 * 0.7, 1));
      expect(rect.top, closeTo(850 * 0.3, 1));
      expect(find.byKey(const Key('behind')), findsOneWidget); // la pantalla de abajo sigue ahí
      expect(tester.getTopLeft(find.byKey(const Key('behind'))).dy, lessThan(rect.top)); // y lo de arriba se ve
    });

    testWidgets('no oscurece lo de abajo: la barrera es transparente', (tester) async {
      await openSheet(tester);
      expect(find.byType(AnimatedModalBarrier), findsNothing);
      for (final barrier in tester.widgetList<ModalBarrier>(find.byType(ModalBarrier))) {
        expect(barrier.color == null || barrier.color!.a == 0, isTrue);
      }
    });

    testWidgets('se cierra tocando fuera', (tester) async {
      await openSheet(tester);
      await tester.tapAt(const Offset(200, 60));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsSheet), findsNothing);
    });

    testWidgets('se cierra arrastrándola hacia abajo desde el tirador', (tester) async {
      await openSheet(tester);
      await tester.drag(find.byKey(const Key('settings-handle')), const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsSheet), findsNothing);
    });

    testWidgets('el contenido se desplaza dentro de la hoja sin cerrarla', (tester) async {
      await openSheet(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsSheet), findsOneWidget);
    });

    testWidgets('«atrás» la cierra', (tester) async {
      await openSheet(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsSheet), findsNothing);
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

    testWidgets('el administrador llega a Configuración con el botón de Inicio', (tester) async {
      await openGate(tester, FakeAccount(uid: 'u1', profile: const Profile(id: 'u1', username: 'gustavo', role: Role.admin)));
      expect(find.byType(SettingsSheet), findsNothing);
      await tester.tap(find.byKey(const Key('home-settings')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-greeting')), findsOneWidget); // Inicio sigue a la vista detrás de la hoja
      expect(tester.getRect(find.byKey(const Key('settings-sheet'))).top, closeTo(850 * 0.3, 1));
      expect(find.text('Cerrar sesión'), findsOneWidget);
      expect(find.byType(SettingsSheet), findsOneWidget);
      expect(find.text('gustavo'), findsOneWidget);
      expect(find.text('Administrador'), findsOneWidget);
    });

    testWidgets('el pasante llega a Configuración con el botón de Inicio y cierra sesión desde allí', (tester) async {
      final account = FakeAccount(uid: 'u2', profile: const Profile(id: 'u2', username: 'ana', role: Role.intern));
      await openGate(tester, account);
      await tester.tap(find.byKey(const Key('home-settings')));
      await tester.pumpAndSettle();
      expect(find.text('Pasante'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('settings-sign-out')));
      await tester.tap(find.byKey(const Key('settings-sign-out')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pumpAndSettle();
      expect(account.signedIn, isFalse);
      expect(find.byType(SettingsSheet), findsNothing);
      expect(find.byKey(const Key('login-button')), findsOneWidget); // volvió al acceso
    });
  });
}
