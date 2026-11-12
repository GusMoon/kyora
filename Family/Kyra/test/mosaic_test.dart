import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/settings_mosaic.dart';

const _tiles = [
  MosaicTile('a', 2, 2),
  MosaicTile('b', 2, 1),
  MosaicTile('c', 2, 1),
  MosaicTile('d', 4, 1),
  MosaicTile('e', 3, 2),
  MosaicTile('f', 1, 2),
];

bool _overlap(Rect a, Rect b) => a.deflate(0.01).overlaps(b.deflate(0.01));

void main() {
  group('el reparto de las fichas', () {
    test('cada una va al primer hueco libre, de izquierda a derecha y de arriba abajo', () {
      final packed = packMosaic(_tiles);
      expect(packed.cells['a'], (col: 0, row: 0));
      expect(packed.cells['b'], (col: 2, row: 0));
      expect(packed.cells['c'], (col: 2, row: 1));
      expect(packed.cells['d'], (col: 0, row: 2));
      expect(packed.cells['e'], (col: 0, row: 3));
      expect(packed.cells['f'], (col: 3, row: 3));
      expect(packed.rows, 5);
    });

    test('si falta una ficha las demás se reacomodan sin dejar agujeros', () {
      final packed = packMosaic([for (final t in _tiles) if (t.id != 'c') t]);
      expect(packed.cells.length, 5);
      // d (4 anchas) no cabe a los lados de a y b: baja a la primera fila libre completa
      expect(packed.cells['d']!.row, 2);
      expect(packed.rows, lessThanOrEqualTo(5));
    });

    test('una ficha más ancha que el espacio que queda salta a la fila siguiente', () {
      final packed = packMosaic(const [MosaicTile('x', 3, 1), MosaicTile('y', 2, 1)]);
      expect(packed.cells['x'], (col: 0, row: 0));
      expect(packed.cells['y'], (col: 0, row: 1));
    });

    test('sin fichas no hay filas', () => expect(packMosaic(const []).rows, 0));
  });

  group('los rectángulos', () {
    const area = Size(368, 700);

    test('el mosaico entero: todo dentro del área, sin pisarse y con los tamaños de cada ficha', () {
      final r = mosaicRects(area, _tiles, null);
      expect(r.length, 6);
      for (final rect in r.values) {
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(area.width + 0.001));
        expect(rect.bottom, lessThanOrEqualTo(area.height + 0.001));
      }
      for (final a in r.keys) {
        for (final b in r.keys) {
          if (a.compareTo(b) < 0) expect(_overlap(r[a]!, r[b]!), isFalse, reason: '$a / $b');
        }
      }
      expect(r['a']!.width, closeTo(r['a']!.height, r['a']!.height * 0.5)); // 2×2
      expect(r['d']!.width, closeTo(area.width, 0.001)); // 4 columnas = todo el ancho
      expect(r['e']!.width, greaterThan(r['b']!.width)); // 3 columnas contra 2
      expect(r['f']!.height, greaterThan(r['f']!.width)); // alta y estrecha
    });

    test('con pocas fichas las celdas no se estiran sin límite', () {
      final r = mosaicRects(const Size(368, 900), const [MosaicTile('a', 2, 1), MosaicTile('b', 2, 1)], null);
      expect(r['a']!.height, lessThan(200));
    });

    test('expandida una: ocupa todo el ancho y casi todo el alto; las demás, en una franja de abajo, iguales y sin pisarse', () {
      final r = mosaicRects(area, _tiles, 'c');
      expect(r['c']!.left, 0);
      expect(r['c']!.top, 0);
      expect(r['c']!.width, area.width);
      expect(r['c']!.height, greaterThan(area.height * 0.8));
      final others = [for (final id in ['a', 'b', 'd', 'e', 'f']) r[id]!];
      for (final o in others) {
        expect(o.top, greaterThan(r['c']!.bottom));
        expect(o.bottom, closeTo(area.height, 0.001));
        expect(o.width, closeTo(others.first.width, 0.001));
      }
      expect(others.last.right, closeTo(area.width, 0.001));
      for (var i = 1; i < others.length; i++) {
        expect(others[i].left, greaterThan(others[i - 1].right));
      }
    });

    test('una ficha que no existe, o ninguna, es el mosaico entero', () {
      expect(mosaicRects(area, _tiles, 'zzz'), mosaicRects(area, _tiles, null));
    });

    test('expandir con una sola ficha no falla', () {
      final r = mosaicRects(area, const [MosaicTile('a', 2, 2)], 'a');
      expect(r['a']!.width, area.width);
    });

    test('sin fichas, nada', () => expect(mosaicRects(area, const [], null), isEmpty));
  });

  group('MosaicView', () {
    Widget entry(String id) => Text('resumen $id');

    List<MosaicEntry> entries() => [
      for (final t in _tiles)
        MosaicEntry(
          id: t.id,
          title: 'Ficha ${t.id}',
          code: 'T·${t.id}',
          icon: Icons.circle_outlined,
          colSpan: t.colSpan,
          rowSpan: t.rowSpan,
          summary: (context, height) => entry(t.id),
          detail: (context) => Text('detalle ${t.id}'),
        ),
    ];

    Future<void> show(WidgetTester tester, String? Function() current, void Function(String?) set, {Size size = const Size(368, 700)}) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox.fromSize(
              size: size,
              child: StatefulBuilder(builder: (context, setState) => MosaicView(entries: entries(), expandedId: current(), onExpand: (id) => setState(() => set(id)))),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('al entrar las fichas aparecen escalonadas: no todas a la vez', (tester) async {
      String? open;
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: MosaicView(entries: entries(), expandedId: open, onExpand: (_) {})),
      ));
      await tester.pump(const Duration(milliseconds: 150));
      double opacityOf(String id) => tester.widget<Opacity>(find.ancestor(of: find.byKey(Key('mosaic-tile-$id')), matching: find.byType(Opacity)).last).opacity;
      expect(opacityOf('a'), greaterThan(opacityOf('f'))); // la primera ya se ve más que la última
      await tester.pumpAndSettle();
      expect(opacityOf('f'), 1);
    });

    testWidgets('tocar una ficha la expande, y la X o volver a pedirlo con null la cierra', (tester) async {
      String? open;
      await show(tester, () => open, (id) => open = id);
      await tester.tap(find.byKey(const Key('mosaic-tile-b')));
      await tester.pumpAndSettle();
      expect(open, 'b');
      expect(find.text('detalle b'), findsOneWidget);
      expect(find.text('resumen b'), findsNothing);
      await tester.tap(find.byKey(const Key('mosaic-close')));
      await tester.pumpAndSettle();
      expect(open, isNull);
      expect(find.text('resumen b'), findsOneWidget);
      expect(find.text('detalle b'), findsNothing);
    });

    testWidgets('las fichas de la franja se pueden tocar para cambiar de ficha', (tester) async {
      String? open = 'a';
      await show(tester, () => open, (id) => open = id);
      expect(find.text('detalle a'), findsOneWidget);
      await tester.tap(find.byKey(const Key('mosaic-tile-e')));
      await tester.pumpAndSettle();
      expect(open, 'e');
      expect(find.text('detalle e'), findsOneWidget);
    });

    testWidgets('la expandida va por encima de las demás', (tester) async {
      String? open = 'a';
      await show(tester, () => open, (id) => open = id);
      final order = [for (final w in tester.widgetList<Positioned>(find.byType(Positioned))) w.key].whereType<ValueKey<String>>().map((k) => k.value).where((v) => v.startsWith('mosaic-pos-')).toList();
      expect(order.last, 'mosaic-pos-a');
    });

    testWidgets('el panel de cada ficha lleva el estilo ciberpunk: esquinas cortadas, sin desenfoque', (tester) async {
      String? open;
      await show(tester, () => open, (id) => open = id);
      expect(find.byType(CyberPanel), findsNWidgets(6));
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('el panel expandido se enciende (activo) y los cerrados no', (tester) async {
      String? open = 'c';
      await show(tester, () => open, (id) => open = id);
      expect(tester.widget<CyberPanel>(find.byKey(const Key('mosaic-tile-c'))).active, 1);
      expect(tester.widget<CyberPanel>(find.byKey(const Key('mosaic-tile-a'))).active, 0);
    });

    testWidgets('si cambia el tamaño del área (teclado, girar) las fichas la siguen sin animar y sin errores', (tester) async {
      String? open = 'c';
      await show(tester, () => open, (id) => open = id);
      tester.view.physicalSize = const Size(400, 500);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
