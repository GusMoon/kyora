import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/dock_store.dart';
import 'package:kyora_chat/data/favorites_store.dart';
import 'package:kyora_chat/data/installed_apps.dart';
import 'package:kyora_chat/data/music_store.dart';
import 'package:kyora_chat/data/reminder_store.dart';
import 'package:kyora_chat/data/task_store.dart';
import 'package:kyora_chat/data/weather_store.dart';
import 'package:kyora_chat/models/track.dart';
import 'package:kyora_chat/state/chat_controller.dart';
import 'package:kyora_chat/state/dock_controller.dart';
import 'package:kyora_chat/state/local_music_controller.dart';
import 'package:kyora_chat/state/music_controller.dart';
import 'package:kyora_chat/state/player_controller.dart';
import 'package:kyora_chat/state/reminder_controller.dart';
import 'package:kyora_chat/state/task_controller.dart';
import 'package:kyora_chat/state/weather_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/chat_page.dart';
import 'package:kyora_chat/ui/home_page.dart';
import 'package:kyora_chat/ui/music_page.dart';
import 'package:kyora_chat/ui/agenda_view.dart';
import 'package:kyora_chat/ui/tasks_page.dart';
import 'package:kyora_chat/ui/widgets/composer.dart';
import 'package:kyora_chat/ui/widgets/section_motion.dart';

import 'fake_backend.dart';
import 'fake_engine.dart';
import 'music_test.dart' show FakeMusicBackend, FakeSaver, MemoryMusicStore;
import 'reminders_test.dart' show FakeScheduler;
import 'task_controller_test.dart' show FakeTaskBackend;
import 'weather_test.dart' show FakeWeather;

/// Cada bloque de cada sección sale y entra por el borde más cercano: lo de arriba por arriba, lo de abajo por abajo, lo del medio por los
/// lados.
MotionEdge edgeOf(WidgetTester tester, Finder block) => tester.widget<FlyIn>(find.ancestor(of: block, matching: find.byType(FlyIn)).first).edge;

void main() {
  Future<void> show(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: page));
    await tester.pump();
  }

  /// `page` dentro de un cambio de sección en curso (o quieta).
  Widget moving(Widget page, {required bool yes}) => SectionMotion(animation: const AlwaysStoppedAnimation(1), leaving: false, moving: yes, child: page);

  group('Inicio', () {
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

    Widget home() => HomePage(
      onOpenSettings: () {},
      weather: weather,
      dock: DockController(MemoryDockStore(), FakeInstalledApps([])),
      now: () => DateTime(2026, 11, 3, 9, 30),
    );

    testWidgets('los paneles de la cuadrícula aparecen por su lado, uno tras otro: la columna izquierda por la izquierda y la derecha por la derecha', (tester) async {
      await show(tester, home());
      await tester.pump();
      expect(edgeOf(tester, find.byKey(const Key('home-time'))), MotionEdge.left);
      expect(edgeOf(tester, find.byKey(const Key('home-weather'))), MotionEdge.right);
      expect(edgeOf(tester, find.byKey(const Key('home-system'))), MotionEdge.left);
      expect(edgeOf(tester, find.byKey(const Key('home-quick'))), MotionEdge.right);
      int orderOf(String key) => tester.widget<FlyIn>(find.ancestor(of: find.byKey(Key(key)), matching: find.byType(FlyIn)).first).order;
      expect([orderOf('home-time'), orderOf('home-weather'), orderOf('home-system'), orderOf('home-quick')], [0, 1, 2, 3]);
    });
  });

  group('Música', () {
    late FakeMusicBackend backend;
    late FakeSaver saver;
    late MusicController music;
    late LocalMusicController local;
    late PlayerController player;
    late FavoritesController favorites;

    LocalSong song(String name) => LocalSong(uri: 'content://tree/musica/document/$name', name: name, sizeBytes: 1024, modified: DateTime.utc(2026, 1, 1));

    setUp(() {
      backend = FakeMusicBackend();
      saver = FakeSaver()..files = [song('a.mp3')];
      music = MusicController(backend, MemoryMusicStore(since: DateTime.utc(2026, 10, 1))..settings = const MusicSettings(auto: false).withTree('content://tree/musica', 'Mi música'), saver);
      local = LocalMusicController(music, saver);
      player = PlayerController(backend, FakeEngine(), art: local, noteAfter: Duration.zero);
      favorites = FavoritesController();
    });

    tearDown(() {
      player.dispose();
      local.dispose();
      music.dispose();
    });

    Widget page() => MusicPage(controller: music, local: local, player: player, favorites: favorites);

    testWidgets('la pila por la izquierda y los iconos discretos por arriba; sin favoritas ni mini-barra', (tester) async {
      await tester.runAsync(() async {
        await music.start();
        await pumpEventQueue();
        await favorites.toggle(Track.local(song('a.mp3')).durationKey);
        await player.play(Track.local(song('a.mp3')), [Track.local(song('a.mp3'))]);
      });
      await show(tester, moving(page(), yes: true));
      expect(find.byKey(const Key('music-title')), findsNothing);
      expect(edgeOf(tester, find.byKey(const Key('album-deck'))), MotionEdge.left);
      expect(edgeOf(tester, find.byKey(const Key('music-refresh'))), MotionEdge.top);
      expect(find.byKey(const Key('favorites-title')), findsNothing);
      expect(find.byKey(const Key('favorites-flow')), findsNothing);
      expect(find.byKey(const Key('mini-player')), findsNothing);
    });

    testWidgets('sin carpeta posible: el resumen por la izquierda y la lista por abajo', (tester) async {
      backend.add('r', at: DateTime.utc(2026, 9, 1));
      await tester.runAsync(music.start);
      await show(tester, MusicPage(controller: music));
      expect(edgeOf(tester, find.byKey(const Key('music-banner'))), MotionEdge.left);
      expect(edgeOf(tester, find.byKey(const Key('track-list'))), MotionEdge.bottom);
    });
  });

  testWidgets('Chat: la ventana de la terminal por arriba, el registro por la izquierda y el prompt dentro de ella, abajo', (tester) async {
    final backend = FakeBackend();
    final controller = ChatController(backend, retryDelay: const Duration(milliseconds: 20), catchUpDelay: const Duration(milliseconds: 10));
    addTearDown(controller.dispose);
    await show(tester, ChatPage(backend: backend, controller: controller));
    await tester.runAsync(controller.start);
    await tester.pump();
    expect(edgeOf(tester, find.byKey(const Key('terminal-header'))), MotionEdge.top);
    expect(edgeOf(tester, find.byKey(const Key('chat-empty'))), MotionEdge.left);
    // el prompt va dentro de la ventana, abajo del todo
    expect(find.descendant(of: find.byKey(const Key('terminal-footer')), matching: find.byType(Composer)), findsOneWidget);
    expect(tester.getBottomLeft(find.byType(Composer)).dy, greaterThan(tester.getBottomLeft(find.byKey(const Key('chat-empty'))).dy));
  });

  testWidgets('Tareas: la barra por arriba, los filtros por la izquierda, la lista por la derecha y el campo por abajo', (tester) async {
    final tasks = TaskController(MemoryTaskStore(), FakeTaskBackend(), retry: const Duration(hours: 1));
    addTearDown(tasks.dispose);
    await tester.runAsync(tasks.start);
    await show(tester, TasksPage(controller: tasks));
    expect(edgeOf(tester, find.byType(AppBar)), MotionEdge.top);
    expect(edgeOf(tester, find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Filters')), MotionEdge.left);
    expect(edgeOf(tester, find.byKey(const Key('tasks-empty'))), MotionEdge.right);
    expect(edgeOf(tester, find.byKey(const Key('task-input'))), MotionEdge.bottom);
  });

  testWidgets('Calendario: la consola y las etiquetas de los paneles por arriba y lo del día por abajo', (tester) async {
    final reminders = ReminderController(MemoryReminderStore(), FakeScheduler());
    addTearDown(reminders.dispose);
    await tester.runAsync(reminders.start);
    await show(tester, AgendaView(reminders: Future.value(reminders), now: () => DateTime(2026, 11, 5, 9)));
    await tester.pump();
    expect(edgeOf(tester, find.byKey(const Key('cal-title'))), MotionEdge.top);
    expect(edgeOf(tester, find.byKey(const Key('cal-summary'))), MotionEdge.top);
    expect(edgeOf(tester, find.byKey(const Key('cal-tab-day'))), MotionEdge.top); // con recordatorios hay dos paneles: Hoy y Recordatorios
    expect(edgeOf(tester, find.byKey(const Key('cal-day-empty'))), MotionEdge.bottom);
  });
}
