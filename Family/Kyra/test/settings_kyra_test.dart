import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/calendar_view_store.dart';
import 'package:kyora_chat/data/dock_store.dart';
import 'package:kyora_chat/data/installed_apps.dart';
import 'package:kyora_chat/data/wallpaper_store.dart';
import 'package:kyora_chat/data/weather_service.dart';
import 'package:kyora_chat/data/weather_store.dart';
import 'package:kyora_chat/models/profile.dart';
import 'package:kyora_chat/state/dock_controller.dart';
import 'package:kyora_chat/state/music_controller.dart';
import 'package:kyora_chat/state/wallpaper_controller.dart';
import 'package:kyora_chat/state/weather_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/settings_page.dart';
import 'package:kyora_chat/util/agenda.dart' show CalendarMode;

import 'music_test.dart' show FakeMusicBackend, FakeSaver, MemoryMusicStore;
import 'sections.dart';
import 'weather_test.dart' show FakeWeather;

final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

void main() {
  late MusicController music;
  late FakeWeather backend;
  late WeatherController weather;
  late FakeInstalledApps apps;
  late DockController dock;
  late WallpaperController wallpaper;

  Future<void> open(WidgetTester tester, {bool withWeather = true, bool withDock = false, bool withWallpaper = false, CalendarViewStore? calendarView, String? initialTile, Size size = const Size(400, 850)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    music = MusicController(FakeMusicBackend(), MemoryMusicStore(since: DateTime.utc(2026, 10, 1)), FakeSaver());
    addTearDown(music.dispose);
    await tester.runAsync(music.start);
    backend = FakeWeather();
    weather = WeatherController(backend, MemoryWeatherStore());
    addTearDown(weather.dispose);
    apps = FakeInstalledApps([for (var i = 1; i <= 3; i++) InstalledApp(package: 'com.app$i', label: 'App $i', icon: Uint8List.fromList(_png))]);
    dock = DockController(MemoryDockStore(), apps);
    addTearDown(dock.dispose);
    wallpaper = WallpaperController(MemoryWallpaperStore(), lookup: (_) async => null);
    addTearDown(wallpaper.dispose);
    await tester.runAsync(dock.refresh);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: SettingsPage(
        music: music,
        role: Role.admin,
        username: 'gustavo',
        onSignOut: () async {},
        weather: withWeather ? weather : null,
        dock: withDock ? dock : null,
        wallpaper: withWallpaper ? wallpaper : null,
        calendarView: calendarView,
        initialTile: initialTile,
      ),
    ));
    await tester.pumpAndSettle();
  }

  Rect tile(WidgetTester tester, String id) => tester.getRect(find.byKey(Key('mosaic-tile-$id')));

  group('el calendario', () {
    testWidgets('la ficha solo sale si hay dónde guardar la vista, y dice cuál es', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('mosaic-tile-calendar')), findsNothing);
      await open(tester, calendarView: MemoryCalendarViewStore());
      expect(find.byKey(const Key('mosaic-tile-calendar')), findsOneWidget);
      expect(find.text('Calendario'), findsOneWidget);
      expect(find.text('SEMANA'), findsOneWidget);
    });

    testWidgets('con la ficha, todas siguen cabiendo en la pantalla sin pisarse', (tester) async {
      await open(tester, withDock: true, withWallpaper: true, calendarView: MemoryCalendarViewStore());
      final ids = ['wallpaper', 'launcher', 'weather', 'dock', 'music', 'calendar', 'account'];
      final area = tester.getRect(find.byKey(const Key('settings-page')));
      final rects = {for (final id in ids) id: tile(tester, id)};
      for (final r in rects.values) {
        expect(area.contains(r.topLeft) && area.contains(r.bottomRight), isTrue);
      }
      for (final a in ids) {
        for (final b in ids) {
          if (a.compareTo(b) >= 0) continue;
          expect(rects[a]!.deflate(0.5).overlaps(rects[b]!.deflate(0.5)), isFalse, reason: '$a pisa a $b');
        }
      }
    });

    testWidgets('elegir Mes o Semana lo guarda, lo marca y se ve en el resumen', (tester) async {
      final store = MemoryCalendarViewStore();
      await open(tester, calendarView: store);
      await openSettingsTile(tester, 'calendar');
      expect(find.byKey(const Key('settings-calendar-view-week')), findsOneWidget);
      expect(find.byKey(const Key('settings-calendar-view-month')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('settings-calendar-view-week')), matching: find.byIcon(Icons.check_rounded)), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings-calendar-view-month')));
      await tester.pumpAndSettle();
      expect(store.mode, CalendarMode.month);
      expect(find.descendant(of: find.byKey(const Key('settings-calendar-view-month')), matching: find.byIcon(Icons.check_rounded)), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('settings-calendar-view-week')), matching: find.byIcon(Icons.check_rounded)), findsNothing);
      await tester.tap(find.byKey(const Key('settings-calendar-view-week')));
      await tester.pumpAndSettle();
      expect(store.mode, CalendarMode.week);
    });
  });

  group('el mosaico', () {
    testWidgets('con todo, salen seis fichas de distintos tamaños, dentro de la pantalla y sin pisarse', (tester) async {
      await open(tester, withDock: true, withWallpaper: true);
      final ids = ['wallpaper', 'launcher', 'weather', 'dock', 'music', 'account'];
      final rects = {for (final id in ids) id: tile(tester, id)};
      for (final id in ids) {
        expect(find.byKey(Key('mosaic-summary-$id')), findsOneWidget, reason: id);
      }
      final area = tester.getRect(find.byKey(const Key('settings-page')));
      for (final r in rects.values) {
        expect(area.contains(r.topLeft) && area.contains(r.bottomRight), isTrue);
      }
      for (final a in ids) {
        for (final b in ids) {
          if (a.compareTo(b) >= 0) continue;
          expect(rects[a]!.deflate(0.5).overlaps(rects[b]!.deflate(0.5)), isFalse, reason: '$a pisa a $b');
        }
      }
      // tamaños distintos: la del fondo es la más grande, la de los iconos es ancha y baja, la de la cuenta es alta y estrecha
      final sizes = {for (final r in rects.values) '${r.width.round()}x${r.height.round()}'};
      expect(sizes.length, greaterThanOrEqualTo(4));
      expect(rects['wallpaper']!.width * rects['wallpaper']!.height, greaterThan(rects['launcher']!.width * rects['launcher']!.height * 2));
      expect(rects['dock']!.width, greaterThan(rects['dock']!.height * 3));
      expect(rects['account']!.height, greaterThan(rects['account']!.width * 1.5));
    });

    testWidgets('los títulos y un resumen en vivo en cada ficha', (tester) async {
      await open(tester, withDock: true, withWallpaper: true);
      for (final title in ['Fondo de pantalla', 'Pantalla de inicio', 'Clima', 'Apps del disco', 'Música', 'gustavo']) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(find.text('SIN FONDO'), findsOneWidget);
      expect(find.text('INACTIVO'), findsOneWidget);
      expect(find.text('ELIGE CIUDAD'), findsOneWidget);
      expect(find.text('Música/Kyora'), findsOneWidget);
      expect(find.text('ADMIN'), findsOneWidget);
    });

    testWidgets('los resúmenes se ponen al día solos', (tester) async {
      await open(tester, withDock: true, withWallpaper: true);
      await tester.runAsync(() => wallpaper.set('C:/fondo.jpg'));
      await tester.pump();
      expect(find.text('SIN FONDO'), findsNothing);
      expect(find.byKey(const Key('settings-wallpaper-preview')), findsOneWidget);
      await tester.runAsync(() => weather.setCity('Lima'));
      await tester.pumpAndSettle();
      expect(find.textContaining('LIMA'), findsWidgets);
    });

    testWidgets('sin un servicio opcional no sale su ficha y las demás se reacomodan sin agujeros ni solapes', (tester) async {
      await open(tester, withWeather: false);
      expect(find.byKey(const Key('mosaic-tile-weather')), findsNothing);
      expect(find.byKey(const Key('mosaic-tile-wallpaper')), findsNothing);
      expect(find.byKey(const Key('mosaic-tile-dock')), findsNothing);
      expect(find.byKey(const Key('mosaic-tile-music')), findsOneWidget);
      expect(find.byKey(const Key('mosaic-tile-account')), findsOneWidget);
      expect(tile(tester, 'music').overlaps(tile(tester, 'account')), isFalse);
      expect(tile(tester, 'music').top, closeTo(tile(tester, 'account').top, 0.5)); // la música sube al primer hueco, junto a la cuenta
    });
  });

  group('al expandir una ficha', () {
    testWidgets('la elegida ocupa casi todo, las demás pasan a una franja de iconos abajo y el resumen se cambia por el detalle', (tester) async {
      await open(tester, withDock: true, withWallpaper: true);
      await openSettingsTile(tester, 'weather');
      final area = tester.getRect(find.byKey(const Key('settings-page')));
      final big = tile(tester, 'weather');
      expect(big.width, closeTo(400 - 32, 0.5)); // todo el ancho útil
      expect(big.height, greaterThan(850 * 0.6));
      expect(find.byKey(const Key('mosaic-detail-weather')), findsOneWidget);
      expect(find.byKey(const Key('mosaic-summary-weather')), findsNothing);
      for (final id in ['wallpaper', 'launcher', 'dock', 'music', 'account']) {
        final r = tile(tester, id);
        expect(r.top, greaterThan(big.bottom - 1), reason: '$id debajo de la expandida');
        expect(r.height, lessThan(80));
        expect(find.byKey(Key('mosaic-strip-$id')), findsOneWidget, reason: id);
        expect(find.byKey(Key('mosaic-summary-$id')), findsNothing, reason: id);
      }
      expect(area.contains(big.bottomRight), isTrue);
    });

    testWidgets('se mueven con fluidez: a mitad del camino cada ficha está entre donde estaba y donde va a quedar', (tester) async {
      await open(tester, withDock: true, withWallpaper: true);
      final before = tile(tester, 'music');
      await tester.tap(find.byKey(const Key('mosaic-tile-weather')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final mid = tile(tester, 'music');
      await tester.pumpAndSettle();
      final after = tile(tester, 'music');
      expect(mid, isNot(before));
      expect(mid, isNot(after));
      expect(mid.top, inInclusiveRange(before.top < after.top ? before.top : after.top, before.top < after.top ? after.top : before.top));
      expect(tester.takeException(), isNull); // y durante el movimiento no se desborda nada
    });

    testWidgets('el contenido se cambia con un fundido: a mitad del camino conviven el resumen y el detalle', (tester) async {
      await open(tester, withDock: true, withWallpaper: true);
      await tester.tap(find.byKey(const Key('mosaic-tile-weather')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 230));
      expect(find.byKey(const Key('mosaic-summary-weather')), findsOneWidget);
      expect(find.byKey(const Key('mosaic-detail-weather')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mosaic-summary-weather')), findsNothing);
    });

    testWidgets('tocar otra ficha de la franja cambia de ficha sin pasar por el mosaico', (tester) async {
      await open(tester, withDock: true, withWallpaper: true);
      await openSettingsTile(tester, 'weather');
      await openSettingsTile(tester, 'music');
      expect(find.byKey(const Key('mosaic-detail-music')), findsOneWidget);
      expect(find.byKey(const Key('mosaic-detail-weather')), findsNothing);
      expect(find.byKey(const Key('mosaic-strip-weather')), findsOneWidget);
      expect(tile(tester, 'music').height, greaterThan(850 * 0.6));
    });

    testWidgets('cambiar de ficha a mitad de un movimiento no salta ni falla', (tester) async {
      await open(tester, withDock: true, withWallpaper: true);
      await tester.tap(find.byKey(const Key('mosaic-tile-weather')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(find.byKey(const Key('mosaic-tile-music')));
      await tester.pump();
      final first = tile(tester, 'music');
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mosaic-detail-music')), findsOneWidget);
      expect(tile(tester, 'music').height, greaterThanOrEqualTo(first.height));
    });

    testWidgets('la X de la ficha vuelve al mosaico y todas recuperan su sitio', (tester) async {
      await open(tester, withDock: true, withWallpaper: true);
      final before = {for (final id in ['wallpaper', 'launcher', 'weather', 'dock', 'music', 'account']) id: tile(tester, id)};
      await openSettingsTile(tester, 'dock');
      await tester.tap(find.byKey(const Key('mosaic-close')));
      await tester.pumpAndSettle();
      for (final e in before.entries) {
        expect(tile(tester, e.key).left, closeTo(e.value.left, 0.5), reason: e.key);
        expect(tile(tester, e.key).top, closeTo(e.value.top, 0.5), reason: e.key);
        expect(tile(tester, e.key).size.width, closeTo(e.value.width, 0.5), reason: e.key);
      }
    });

    testWidgets('una ficha puede abrirse ya expandida (el clima desde Inicio)', (tester) async {
      await open(tester, initialTile: 'weather');
      expect(find.byKey(const Key('mosaic-detail-weather')), findsOneWidget);
      expect(find.byKey(const Key('settings-city-field')), findsOneWidget);
    });

    testWidgets('con el teclado abierto la ficha se queda por encima de él', (tester) async {
      await open(tester, initialTile: 'weather');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tile(tester, 'weather').bottom, lessThanOrEqualTo(850 - 300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('en una pantalla baja y estrecha no se desborda', (tester) async {
      await open(tester, withDock: true, withWallpaper: true, size: const Size(320, 520));
      expect(tester.takeException(), isNull);
      await openSettingsTile(tester, 'music');
      expect(tester.takeException(), isNull);
      await openSettingsTile(tester, 'dock');
      expect(tester.takeException(), isNull);
    });
  });

  group('lo de dentro de cada ficha', () {
    testWidgets('la ciudad se escribe, se guarda al enviar y dice si la encontró', (tester) async {
      await open(tester);
      await openSettingsTile(tester, 'weather');
      expect(find.text('Escribe tu ciudad y pulsa enviar.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('settings-city-field')), 'Lima');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      expect(backend.asked, ['Lima']);
      expect(weather.city, 'Lima');
      expect(find.text('Encontrada: Lima.'), findsOneWidget);
    });

    testWidgets('una ciudad que no existe se avisa en la propia fila', (tester) async {
      await open(tester);
      await openSettingsTile(tester, 'weather');
      backend.error = const CityNotFound('Xyzzy');
      await tester.enterText(find.byKey(const Key('settings-city-field')), 'Xyzzy');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      expect(find.text('No encontré esa ciudad. Prueba con otro nombre.'), findsOneWidget);
    });

    testWidgets('el fondo: elegir y quitar desde su ficha', (tester) async {
      await open(tester, withWallpaper: true);
      await openSettingsTile(tester, 'wallpaper');
      expect(find.byKey(const Key('settings-wallpaper')), findsOneWidget);
      expect(find.byKey(const Key('settings-wallpaper-clear')), findsNothing);
      await tester.runAsync(() => wallpaper.set('C:/fondo.jpg'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-wallpaper-clear')), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings-wallpaper-clear')));
      await tester.pumpAndSettle();
      expect(wallpaper.hasWallpaper, isFalse);
    });

    testWidgets('las apps del disco: una fila por ranura y «Rellenar solo» al fijar alguna', (tester) async {
      await open(tester, withDock: true);
      await openSettingsTile(tester, 'dock');
      expect(find.byKey(const Key('settings-dock-0')), findsOneWidget);
      await tester.runAsync(() => dock.setSlot(0, 'com.app3'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-dock-reset')), findsOneWidget);
    });

    testWidgets('no hay ninguna ficha ni grupo de colores: el color sale del fondo', (tester) async {
      await open(tester, withDock: true, withWallpaper: true);
      expect(find.text('COLORES'), findsNothing);
      expect(find.byKey(const Key('settings-colors')), findsNothing);
      expect(find.text('Colores'), findsNothing);
    });
  });

  group('pantalla de inicio (launcher)', () {
    testWidgets('con el disco sale la ficha «Pantalla de inicio» con la opción de usar Kyra como launcher', (tester) async {
      await open(tester, withDock: true);
      expect(find.text('Pantalla de inicio'), findsOneWidget);
      await openSettingsTile(tester, 'launcher');
      expect(find.text('Usar Kyra como pantalla de inicio'), findsOneWidget);
    });

    testWidgets('tocarla pide a Android que Kyra sea la pantalla de inicio', (tester) async {
      await open(tester, withDock: true);
      await openSettingsTile(tester, 'launcher');
      await tester.tap(find.byKey(const Key('settings-launcher')));
      await tester.pump();
      expect(apps.chooseCalls, 1);
    });

    testWidgets('si Kyra ya es la pantalla de inicio lo dice, en el resumen y dentro', (tester) async {
      apps.launcher = true;
      await open(tester, withDock: true);
      apps.launcher = true;
      await tester.runAsync(dock.refresh);
      await tester.pumpAndSettle();
      expect(find.text('ACTIVO'), findsOneWidget);
      await openSettingsTile(tester, 'launcher');
      expect(find.text('Kyra es tu pantalla de inicio'), findsOneWidget);
      expect(find.text('Usar Kyra como pantalla de inicio'), findsNothing);
    });

    testWidgets('sin disco no sale la ficha', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('mosaic-tile-launcher')), findsNothing);
    });

    test('el estado se pone al día al volver a la app (refresh)', () async {
      final fake = FakeInstalledApps([]);
      final d = DockController(MemoryDockStore(), fake);
      addTearDown(d.dispose);
      expect(d.isLauncher, isFalse);
      fake.launcher = true;
      await d.refresh();
      expect(d.isLauncher, isTrue);
      fake.launcher = false;
      await d.refresh();
      expect(d.isLauncher, isFalse);
    });
  });
}
