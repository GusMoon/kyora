import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/task_store.dart';
import 'package:kyora_chat/data/wallpaper_store.dart';
import 'package:kyora_chat/data/weather_service.dart';
import 'package:kyora_chat/data/weather_store.dart';
import 'package:kyora_chat/models/task.dart';
import 'package:kyora_chat/state/task_controller.dart';
import 'package:kyora_chat/state/wallpaper_controller.dart';
import 'package:kyora_chat/state/weather_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/home_page.dart';
import 'package:kyora_chat/ui/section_host.dart';
import 'package:kyora_chat/ui/widgets/app_backdrop.dart';
import 'package:kyora_chat/ui/widgets/notched_card.dart';
import 'package:kyora_chat/ui/widgets/app_section.dart';
import 'package:kyora_chat/util/palette.dart';

import 'task_controller_test.dart' show FakeTaskBackend;
import 'weather_test.dart' show FakeWeather;

const _five = [Color(0xFF112233), Color(0xFF445566), Color(0xFF778899), Color(0xFFAABBCC), Color(0xFFDDEEFF)];

void main() {
  late TaskController tasks;
  late FakeWeather backend;
  late WeatherController weather;
  late MemoryWallpaperStore wallpaperStore;
  var n = 0;

  setUp(() {
    n = 0;
    tasks = TaskController(MemoryTaskStore(), FakeTaskBackend(), newId: () => 'id-${++n}', retry: const Duration(hours: 1));
    backend = FakeWeather();
    weather = WeatherController(backend, MemoryWeatherStore());
    wallpaperStore = MemoryWallpaperStore();
  });

  tearDown(() {
    tasks.dispose();
    weather.dispose();
  });

  // un martes
  final tuesday = DateTime(2026, 11, 3, 9, 30);

  Future<void> open(
    WidgetTester tester, {
    List<void Function()>? taps,
    bool withTasks = true,
    bool withWeather = true,
    DateTime? now,
  }) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (withTasks) await tester.runAsync(tasks.start);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: HomePage(
        onOpenSettings: () => taps?.add(() {}),
        tasks: withTasks ? Future.value(tasks) : null,
        weather: withWeather ? weather : null,
        now: () => now ?? tuesday,
      ),
    ));
    await tester.pumpAndSettle();
  }

  String text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

  group('cabecera', () {
    testWidgets('primero la fecha como «Mes Día, año», debajo el saludo y debajo los días, todo a la izquierda', (tester) async {
      await open(tester);
      expect(text(tester, 'home-date'), 'Noviembre 3, 2026');
      final date = tester.getTopLeft(find.byKey(const Key('home-date')));
      final greeting = tester.getTopLeft(find.byKey(const Key('home-greeting')));
      final days = tester.getTopLeft(find.byKey(const Key('home-day-1')));
      expect(date.dx, lessThan(40));
      expect(greeting.dx, date.dx);
      expect(days.dx, lessThanOrEqualTo(date.dx + 8));
      expect(date.dy, lessThan(greeting.dy));
      expect(greeting.dy, lessThan(days.dy));
    });

    testWidgets('el saludo lleva el nombre fijo «Señor Marrufo»', (tester) async {
      await open(tester);
      expect(text(tester, 'home-greeting'), 'Buenos días,\nSeñor Marrufo');
    });

    for (final (hour, saludo) in [(5, 'Buenos días'), (11, 'Buenos días'), (12, 'Buenas tardes'), (18, 'Buenas tardes'), (19, 'Buenas noches'), (23, 'Buenas noches'), (4, 'Buenas noches')]) {
      testWidgets('a las $hour h dice «$saludo»', (tester) async {
        await open(tester, now: DateTime(2026, 11, 3, hour, 15));
        expect(text(tester, 'home-greeting'), startsWith('$saludo,'));
      });
    }

    testWidgets('los días de la semana son L M M J V S D y solo el de hoy va remarcado', (tester) async {
      await open(tester);
      final letters = [
        for (var day = 1; day <= 7; day++) tester.widget<Text>(find.descendant(of: find.byKey(Key('home-day-$day')), matching: find.byType(Text))).data,
      ];
      expect(letters, ['L', 'M', 'M', 'J', 'V', 'S', 'D']);
      for (var day = 1; day <= 7; day++) {
        final box = tester.widget<Container>(find.byKey(Key('home-day-$day')));
        final label = tester.widget<Text>(find.descendant(of: find.byKey(Key('home-day-$day')), matching: find.byType(Text)));
        final today = day == 2; // martes
        expect(box.decoration != null, today, reason: 'marca del día $day');
        expect(label.style!.fontWeight, today ? FontWeight.w800 : FontWeight.w500, reason: 'negrita del día $day');
      }
    });

    testWidgets('el día remarcado cambia con la fecha (domingo = la última letra)', (tester) async {
      await open(tester, now: DateTime(2026, 11, 8, 20));
      expect(tester.widget<Container>(find.byKey(const Key('home-day-7'))).decoration, isNotNull);
      expect(tester.widget<Container>(find.byKey(const Key('home-day-2'))).decoration, isNull);
    });

    testWidgets('el botón de configuración está arriba a la derecha, es redondo y avisa al tocarlo', (tester) async {
      final taps = <void Function()>[];
      await open(tester, taps: taps);
      final rect = tester.getRect(find.byKey(const Key('home-settings')));
      expect(rect.center.dx, greaterThan(300));
      expect(rect.top, lessThan(120));
      expect(rect.width, rect.height);
      await tester.tap(find.byKey(const Key('home-settings')));
      expect(taps, hasLength(1));
    });

    testWidgets('ya no hay día grande ni fecha larga, ni almacenamiento, ni franja de colores', (tester) async {
      await open(tester);
      expect(find.text('Martes'), findsNothing);
      expect(find.text('3 de noviembre de 2026'), findsNothing);
      expect(find.byKey(const Key('home-storage')), findsNothing);
      expect(find.byKey(const Key('palette-strip')), findsNothing); // los colores se ven en Configuración
    });
  });

  group('tarjeta de tareas con el clima en la muesca', () {
    testWidgets('abajo del todo y a todo el ancho, con la forma de la muesca', (tester) async {
      await open(tester);
      final card = tester.getRect(find.byKey(const Key('notched-card')));
      expect(card.bottom, greaterThan(850 - 60)); // pegada abajo
      expect(card.left, 16);
      expect(card.right, 384);
      expect(card.height, 376);
    });

    testWidgets('el clima ocupa la muesca: arriba a la derecha de la tarjeta, con su separación', (tester) async {
      await open(tester);
      final card = tester.getRect(find.byKey(const Key('notched-card')));
      final tile = tester.getRect(find.byKey(const Key('home-weather')));
      final expected = NotchShape.tileRect(card.size).shift(card.topLeft);
      expect(tile.left, closeTo(expected.left, 0.5));
      expect(tile.top, closeTo(expected.top, 0.5));
      expect(tile.right, closeTo(card.right, 0.5)); // al borde de la derecha
      expect(tile.top, closeTo(card.top, 0.5)); // y al de arriba
      expect(tile.bottom, lessThan(card.top + NotchShape.notchHeight)); // sin tocar el fondo de la muesca
    });

    test('la forma: esquinas redondeadas, muesca arriba a la derecha y esquinas cóncavas dentro', () {
      const size = Size(368, 376);
      final path = NotchShape.pathFor(size);
      final a = NotchShape.notchLeft(size.width);
      expect(path.contains(const Offset(50, 50)), isTrue); // el cuerpo de arriba a la izquierda
      expect(path.contains(const Offset(184, 300)), isTrue); // el cuerpo de abajo
      expect(path.contains(Offset(size.width - 20, NotchShape.notchHeight + 40)), isTrue); // a la derecha, debajo de la muesca
      expect(path.contains(Offset(size.width - 40, 60)), isFalse); // la muesca está vacía
      expect(path.contains(Offset(a + 40, 10)), isFalse);
      expect(path.contains(const Offset(1, 1)), isFalse); // esquina de arriba a la izquierda, redondeada
      expect(path.contains(Offset(1, size.height - 1)), isFalse); // abajo a la izquierda
      expect(path.contains(Offset(size.width - 1, size.height - 1)), isFalse); // abajo a la derecha
      expect(path.contains(Offset(a - 1, 1)), isFalse); // esquina de arriba, junto a la muesca
      // la esquina de dentro de la muesca es cóncava: justo en el rincón, con una esquina viva no habría tarjeta; con una redondeada sí
      expect(path.contains(Offset(a + 4, NotchShape.notchHeight - 4)), isTrue);
      expect(path.contains(Offset(size.width - 1, NotchShape.notchHeight + 1)), isFalse); // y la de debajo, a la derecha, redondeada
    });

    testWidgets('lo pendiente en grande y las cifras de en curso y hechas', (tester) async {
      await tester.runAsync(() async {
        await tasks.start();
        await tasks.add('Una');
        await tasks.add('Dos');
        final doing = await tasks.add('Tres');
        await tasks.setStatus(doing!, TaskStatus.doing);
        final done = await tasks.add('Cuatro');
        await tasks.toggleDone(done!);
      });
      await open(tester);
      expect(text(tester, 'home-tasks-count'), '3'); // la finalizada no cuenta
      expect(find.descendant(of: find.byKey(const Key('home-tasks-doing')), matching: find.text('1')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('home-tasks-done')), matching: find.text('1')), findsOneWidget);
      expect(find.text('Pendientes'), findsOneWidget);
      expect(find.text('En curso'), findsOneWidget);
      expect(find.text('Hechas'), findsOneWidget);
    });

    testWidgets('a la izquierda de la muesca, la próxima tarea (la que tiene entrega, primero)', (tester) async {
      await tester.runAsync(() async {
        await tasks.start();
        await tasks.add('Sin fecha');
        await tasks.add('Entregar informe', due: DateTime.now().toUtc().add(const Duration(days: 3)));
      });
      await open(tester);
      expect(text(tester, 'home-next-name'), 'Entregar informe');
      final name = tester.getRect(find.byKey(const Key('home-next-name')));
      final tile = tester.getRect(find.byKey(const Key('home-weather')));
      expect(name.right, lessThanOrEqualTo(tile.left)); // al lado de la muesca, no debajo del clima
    });

    testWidgets('sin ninguna tarea dice que todo está al día', (tester) async {
      await open(tester);
      expect(text(tester, 'home-tasks-count'), '0');
      expect(find.byKey(const Key('home-tasks-empty')), findsOneWidget);
      expect(find.byKey(const Key('home-next-name')), findsNothing);
    });

    testWidgets('«Tareas» es el título y el botón redondo de al lado abre esa sección', (tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(tasks.start);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: SectionHost(sections: [
          AppSection(id: 'home', icon: Icons.home_outlined, label: 'Inicio', builder: (_) => HomePage(onOpenSettings: () {}, tasks: Future.value(tasks), weather: weather, now: () => tuesday)),
          AppSection(id: 'tasks', icon: Icons.checklist_rounded, label: 'Tareas', builder: (_) => const Scaffold(body: Center(child: Text('Pantalla Tareas')))),
        ]),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Tareas'), findsOneWidget);
      await tester.tap(find.byKey(const Key('home-open-tasks')));
      await tester.pumpAndSettle();
      expect(find.text('Pantalla Tareas'), findsOneWidget);
    });

    testWidgets('sin servicio de tareas no hay tarjeta y el clima queda solo', (tester) async {
      await open(tester, withTasks: false);
      expect(find.byKey(const Key('notched-card')), findsNothing);
      expect(find.byKey(const Key('home-weather')), findsOneWidget);
    });
  });

  group('clima', () {
    testWidgets('sin ciudad invita a elegirla y al tocar abre la configuración', (tester) async {
      final taps = <void Function()>[];
      await open(tester, taps: taps);
      expect(find.byKey(const Key('home-weather-nocity')), findsOneWidget);
      await tester.tap(find.byKey(const Key('home-weather')));
      expect(taps, hasLength(1));
    });

    testWidgets('con ciudad enseña grados, cielo y ciudad', (tester) async {
      await tester.runAsync(() => weather.setCity('Lima'));
      await open(tester);
      expect(find.text('19°C'), findsOneWidget);
      expect(find.text('Nublado'), findsOneWidget);
      expect(find.text('Lima'), findsOneWidget);
    });

    testWidgets('una ciudad que no se encuentra lo avisa', (tester) async {
      backend.error = const CityNotFound('Xyzzy');
      await tester.runAsync(() => weather.setCity('Xyzzy'));
      await open(tester);
      expect(find.byKey(const Key('home-weather-unknown')), findsOneWidget);
    });
  });

  group('cristal sin color', () {
    testWidgets('la tarjeta grande, el clima y el botón de configuración difuminan lo de detrás y no llevan relleno', (tester) async {
      await open(tester);
      // la tarjeta grande
      expect(find.ancestor(of: find.byKey(const Key('notched-card')), matching: find.byType(BackdropFilter)), findsOneWidget);
      // el clima y el botón de configuración son GlassCard: cada uno con su difuminado
      expect(find.byType(BackdropFilter), findsNWidgets(3));
      final cards = tester.widgetList<DecoratedBox>(find.byKey(const Key('glass-card'))).toList();
      expect(cards, hasLength(2));
      for (final card in cards) {
        final decoration = card.decoration as BoxDecoration;
        expect(decoration.color, isNull); // sin color de fondo
        expect(decoration.borderRadius, isNotNull); // con las esquinas redondeadas
      }
    });

    testWidgets('el pintado de la tarjeta grande es solo borde: el relleno no existe', (tester) async {
      await open(tester);
      final paint = tester.widget<CustomPaint>(find.byKey(const Key('notched-card')));
      expect(paint.painter, isNull); // nada pintado debajo (sin fondo)
      expect(paint.foregroundPainter, isNotNull); // solo el borde, por encima
    });
  });

  group('fondo de la app: nítido arriba, efecto desde abajo (el mismo en todas las secciones)', () {
    test('el efecto cubre el 70 % de abajo: nítido hasta el 30 % y luego se va perdiendo hasta 0 abajo', () {
      expect(AppBackdrop.sharpUntil, 0.30);
      expect(AppBackdrop.sharpStops.length, AppBackdrop.sharpAlphas.length);
      final at = AppBackdrop.sharpStops.indexOf(AppBackdrop.sharpUntil);
      expect(at, greaterThan(0));
      expect(AppBackdrop.sharpAlphas.sublist(0, at + 1), everyElement(1.0)); // hasta la línea, la foto del todo nítida
      expect(AppBackdrop.sharpAlphas.last, 0.0); // abajo, solo el fondo con el efecto completo
      for (var i = 1; i < AppBackdrop.sharpAlphas.length; i++) {
        expect(AppBackdrop.sharpAlphas[i], lessThanOrEqualTo(AppBackdrop.sharpAlphas[i - 1])); // el efecto solo crece al bajar
        expect(AppBackdrop.sharpStops[i], greaterThan(AppBackdrop.sharpStops[i - 1]));
      }
    });

    testWidgets('con un fondo puesto hay una capa nítida (con la foto al ancho de la pantalla); sin fondo, no', (tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final wallpaper = WallpaperController(wallpaperStore, lookup: (_) async => _five);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), builder: (context, child) => AppBackdrop(wallpaper: wallpaper, child: child!), home: const SizedBox()));
      expect(find.byKey(const Key('backdrop-sharp')), findsNothing);
      await tester.runAsync(() => wallpaper.set('/no-existe.jpg'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('backdrop-sharp')), findsOneWidget);
      final image = tester.widget<Image>(find.byKey(const Key('backdrop-sharp-image')));
      expect((image.image as ResizeImage).width, 400); // el ancho de la pantalla, no los 96 px del fondo suavizado
      expect(find.byKey(const Key('backdrop-sharp-veil')), findsOneWidget); // y el velo de arriba para leer el texto
      await tester.runAsync(wallpaper.clear);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('backdrop-sharp')), findsNothing);
    });

    testWidgets('el fondo no está en Inicio sino en toda la app: Inicio no pinta ninguna foto propia', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('backdrop-sharp')), findsNothing);
      expect(find.byType(Image), findsNothing);
    });
  });

  group('fondo de la app', () {
    testWidgets('sin fondo es un gris muy oscuro, sin imagen', (tester) async {
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), builder: (context, child) => AppBackdrop(child: child!), home: const SizedBox()));
      expect(find.byKey(const Key('app-backdrop')), findsOneWidget);
      expect(find.byKey(const Key('wallpaper-image')), findsNothing);
      final decoration = tester.widget<DecoratedBox>(find.byKey(const Key('app-backdrop'))).decoration as BoxDecoration;
      final top = (decoration.gradient! as LinearGradient).colors.first;
      expect(HSLColor.fromColor(top).lightness, lessThan(0.1)); // muy oscuro
      expect(HSLColor.fromColor(top).saturation, lessThan(0.1)); // y sin tinte
    });

    testWidgets('el efecto completo: sin la foto nítida, con la imagen suavizada y un velo más oscuro que el de Inicio', (tester) async {
      final wallpaper = WallpaperController(wallpaperStore, lookup: (_) async => _five);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: BackdropLayers(wallpaper: wallpaper, full: true)));
      await tester.runAsync(() => wallpaper.set('/no-existe.jpg'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('backdrop-sharp')), findsNothing);
      expect(find.byKey(const Key('backdrop-sharp-image')), findsNothing);
      final image = tester.widget<Image>(find.byKey(const Key('backdrop-full-image')));
      expect((image.image as ResizeImage).width, AppBackdrop.decodeWidth);
      final veil = tester.widget<DecoratedBox>(find.byKey(const Key('backdrop-full-veil'))).decoration as BoxDecoration;
      final colors = (veil.gradient! as LinearGradient).colors;
      expect(colors, AppBackdrop.fullVeil);
      expect(colors.first.a, greaterThanOrEqualTo(0.65)); // el de Inicio va de 50 % a 65 %
      expect(colors.last.a, greaterThan(0.65));
      await tester.runAsync(wallpaper.clear);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('backdrop-full-image')), findsNothing);
      expect(find.byKey(const Key('backdrop-full-veil')), findsOneWidget); // sin imagen, el gris también se oscurece
      expect(find.byKey(const Key('app-backdrop')), findsNothing);
    });

    testWidgets('una pantalla empujada lleva el efecto completo detrás, no la foto nítida', (tester) async {
      final wallpaper = WallpaperController(wallpaperStore, lookup: (_) async => _five);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), builder: (context, child) => AppBackdrop(wallpaper: wallpaper, child: child!), home: const Scaffold(body: Text('abajo'))));
      await tester.runAsync(() => wallpaper.set('/no-existe.jpg'));
      await tester.pumpAndSettle();
      unawaited(Navigator.of(tester.element(find.text('abajo'))).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('encima')))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('backdrop-full-image')), findsOneWidget);
      await tester.runAsync(wallpaper.clear);
      await tester.pumpAndSettle();
    });

    testWidgets('con fondo se ve la imagen, muy pequeña (suavizada) y con el velo oscuro encima', (tester) async {
      final wallpaper = WallpaperController(wallpaperStore, lookup: (_) async => _five);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), builder: (context, child) => AppBackdrop(wallpaper: wallpaper, child: child!), home: const SizedBox()));
      await tester.runAsync(() => wallpaper.set('/no-existe.jpg'));
      await tester.pumpAndSettle();
      final image = tester.widget<Image>(find.byKey(const Key('wallpaper-image')));
      expect((image.image as ResizeImage).width, AppBackdrop.decodeWidth);
      final veil = tester.widget<DecoratedBox>(find.byKey(const Key('wallpaper-veil'))).decoration as BoxDecoration;
      for (final color in (veil.gradient! as LinearGradient).colors) {
        expect(color.a, greaterThanOrEqualTo(0.45)); // lo bastante oscuro para que el texto claro se lea
      }
      await tester.runAsync(wallpaper.clear);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('wallpaper-image')), findsNothing); // vuelve el gris
    });
  });

  testWidgets('paletteOfFile lee una imagen real y devuelve sus 5 colores', (tester) async {
    final dir = Directory.systemTemp.createTempSync('kyra_palette_'); // sincrónico: fuera de `runAsync` un `await` de archivos no termina
    addTearDown(() => dir.deleteSync(recursive: true));
    const bands = [Color(0xFFD62828), Color(0xFF2A9D4F), Color(0xFF1D4ED8), Color(0xFFF2C94C), Color(0xFFF5F5F5)];
    final colors = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      // cinco franjas verticales de ancho distinto: 40, 30, 20, 6 y 4 de cada 100
      var x = 0.0;
      for (final (i, width) in [40.0, 30.0, 20.0, 6.0, 4.0].indexed) {
        canvas.drawRect(Rect.fromLTWH(x, 0, width, 100), Paint()..color = bands[i]);
        x += width;
      }
      final image = await recorder.endRecording().toImage(100, 100);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final file = File('${dir.path}/fondo.png')..writeAsBytesSync(bytes.buffer.asUint8List());
      return paletteOfFile(file.path);
    });
    expect(colors, isNotNull);
    expect(colors!, hasLength(5));
    // al reducir la imagen los bordes de las franjas se mezclan un poco: cada color sale a pocos puntos del original
    bool near(Color a, Color b) => [a.r - b.r, a.g - b.g, a.b - b.b].every((d) => d.abs() * 255 <= 12);
    expect(near(colors.first, bands.first), isTrue, reason: 'el que más ocupa es el primero: ${colors.first}');
    for (final band in bands) {
      expect(colors.any((c) => near(c, band)), isTrue, reason: '$band no está en $colors');
    }
  });
}
