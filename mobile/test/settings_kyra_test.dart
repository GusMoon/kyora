import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/wallpaper_store.dart';
import 'package:kyora_chat/data/weather_service.dart';
import 'package:kyora_chat/data/weather_store.dart';
import 'package:kyora_chat/models/profile.dart';
import 'package:kyora_chat/state/music_controller.dart';
import 'package:kyora_chat/state/wallpaper_controller.dart';
import 'package:kyora_chat/state/weather_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/settings_sheet.dart';
import 'package:kyora_chat/util/palette.dart';

import 'music_test.dart' show FakeMusicBackend, FakeSaver, MemoryMusicStore;
import 'weather_test.dart' show FakeWeather;

const _five = [Color(0xFF112233), Color(0xFF445566), Color(0xFF778899), Color(0xFFAABBCC), Color(0xFFDDEEFF)];

void main() {
  late MusicController music;
  late MemoryWallpaperStore store;
  late WallpaperController wallpaper;
  late FakeWeather backend;
  late WeatherController weather;
  String? picked;

  Future<void> open(WidgetTester tester, {bool withWallpaper = true, bool withWeather = true}) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    music = MusicController(FakeMusicBackend(), MemoryMusicStore(since: DateTime.utc(2026, 10, 1)), FakeSaver());
    addTearDown(music.dispose);
    await tester.runAsync(music.start);
    store = MemoryWallpaperStore();
    wallpaper = WallpaperController(store, lookup: (_) async => _five);
    backend = FakeWeather();
    weather = WeatherController(backend, MemoryWeatherStore());
    addTearDown(weather.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: SettingsSheet(
        music: music,
        role: Role.admin,
        username: 'gustavo',
        onSignOut: () async {},
        wallpaper: withWallpaper ? wallpaper : null,
        weather: withWeather ? weather : null,
        pickImage: () async => picked,
      ),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() => picked = '/galeria/lluvia.jpg');

  testWidgets('está organizada en grupos con su explicación: Apariencia, Clima, Música y Cuenta', (tester) async {
    await open(tester);
    for (final title in ['Apariencia', 'Clima', 'Música', 'Cuenta']) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.text('El fondo de la app y los colores que salen de él.'), findsOneWidget);
    expect(find.text('Con quién has entrado.'), findsOneWidget);
  });

  testWidgets('sin fondo ni clima solo salen Música y Cuenta', (tester) async {
    await open(tester, withWallpaper: false, withWeather: false);
    expect(find.text('Apariencia'), findsNothing);
    expect(find.text('Clima'), findsNothing);
    expect(find.text('Música'), findsOneWidget);
  });

  testWidgets('sin fondo no hay colores que enseñar y se invita a elegir uno', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('palette-strip')), findsNothing);
    expect(find.text('Elige un fondo y aquí salen sus 5 colores.'), findsOneWidget);
    expect(find.byKey(const Key('settings-wallpaper-clear')), findsNothing);
  });

  testWidgets('elegir una imagen pone el fondo y enseña sus 5 colores con su código', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('settings-wallpaper')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(wallpaper.path, '/galeria/lluvia.jpg');
    expect(find.byKey(const Key('palette-strip')), findsOneWidget);
    for (final color in _five) {
      expect(find.text(hexOf(color)), findsOneWidget);
    }
    expect(find.byKey(const Key('settings-wallpaper-clear')), findsOneWidget);
  });

  testWidgets('cancelar el selector no cambia nada', (tester) async {
    picked = null;
    await open(tester);
    await tester.tap(find.byKey(const Key('settings-wallpaper')));
    await tester.pumpAndSettle();
    expect(wallpaper.hasWallpaper, isFalse);
  });

  testWidgets('«Quitar el fondo» vuelve al gris y esconde los colores', (tester) async {
    await open(tester);
    await tester.runAsync(() => wallpaper.set('/galeria/lluvia.jpg'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-wallpaper-clear')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(wallpaper.hasWallpaper, isFalse);
    expect(find.byKey(const Key('palette-strip')), findsNothing);
  });

  testWidgets('la ciudad se escribe, se guarda al enviar y dice si la encontró', (tester) async {
    await open(tester);
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
    backend.error = const CityNotFound('Xyzzy');
    await tester.enterText(find.byKey(const Key('settings-city-field')), 'Xyzzy');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(find.text('No encontré esa ciudad. Prueba con otro nombre.'), findsOneWidget);
  });

  testWidgets('la hoja es de gris oscuro semitransparente que difumina lo de detrás, con las esquinas de arriba redondeadas y su tirador', (tester) async {
    await open(tester);
    final sheet = tester.widget<ClipRRect>(find.byKey(const Key('settings-sheet')));
    expect((sheet.borderRadius as BorderRadius).topLeft.x, greaterThan(0));
    expect((sheet.borderRadius as BorderRadius).bottomLeft.x, 0);
    expect(find.descendant(of: find.byKey(const Key('settings-sheet')), matching: find.byType(BackdropFilter)), findsOneWidget);
    // el relleno: un gris oscuro, algo transparente
    final fill = tester.widget<ColoredBox>(find.descendant(of: find.byKey(const Key('settings-sheet')), matching: find.byType(ColoredBox)).first).color;
    expect(fill.a, inExclusiveRange(0.4, 0.95));
    expect(HSLColor.fromColor(fill).lightness, lessThan(0.2));
    expect(HSLColor.fromColor(fill).saturation, lessThan(0.15));
    expect(find.byKey(const Key('settings-handle')), findsOneWidget);
    // dentro, los grupos van sin tarjetas de cristal propias (no se apilan desenfoques)
    expect(find.byKey(const Key('glass-card')), findsNothing);
  });

  testWidgets('con el teclado abierto la lista se queda por encima de él', (tester) async {
    await open(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(ListView)).bottom, lessThanOrEqualTo(1400 - 300));
  });

  group('el color de la app', () {
    test('con un fondo puesto la app se viste con su color, no con el de la carátula', () {
      const cover = Color(0xFFD62828); // rojo
      final seed = paletteSeed([const Color(0xFF808080), const Color(0xFF1B998B), const Color(0xFF808080), const Color(0xFF808080), const Color(0xFF808080)]);
      // lo mismo que hace `main.dart`: `wallpaper?.seed ?? cover`
      final withWallpaper = buildCoverTheme(seed).extension<KyoraColors>()!;
      final withoutWallpaper = buildCoverTheme(cover).extension<KyoraColors>()!;
      expect(HSLColor.fromColor(withWallpaper.accent).hue, closeTo(HSLColor.fromColor(seed).hue, 8));
      expect(HSLColor.fromColor(withoutWallpaper.accent).hue, closeTo(HSLColor.fromColor(cover).hue, 8));
      expect(withWallpaper.accent, isNot(withoutWallpaper.accent));
    });

    test('con el fondo del gris oscuro de siempre y sin carátula, los colores clásicos', () {
      expect(buildCoverTheme(null).extension<KyoraColors>()!.accent, KyoraColors.classic().accent);
    });

    test('sea cual sea el fondo, el texto y el acento se leen sobre las placas', () {
      for (final seed in const [Color(0xFFFFFFFF), Color(0xFF000000), Color(0xFFFFEB3B), Color(0xFF1B998B), Color(0xFF3F51B5)]) {
        final c = buildCoverTheme(seed).extension<KyoraColors>()!;
        for (final plate in [c.background, c.surface, c.plate, c.pick]) {
          expect(contrastRatio(c.ink, plate), greaterThanOrEqualTo(7), reason: 'texto sobre $plate con $seed');
          expect(contrastRatio(c.accent, plate), greaterThanOrEqualTo(4.5), reason: 'acento sobre $plate con $seed');
        }
      }
    });
  });
}
