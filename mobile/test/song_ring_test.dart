import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/models/track.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/widgets/song_ring.dart';
import 'package:kyora_chat/ui/widgets/subalbum_strip.dart';

List<Track> tracks(int n) => [
  for (var i = 0; i < n; i++)
    Track(id: 't$i', title: 'Artista $i - Canción $i', fileName: 'x.mp3', storagePath: '', sizeBytes: 1, createdAt: DateTime.utc(2026)),
];

void main() {
  group('anillo (cuentas)', () {
    test('de 6 a 11 canciones el anillo se cierra; con otras cantidades es un arco', () {
      expect(
        [
          for (final n in [1, 5, 6, 8, 11, 12, 30]) SongRing.isClosed(n),
        ],
        [false, false, true, true, true, false, false],
      );
    });

    test('el ángulo entre dos canciones seguidas reparte la vuelta entera si es anillo cerrado', () {
      expect(SongRing.stepFor(8) * 8, closeTo(2 * math.pi, 1e-9));
      expect(SongRing.stepFor(3), closeTo(math.pi / 6, 1e-9)); // un arco: pasos fijos
    });

    test('la de enfrente está a 0, y en el anillo cerrado la última queda a la izquierda de la primera', () {
      expect(SongRing.angleOf(0, 0, 8), 0);
      expect(SongRing.angleOf(1, 0, 8), closeTo(SongRing.stepFor(8), 1e-9)); // a la derecha
      expect(SongRing.angleOf(7, 0, 8), closeTo(-SongRing.stepFor(8), 1e-9)); // el anillo da la vuelta
      expect(SongRing.angleOf(7, 0, 3), isNot(closeTo(-SongRing.stepFor(3), 1e-9))); // un arco no
    });
  });

  group('anillo (pantalla)', () {
    var selected = <int>[];
    var tapped = <String>[];

    Future<void> show(WidgetTester tester, int n, {int initial = 0}) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      selected = [];
      tapped = [];
      final list = tracks(n);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: SongRing(
              tracks: list,
              animation: const AlwaysStoppedAnimation(1),
              origin: Rect.zero,
              artOf: (_) => null,
              initialIndex: initial,
              onSelect: selected.add,
              onTap: (t, i) => tapped.add(t.id),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('arrastrar de lado gira: lo que pasa de media canción llega a la siguiente', (tester) async {
      await show(tester, 3);
      await tester.drag(find.byType(SongRing), const Offset(-30, 0));
      await tester.pumpAndSettle();
      expect(selected, isEmpty); // 30 px no llegan a media canción
      await tester.drag(find.byType(SongRing), const Offset(-100, 0));
      await tester.pumpAndSettle();
      expect(selected, [1]);
    });

    testWidgets('un arco tiene tope en la primera y en la última', (tester) async {
      await show(tester, 3);
      await tester.drag(find.byType(SongRing), const Offset(900, 0)); // hacia atrás de la primera
      await tester.pumpAndSettle();
      expect(selected, isEmpty);
      await tester.drag(find.byType(SongRing), const Offset(-900, 0));
      await tester.pumpAndSettle();
      expect(selected.last, 2);
      await tester.drag(find.byType(SongRing), const Offset(-900, 0));
      await tester.pumpAndSettle();
      expect(selected.last, 2); // no pasa de la última
    });

    testWidgets('un anillo cerrado da vueltas sin fin: tras la última vuelve la primera', (tester) async {
      await show(tester, 8);
      await tester.drag(find.byType(SongRing), const Offset(100, 0)); // hacia atrás de la primera: la última
      await tester.pumpAndSettle();
      expect(selected.last, 7);
      await tester.drag(find.byType(SongRing), const Offset(-100, 0));
      await tester.pumpAndSettle();
      expect(selected.last, 0);
    });

    testWidgets('tocar la portada de enfrente, o una de los lados, avisa con su canción', (tester) async {
      await show(tester, 3);
      await tester.tap(find.byKey(const ValueKey('ring-t0')));
      await tester.tap(find.byKey(const ValueKey('ring-t1'))); // una de las de al lado también recibe el toque
      await tester.tap(find.byKey(const ValueKey('ring-t2')));
      expect(tapped, ['t0', 't1', 't2']);
    });

    testWidgets('cada portada lleva el título de su canción, sin el artista', (tester) async {
      await show(tester, 3);
      expect(find.descendant(of: find.byKey(const ValueKey('ring-t1')), matching: find.text('Canción 1')), findsOneWidget);
    });

    testWidgets('con la lista vacía no se pinta nada y no falla', (tester) async {
      await show(tester, 0);
      expect(find.byType(GestureDetector), findsWidgets); // solo el del propio anillo
      expect(find.byKey(const ValueKey('ring-t0')), findsNothing);
    });
  });

  group('tira de subálbumes', () {
    testWidgets('tocar la tarjeta del centro la abre; tocar una de los lados la lleva al centro y luego se abre', (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: SubalbumStrip(
              albums: [
                for (final name in ['Uno', 'Dos', 'Tres']) SubAlbum(id: name, title: name, subtitle: '2 canciones', onOpen: (_) => opened.add(name)),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Uno'), findsOneWidget);
      await tester.tap(find.byKey(const Key('subalbum-Dos'))); // de al lado: primero va al centro
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      await tester.tap(find.byKey(const Key('subalbum-Dos')));
      await tester.pumpAndSettle();
      expect(opened, ['Dos']);
    });
  });
}
