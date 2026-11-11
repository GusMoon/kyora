import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/wallpaper_store.dart';
import 'package:kyora_chat/state/wallpaper_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/util/pixel_art.dart';
import 'package:kyora_chat/ui/section_host.dart';
import 'package:kyora_chat/ui/widgets/app_backdrop.dart';
import 'package:kyora_chat/ui/widgets/app_section.dart';
import 'package:kyora_chat/ui/widgets/device_shell.dart';
import 'package:kyora_chat/ui/widgets/lcd_image.dart';
import 'package:kyora_chat/ui/widgets/mode_tabs.dart';
import 'package:kyora_chat/ui/widgets/pixel_glyph.dart';
import 'package:kyora_chat/ui/widgets/vinyl_disc.dart';

import 'sections.dart';

/// Una sección de prueba con un campo de texto y un botón que abre una página encima.
class _Page extends StatelessWidget {
  const _Page(this.id);

  final String id;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Pantalla $id'),
            TextButton(
              key: Key('push-$id'),
              onPressed: () => unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Center(child: Text('Encima')))))),
              child: const Text('abrir'),
            ),
            TextField(key: Key('field-$id')),
          ]),
        ),
      );
}

void main() {
  group('los iconos', () {
    test('cada icono con nombre es un icono redondeado de Material, y glyphFor devuelve el mismo icono', () {
      expect(PixelGlyphs.home.icon, Icons.grid_view_rounded);
      expect(glyphFor(Icons.ac_unit), PixelGlyph(Icons.ac_unit));
      expect(pixelWeatherGlyph(0), PixelGlyphs.sun);
      expect(pixelWeatherGlyph(95), PixelGlyphs.storm);
    });

    testWidgets('LcdIcon pinta el icono de Material en una caja del tamaño pedido, y PixelIcon el del glifo', (tester) async {
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: const Scaffold(body: Center(child: Column(children: [LcdIcon(Icons.home_outlined, size: 30), PixelIcon(PixelGlyphs.task, size: 24)])))));
      expect(tester.getSize(find.byType(LcdIcon)), const Size(30, 30));
      expect(tester.widget<Icon>(find.descendant(of: find.byType(LcdIcon), matching: find.byType(Icon))).icon, Icons.home_outlined);
      expect(tester.widget<Icon>(find.descendant(of: find.byType(PixelIcon), matching: find.byType(Icon))).icon, PixelGlyphs.task.icon);
    });
  });

  group('las portadas', () {
    testWidgets('las portadas son pixel art: pocos cuadros grandes, que dependen de lo grande que se vea', (tester) async {
      final provider = MemoryImage(Uint8List(8));
      // una miniatura de 48 px se reduce al mínimo; una grande, a los cuadros de la portada
      expect(LcdImage(image: provider, mode: LcdImageMode.pixel, width: 48).effectiveResolution, LcdImage.minPixelResolution);
      expect(LcdImage(image: provider, mode: LcdImageMode.pixel, width: 300).effectiveResolution, LcdImage.coverResolution);
      expect(LcdImage(image: provider, mode: LcdImageMode.pixel, width: 160).effectiveResolution, 20);
      // cuadros de unos 8 px de pantalla como mínimo
      expect(300 / LcdImage.coverResolution, greaterThanOrEqualTo(8));
      // en dos tonos, la resolución dada
      expect(LcdImage(image: provider, resolution: 200, width: 48).effectiveResolution, 200);
    });
  });

  group('la paleta corta del pixel art', () {
    Uint8List gradient(int w, int h) {
      final out = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final i = (y * w + x) * 4;
          out[i] = (x * 255 / (w - 1)).round();
          out[i + 1] = (y * 255 / (h - 1)).round();
          out[i + 2] = ((x + y) * 255 / (w + h - 2)).round();
          out[i + 3] = 255;
        }
      }
      return out;
    }

    test('un degradado de miles de tintes se queda en una paleta de pocos colores planos', () {
      final rgba = gradient(32, 32);
      final raw = PixelArt(32, 32, rgba).colors.length;
      final art = PixelArt(32, 32, quantize(rgba, 32, 32, k: 8));
      expect(raw, greaterThan(500));
      expect(art.colors.length, lessThanOrEqualTo(8));
      expect(art.colors.length, greaterThan(3)); // sigue teniendo color: no se vuelve plano
    });

    test('es determinista: la misma imagen da siempre la misma paleta', () {
      final rgba = gradient(24, 24);
      expect(quantize(rgba, 24, 24), quantize(rgba, 24, 24));
    });

    test('los colores de la paleta salen de la propia imagen: una imagen de dos colores vuelve con esos dos', () {
      final rgba = Uint8List(16 * 16 * 4);
      for (var i = 0; i < 16 * 16; i++) {
        final left = i % 16 < 8;
        rgba[i * 4] = left ? 214 : 27;
        rgba[i * 4 + 1] = left ? 40 : 58;
        rgba[i * 4 + 2] = left ? 40 : 107;
        rgba[i * 4 + 3] = 255;
      }
      expect(PixelArt(16, 16, quantize(rgba, 16, 16)).colors, {0xFFD62828, 0xFF1B3A6B});
    });

    test('lo transparente se pone sobre el fondo', () {
      final rgba = Uint8List(4 * 4 * 4); // todo transparente
      expect(PixelArt(4, 4, quantize(rgba, 4, 4, background: 0xFF102030)).colors, {0xFF102030});
    });
  });

  group('las imágenes en dos tonos', () {
    test('el difuminado solo deja la tinta y el fondo', () {
      const ink = Color(0xFF121C11);
      const screen = Color(0xFFA9B59C);
      // un degradado de negro a blanco, de 16 píxeles
      final rgba = Uint8List(16 * 4 * 4);
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 16; x++) {
          final i = (y * 16 + x) * 4;
          rgba[i] = rgba[i + 1] = rgba[i + 2] = (x * 17).clamp(0, 255);
          rgba[i + 3] = 255;
        }
      }
      final out = LcdImage.dither(rgba, 16, 4, ink, screen);
      final colors = <int>{};
      for (var i = 0; i < out.length; i += 4) {
        colors.add(out[i] << 16 | out[i + 1] << 8 | out[i + 2]);
      }
      expect(colors, {0x121C11, 0xA9B59C});
      // lo negro, todo tinta; lo blanco, todo fondo
      expect(out[0], 0x12);
      expect(out[(15) * 4], 0xA9);
    });
  });

  group('el disco de vinilo', () {
    test('el plástico toma el color de la portada, algo oscuro y mate', () {
      final base = VinylPainter.plastic(const Color(0xFFFF8A3D));
      final hsl = HSLColor.fromColor(base);
      expect(hsl.hue, closeTo(HSLColor.fromColor(const Color(0xFFFF8A3D)).hue, 2));
      expect(hsl.lightness, lessThan(0.65));
      expect(hsl.lightness, greaterThan(0.1));
    });

    testWidgets('se pinta redondo: las esquinas quedan vacías y el centro lleva el agujero oscuro', (tester) async {
      final holder = GlobalKey();
      tester.view.physicalSize = const Size(400, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: holder,
            child: SizedBox.square(dimension: 400, child: CustomPaint(painter: VinylPainter(angle: null, label: null, ink: const Color(0xFFFF8A3D)))),
          ),
        ),
      ));
      final data = await tester.runAsync(() async {
        final boundary = holder.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      });
      int alphaAt(int x, int y) => data!.getUint8((y * 400 + x) * 4 + 3);
      int redAt(int x, int y) => data!.getUint8((y * 400 + x) * 4);
      expect(alphaAt(2, 2), 0, reason: 'la esquina está fuera del disco');
      expect(alphaAt(200, 360), 255, reason: 'el plástico cubre el disco');
      expect(redAt(200, 200), lessThan(30), reason: 'el agujero del eje es oscuro');
      // el plástico es naranja (más rojo que azul)
      final i = (360 * 400 + 200) * 4;
      expect(data!.getUint8(i), greaterThan(data.getUint8(i + 2)));
    });
  });

  group('las pestañas', () {
    Future<void> show(WidgetTester tester, List<ModeTab> tabs, {bool top = false}) async {
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: Align(alignment: top ? Alignment.topCenter : Alignment.bottomCenter, child: top ? SegmentTabs(tabs: tabs) : ModeTabs(tabs: tabs)))));
      await tester.pumpAndSettle();
    }

    testWidgets('la barra de píldora: la elegida lleva su nombre y el acento; las demás, solo el icono', (tester) async {
      await show(tester, [
        for (final id in ['a', 'b', 'c']) ModeTab(id: id, label: 'Tab $id', glyph: PixelGlyphs.task, active: id == 'b', onPressed: () {}),
      ]);
      expect(find.text('Tab b'), findsOneWidget);
      expect(find.text('Tab a'), findsNothing);
      expect(find.byType(PixelIcon), findsNWidgets(3));
      final c = KyoraColors.classic();
      expect(tester.widget<Text>(find.text('Tab b')).style!.color, c.onAccent);
      final pill = tester.widget<Container>(find.descendant(of: find.byKey(const Key('b')), matching: find.byType(Container)).first);
      expect((pill.decoration! as ShapeDecoration).color, c.accent);
      expect(tester.getSize(find.byType(ModeTabs)).height, ModeTabs.height);
    });

    testWidgets('tocar una pestaña llama a la suya', (tester) async {
      final taps = <String>[];
      await show(tester, [
        for (final id in ['a', 'b']) ModeTab(id: id, label: id, glyph: PixelGlyphs.task, active: id == 'b', onPressed: () => taps.add(id)),
      ]);
      await tester.tap(find.byKey(const Key('a')));
      expect(taps, ['a']);
    });

    testWidgets('el selector de arriba enseña todos los nombres y marca la elegida', (tester) async {
      await show(top: true, tester, [
        for (final id in ['a', 'b', 'c']) ModeTab(id: id, label: 'Tab $id', glyph: PixelGlyphs.task, active: id == 'b', onPressed: () {}),
      ]);
      for (final id in ['a', 'b', 'c']) {
        expect(find.text('Tab $id'), findsOneWidget);
      }
      final c = KyoraColors.classic();
      expect(tester.widget<Text>(find.text('Tab b')).style!.color, c.onAccent);
      expect(tester.widget<Text>(find.text('Tab a')).style!.color, c.dim);
    });

    testWidgets('sin pestañas no ocupa nada', (tester) async {
      await show(tester, const []);
      expect(tester.getSize(find.byType(ModeTabs)).height, 0);
    });
  });

  group('el aparato', () {
    Future<void> open(WidgetTester tester, {WallpaperController? wallpaper, EdgeInsets padding = EdgeInsets.zero}) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = FakeViewPadding(top: padding.top, bottom: padding.bottom);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ListenableBuilder(
        listenable: wallpaper ?? ValueNotifier(0),
        builder: (context, _) => MaterialApp(
          theme: buildAccentTheme(wallpaper?.accent),
          builder: (context, child) => AppBackdrop(child: child!),
          home: SectionHost(sections: [
            for (final id in ['home', 'music', 'chat']) AppSection(id: id, icon: Icons.circle_outlined, label: id, builder: (_) => _Page(id)),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('no hay bisel ni borde: la pantalla ocupa todo el dispositivo, de borde a borde', (tester) async {
      await open(tester);
      expect(tester.getRect(find.byType(DeviceScreenFrame)), const Rect.fromLTWH(0, 0, 400, 800));
      expect(find.byKey(const Key('device-bevel')), findsNothing);
      expect(find.byKey(const Key('screen-depth')), findsNothing);
      // lo de dentro ve el tamaño del dispositivo
      expect(MediaQuery.of(tester.element(find.text('Pantalla home'))).size, const Size(400, 800));
    });

    testWidgets('con márgenes del sistema, la pantalla sigue llenándolo todo y lo de dentro los respeta', (tester) async {
      await open(tester, padding: const EdgeInsets.only(top: 30, bottom: 20));
      expect(tester.getRect(find.byType(DeviceScreenFrame)), const Rect.fromLTWH(0, 0, 400, 800));
      final media = MediaQuery.of(tester.element(find.text('Pantalla home')));
      expect(media.padding.top, 30);
      expect(media.padding.bottom, 20); // sin barra de pestañas, lo de dentro respeta también el margen de abajo
    });

    testWidgets('el fondo es casi negro y la letra es la grotesca; sin cuadrícula', (tester) async {
      await open(tester);
      final c = KyoraColors.classic();
      expect(c.background.computeLuminance(), lessThan(0.02));
      expect(tester.widget<ColoredBox>(find.descendant(of: find.byType(DeviceScreenFrame), matching: find.byType(ColoredBox)).first).color, c.background);
      expect(Theme.of(tester.element(find.text('Pantalla home'))).brightness, Brightness.dark);
      expect(Theme.of(tester.element(find.text('Pantalla home'))).textTheme.bodyMedium!.fontFamily, appFont);
      expect(appFont, 'Space Grotesk');
      expect(find.byKey(const Key('pixel-grid')), findsNothing);
    });

    testWidgets('sin fondo el acento es el de siempre; al poner un fondo, el acento sale de sus colores', (tester) async {
      final wallpaper = WallpaperController(MemoryWallpaperStore(), lookup: (_) async => const Color(0xFF35D4FF));
      addTearDown(wallpaper.dispose);
      await open(tester, wallpaper: wallpaper);
      Color accent() => Theme.of(tester.element(find.text('Pantalla home'))).extension<KyoraColors>()!.accent;
      expect(accent(), AppPalette.standard.accent);
      await tester.runAsync(() => wallpaper.set('fondo.jpg'));
      await tester.pumpAndSettle();
      expect(accent(), const Color(0xFF35D4FF));
      await tester.runAsync(wallpaper.clear);
      await tester.pumpAndSettle();
      expect(accent(), AppPalette.standard.accent);
    });

    testWidgets('no hay barra de pestañas abajo: se navega solo con el menú circular', (tester) async {
      await open(tester);
      expect(find.byType(ModeTabs), findsNothing);
      for (final id in ['home', 'music', 'chat']) {
        expect(find.byKey(Key('nav-$id')), findsNothing, reason: id);
      }
      await goToSection(tester, 'music');
      expect(find.text('Pantalla music'), findsOneWidget);
      expect(find.text('Pantalla home'), findsNothing);
    });

    testWidgets('dibujar un círculo en la pantalla abre el menú', (tester) async {
      await open(tester);
      expect(await menuOptions(tester), {'home', 'music', 'chat'});
    });

    testWidgets('una página que se abre encima se queda dentro de la pantalla; mientras está, el menú no sale y «atrás» la cierra', (tester) async {
      await open(tester);
      await goToSection(tester, 'music');
      await tester.tap(find.byKey(const Key('push-music')));
      await tester.pumpAndSettle();
      expect(find.text('Encima'), findsOneWidget);
      final screen = tester.getRect(find.byType(DeviceScreenFrame));
      final page = tester.getRect(find.ancestor(of: find.text('Encima'), matching: find.byType(Scaffold)));
      expect(screen.contains(page.topLeft) && screen.contains(page.bottomRight - const Offset(1, 1)), isTrue);
      await drawCircle(tester);
      expect(find.byKey(const Key('radial-menu')), findsNothing);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Encima'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Pantalla home'), findsOneWidget);
    });

    testWidgets('con el teclado abierto lo de dentro sabe cuánto le tapa', (tester) async {
      await open(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(MediaQuery.viewInsetsOf(tester.element(find.byType(_Page))).bottom, 300);
    });
  });
}
