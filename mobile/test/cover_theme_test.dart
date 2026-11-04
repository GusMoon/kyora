import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/models/profile.dart';
import 'package:kyora_chat/state/cover_theme.dart';
import 'package:kyora_chat/state/player_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/auth_gate.dart';
import 'package:kyora_chat/util/cover_color.dart';

import 'auth_gate_test.dart' show FakeAccount, MemoryRoleCache;
import 'fake_backend.dart';
import 'fake_engine.dart';
import 'music_test.dart' show FakeMusicBackend, FakeSaver, MemoryMusicStore;

void main() {
  group('la paleta de una carátula', () {
    final seeds = [
      for (var hue = 0.0; hue < 360; hue += 15)
        for (final saturation in [0.15, 0.5, 0.9])
          for (final lightness in [0.2, 0.5, 0.8]) HSLColor.fromAHSL(1, hue, saturation, lightness).toColor(),
      const Color(0xFF808080), // gris
      const Color(0xFF000000), // negro
      const Color(0xFFFFFFFF), // blanco
    ];

    test('todos los textos y el acento se leen sobre todos los fondos, con cualquier carátula', () {
      for (final seed in seeds) {
        final c = KyoraColors.fromCover(seed);
        final backs = {'field': c.field, 'background': c.background, 'surface': c.surface, 'plate': c.plate, 'pick': c.pick};
        backs.forEach((name, back) {
          expect(contrastRatio(c.ink, back), greaterThanOrEqualTo(7), reason: 'ink sobre $name con $seed');
          expect(contrastRatio(c.dim, back), greaterThanOrEqualTo(4.5), reason: 'dim sobre $name con $seed');
          expect(contrastRatio(c.accent, back), greaterThanOrEqualTo(4.5), reason: 'acento sobre $name con $seed');
        });
        expect(contrastRatio(c.onAccent, c.accent), greaterThanOrEqualTo(4.5), reason: 'texto sobre el acento con $seed');
      }
    });

    test('los fondos siempre son oscuros y van de menos a más claros, como los de siempre', () {
      for (final seed in seeds) {
        final c = KyoraColors.fromCover(seed);
        final l = [c.field, c.background, c.surface, c.plate, c.pick].map((x) => HSLColor.fromColor(x).lightness).toList();
        expect(l, orderedEquals([...l]..sort()), reason: '$seed');
        expect(l.last, lessThan(0.27), reason: '$seed');
        expect(l.first, greaterThan(0.05), reason: '$seed');
      }
    });

    test('el tono de la carátula manda: fondos, textos y acento salen de él (100 %)', () {
      final blue = KyoraColors.fromCover(const Color(0xFF2255DD));
      final red = KyoraColors.fromCover(const Color(0xFFDD2222));
      double hue(Color color) => HSLColor.fromColor(color).hue;
      expect(hue(blue.accent), closeTo(HSLColor.fromColor(const Color(0xFF2255DD)).hue, 3));
      expect(hue(blue.background), closeTo(hue(blue.accent), 3));
      expect(hue(blue.surface), closeTo(hue(blue.accent), 3));
      expect(hue(red.background), closeTo(hue(red.accent), 6));
      expect(blue.background, isNot(red.background));
      expect(blue.accent, isNot(KyoraColors.classic().accent));
      expect(blue.background, isNot(KyoraColors.classic().background));
    });

    test('una carátula gris da un juego neutro: sin color en los fondos ni en el acento', () {
      final c = KyoraColors.fromCover(const Color(0xFF777777));
      expect(HSLColor.fromColor(c.accent).saturation, lessThan(0.05));
      expect(HSLColor.fromColor(c.background).saturation, lessThan(0.08));
      expect(HSLColor.fromColor(c.surface).saturation, lessThan(0.08));
    });

    test('los avisos de error y de bien no cambian con la carátula', () {
      final c = KyoraColors.fromCover(const Color(0xFF2255DD));
      expect(c.warn, KyoraColors.classic().warn);
      expect(c.ok, KyoraColors.classic().ok);
    });

    test('el tema para un color lleva esa paleta, se guarda y sin color son los de siempre', () {
      expect(buildCoverTheme(null).extension<KyoraColors>()!.accent, KyoraColors.classic().accent);
      expect(identical(buildCoverTheme(null), buildCoverTheme(null)), isTrue);
      const tint = Color(0xFF22AA66);
      final theme = buildCoverTheme(tint);
      expect(identical(theme, buildCoverTheme(tint)), isTrue); // no se vuelve a construir
      final colors = theme.extension<KyoraColors>()!;
      expect(colors.accent, KyoraColors.fromCover(tint).accent);
      expect(theme.colorScheme.primary, colors.accent);
      expect(theme.scaffoldBackgroundColor, Colors.transparent);
      expect(buildCoverTheme(const Color(0xFFAA2266)).extension<KyoraColors>()!.accent, isNot(colors.accent));
    });

    test('pasar de un color a otro se anima: los colores se mezclan', () {
      final a = KyoraColors.fromCover(const Color(0xFF2255DD));
      final b = KyoraColors.fromCover(const Color(0xFFDD2222));
      final half = a.lerp(b, 0.5);
      expect(half.accent, isNot(a.accent));
      expect(half.accent, isNot(b.accent));
      expect(a.lerp(b, 0).accent, a.accent);
      expect(a.lerp(b, 1).accent, b.accent);
    });
  });

  group('color de la imagen', () {
    Uint8List pixels(List<List<int>> rgb) => Uint8List.fromList([for (final c in rgb) ...[...c, 255]]);

    test('el color medio de una imagen gris es su gris, y de una vacía no hay', () {
      final dark = meanColor(pixels([for (var i = 0; i < 20; i++) [40, 40, 40]]))!;
      final light = meanColor(pixels([for (var i = 0; i < 20; i++) [200, 200, 200]]))!;
      expect(dark.computeLuminance(), lessThan(light.computeLuminance()));
      expect(meanColor(Uint8List(0)), isNull);
      expect(meanColor(Uint8List.fromList([10, 10, 10, 0])), isNull); // transparente: no cuenta
    });

    test('una carátula gris da su gris a la app, y una con color da su color', () {
      expect(dominantColor(pixels([for (var i = 0; i < 20; i++) [90, 90, 90]])), isNull);
      expect(meanColor(pixels([for (var i = 0; i < 20; i++) [90, 90, 90]])), const Color(0xFF5A5A5A));
    });
  });

  group('seguir al reproductor', () {
    late FakeMusicBackend backend;
    late FakeEngine engine;
    late PlayerController player;
    late Map<String, Completer<Color?>> pending;
    late List<String> asked;

    CoverTheme make() => CoverTheme(lookup: ({String? url, String? file}) {
          asked.add(url ?? file ?? '');
          return pending[url ?? file]?.future ?? Future.value(const Color(0xFF123456));
        });

    setUp(() {
      backend = FakeMusicBackend();
      engine = FakeEngine();
      pending = {};
      asked = [];
      player = PlayerController(backend, engine, noteAfter: Duration.zero);
    });

    tearDown(() => player.dispose());

    test('nada suena: los colores de siempre', () {
      final theme = make()..attach(player);
      expect(theme.value, isNull);
      theme.dispose();
    });

    test('al sonar una canción con carátula, la app toma su color; al cambiar de canción, el de la nueva', () async {
      final a = backend.add('a', cover: 'https://img.test/a.jpg');
      final b = backend.add('b', cover: 'https://img.test/b.jpg');
      pending['https://img.test/a.jpg'] = Completer()..complete(const Color(0xFFAA0000));
      pending['https://img.test/b.jpg'] = Completer()..complete(const Color(0xFF0000AA));
      final theme = make()..attach(player);
      await player.play(a, [a, b]);
      await pumpEventQueue();
      expect(theme.value, const Color(0xFFAA0000));
      await player.play(b, [a, b]);
      await pumpEventQueue();
      expect(theme.value, const Color(0xFF0000AA));
      expect(asked, ['https://img.test/a.jpg', 'https://img.test/b.jpg']);
      theme.dispose();
    });

    test('la misma canción no se analiza dos veces', () async {
      final a = backend.add('a', cover: 'https://img.test/a.jpg');
      final theme = make()..attach(player);
      await player.play(a, [a]);
      await pumpEventQueue();
      await player.toggle(); // pausa y reanuda: avisa el reproductor, pero es la misma carátula
      await player.toggle();
      await pumpEventQueue();
      expect(asked.length, 1);
      theme.dispose();
    });

    test('una canción sin carátula deja el color de la anterior', () async {
      final a = backend.add('a', cover: 'https://img.test/a.jpg');
      final b = backend.add('b'); // sin carátula
      final theme = make()..attach(player);
      await player.play(a, [a, b]);
      await pumpEventQueue();
      final color = theme.value;
      expect(color, isNotNull);
      await player.play(b, [a, b]);
      await pumpEventQueue();
      expect(theme.value, color);
      theme.dispose();
    });

    test('si la carátula tarda y entre tanto cambia la canción, gana la de ahora, no la que llegó tarde', () async {
      final a = backend.add('a', cover: 'https://img.test/a.jpg');
      final b = backend.add('b', cover: 'https://img.test/b.jpg');
      final slow = Completer<Color?>();
      pending['https://img.test/a.jpg'] = slow; // la de «a» todavía no llega
      pending['https://img.test/b.jpg'] = Completer()..complete(const Color(0xFF00AA00));
      final theme = make()..attach(player);
      await player.play(a, [a, b]);
      await pumpEventQueue();
      await player.play(b, [a, b]);
      await pumpEventQueue();
      expect(theme.value, const Color(0xFF00AA00));
      slow.complete(const Color(0xFFFF0000)); // llega tarde
      await pumpEventQueue();
      expect(theme.value, const Color(0xFF00AA00));
      theme.dispose();
    });

    test('al soltar el reproductor (cerrar sesión) vuelve a los colores de siempre', () async {
      final a = backend.add('a', cover: 'https://img.test/a.jpg');
      final theme = make()..attach(player);
      await player.play(a, [a]);
      await pumpEventQueue();
      expect(theme.value, isNotNull);
      theme.detach();
      await pumpEventQueue();
      expect(theme.value, isNull);
      await player.toggle(); // lo que haga el reproductor después ya no cuenta
      await pumpEventQueue();
      expect(theme.value, isNull);
      theme.dispose();
    });

    test('un cambio de color avisa a quien lo escucha (la app se reconstruye con el tema nuevo)', () async {
      final a = backend.add('a', cover: 'https://img.test/a.jpg');
      final theme = make()..attach(player);
      var notified = 0;
      theme.addListener(() => notified++);
      await player.play(a, [a]);
      await pumpEventQueue();
      expect(notified, 1);
      theme.dispose();
    });
  });

  group('desde la app', () {
    testWidgets('al cerrar sesión la app vuelve a los colores de siempre', (tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final cover = CoverTheme(lookup: ({String? url, String? file}) async => const Color(0xFF2255DD));
      addTearDown(cover.dispose);
      cover.value = const Color(0xFF2255DD); // algo sonó antes
      final account = FakeAccount(uid: 'u2', profile: const Profile(id: 'u2', username: 'ana', role: Role.intern));
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: AuthGate(
          account: account,
          chat: FakeBackend(),
          music: FakeMusicBackend(),
          musicStore: MemoryMusicStore(since: DateTime.utc(2026, 10, 1)),
          saver: FakeSaver(),
          roleCache: MemoryRoleCache(),
          engine: FakeEngine.new,
          coverTheme: cover,
        ),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
      await tester.tap(find.byKey(const Key('home-settings'))); // el botón de Inicio abre la configuración
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('settings-sign-out')));
      await tester.tap(find.byKey(const Key('settings-sign-out')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pumpAndSettle();
      expect(account.signedIn, isFalse);
      expect(cover.value, isNull);
    });
  });

  group('similarColors', () {
    test('un color casi igual no cambia el tema; uno distinto, sí', () {
      const red = Color(0xFFD62828);
      expect(similarColors(red, const Color(0xFFD72A2A)), isTrue);
      expect(similarColors(red, const Color(0xFF2A9D4F)), isFalse); // otro tono
      expect(similarColors(red, const Color(0xFF7A1010)), isFalse); // mucho más oscuro
      expect(similarColors(null, null), isTrue);
      expect(similarColors(red, null), isFalse);
      expect(similarColors(null, red), isFalse);
      // el rojo está a los dos lados de los 0°: 358° y 2° son casi el mismo tono
      expect(similarColors(HSLColor.fromAHSL(1, 358, 0.7, 0.5).toColor(), HSLColor.fromAHSL(1, 2, 0.7, 0.5).toColor()), isTrue);
    });
  });
}
