import 'dart:io';
import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/widgets/app_backdrop.dart';
import 'package:kyora_chat/ui/widgets/cover.dart';
import 'package:kyora_chat/ui/widgets/cut_border.dart';
import 'package:kyora_chat/ui/widgets/cyber_panel.dart';
import 'package:kyora_chat/ui/widgets/lcd_image.dart';
import 'package:kyora_chat/ui/widgets/terminal_window.dart';

void main() {
  group('la forma de los componentes: cuadrados, sin esquinas redondas ni cortadas', () {
    test('las cuatro esquinas son rectas, se pida el corte que se pida', () {
      for (final border in const [CutBorder(), CutBorder(cut: 20), CutBorder(cut: 20, all: true), CutBorder(cut: 50)]) {
        final path = border.getOuterPath(const Rect.fromLTWH(0, 0, 200, 100));
        for (final corner in const [Offset(1, 1), Offset(199, 1), Offset(1, 99), Offset(199, 99)]) {
          expect(path.contains(corner), isTrue, reason: '$border en $corner');
        }
        expect(path.contains(const Offset(201, 50)), isFalse);
        expect(path.contains(const Offset(100, 101)), isFalse);
      }
    });

    testWidgets('un panel ciberpunk es un rectángulo con degradado oscuro, sin líneas de barrido', (tester) async {
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: const Scaffold(body: Center(child: CyberPanel(child: SizedBox(width: 200, height: 100))))));
      final paint = tester.widget<CustomPaint>(find.descendant(of: find.byType(CyberPanel), matching: find.byType(CustomPaint)).first);
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      paint.painter!.paint(canvas, const Size(200, 100));
      expect(recorder.endRecording(), isNotNull);
      expect(find.byKey(const Key('backdrop-lines')), findsNothing);
    });

    test('el tema usa esta forma en los botones, los campos y las hojas', () {
      final theme = buildTheme();
      expect(theme.filledButtonTheme.style!.shape!.resolve({}), isA<CutBorder>());
      expect(theme.outlinedButtonTheme.style!.shape!.resolve({}), isA<CutBorder>());
      expect(theme.textButtonTheme.style!.shape!.resolve({}), isA<CutBorder>());
      expect(theme.dialogTheme.shape, isA<CutBorder>());
      expect(theme.popupMenuTheme.shape, isA<CutBorder>());
      expect((theme.checkboxTheme.shape! as RoundedRectangleBorder).borderRadius, BorderRadius.zero);
    });

    testWidgets('la ventana de la terminal no tiene recortes redondeados y lleva el prompt abajo', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: const Scaffold(body: TerminalWindow(title: 'T', footer: Text('pie'), child: Text('cuerpo'))),
      ));
      expect(find.byType(ClipRRect), findsNothing);
      expect(find.byKey(const Key('terminal-footer')), findsOneWidget);
      expect(tester.getTopLeft(find.text('pie')).dy, greaterThan(tester.getTopLeft(find.text('cuerpo')).dy));
    });
  });

  group('la portada', () {
    testWidgets('se ve entera, con sus colores, sin pixelar, dentro de su marco cuadrado', (tester) async {
      final file = File('${Directory.systemTemp.path}/cover_test_none.png');
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: Cover(url: null, file: file.path, size: 200))));
      expect(find.byType(LcdImage), findsNothing); // ya no es un mosaico
      expect(find.byType(CoverFrame), findsOneWidget);
      expect(find.byType(ClipRRect), findsNothing);
    });
  });

  test('el fondo de las secciones se oscurece de verdad: la información se lee y el texto y la luz lucen', () {
    expect(kBackdropDim, inInclusiveRange(0.3, 0.6)); // plano y ligero
  });
}
