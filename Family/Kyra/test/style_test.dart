import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/habit_store.dart';
import 'package:kyora_chat/data/reminder_store.dart';
import 'package:kyora_chat/data/task_store.dart';
import 'package:kyora_chat/data/weather_store.dart';
import 'package:kyora_chat/models/profile.dart';
import 'package:kyora_chat/state/habit_controller.dart';
import 'package:kyora_chat/state/music_controller.dart';
import 'package:kyora_chat/state/reminder_controller.dart';
import 'package:kyora_chat/state/task_controller.dart';
import 'package:kyora_chat/state/weather_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/agenda_view.dart';
import 'package:kyora_chat/ui/home_page.dart';
import 'package:kyora_chat/ui/music_page.dart';
import 'package:kyora_chat/ui/settings_page.dart';
import 'package:kyora_chat/ui/widgets/app_backdrop.dart';
import 'package:kyora_chat/ui/widgets/device_shell.dart';
import 'package:kyora_chat/ui/widgets/glass_card.dart';
import 'package:kyora_chat/ui/widgets/tech_shapes.dart';
import 'package:kyora_chat/ui/widgets/cut_border.dart';

import 'habit_test.dart' show FakeHabitBackend;
import 'music_test.dart' show FakeMusicBackend, FakeSaver, MemoryMusicStore;
import 'reminders_test.dart' show FakeScheduler;
import 'task_controller_test.dart' show FakeTaskBackend;
import 'weather_test.dart' show FakeWeather;

/// La guardia del estilo: dentro de la pantalla, **sin cristal ni desenfoque** (salvo el velo del espacio focal: el menú circular y los paneles), **sin sombras ni esquinas redondeadas en las cajas**, **solo las dos
/// letras de la app** (la grotesca y la monoespaciada) y **ningún texto por debajo de 15 px** (la regla de la vista).
void expectStyle(WidgetTester tester, {String? reason}) {
  // el único cristal permitido es el del espacio focal (alrededor del menú circular y de los paneles)
  final allowed = find.byWidgetPredicate((w) => w is BackdropFilter).evaluate().where((e) {
    var ok = false;
    e.visitAncestorElements((a) {
      final key = a.widget.key;
      if (key == const Key('focus-veil')) ok = true;
      return !ok;
    });
    return ok;
  }).length;
  expect(find.byType(BackdropFilter), findsNWidgets(allowed), reason: 'cristal fuera de Inicio ${reason ?? ''}');
  Finder inside(Type type) => find.descendant(of: find.byType(DeviceScreenFrame), matching: find.byType(type));
  for (final text in tester.widgetList<Text>(inside(Text))) {
    final family = text.style?.fontFamily;
    if (family != null) expect([appFont, monoFont], contains(family), reason: '«${text.data}» ${reason ?? ''}');
    final size = text.style?.fontSize;
    if (size != null) expect(size, greaterThanOrEqualTo(15), reason: '«${text.data}» ${reason ?? ''}');
  }
  for (final box in tester.widgetList<DecoratedBox>(inside(DecoratedBox))) {
    final decoration = box.decoration;
    if (decoration is! BoxDecoration) continue;
    expect(decoration.boxShadow, isNull, reason: 'sombras ${reason ?? ''}');
    expect(decoration.borderRadius == null || decoration.borderRadius == BorderRadius.zero, isTrue, reason: 'esquinas redondeadas ${reason ?? ''}');
  }
  expect(inside(ClipRRect), findsNothing, reason: 'esquinas redondeadas (recorte) ${reason ?? ''}');
}

void main() {
  late TaskController tasks;
  late ReminderController reminders;
  late WeatherController weather;
  late MusicController music;

  setUp(() {
    tasks = TaskController(MemoryTaskStore(), FakeTaskBackend(), retry: const Duration(hours: 1));
    reminders = ReminderController(MemoryReminderStore(), FakeScheduler(), now: () => DateTime(2026, 11, 3, 9, 30).toUtc());
    weather = WeatherController(FakeWeather(), MemoryWeatherStore());
    music = MusicController(FakeMusicBackend(), MemoryMusicStore(since: DateTime.utc(2026, 10, 1)), FakeSaver());
  });

  tearDown(() {
    tasks.dispose();
    reminders.dispose();
    weather.dispose();
    music.dispose();
  });

  Future<void> show(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), builder: (context, child) => AppBackdrop(child: child!), home: page));
    await tester.pumpAndSettle();
  }

  testWidgets('Inicio: el encabezado y los hábitos', (tester) async {
    await tester.runAsync(() async {
      await tasks.start();
      await reminders.start();
      await weather.setCity('Lima');
    });
    final habits = HabitController(MemoryHabitStore(), FakeHabitBackend(), now: () => DateTime(2026, 11, 3, 9).toUtc(), newId: () => 'h1', retry: const Duration(hours: 1));
    addTearDown(habits.dispose);
    await tester.runAsync(() async {
      await habits.start();
      await habits.add('Leer', remindAt: 9 * 60);
    });
    final now = DateTime(2026, 11, 3, 9, 30);
    await show(tester, HomePage(onOpenSettings: () {}, weather: weather, now: () => now));
    expectStyle(tester, reason: 'en Inicio');
  });

  testWidgets('Calendario', (tester) async {
    await tester.runAsync(() async {
      await tasks.start();
      await reminders.start();
      await reminders.add('Llamar', DateTime(2026, 11, 3, 8).toUtc());
    });
    await show(tester, AgendaView(tasks: Future.value(tasks), reminders: Future.value(reminders), now: () => DateTime(2026, 11, 3, 9)));
    await tester.pump();
    expectStyle(tester);
  });

  testWidgets('Música', (tester) async {
    await tester.runAsync(music.start);
    await show(tester, MusicPage(controller: music));
    expectStyle(tester);
  });

  testWidgets('Configuración', (tester) async {
    await tester.runAsync(music.start);
    await show(tester, Builder(builder: (context) => const Scaffold(body: SizedBox.expand())));
    unawaited(showSettings(tester.element(find.byType(Scaffold)), SettingsPage(music: music, role: Role.admin, onSignOut: () async {}, weather: weather)));
    await tester.pumpAndSettle();
    expectStyle(tester, reason: 'en el mosaico');
    await tester.tap(find.byKey(const Key('mosaic-tile-weather')));
    await tester.pumpAndSettle();
    expectStyle(tester, reason: 'con una ficha expandida');
  });

  testWidgets('una tarjeta es gris oscuro con filo fino y esquinas cortadas (nada redondo), sin cristal', (tester) async {
    await show(tester, const Scaffold(body: Center(child: GlassCard(child: SizedBox(width: 80, height: 40)))));
    final material = tester.widget<Material>(find.descendant(of: find.byKey(const Key('glass-card')), matching: find.byType(Material)).first);
    expect(material.color, KyoraColors.classic().surface);
    final shape = material.shape! as CutBorder;
    expect(shape.cut, greaterThan(0));
    expect(shape.side.color, KyoraColors.classic().edge);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('la tarjeta con la esquina cortada: el hueco queda sin pintar y la tarjeta de acento va rellena', (tester) async {
    await show(tester, const Scaffold(body: Center(child: TechCard(accent: true, notch: 46, child: SizedBox(width: 200, height: 120)))));
    final material = tester.widget<Material>(find.descendant(of: find.byKey(const Key('tech-card')), matching: find.byType(Material)).first);
    expect(material.color, KyoraColors.classic().accent);
    final path = (material.shape! as NotchedBorder).getOuterPath(const Rect.fromLTWH(0, 0, 200, 120));
    expect(path.contains(const Offset(100, 60)), isTrue);
    expect(path.contains(const Offset(199, 1)), isFalse); // la esquina cortada
    expect(path.contains(const Offset(40, 110)), isTrue);
  });

  testWidgets('el desplazamiento no estira en los extremos', (tester) async {
    await tester.pumpWidget(MaterialApp(
      scrollBehavior: const KyraScrollBehavior(),
      home: ListView(children: [for (var i = 0; i < 30; i++) SizedBox(height: 80, child: Text('fila $i'))]),
    ));
    expect(find.byType(StretchingOverscrollIndicator), findsNothing);
    expect(find.byType(GlowingOverscrollIndicator), findsNothing);
  });
}
