import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/system_info.dart';
import 'package:kyora_chat/state/system_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/widgets/focus_space.dart';

void main() {
  tearDown(() => FocusSpace.last = null);

  group('dónde va un panel del espacio focal', () {
    const screen = Size(400, 800);

    test('centrado en el punto focal', () {
      final r = FocusSpace.place(const Size(200, 100), screen, EdgeInsets.zero, around: const Offset(200, 400));
      expect(r.center, const Offset(200, 400));
    });

    test('cerca de un borde se corre lo justo para caber entero', () {
      final r = FocusSpace.place(const Size(200, 100), screen, const EdgeInsets.only(top: 24), around: const Offset(10, 10));
      expect(r.left, FocusSpace.margin);
      expect(r.top, 24 + FocusSpace.margin);
    });

    test('sin punto focal, en el centro; con uno guardado (el del último menú), ahí', () {
      expect(FocusSpace.place(const Size(100, 100), screen, EdgeInsets.zero).center, const Offset(200, 400));
      FocusSpace.last = const Offset(200, 600);
      expect(FocusSpace.place(const Size(100, 100), screen, EdgeInsets.zero).center, const Offset(200, 600));
    });
  });

  group('el panel focal', () {
    Future<BuildContext> app(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox.expand();
      }))));
      return ctx;
    }

    testWidgets('se abre donde se abrió el menú, con su título, y alrededor el fondo oscurecido (sin desenfoque) con un hueco nítido del tamaño del panel', (tester) async {
      final context = await app(tester);
      FocusSpace.last = const Offset(200, 500);
      unawaited(showFocusPanel<void>(context, title: 'Opciones', builder: (_) => const SizedBox(height: 120, child: Text('dentro'))));
      await tester.pumpAndSettle();
      final panel = tester.getRect(find.byKey(const Key('focus-panel')));
      expect((panel.center - const Offset(200, 500)).distance, lessThan(2));
      expect(find.text('Opciones'), findsOneWidget);
      expect(find.text('dentro'), findsOneWidget);
      final veil = find.byKey(const Key('focus-veil'));
      expect(find.byType(BackdropFilter), findsNothing); // un desenfoque animado a pantalla completa hacía lento abrir el panel
      final clip = tester.widget<ClipPath>(find.descendant(of: veil, matching: find.byType(ClipPath))).clipper!.getClip(const Size(400, 800));
      expect(clip.contains(panel.center), isFalse); // el panel, nítido
      expect(clip.contains(const Offset(5, 5)), isTrue); // el resto, oscurecido
    });

    testWidgets('tocar fuera lo cierra sin respuesta; un botón de dentro lo cierra con la suya', (tester) async {
      final context = await app(tester);
      String? answer = 'sin cerrar';
      unawaited(showFocusPanel<String>(context, builder: (c) => TextButton(onPressed: () => Navigator.of(c).pop('sí'), child: const Text('Aceptar'))).then((v) => answer = v));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('focus-panel')), findsNothing);
      expect(answer, isNull);
      unawaited(showFocusPanel<String>(context, builder: (c) => TextButton(onPressed: () => Navigator.of(c).pop('sí'), child: const Text('Aceptar'))).then((v) => answer = v));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
      expect(answer, 'sí');
    });

    testWidgets('un aviso (FocusDialog) lleva su texto y sus botones', (tester) async {
      final context = await app(tester);
      unawaited(showFocusPanel<bool>(context, title: '¿Borrar?', builder: (c) => FocusDialog(content: const Text('No se puede deshacer.'), actions: [TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Borrar'))])));
      await tester.pumpAndSettle();
      expect(find.text('¿Borrar?'), findsOneWidget);
      expect(find.text('No se puede deshacer.'), findsOneWidget);
      expect(find.text('Borrar'), findsOneWidget);
    });
  });

  group('el estado del teléfono', () {
    test('lo que manda Android se entiende, y lo que falta queda en null', () {
      final s = SystemStats.fromMap({'battery': 54, 'charging': true, 'ramTotal': 4000, 'ramFree': 1000, 'storageTotal': 100, 'storageFree': 25, 'wifi': false, 'bluetooth': null});
      expect(s.battery, 54);
      expect(s.charging, isTrue);
      expect(s.ramUsed, 0.75);
      expect(s.storageUsed, 0.75);
      expect(s.wifi, isFalse);
      expect(s.bluetooth, isNull);
      expect(SystemStats.fromMap(const {}).ramUsed, isNull);
    });

    test('el controlador lee al empezar a mirar, cada poco mientras se mira y deja de leer al dejar de mirar', () async {
      final info = FakeSystemInfo(const SystemStats(battery: 10));
      final c = SystemController(info, every: const Duration(milliseconds: 10));
      addTearDown(c.dispose);
      c.watch();
      await Future<void>.delayed(const Duration(milliseconds: 35));
      expect(c.stats?.battery, 10);
      expect(info.reads, greaterThanOrEqualTo(3));
      c.unwatch();
      final reads = info.reads;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(info.reads, reads);
    });
  });
}
