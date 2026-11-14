import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/dock_store.dart';
import 'package:kyora_chat/data/installed_apps.dart';
import 'package:kyora_chat/data/system_info.dart';
import 'package:kyora_chat/data/wallpaper_store.dart';
import 'package:kyora_chat/data/weather_service.dart';
import 'package:kyora_chat/data/weather_store.dart';
import 'package:kyora_chat/state/dock_controller.dart';
import 'package:kyora_chat/state/system_controller.dart';
import 'package:kyora_chat/state/wallpaper_controller.dart';
import 'package:kyora_chat/state/weather_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/home_page.dart';
import 'package:kyora_chat/ui/section_host.dart';
import 'package:kyora_chat/ui/widgets/app_section.dart';
import 'package:kyora_chat/ui/widgets/cyber_panel.dart';
import 'package:kyora_chat/ui/widgets/radial_menu.dart';
import 'package:kyora_chat/ui/widgets/app_backdrop.dart';
import 'package:kyora_chat/ui/widgets/home_clock.dart' show softFade, softStops;
import 'package:kyora_chat/ui/widgets/mode_tabs.dart';
import 'package:kyora_chat/ui/widgets/pixel_glyph.dart';
import 'package:kyora_chat/util/format.dart';
import 'package:kyora_chat/util/wallpaper_color.dart';

import 'sections.dart' show drawCircle;
import 'weather_test.dart' show FakeWeather;

/// Un lunes (el 9 de noviembre de 2026), por la mañana.
final monday = DateTime(2026, 11, 9, 9, 30);

/// Un PNG de un punto: lo justo para que las ranuras tengan un icono que pintar.
final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

InstalledApp app(String package, String label) => InstalledApp(package: package, label: label, icon: Uint8List.fromList(_png));

/// La ruta de un archivo de imagen (`Image.file`, con o sin `cacheWidth`), o `null` si la imagen no es de un archivo.
String? _fileOf(ImageProvider image) {
  final inner = image is ResizeImage ? image.imageProvider : image;
  return inner is FileImage ? inner.file.path : null;
}

void main() {
  late FakeWeather backend;
  late WeatherController weather;
  late FakeInstalledApps apps;
  late MemoryDockStore dockStore;
  late DockController dock;
  late FakeSystemInfo info;
  late SystemController system;

  setUp(() {
    info = FakeSystemInfo(const SystemStats(battery: 82, charging: true, ramTotal: 8000, ramFree: 2000, storageTotal: 128 * 1024 * 1024 * 1024, storageFree: 40 * 1024 * 1024 * 1024, wifi: true, bluetooth: false, mobileData: true));
    system = SystemController(info, every: const Duration(hours: 1));
    backend = FakeWeather();
    weather = WeatherController(backend, MemoryWeatherStore());
    apps = FakeInstalledApps([for (var i = 1; i <= 10; i++) app('com.app$i', 'App $i')]);
    dockStore = MemoryDockStore();
    dock = DockController(dockStore, apps);
  });

  tearDown(() {
    weather.dispose();
    dock.dispose();
    system.dispose();
  });

  Future<void> open(
    WidgetTester tester, {
    bool withWeather = true,
    bool withDock = true,
    WallpaperController? wallpaper,
    DateTime Function()? now,
    List<void Function()>? taps,
    Future<void> Function()? seed,
    Size size = const Size(400, 850),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async => seed?.call());
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      builder: (context, child) => AppBackdrop(wallpaper: wallpaper, child: child!),
      home: HomePage(
        key: UniqueKey(),
        onOpenSettings: () => taps?.add(() {}),
        weather: withWeather ? weather : null,
        dock: withDock ? dock : null,
        system: system,
        now: now ?? () => monday,
      ),
    ));
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
  }

  String text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

  test('la fecha larga: día abreviado, día del mes y mes en palabras', () {
    expect(longDate(DateTime(2026, 11, 9)), 'Lun, 9 de noviembre');
    expect(longDate(DateTime(2026, 12, 31)), 'Jue, 31 de diciembre');
    expect(longDate(DateTime(2027, 3, 7)), 'Dom, 7 de marzo');
  });

  group('el tablero: una cuadrícula de 2 × 2', () {
    testWidgets('cuatro paneles: la hora, el clima, el sistema y los accesos rápidos, en dos filas de dos', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('home-grid')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('home-grid')), matching: find.byType(CyberPanel)), findsNWidgets(4));
      final time = tester.getRect(find.byKey(const Key('home-time')));
      final weatherBox = tester.getRect(find.byKey(const Key('home-weather')));
      final systemBox = tester.getRect(find.byKey(const Key('home-system')));
      final quick = tester.getRect(find.byKey(const Key('home-quick')));
      expect(time.center.dx, lessThan(200)); // arriba a la izquierda
      expect(weatherBox.center.dx, greaterThan(200)); // arriba a la derecha
      expect(systemBox.center.dx, lessThan(200)); // abajo a la izquierda
      expect(quick.center.dx, greaterThan(200)); // abajo a la derecha
      expect(systemBox.top, greaterThan(time.bottom));
      expect(quick.top, greaterThan(weatherBox.bottom - 1));
      // ya no hay disco de apps ni lista alfabética
      expect(find.byKey(const Key('app-disc')), findsNothing);
      expect(find.byKey(const Key('disc-center')), findsNothing);
    });

    testWidgets('la hora y la fecha', (tester) async {
      await open(tester);
      expect(text(tester, 'home-time'), '09:30');
      expect(text(tester, 'home-date'), 'Lun, 9 de noviembre');
    });

    testWidgets('la hora cambia sola al pasar el minuto', (tester) async {
      var now = DateTime(2026, 11, 9, 9, 30, 50);
      await open(tester, now: () => now);
      expect(text(tester, 'home-time'), '09:30');
      now = DateTime(2026, 11, 9, 9, 31, 1);
      await tester.pump(const Duration(seconds: 11));
      expect(text(tester, 'home-time'), '09:31');
    });

    testWidgets('sin ciudad invita a elegirla y al tocar abre la configuración', (tester) async {
      final taps = <void Function()>[];
      await open(tester, taps: taps);
      expect(text(tester, 'home-weather-text'), 'Elige tu ciudad');
      await tester.tap(find.byKey(const Key('home-weather')));
      expect(taps, hasLength(1));
    });

    testWidgets('con ciudad enseña el icono, los grados, el cielo y la ciudad', (tester) async {
      await open(tester, seed: () => weather.setCity('Lima'));
      expect(text(tester, 'home-weather-temp'), '19°');
      expect(text(tester, 'home-weather-text'), 'Nublado');
      expect(tester.widget<PixelIcon>(find.descendant(of: find.byKey(const Key('home-weather')), matching: find.byType(PixelIcon))).glyph, PixelGlyphs.cloud);
    });

    testWidgets('una ciudad que no se encuentra lo avisa', (tester) async {
      backend.error = const CityNotFound('Xyzzy');
      await open(tester, seed: () => weather.setCity('Xyzzy'));
      expect(text(tester, 'home-weather-text'), 'No encontré «Xyzzy»');
    });

    testWidgets('el sistema: batería (cargando), memoria en uso y almacenamiento libre', (tester) async {
      await open(tester);
      expect(text(tester, 'BAT-value'), '82%+');
      expect(text(tester, 'RAM-value'), '75%');
      expect(text(tester, 'ALM-value'), '40,0 GB');
      expect(info.reads, greaterThan(0));
    });

    testWidgets('sin datos del sistema enseña guiones y no falla', (tester) async {
      info.current = null;
      await open(tester);
      expect(text(tester, 'BAT-value'), '--');
      expect(text(tester, 'WI-FI-state'), '--');
    });

    testWidgets('los accesos rápidos dicen si el Wi-Fi, los datos y el Bluetooth están encendidos y al tocarlos abren su panel del sistema', (tester) async {
      await open(tester);
      expect(text(tester, 'WI-FI-state'), 'ON');
      expect(text(tester, 'DATOS-state'), 'ON');
      expect(text(tester, 'BT-state'), 'OFF');
      await tester.tap(find.byKey(const Key('quick-wifi')));
      await tester.tap(find.byKey(const Key('quick-data')));
      await tester.tap(find.byKey(const Key('quick-bluetooth')));
      await tester.runAsync(pumpEventQueue);
      expect(info.opened, ['wifi', 'internet', 'bluetooth']);
    });

    testWidgets('mantener el Wi-Fi abre los ajustes de red y mantener los datos, los ajustes de datos (sin tocar el panel)', (tester) async {
      await open(tester);
      await tester.longPress(find.byKey(const Key('quick-wifi')));
      await tester.longPress(find.byKey(const Key('quick-data')));
      await tester.runAsync(pumpEventQueue);
      expect(info.opened, ['network', 'data']);
    });

    testWidgets('sin saber lo de los datos enseña guiones', (tester) async {
      info.current = const SystemStats(battery: 50, wifi: false);
      await open(tester);
      expect(text(tester, 'DATOS-state'), '--');
      expect(text(tester, 'WI-FI-state'), 'OFF');
    });

    testWidgets('con ciudad, tocar el clima enseña el detalle: ahora, máxima y mínima, el amanecer y el día hora a hora', (tester) async {
      backend.result = Weather(
        city: 'Lima',
        temperature: 21,
        code: 61,
        time: DateTime(2026, 11, 9, 9, 15),
        humidity: 70,
        wind: 12,
        high: 24.4,
        low: 17.2,
        sunrise: DateTime(2026, 11, 9, 5, 40),
        sunset: DateTime(2026, 11, 9, 18, 20),
        hourly: [
          for (var h = 7; h < 24; h++) HourlyForecast(time: DateTime(2026, 11, 9, h), temperature: 15.0 + h / 2, code: h < 12 ? 61 : 3, rainChance: 40, wind: 10, humidity: 70),
        ],
      );
      await open(tester, seed: () => weather.setCity('Lima'));
      await tester.tap(find.byKey(const Key('home-weather')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('focus-panel')), findsOneWidget);
      expect(text(tester, 'weather-detail-temp'), '21°');
      expect(text(tester, 'weather-detail-label'), 'Lluvia');
      expect(text(tester, 'weather-detail-range'), '24° / 17°');
      expect(text(tester, 'weather-detail-humidity'), '70%');
      expect(text(tester, 'weather-detail-wind'), '12 km/h');
      expect(text(tester, 'weather-detail-sunrise'), '05:40');
      expect(text(tester, 'weather-detail-sunset'), '18:20');
      // las horas empiezan en la de ahora (9:00) y no enseñan las que ya pasaron
      expect(find.byKey(const Key('weather-hour-9-9')), findsOneWidget);
      expect(find.byKey(const Key('weather-hour-9-8')), findsNothing);
      expect(find.text('Ahora'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('si lo guardado no trae las horas, el detalle las pide otra vez', (tester) async {
      await open(tester, seed: () => weather.setCity('Lima'));
      backend.asked.clear();
      await tester.tap(find.byKey(const Key('home-weather')));
      await tester.pumpAndSettle();
      expect(backend.asked, ['Lima']);
      expect(find.byKey(const Key('weather-detail-updating')), findsOneWidget);
    });

    testWidgets('al salir de Inicio deja de leer el estado del sistema', (tester) async {
      await open(tester);
      await tester.pumpWidget(const SizedBox());
      final before = info.reads;
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      expect(info.reads, before);
    });

    testWidgets('en una pantalla baja y estrecha no se desborda', (tester) async {
      await open(tester, size: const Size(320, 560), seed: () => weather.setCity('Lima'));
      expect(tester.takeException(), isNull);
    });
  });

  group('el menú circular: un giro del dedo, y elegir', () {
    final went = <String>[];

    Future<void> openInHost(WidgetTester tester) async {
      went.clear();
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(dock.refresh);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: SectionHost(
          dock: dock,
          sections: [
            AppSection(id: 'home', icon: Icons.home_outlined, label: 'Inicio', builder: (context) => HomePage(onOpenSettings: () {}, dock: dock, system: system, now: () => monday)),
            AppSection(id: 'chat', icon: Icons.chat_outlined, label: 'Chat', builder: (_) => const Text('Pantalla chat')),
            AppSection(id: 'music', icon: Icons.music_note_outlined, label: 'Música', builder: (_) => const Text('Pantalla música')),
          ],
          actions: [NavAction(id: 'settings', icon: Icons.settings_outlined, label: 'Configuración', run: (_) => went.add('settings'))],
        ),
      ));
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
    }

    /// Donde se dibuja el círculo: el centro de la pantalla.
    const free = Offset(200, 425);

    Future<void> swirl(WidgetTester tester, {required bool clockwise}) async {
      await drawCircle(tester, center: free, clockwise: clockwise);
      await tester.pumpAndSettle();
    }

    /// Gira el aro abierto con el dedo alrededor de su centro: `clockwise` = a la derecha.
    Future<void> turn(WidgetTester tester, {required bool clockwise}) async {
      const r = 100.0;
      final sign = clockwise ? 1 : -1;
      final gesture = await tester.startGesture(free + const Offset(r, 0));
      for (var i = 1; i <= 12; i++) {
        await gesture.moveTo(free + Offset.fromDirection(sign * i * 0.12, r));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    String label(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('radial-label'))).data!;

    testWidgets('ni un toque ni mantener el dedo lo abren; un giro a la derecha abre el aro de funciones ahí mismo', (tester) async {
      await openInHost(tester);
      await tester.tapAt(free);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('radial-menu')), findsNothing);
      final hold = await tester.startGesture(free);
      await tester.pump(const Duration(seconds: 1));
      await hold.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('radial-menu')), findsNothing);
      await swirl(tester, clockwise: true);
      expect(find.byKey(const Key('radial-menu')), findsOneWidget);
      for (final id in ['home', 'chat', 'music', 'settings']) {
        expect(find.byKey(Key('radial-$id')), findsOneWidget, reason: id);
      }
      expect(label(tester), 'Inicio'); // la sección en la que se está
      expect(find.byKey(const Key('radial-turn-hint')), findsOneWidget);
      final center = tester.getCenter(find.byKey(const Key('radial-label')));
      expect((center - free).distance, lessThan(80)); // el aro va donde se dibujó el círculo
    });

    testWidgets('un giro a la izquierda abre el aro de aplicaciones (las 8 elegidas)', (tester) async {
      await openInHost(tester);
      await swirl(tester, clockwise: false);
      expect(label(tester), 'APPS');
      for (var i = 1; i <= 8; i++) {
        expect(find.byKey(Key('radial-app-com.app$i')), findsOneWidget, reason: 'app $i');
      }
      expect(find.byKey(const Key('radial-app-com.app9')), findsNothing);
      expect(find.byKey(const Key('radial-chat')), findsNothing);
      expect(find.byKey(const Key('radial-all-hint')), findsOneWidget);
    });

    testWidgets('alrededor del reactor el contenido se corta y baja de opacidad (sin oscurecer ni desenfocar); el centro queda libre', (tester) async {
      await openInHost(tester);
      await swirl(tester, clockwise: true);
      expect(find.byType(BackdropFilter), findsNothing);
      final cut = find.byKey(const Key('radial-cut'));
      final path = tester.widget<ClipPath>(cut).clipper!.getClip(const Size(400, 850));
      expect(path.contains(tester.getCenter(find.byKey(const Key('radial-label')))), isFalse);
      expect(path.contains(const Offset(10, 10)), isTrue);
      expect(tester.widget<Opacity>(find.descendant(of: cut, matching: find.byType(Opacity)).first).opacity, lessThan(1));
    });

    testWidgets('tocar una función va a su sección; la acción hace lo suyo', (tester) async {
      await openInHost(tester);
      await swirl(tester, clockwise: true);
      await tester.tapAt(tester.getCenter(find.byKey(const Key('radial-music'))));
      await tester.pumpAndSettle();
      expect(find.text('Pantalla música'), findsOneWidget);
      expect(find.byKey(const Key('radial-menu')), findsNothing);
      await swirl(tester, clockwise: true);
      await tester.tapAt(tester.getCenter(find.byKey(const Key('radial-settings'))));
      await tester.pumpAndSettle();
      expect(went, ['settings']);
    });

    testWidgets('el giro funciona en cualquier sección, no solo en Inicio', (tester) async {
      await openInHost(tester);
      await swirl(tester, clockwise: true);
      await tester.tapAt(tester.getCenter(find.byKey(const Key('radial-chat'))));
      await tester.pumpAndSettle();
      await swirl(tester, clockwise: false);
      expect(label(tester), 'APPS');
    });

    testWidgets('tocar fuera del aro lo cierra sin hacer nada; «atrás» también', (tester) async {
      await openInHost(tester);
      await swirl(tester, clockwise: true);
      await tester.tapAt(const Offset(20, 120));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('radial-menu')), findsNothing);
      expect(find.byType(HomePage), findsOneWidget);
      await swirl(tester, clockwise: true);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('radial-menu')), findsNothing);
      expect(find.byType(HomePage), findsOneWidget);
    });

    testWidgets('girar el aro abierto: a la izquierda enseña las aplicaciones; a la derecha, otra vez las funciones', (tester) async {
      await openInHost(tester);
      await swirl(tester, clockwise: true);
      await turn(tester, clockwise: false);
      expect(label(tester), 'APPS');
      expect(find.byKey(const Key('radial-app-com.app1')), findsOneWidget);
      expect(find.byKey(const Key('radial-chat')), findsNothing);
      await turn(tester, clockwise: true);
      expect(find.byKey(const Key('radial-chat')), findsOneWidget);
      expect(find.byKey(const Key('radial-app-com.app1')), findsNothing);
    });

    testWidgets('tocar una app del aro la abre', (tester) async {
      await openInHost(tester);
      await swirl(tester, clockwise: false);
      await tester.tapAt(tester.getCenter(find.byKey(const Key('radial-app-com.app2'))));
      await tester.pumpAndSettle();
      expect(apps.launched, ['com.app2']);
      expect(find.byKey(const Key('radial-menu')), findsNothing);
    });

    testWidgets('al abrir una app sale antes un efecto de holograma con su icono y su nombre, y la app se lanza al terminar de aparecer', (tester) async {
      await openInHost(tester);
      await swirl(tester, clockwise: false);
      await tester.tapAt(tester.getCenter(find.byKey(const Key('radial-app-com.app2'))));
      await tester.pump(); // el primer cuadro arranca la animación
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('launch-effect')), findsOneWidget);
      expect(find.byKey(const Key('launch-icon')), findsOneWidget);
      expect(find.byKey(const Key('launch-label')), findsOneWidget);
      expect(find.byKey(const Key('launch-bar')), findsOneWidget);
      expect(apps.launched, isEmpty); // todavía no: primero el efecto
      await tester.pump(const Duration(milliseconds: 650)); // ya terminó de aparecer
      expect(apps.launched, ['com.app2']);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('launch-effect')), findsNothing); // y se desvanece
      expect(apps.launched, ['com.app2']); // una sola vez
    });

    testWidgets('mientras se abre una app no se abre otra, «atrás» no hace nada y no sale el menú', (tester) async {
      apps.apps = [app('com.alfa', 'Alfa'), app('com.beta', 'Beta')];
      await openInHost(tester);
      await swirl(tester, clockwise: false);
      await tester.tapAt(tester.getCenter(find.byKey(const Key('radial-app-com.alfa'))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.binding.handlePopRoute(); // «atrás» durante el efecto
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('launch-effect')), findsOneWidget);
      await tester.tapAt(const Offset(200, 400)); // un toque encima: lo absorbe el efecto
      await tester.pumpAndSettle();
      expect(apps.launched, ['com.alfa']);
    });

    testWidgets('al volver a Kyra desde la app el efecto ya no está', (tester) async {
      await openInHost(tester);
      await swirl(tester, clockwise: false);
      await tester.tapAt(tester.getCenter(find.byKey(const Key('radial-app-com.app1'))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700)); // la app ya se lanzó y el efecto se está yendo
      expect(apps.launched, ['com.app1']);
      expect(find.byKey(const Key('launch-effect')), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.byKey(const Key('launch-effect')), findsNothing);
    });

    testWidgets('con las animaciones del sistema quitadas la app se abre directa, sin efecto', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await openInHost(tester);
      await swirl(tester, clockwise: false);
      await tester.tapAt(tester.getCenter(find.byKey(const Key('radial-app-com.app3'))));
      await tester.pump();
      expect(apps.launched, ['com.app3']);
      expect(find.byKey(const Key('launch-effect')), findsNothing);
    });

    testWidgets('tocar el centro del aro de apps (o deslizar hacia arriba desde él) abre todas a pantalla completa, quitando el contenido', (tester) async {
      await openInHost(tester);
      expect(find.byKey(const Key('home-grid')), findsOneWidget);
      await swirl(tester, clockwise: false);
      await tester.tapAt(free);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('all-apps')), findsOneWidget);
      expect(find.byKey(const Key('radial-menu')), findsNothing);
      expect(find.byKey(const Key('home-grid')), findsNothing); // el contenido se quita (queda vivo, pero no se ve)
      expect(find.byKey(const Key('home-grid'), skipOffstage: false), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing); // y nada se oscurece
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('all-apps')), findsNothing);
      expect(find.byKey(const Key('home-grid')), findsOneWidget); // el contenido vuelve
      await swirl(tester, clockwise: false);
      await tester.dragFrom(free, const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('all-apps')), findsOneWidget);
    });

    testWidgets('en todas las apps tocar una letra lleva su primera app a la cima, tocar una app la abre y la cruz cierra', (tester) async {
      apps.apps = [app('com.alfa', 'Alfa'), app('com.beta', 'Beta'), app('com.banco', 'Banco'), app('com.zeta', 'Zeta')];
      await openInHost(tester);
      await swirl(tester, clockwise: false);
      await tester.tapAt(free);
      await tester.pumpAndSettle();
      for (final p in ['alfa', 'beta', 'banco', 'zeta']) {
        expect(find.byKey(Key('arch-app-com.$p')), findsOneWidget, reason: p);
      }
      await tester.tap(find.byKey(const Key('letter-Z')));
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.byKey(const Key('arch-app-com.zeta'))).dx, closeTo(200, 6)); // en la cima
      await tester.tap(find.byKey(const Key('arch-app-com.zeta')));
      await tester.pumpAndSettle();
      expect(apps.launched, ['com.zeta']);
      expect(find.byKey(const Key('all-apps')), findsNothing);
      await swirl(tester, clockwise: false);
      await tester.tapAt(free);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('arch-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('all-apps')), findsNothing);
    });

    testWidgets('al pasar de funciones a apps girando, el hueco y el reactor no se mueven ni se reabren, y el giro se asienta solo al soltar', (tester) async {
      await openInHost(tester);
      await swirl(tester, clockwise: true);
      final cut = find.byKey(const Key('radial-cut'));
      final before = tester.widget<ClipPath>(cut).clipper!.getClip(const Size(400, 850)).getBounds();
      final reactorBefore = tester.getCenter(find.byKey(const Key('radial-reactor')));
      // gira con el dedo hasta pasar a apps, sin soltar
      final gesture = await tester.startGesture(free + const Offset(100, 0));
      for (var i = 1; i <= 12; i++) {
        await gesture.moveTo(free + Offset.fromDirection(-i * 0.12, 100));
        await tester.pump(const Duration(milliseconds: 8));
      }
      expect(label(tester), 'APPS');
      // el hueco sigue igual (no se reinicia la apertura) y el centro del reactor no salta
      expect(tester.widget<ClipPath>(cut).clipper!.getClip(const Size(400, 850)).getBounds(), before);
      expect((tester.getCenter(find.byKey(const Key('radial-reactor'))) - reactorBefore).distance, lessThan(2));
      // las opciones nuevas se materializan en su sitio (parpadeando), no aparecen de golpe
      final app = find.byKey(const Key('radial-app-com.app1'));
      expect(app, findsOneWidget);
      await gesture.up();
      await tester.pump();
      // el giro vuelve a 0 con suavidad: a mitad de camino las opciones aún están desplazadas
      final spot = tester.getCenter(app);
      await tester.pump(const Duration(milliseconds: 60));
      expect((tester.getCenter(app) - spot).distance, greaterThan(0.5));
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.byKey(const Key('radial-app-com.app1'))).dy, lessThan(free.dy)); // la primera arriba, como siempre
    });

    testWidgets('todas las apps se cierran con animación: se van por donde entraron y después vuelve el contenido', (tester) async {
      await openInHost(tester);
      await swirl(tester, clockwise: false);
      await tester.tapAt(free);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-grid')), findsNothing);
      await tester.tap(find.byKey(const Key('arch-close')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byKey(const Key('all-apps')), findsOneWidget); // se están yendo
      expect(find.byKey(const Key('home-grid')), findsNothing); // el contenido aún no vuelve
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const Key('all-apps')), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-grid')), findsOneWidget); // y vuelve materializándose
    });

    test('el giro del dedo alrededor del centro: positivo a la derecha, negativo a la izquierda, sin saltar al cruzar el lado izquierdo', () {
      final g = RadialGeometry(count: 4, bounds: const Rect.fromLTWH(0, 0, 400, 850), touch: const Offset(200, 425));
      expect(g.turnBetween(const Offset(300, 425), const Offset(200, 525)), greaterThan(0)); // de las 3 a las 6: a la derecha
      expect(g.turnBetween(const Offset(200, 525), const Offset(300, 425)), lessThan(0));
      expect(g.turnBetween(const Offset(100, 430), const Offset(100, 420)).abs(), lessThan(0.2)); // cruzando el lado izquierdo
    });
  });

  group('el fondo', () {
    testWidgets('sin fondo no hay imagen; con fondo sale la imagen a pantalla completa', (tester) async {
      final store = MemoryWallpaperStore();
      final wallpaper = WallpaperController(store);
      addTearDown(wallpaper.dispose);
      await open(tester, wallpaper: wallpaper);
      List<Image> shown() => [for (final e in find.byType(Image).evaluate()) if (_fileOf((e.widget as Image).image) != null) e.widget as Image];
      expect(shown(), isEmpty);
      await tester.runAsync(() => wallpaper.set('C:/fondo.jpg'));
      await tester.pump();
      expect(shown(), hasLength(1));
      expect(_fileOf(shown().single.image), 'C:/fondo.jpg');
      expect(shown().single.fit, BoxFit.cover);
      await tester.runAsync(wallpaper.clear);
      await tester.pump();
      expect(shown(), isEmpty);
    });

    testWidgets('no hay barra de pestañas', (tester) async {
      await open(tester);
      expect(find.byType(ModeTabs), findsNothing);
    });

    test('el degradado suave (lo usa la consola del calendario) baja con una curva y acaba en 0', () {
      final colors = softFade(0.9);
      expect(colors.first.a, closeTo(0.9, 0.001));
      expect(colors.last.a, 0);
      expect(softStops(), hasLength(colors.length));
    });
  });

  group('el controlador del disco', () {
    test('rellena solo prefiriendo las apps comunes y, si faltan, por nombre', () async {
      apps.apps = [app('com.zeta', 'Zeta'), app('com.whatsapp', 'WhatsApp'), app('com.android.chrome', 'Chrome'), app('com.alfa', 'Alfa')];
      await dock.refresh();
      expect(dock.automatic, isTrue);
      expect(dock.slots.take(4).map((a) => a?.package), ['com.whatsapp', 'com.android.chrome', 'com.zeta', 'com.alfa']);
      expect(dock.slots.skip(4), everyElement(isNull));
    });

    test('al cambiar una ranura las 8 quedan fijas y se guardan', () async {
      await dock.refresh();
      await dock.setSlot(7, 'com.app10');
      expect(dock.automatic, isFalse);
      expect(dockStore.slots, hasLength(dockSlots));
      expect(dockStore.slots![7], 'com.app10');
      expect(dockStore.slots!.take(7), [for (var i = 1; i <= 7; i++) 'com.app$i']);
    });

    test('vaciar una ranura la deja sin app y «rellenar solo» la recupera', () async {
      await dock.refresh();
      await dock.clearSlot(0);
      expect(dock.slots[0], isNull);
      await dock.reset();
      expect(dock.automatic, isTrue);
      expect(dockStore.slots, isNull);
      expect(dock.slots[0]?.package, 'com.app1');
    });

    test('una app que se desinstaló deja su ranura vacía', () async {
      dockStore.slots = ['com.app1', 'com.gone', null, null, null, null, null, null];
      final fresh = DockController(dockStore, apps);
      addTearDown(fresh.dispose);
      await fresh.refresh();
      expect(fresh.slots[0]?.package, 'com.app1');
      expect(fresh.slots[1], isNull);
    });

    test('lo elegido se recuerda al abrir de nuevo', () async {
      await dock.refresh();
      await dock.setSlot(0, 'com.app9');
      final again = DockController(dockStore, apps);
      addTearDown(again.dispose);
      await again.refresh();
      expect(again.slots[0]?.package, 'com.app9');
    });
  });

  group('el fondo de pantalla (controlador)', () {
    test('al poner uno lo copia y borra el anterior; al quitarlo vuelve el liso', () async {
      final store = MemoryWallpaperStore();
      final wallpaper = WallpaperController(store);
      addTearDown(wallpaper.dispose);
      expect(wallpaper.hasWallpaper, isFalse);
      expect(await wallpaper.set('a.jpg'), isTrue);
      expect(wallpaper.path, 'a.jpg');
      expect(store.state.path, 'a.jpg');
      expect(await wallpaper.set('b.jpg'), isTrue);
      expect(store.discarded, ['a.jpg']);
      await wallpaper.clear();
      expect(wallpaper.path, isNull);
      expect(store.state.path, isNull);
      expect(store.discarded, ['a.jpg', 'b.jpg']);
    });

    test('se recuerda al abrir de nuevo', () {
      final store = MemoryWallpaperStore()..state = const WallpaperState(path: 'guardado.jpg', accent: 0xFF35D4FF);
      final wallpaper = WallpaperController(store);
      addTearDown(wallpaper.dispose);
      expect(wallpaper.path, 'guardado.jpg');
      expect(wallpaper.accent, const Color(0xFF35D4FF));
    });

    test('el acento sale del fondo: se saca al ponerlo, se guarda, y sin fondo vuelve el de siempre', () async {
      final store = MemoryWallpaperStore();
      final wallpaper = WallpaperController(store, lookup: (_) async => const Color(0xFFFF4FD8));
      addTearDown(wallpaper.dispose);
      expect(wallpaper.accent, isNull);
      await wallpaper.set('a.jpg');
      expect(wallpaper.accent, const Color(0xFFFF4FD8));
      expect(store.state.accent, const Color(0xFFFF4FD8).toARGB32());
      await wallpaper.clear();
      expect(wallpaper.accent, isNull);
      expect(store.state.accent, isNull);
    });

    test('una imagen casi gris no da acento: se queda el de siempre', () async {
      final wallpaper = WallpaperController(MemoryWallpaperStore(), lookup: (_) async => null);
      addTearDown(wallpaper.dispose);
      await wallpaper.set('gris.jpg');
      expect(wallpaper.hasWallpaper, isTrue);
      expect(wallpaper.accent, isNull);
    });
  });

  group('el color de un fondo', () {
    Uint8List pixels(Map<Color, int> counts) => Uint8List.fromList([
      for (final e in counts.entries) for (var i = 0; i < e.value; i++) ...[(e.key.r * 255).round(), (e.key.g * 255).round(), (e.key.b * 255).round(), 255],
    ]);

    test('el tono que más pesa gana: una imagen casi toda azul da un acento azul vivo', () {
      final accent = accentOf(pixels({const Color(0xFF2040C0): 80, const Color(0xFFC03020): 10}));
      final hsv = HSVColor.fromColor(accent!);
      expect(hsv.hue, inInclusiveRange(215, 240));
      expect(hsv.saturation, greaterThan(0.7));
      expect(hsv.value, greaterThan(0.95)); // brillante, para leerse sobre el fondo oscuro
    });

    test('una imagen gris, negra o blanca no da acento', () {
      expect(accentOf(pixels({const Color(0xFF808080): 50, const Color(0xFF101010): 50, const Color(0xFFF0F0F0): 50})), isNull);
    });

    test('los píxeles transparentes no cuentan', () {
      final rgba = Uint8List.fromList([255, 0, 0, 0, 255, 0, 0, 0]);
      expect(accentOf(rgba), isNull);
    });
  });
}
