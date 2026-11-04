import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/favorites_store.dart';
import 'package:kyora_chat/data/music_store.dart';
import 'package:kyora_chat/data/reminder_store.dart';
import 'package:kyora_chat/data/task_store.dart';
import 'package:kyora_chat/data/weather_store.dart';
import 'package:kyora_chat/models/track.dart';
import 'package:kyora_chat/state/chat_controller.dart';
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
import 'package:kyora_chat/ui/reminders_page.dart';
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

    Widget home() => HomePage(onOpenSettings: () {}, tasks: Future.value(tasks), weather: weather, now: () => DateTime(2026, 11, 3, 9, 30));

    testWidgets('la cabecera por arriba, el botón por la derecha y la tarjeta (con el clima) por abajo', (tester) async {
      await tester.runAsync(tasks.start);
      await show(tester, home());
      expect(edgeOf(tester, find.byKey(const Key('home-date'))), MotionEdge.top);
      expect(edgeOf(tester, find.byKey(const Key('home-greeting'))), MotionEdge.top);
      expect(edgeOf(tester, find.byKey(const Key('home-settings'))), MotionEdge.right);
      expect(edgeOf(tester, find.byKey(const Key('notched-card'))), MotionEdge.bottom);
      expect(edgeOf(tester, find.byKey(const Key('home-weather'))), MotionEdge.bottom);
    });

    testWidgets('sin tareas, el clima solo también sale por abajo', (tester) async {
      await show(tester, HomePage(onOpenSettings: () {}, weather: weather, now: () => DateTime(2026, 11, 3, 9, 30)));
      expect(edgeOf(tester, find.byKey(const Key('home-weather'))), MotionEdge.bottom);
    });

    testWidgets('la lista solo deja de recortar mientras dura el cambio', (tester) async {
      await tester.runAsync(tasks.start);
      await show(tester, moving(home(), yes: true));
      expect(tester.widget<CustomScrollView>(find.byType(CustomScrollView)).clipBehavior, Clip.none);
      await show(tester, moving(home(), yes: false));
      expect(tester.widget<CustomScrollView>(find.byType(CustomScrollView)).clipBehavior, Clip.hardEdge);
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

    testWidgets('la ruleta por la izquierda; las favoritas y la mini-barra por abajo', (tester) async {
      await tester.runAsync(() async {
        await music.start();
        await pumpEventQueue();
        await favorites.toggle(Track.local(song('a.mp3')).durationKey);
        await player.play(Track.local(song('a.mp3')), [Track.local(song('a.mp3'))]);
      });
      await show(tester, page());
      expect(find.byKey(const Key('music-title')), findsNothing);
      expect(edgeOf(tester, find.byKey(const Key('album-deck'))), MotionEdge.left);
      expect(edgeOf(tester, find.byKey(const Key('favorites-title'))), MotionEdge.bottom);
      expect(edgeOf(tester, find.byKey(const Key('mini-player'))), MotionEdge.bottom);
      await tester.drag(find.byKey(const Key('music-scroll')), const Offset(0, -400));
      await tester.pump();
      expect(edgeOf(tester, find.byKey(const Key('local-local:content://tree/musica/document/a.mp3'))), MotionEdge.bottom);
    });

    testWidgets('sin favoritas, el aviso va por abajo; y la lista solo deja de recortar durante el cambio', (tester) async {
      await tester.runAsync(music.start);
      await tester.runAsync(pumpEventQueue);
      await show(tester, moving(page(), yes: true));
      expect(tester.widget<CustomScrollView>(find.byKey(const Key('music-scroll'))).clipBehavior, Clip.none);
      await tester.drag(find.byKey(const Key('music-scroll')), const Offset(0, -300));
      await tester.pump();
      expect(edgeOf(tester, find.byKey(const Key('favorites-empty'))), MotionEdge.bottom);
      await show(tester, moving(page(), yes: false));
      expect(tester.widget<CustomScrollView>(find.byKey(const Key('music-scroll'))).clipBehavior, Clip.hardEdge);
    });

    testWidgets('sin carpeta posible: el resumen por la izquierda y la lista por abajo', (tester) async {
      backend.add('r', at: DateTime.utc(2026, 9, 1));
      await tester.runAsync(music.start);
      await show(tester, MusicPage(controller: music));
      expect(edgeOf(tester, find.byKey(const Key('music-banner'))), MotionEdge.left);
      expect(edgeOf(tester, find.byKey(const Key('track-list'))), MotionEdge.bottom);
    });
  });

  testWidgets('Chat: la barra por arriba, los mensajes por la izquierda y el campo de escribir por abajo', (tester) async {
    final backend = FakeBackend();
    final controller = ChatController(backend, retryDelay: const Duration(milliseconds: 20), catchUpDelay: const Duration(milliseconds: 10));
    addTearDown(controller.dispose);
    await show(tester, ChatPage(backend: backend, controller: controller));
    await tester.runAsync(controller.start);
    await tester.pump();
    expect(edgeOf(tester, find.byType(AppBar)), MotionEdge.top);
    expect(edgeOf(tester, find.textContaining('mensajes')), MotionEdge.left);
    expect(edgeOf(tester, find.byType(Composer)), MotionEdge.bottom);
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

  testWidgets('Recordatorios: la barra por arriba, la lista por la derecha y «Nuevo» por abajo', (tester) async {
    final reminders = ReminderController(MemoryReminderStore(), FakeScheduler());
    addTearDown(reminders.dispose);
    await tester.runAsync(reminders.start);
    await show(tester, RemindersPage(controller: reminders));
    expect(edgeOf(tester, find.byType(AppBar)), MotionEdge.top);
    expect(edgeOf(tester, find.byKey(const Key('reminders-empty'))), MotionEdge.right);
    expect(edgeOf(tester, find.byKey(const Key('reminder-new'))), MotionEdge.bottom);
  });
}
