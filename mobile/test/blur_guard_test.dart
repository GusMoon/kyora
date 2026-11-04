import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/task_store.dart';
import 'package:kyora_chat/data/weather_store.dart';
import 'package:kyora_chat/models/profile.dart';
import 'package:kyora_chat/state/music_controller.dart';
import 'package:kyora_chat/state/task_controller.dart';
import 'package:kyora_chat/state/weather_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/home_page.dart';
import 'package:kyora_chat/ui/settings_sheet.dart';
import 'package:kyora_chat/ui/widgets/app_backdrop.dart';
import 'package:kyora_chat/ui/widgets/glass_card.dart';

import 'music_test.dart' show FakeMusicBackend, FakeSaver, MemoryMusicStore;
import 'task_controller_test.dart' show FakeTaskBackend;
import 'weather_test.dart' show FakeWeather;

/// El desenfoque de una tarjeta de cristal solo ve lo que ya está pintado dentro de su capa. Un `Opacity`, un `FadeTransition`, un
/// `AnimatedOpacity` o un `ShaderMask` por encima crean una capa aparte, y mientras dura el cristal no ve el fondo: se «quita» el desenfoque.
/// Estas pruebas vigilan que eso no vuelva a pasar.
final _layerMakers = find.byWidgetPredicate(
  (widget) => widget is Opacity || widget is FadeTransition || widget is AnimatedOpacity || widget is ShaderMask || widget is ImageFiltered && widget.enabled,
  description: 'Opacity / FadeTransition / AnimatedOpacity / ShaderMask / ImageFiltered',
);

void expectNoLayerAbove(WidgetTester tester, {String? reason}) {
  final filters = find.byType(BackdropFilter);
  expect(filters, findsWidgets, reason: 'tiene que haber cristal que vigilar');
  expect(find.ancestor(of: filters, matching: _layerMakers), findsNothing, reason: reason);
}

void main() {
  late TaskController tasks;
  late WeatherController weather;

  setUp(() {
    tasks = TaskController(MemoryTaskStore(), FakeTaskBackend(), retry: const Duration(hours: 1));
    weather = WeatherController(FakeWeather(), MemoryWeatherStore());
  });

  tearDown(() {
    tasks.dispose();
    weather.dispose();
  });

  Future<void> openHome(WidgetTester tester, {Widget Function(BuildContext)? extra}) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(tasks.start);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      scrollBehavior: const KyraScrollBehavior(),
      builder: (context, child) => AppBackdrop(child: child!),
      home: Builder(
        builder: (context) => HomePage(
          onOpenSettings: () {},
          tasks: Future.value(tasks),
          weather: weather,
          now: () => DateTime(2026, 11, 3, 9, 30),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('Inicio: ninguna tarjeta de cristal tiene encima una capa con opacidad', (tester) async {
    await openHome(tester);
    expectNoLayerAbove(tester);
  });

  testWidgets('las tarjetas de Inicio comparten una sola captura del fondo (BackdropGroup), y la hoja de Configuración va aparte', (tester) async {
    await openHome(tester);
    expect(find.byType(BackdropGroup), findsOneWidget);
    // la hoja se solapa con las tarjetas: su filtro no puede compartir clave con ellas
    final music = MusicController(FakeMusicBackend(), MemoryMusicStore(since: DateTime.utc(2026, 10, 1)), FakeSaver());
    addTearDown(music.dispose);
    await tester.runAsync(music.start);
    unawaited(showSettingsSheet(tester.element(find.byType(HomePage)), SettingsSheet(music: music, role: Role.admin, onSignOut: () async {})));
    await tester.pumpAndSettle();
    final sheetFilter = find.descendant(of: find.byKey(const Key('settings-sheet')), matching: find.byType(BackdropFilter));
    expect(find.ancestor(of: sheetFilter, matching: find.byType(BackdropGroup)), findsNothing);
  });

  testWidgets('Inicio con el desplazamiento al límite: sigue sin capas y sin el efecto de estiramiento', (tester) async {
    await openHome(tester);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 300)); // más allá del extremo
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(StretchingOverscrollIndicator), findsNothing);
    expectNoLayerAbove(tester, reason: 'al estirar en el extremo');
    await tester.pumpAndSettle();
  });

  testWidgets('una pantalla que se empuja sube sin ninguna capa de opacidad, ni la de encima ni la de debajo, durante toda la animación', (tester) async {
    await openHome(tester);
    final context = tester.element(find.byType(HomePage));
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Center(child: GlassCard(child: Text('pantalla nueva')))),
    )));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expectNoLayerAbove(tester, reason: 'a los ${(i + 1) * 50} ms de abrirse');
    }
    await tester.pumpAndSettle();
    expect(find.text('pantalla nueva'), findsOneWidget);
    // y al volver
    Navigator.of(tester.element(find.text('pantalla nueva'))).pop();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expectNoLayerAbove(tester, reason: 'a los ${(i + 1) * 50} ms de cerrarse');
    }
    await tester.pumpAndSettle();
  });

  testWidgets('la hoja de Configuración, al abrirse, durante la animación y ya abierta, tampoco', (tester) async {
    await openHome(tester);
    final music = MusicController(FakeMusicBackend(), MemoryMusicStore(since: DateTime.utc(2026, 10, 1)), FakeSaver());
    addTearDown(music.dispose);
    await tester.runAsync(music.start);
    final context = tester.element(find.byType(HomePage));
    unawaited(showSettingsSheet(context, SettingsSheet(music: music, role: Role.admin, onSignOut: () async {})));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expectNoLayerAbove(tester, reason: 'a los ${(i + 1) * 50} ms de abrirse la hoja');
    }
    await tester.pumpAndSettle();
    expectNoLayerAbove(tester, reason: 'con la hoja abierta');
  });

  testWidgets('el comportamiento de desplazamiento de Kyra no estira ni deja pasar el filtro de imagen', (tester) async {
    await tester.pumpWidget(MaterialApp(
      scrollBehavior: const KyraScrollBehavior(),
      home: ListView(children: [for (var i = 0; i < 30; i++) SizedBox(height: 80, child: Text('fila $i'))]),
    ));
    expect(find.byType(StretchingOverscrollIndicator), findsNothing);
    expect(find.byType(GlowingOverscrollIndicator), findsNothing);
    expect(const KyraScrollBehavior().getScrollPhysics(tester.element(find.byType(Scrollable))), isA<ClampingScrollPhysics>());
  });
}
