import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/wallpaper_store.dart';
import 'package:kyora_chat/state/wallpaper_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/section_host.dart';
import 'package:kyora_chat/ui/widgets/app_backdrop.dart';
import 'package:kyora_chat/ui/widgets/app_section.dart';

/// El fondo de pantalla en toda la app: lo pinta `AppBackdrop` una vez, detrás de todas las secciones, con el oscurecido en degradado; fuera de
/// Inicio se oscurece un poco más.
String? _fileOf(ImageProvider image) {
  final inner = image is ResizeImage ? image.imageProvider : image;
  return inner is FileImage ? inner.file.path : null;
}

void main() {
  late WallpaperController wallpaper;

  setUp(() => wallpaper = WallpaperController(MemoryWallpaperStore(), lookup: (_) async => null));
  tearDown(() => wallpaper.dispose());

  List<String> shownFiles(WidgetTester tester) => [
    for (final e in find.byType(Image).evaluate())
      if (_fileOf((e.widget as Image).image) != null) _fileOf((e.widget as Image).image)!,
  ];

  Future<void> openHost(WidgetTester tester, {WallpaperController? wp}) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget page(String id) => Builder(
      builder: (context) => Center(
        child: TextButton(key: Key('go-$id'), onPressed: () => SectionHost.goTo(context, id), child: Text('Pantalla $id')),
      ),
    );
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      builder: (context, child) => AppBackdrop(wallpaper: wp, child: child!),
      home: SectionHost(
        sections: [
          for (final id in ['home', 'chat', 'music']) AppSection(id: id, icon: Icons.circle_outlined, label: id, builder: (_) => page(id == 'home' ? 'chat' : 'home')),
        ],
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('sin fondo de pantalla: el gris oscuro de siempre, sin imagen ni oscurecido, pero con las líneas de pantalla', (tester) async {
    await openHost(tester, wp: wallpaper);
    expect(shownFiles(tester), isEmpty);
    expect(find.byKey(const Key('backdrop-dim')), findsNothing);
    expect(find.byKey(const Key('backdrop-lines')), findsOneWidget);
    expect(tester.widget<ColoredBox>(find.byKey(const Key('screen-backdrop'))).color, KyoraColors.classic().background);
  });

  testWidgets('con fondo, la imagen sale a pantalla completa con un oscurecido plano (sin degradado) y las líneas encima', (tester) async {
    await tester.runAsync(() => wallpaper.set('C:/fondo.jpg'));
    await openHost(tester, wp: wallpaper);
    expect(shownFiles(tester), ['C:/fondo.jpg']);
    expect(tester.getRect(find.byKey(const Key('screen-backdrop'))), const Rect.fromLTWH(0, 0, 400, 800));
    // plano: un solo color en toda la pantalla, nada de degradados
    final dim = tester.widget<ColoredBox>(find.byKey(const Key('backdrop-dim')));
    expect(dim.color.a, closeTo(kBackdropDim, 0.001));
    expect(tester.getRect(find.byKey(const Key('backdrop-dim'))), const Rect.fromLTWH(0, 0, 400, 800));
    expect(find.byWidgetPredicate((w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).gradient != null), findsNothing);
    // las líneas, por encima del oscurecido
    final lines = tester.getRect(find.byKey(const Key('backdrop-lines')));
    expect(lines, const Rect.fromLTWH(0, 0, 400, 800));
  });

  testWidgets('el oscurecido es el mismo en todas las secciones: al cambiar de sección no se oscurece de más', (tester) async {
    await tester.runAsync(() => wallpaper.set('C:/fondo.jpg'));
    await openHost(tester, wp: wallpaper);
    double dim() => tester.widget<ColoredBox>(find.byKey(const Key('backdrop-dim'))).color.a;
    final home = dim();
    await tester.tap(find.byKey(const Key('go-chat')));
    await tester.pumpAndSettle();
    expect(dim(), home);
    expect(find.byKey(const Key('section-dim')), findsNothing);
    expect(shownFiles(tester), ['C:/fondo.jpg']); // el mismo fondo, una sola imagen
  });

  test('las líneas son marcadas: una raya oscura cada pocos píxeles, bien visible', () {
    expect(HackerScreen.pitch, lessThanOrEqualTo(4));
    expect(HackerScreen.lineAlpha, greaterThanOrEqualTo(0.3));
    expect(HackerScreen.lineWidth, greaterThanOrEqualTo(1.4));
  });

  testWidgets('el fondo cambia en vivo al elegir otro y vuelve el liso al quitarlo', (tester) async {
    await openHost(tester, wp: wallpaper);
    await tester.runAsync(() => wallpaper.set('C:/uno.jpg'));
    await tester.pump();
    expect(shownFiles(tester), ['C:/uno.jpg']);
    await tester.runAsync(() => wallpaper.set('C:/dos.jpg'));
    await tester.pump();
    expect(shownFiles(tester), ['C:/dos.jpg']);
    await tester.runAsync(wallpaper.clear);
    await tester.pump();
    expect(shownFiles(tester), isEmpty);
    expect(find.byKey(const Key('backdrop-dim')), findsNothing);
  });

  testWidgets('las páginas que se abren encima llevan el mismo fondo, oscurecido y con líneas', (tester) async {
    await tester.runAsync(() => wallpaper.set('C:/fondo.jpg'));
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      builder: (context, child) => AppBackdrop(wallpaper: wallpaper, child: child!),
      home: const BackdropLayers(),
    ));
    expect(find.byKey(const Key('backdrop-dim')), findsNWidgets(2));
    expect(shownFiles(tester), hasLength(2)); // la del fondo de toda la app y la de esta capa (la misma imagen)
  });
}
