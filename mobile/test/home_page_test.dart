import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/device_info.dart';
import 'package:kyora_chat/data/task_store.dart';
import 'package:kyora_chat/data/wallpaper_store.dart';
import 'package:kyora_chat/data/weather_service.dart';
import 'package:kyora_chat/data/weather_store.dart';
import 'package:kyora_chat/state/task_controller.dart';
import 'package:kyora_chat/state/wallpaper_controller.dart';
import 'package:kyora_chat/state/weather_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/home_page.dart';
import 'package:kyora_chat/ui/widgets/app_backdrop.dart';
import 'package:kyora_chat/util/palette.dart';

import 'task_controller_test.dart' show FakeTaskBackend;
import 'weather_test.dart' show FakeWeather;

class FakeDevice implements DeviceInfo {
  FakeDevice(this.info);

  StorageInfo? info;

  @override
  Future<StorageInfo?> storage() async => info;
}

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

  Future<void> open(
    WidgetTester tester, {
    int opened = 0,
    List<void Function()>? taps,
    StorageInfo? storage = const StorageInfo(total: 128 * 1024 * 1024 * 1024, free: 40 * 1024 * 1024 * 1024),
    WallpaperController? wallpaper,
    bool withTasks = true,
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
        weather: weather,
        device: FakeDevice(storage),
        wallpaper: wallpaper,
        now: () => DateTime(2026, 11, 3, 9, 30), // un martes
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('cabecera', () {
    testWidgets('arriba a la izquierda el día de la semana y la fecha con el año', (tester) async {
      await open(tester);
      expect(find.text('Martes'), findsOneWidget);
      expect(find.text('3 de noviembre de 2026'), findsOneWidget);
      final weekday = tester.getTopLeft(find.byKey(const Key('home-weekday')));
      expect(weekday.dx, lessThan(40)); // pegado a la izquierda
      expect(weekday.dy, lessThan(120)); // y arriba
      expect(tester.getTopLeft(find.byKey(const Key('home-date'))).dy, greaterThan(weekday.dy)); // la fecha, debajo
    });

    testWidgets('el botón de configuración está arriba a la derecha y avisa al tocarlo', (tester) async {
      final taps = <void Function()>[];
      await open(tester, taps: taps);
      final button = tester.getCenter(find.byKey(const Key('home-settings')));
      expect(button.dx, greaterThan(300));
      await tester.tap(find.byKey(const Key('home-settings')));
      expect(taps, hasLength(1));
    });
  });

  group('tarjetas', () {
    testWidgets('ninguna tiene las esquinas redondeadas', (tester) async {
      await open(tester);
      for (final key in ['home-tasks', 'home-weather', 'home-storage', 'home-settings']) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      final boxes = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
      for (final box in boxes) {
        final decoration = box.decoration;
        if (decoration is BoxDecoration) {
          expect(decoration.borderRadius, isNull);
          expect(decoration.shape, BoxShape.rectangle);
        }
      }
      expect(find.byType(ClipRRect), findsNothing);
    });

    testWidgets('tareas: cuántas hay pendientes y las próximas, con la entrega primero', (tester) async {
      await tester.runAsync(() async {
        await tasks.start();
        await tasks.add('Sin fecha');
        await tasks.add('Entregar informe', due: DateTime.now().toUtc().add(const Duration(days: 3)));
        final done = await tasks.add('Ya hecha');
        await tasks.toggleDone(done!);
      });
      await open(tester);
      expect(tester.widget<Text>(find.byKey(const Key('home-tasks-count'))).data, '2'); // la finalizada no cuenta
      final order = [
        tester.getTopLeft(find.text('Entregar informe')).dy,
        tester.getTopLeft(find.text('Sin fecha')).dy,
      ];
      expect(order[0], lessThan(order[1])); // la que tiene entrega, primero
      expect(find.text('Ya hecha'), findsNothing);
    });

    testWidgets('tareas: sin ninguna dice que todo está al día', (tester) async {
      await open(tester);
      expect(tester.widget<Text>(find.byKey(const Key('home-tasks-count'))).data, '0');
      expect(find.byKey(const Key('home-tasks-empty')), findsOneWidget);
    });

    testWidgets('sin servicio de tareas no hay tarjeta de tareas', (tester) async {
      await open(tester, withTasks: false);
      expect(find.byKey(const Key('home-tasks')), findsNothing);
    });

    testWidgets('clima: sin ciudad invita a elegirla y al tocar abre la configuración', (tester) async {
      final taps = <void Function()>[];
      await open(tester, taps: taps);
      expect(find.byKey(const Key('home-weather-nocity')), findsOneWidget);
      await tester.tap(find.byKey(const Key('home-weather')));
      expect(taps, hasLength(1));
    });

    testWidgets('clima: con ciudad enseña grados, cielo y ciudad', (tester) async {
      await tester.runAsync(() => weather.setCity('Lima'));
      await open(tester);
      expect(find.text('19°C'), findsOneWidget);
      expect(find.text('Nublado'), findsOneWidget);
      expect(find.text('Lima'), findsOneWidget);
    });

    testWidgets('clima: una ciudad que no se encuentra lo avisa', (tester) async {
      backend.error = const CityNotFound('Xyzzy');
      await tester.runAsync(() => weather.setCity('Xyzzy'));
      await open(tester);
      expect(find.byKey(const Key('home-weather-unknown')), findsOneWidget);
    });

    testWidgets('almacenamiento: lo libre, el total y la barra de lo usado', (tester) async {
      await open(tester);
      expect(find.text('40,0 GB'), findsOneWidget);
      expect(find.text('libres de 128,0 GB'), findsOneWidget);
      final bar = tester.getSize(find.byKey(const Key('home-storage-bar')));
      final track = tester.getSize(find.byKey(const Key('home-storage')));
      expect(bar.width, greaterThan(0));
      expect(bar.width, lessThan(track.width));
    });

    testWidgets('almacenamiento: si el teléfono no lo da, lo dice', (tester) async {
      await open(tester, storage: null);
      expect(find.byKey(const Key('home-storage-none')), findsOneWidget);
    });
  });

  group('colores del fondo', () {
    testWidgets('con un fondo puesto, sus 5 colores se ven bajo la fecha; sin fondo, no', (tester) async {
      final wallpaper = WallpaperController(wallpaperStore, lookup: (_) async => const [Color(0xFF112233), Color(0xFF445566), Color(0xFF778899), Color(0xFFAABBCC), Color(0xFFDDEEFF)]);
      await open(tester, wallpaper: wallpaper);
      expect(find.byKey(const Key('palette-strip')), findsNothing);
      await tester.runAsync(() => wallpaper.set('/foto.jpg'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('palette-strip')), findsOneWidget);
      for (var i = 0; i < 5; i++) {
        expect(find.byKey(Key('palette-$i')), findsOneWidget);
      }
      final first = tester.widget<Container>(find.byKey(const Key('palette-0'))).decoration as BoxDecoration;
      expect(first.color, const Color(0xFF112233));
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

    testWidgets('con fondo se ve la imagen, muy pequeña (suavizada) y con el velo oscuro encima', (tester) async {
      final wallpaper = WallpaperController(wallpaperStore, lookup: (_) async => const [Color(0xFF112233), Color(0xFF445566), Color(0xFF778899), Color(0xFFAABBCC), Color(0xFFDDEEFF)]);
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
