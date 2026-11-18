import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/widgets/app_icon_lines.dart';
import 'package:kyora_chat/ui/widgets/apps_arch.dart';

import 'home_page_test.dart' show app;

/// Un icono de 8x8 **opaco** como los de Android (con fondo): la mitad de arriba roja (el dibujo) y la de abajo azul (el fondo).
Future<Uint8List> twoToneIcon() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 8, 4), Paint()..color = const Color(0xFFE53935));
  canvas.drawRect(const Rect.fromLTWH(0, 4, 8, 4), Paint()..color = const Color(0xFF1E88E5));
  final image = await recorder.endRecording().toImage(8, 8);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// El color del píxel (x, y) de lo que se ve dentro de [boundary].
Future<Color> pixel(RenderRepaintBoundary boundary, int x, int y) async {
  final image = await boundary.toImage();
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final i = (y * image.width + x) * 4;
  return Color.fromARGB(data.getUint8(i + 3), data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
}

void main() {
  testWidgets('el icono conserva sus colores de siempre (no se tiñe con el tema)', (tester) async {
    final icon = (await tester.runAsync(twoToneIcon))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: RepaintBoundary(key: const Key('rb'), child: ScanlineAppIcon(bytes: icon, size: 8, lines: false))),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50))); // la imagen termina de decodificarse
    await tester.pump();
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('rb')));
    final top = (await tester.runAsync(() => pixel(boundary, 4, 1)))!;
    final bottom = (await tester.runAsync(() => pixel(boundary, 4, 6)))!;
    int ch(double v) => (v * 255).round();
    expect((ch(top.r), ch(top.g), ch(top.b)), (0xE5, 0x39, 0x35)); // rojo, como el PNG
    expect((ch(bottom.r), ch(bottom.g), ch(bottom.b)), (0x1E, 0x88, 0xE5)); // azul, como el PNG
  });

  testWidgets('las líneas de barrido borran filas del icono (se ve lo de detrás) y dejan el resto, sin cambiar sus colores', (tester) async {
    final icon = (await tester.runAsync(twoToneIcon))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: RepaintBoundary(key: const Key('rb'), child: ScanlineAppIcon(bytes: icon, size: 8))),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.byKey(const Key('icon-lines')), findsOneWidget);
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('rb')));
    // el dibujo (mitad de arriba): la fila 0 tiene línea y la 2 no
    final onLine = (await tester.runAsync(() => pixel(boundary, 4, 0)))!;
    final between = (await tester.runAsync(() => pixel(boundary, 4, 2)))!;
    expect((between.a * 255).round(), 255);
    expect(onLine.a, lessThan(between.a - 0.3));
    expect((between.r * 255).round(), 0xE5); // y lo que no borra sigue en su color
  });

  testWidgets('el filtro de la capa no cambia ningún color', (tester) async {
    expect(ScanlineAppIcon.sameColors, const ColorFilter.mode(Color(0x00000000), BlendMode.dst));
  });

  testWidgets('las apps de la pantalla de todas las apps llevan las líneas y van sin teñir', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: AppsArch(apps: [for (var i = 0; i < 3; i++) app('com.a$i', 'App $i')], onOpen: (_) {}, onClose: () {}))));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      expect(find.descendant(of: find.byKey(Key('arch-app-com.a$i')), matching: find.byKey(const Key('icon-lines'))), findsOneWidget, reason: 'app $i');
      final filter = tester.widget<ColorFiltered>(find.descendant(of: find.byKey(Key('arch-app-com.a$i')), matching: find.byType(ColorFiltered))).colorFilter;
      expect(filter, ScanlineAppIcon.sameColors, reason: 'app $i sin teñir');
    }
  });
}
