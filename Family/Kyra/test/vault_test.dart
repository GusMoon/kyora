import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/vault_source.dart';
import 'package:kyora_chat/state/vault_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/vault_page.dart';

/// Un PNG de un punto: lo justo para que haya bytes de imagen.
final _png = Uint8List.fromList(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='));

VaultEntry dir(String name, [String? uri]) => VaultEntry(uri: uri ?? 'dir://$name', name: name, isDir: true, mime: 'vnd.android.document/directory');
VaultEntry file(String name, {String mime = '', int size = 1500, String? uri}) => VaultEntry(uri: uri ?? 'file://$name', name: name, isDir: false, mime: mime, size: size);
VaultEntry image(String name) => file(name, mime: 'image/png');

/// Un Vault con: la raíz (una carpeta «Fotos», una «docs», un PDF y una imagen suelta) y dentro de «Fotos» otra carpeta y dos imágenes.
FakeVaultSource makeSource() => FakeVaultSource(
  folders: {
    '': [file('nota.pdf', mime: 'application/pdf'), dir('docs'), image('logo.png'), dir('Fotos')],
    'dir://Fotos': [image('b.png'), dir('2026'), image('a.png')],
    'dir://docs': [file('cv.txt', mime: 'text/plain')],
    'dir://2026': [image('c.png')],
  },
  files: {for (final n in ['logo.png', 'a.png', 'b.png', 'c.png']) 'file://$n': _png},
);

void main() {
  group('los archivos', () {
    test('una imagen se reconoce por su tipo o por su extensión', () {
      expect(image('x').isImage, isTrue);
      expect(file('foto.JPG').isImage, isTrue);
      expect(file('doc.pdf', mime: 'application/pdf').isImage, isFalse);
      expect(dir('imagenes.png').isImage, isFalse);
    });

    test('las HEIC son imágenes pero no se pueden enseñar aquí: se abren con otra app', () {
      expect(file('foto.heic', mime: 'image/heic').isImage, isTrue);
      expect(file('foto.heic', mime: 'image/heic').canShow, isFalse);
      expect(image('a.png').canShow, isTrue);
    });

    test('primero las carpetas y luego los archivos, de la A a la Z', () {
      final list = [file('b.txt'), dir('zeta'), file('A.txt'), dir('alfa')]..sort(compareVaultEntries);
      expect([for (final e in list) e.name], ['alfa', 'zeta', 'A.txt', 'b.txt']);
    });
  });

  group('el controlador', () {
    late FakeVaultSource source;
    late MemoryVaultStore store;
    late VaultController controller;

    setUp(() {
      source = makeSource();
      store = MemoryVaultStore();
      controller = VaultController(source, store);
    });

    tearDown(() => controller.dispose());

    test('sin carpeta elegida no hay nada; al elegir una se lee y se recuerda', () async {
      expect(controller.root, isNull);
      expect(await controller.pick(), isTrue);
      expect(controller.root?.name, 'Mi Vault');
      expect([for (final e in controller.entries) e.name], ['docs', 'Fotos', 'logo.png', 'nota.pdf']);
      expect(store.folder?.uri, 'tree://vault');
      // al abrir la app otra vez, la carpeta ya está
      final again = VaultController(source, store);
      addTearDown(again.dispose);
      expect(again.root?.uri, 'tree://vault');
    });

    test('cerrar el selector sin elegir no cambia nada', () async {
      source.picked = null;
      expect(await controller.pick(), isFalse);
      expect(controller.root, isNull);
    });

    test('se entra en una carpeta, se sube y se vuelve a un punto del camino', () async {
      await controller.pick();
      await controller.enter(controller.entries.firstWhere((e) => e.name == 'Fotos'));
      expect([for (final e in controller.trail) e.name], ['Fotos']);
      expect([for (final e in controller.entries) e.name], ['2026', 'a.png', 'b.png']);
      expect(controller.canGoUp, isTrue);
      await controller.enter(controller.entries.first);
      expect([for (final e in controller.trail) e.name], ['Fotos', '2026']);
      await controller.goTo(1);
      expect([for (final e in controller.trail) e.name], ['Fotos']);
      await controller.up();
      expect(controller.canGoUp, isFalse);
      expect(controller.entries.length, 4);
      await controller.goTo(0); // ya en la raíz: nada
      expect(controller.trail, isEmpty);
    });

    test('las imágenes de la carpeta de ahora son las que se pueden enseñar, en orden', () async {
      await controller.pick();
      await controller.enter(controller.entries.firstWhere((e) => e.name == 'Fotos'));
      expect([for (final e in controller.images) e.name], ['a.png', 'b.png']);
    });

    test('si la carpeta se perdió lo dice y pide elegirla otra vez; si no, deja reintentar', () async {
      await controller.pick();
      source
        ..failing = true
        ..lost = true;
      await controller.refresh();
      expect(controller.error, isNotNull);
      expect(controller.lost, isTrue);
      expect(controller.entries, isEmpty);
      source
        ..failing = false
        ..lost = false;
      await controller.refresh();
      expect(controller.error, isNull);
      expect(controller.entries, isNotEmpty);
    });

    test('olvidar la carpeta deja el Vault vacío', () async {
      await controller.pick();
      await controller.forget();
      expect(controller.root, isNull);
      expect(controller.entries, isEmpty);
      expect(store.folder, isNull);
    });

    test('el árbol: parte de la raíz, abre y cierra carpetas en su sitio y sangra a los hijos', () async {
      await controller.pick();
      await controller.setView(VaultView.tree);
      expect(store.tree, isTrue);
      expect([for (final r in controller.rows) r.entry.name], ['docs', 'Fotos', 'logo.png', 'nota.pdf']);
      final fotos = controller.rows.firstWhere((r) => r.entry.name == 'Fotos').entry;
      await controller.toggle(fotos);
      expect([for (final r in controller.rows) '${r.depth}:${r.entry.name}'], ['0:docs', '0:Fotos', '1:2026', '1:a.png', '1:b.png', '0:logo.png', '0:nota.pdf']);
      await controller.toggle(controller.rows.firstWhere((r) => r.entry.name == '2026').entry);
      expect(controller.rows.map((r) => r.entry.name), contains('c.png'));
      expect(controller.rows.firstWhere((r) => r.entry.name == 'c.png').depth, 2);
      await controller.toggle(fotos); // se cierra
      expect(controller.rows.map((r) => r.entry.name), ['docs', 'Fotos', 'logo.png', 'nota.pdf']);
      final before = source.listed.length;
      await controller.toggle(fotos); // al abrir otra vez no se vuelve a leer
      expect(source.listed.length, before);
      expect(controller.rows.map((r) => r.entry.name), contains('a.png'));
    });

    test('el modo se recuerda', () async {
      await controller.setView(VaultView.tree);
      final again = VaultController(source, store);
      addTearDown(again.dispose);
      expect(again.view, VaultView.tree);
      await again.toggleView();
      expect(store.tree, isFalse);
    });

    test('las imágenes reducidas se piden una sola vez cada una', () async {
      final a = image('a.png');
      await controller.thumb(a);
      await controller.thumb(a);
      expect(source.thumbs, ['file://a.png']);
    });
  });

  group('la pantalla', () {
    late FakeVaultSource source;
    late MemoryVaultStore store;
    late VaultController controller;

    setUp(() {
      source = makeSource();
      store = MemoryVaultStore(folder: const VaultFolder(uri: 'tree://vault', name: 'Mi Vault'));
      controller = VaultController(source, store);
    });

    tearDown(() => controller.dispose());

    Future<void> show(WidgetTester tester, {Size size = const Size(400, 850)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: VaultPage(controller: controller)));
      await tester.pumpAndSettle();
    }

    testWidgets('sin carpeta elegida invita a elegirla; al elegirla sale su contenido', (tester) async {
      store.folder = null;
      controller = VaultController(source, store);
      await show(tester);
      expect(find.byKey(const Key('vault-pick')), findsOneWidget);
      await tester.tap(find.byKey(const Key('vault-pick')));
      await tester.pumpAndSettle();
      expect(source.picks, 1);
      expect(find.byKey(const Key('vault-name')), findsOneWidget);
      expect(find.byKey(const Key('vault-entry-Fotos')), findsOneWidget);
    });

    testWidgets('en cuadrícula: carpetas, archivos y las imágenes tal cual, sin nada encima', (tester) async {
      await show(tester);
      expect(tester.widget<Text>(find.byKey(const Key('vault-name'))).data, 'MI VAULT');
      expect(find.byKey(const Key('vault-entry-docs')), findsOneWidget);
      expect(find.text('nota.pdf'), findsOneWidget); // un archivo: su nombre
      // una imagen: la imagen misma, sin pixelar ni capas de efecto
      final tile = find.byKey(const Key('vault-entry-logo.png'));
      expect(find.descendant(of: tile, matching: find.byType(Image)), findsOneWidget);
      expect(find.descendant(of: tile, matching: find.byType(ColorFiltered)), findsNothing);
      expect(find.descendant(of: tile, matching: find.byType(BackdropFilter)), findsNothing);
      expect(find.descendant(of: tile, matching: find.byType(ImageFiltered)), findsNothing);
      expect(find.text('logo.png'), findsNothing); // la imagen no lleva rótulo encima
    });

    testWidgets('tocar una carpeta entra; el camino de arriba lleva de vuelta; «atrás» sube', (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const Key('vault-entry-Fotos')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vault-entry-a.png')), findsOneWidget);
      expect(find.byKey(const Key('vault-entry-nota.pdf')), findsNothing);
      expect(find.byKey(const Key('crumb-1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('vault-entry-2026')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('crumb-2')), findsOneWidget);
      await tester.binding.handlePopRoute(); // «atrás»: sube una carpeta
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vault-entry-a.png')), findsOneWidget);
      await tester.tap(find.byKey(const Key('crumb-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vault-entry-nota.pdf')), findsOneWidget);
      expect(find.byKey(const Key('crumb-1')), findsNothing);
    });

    testWidgets('tocar una imagen la abre entera, tal cual, con su nombre y su lugar entre las de la carpeta; se pasa a la siguiente deslizando', (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const Key('vault-entry-Fotos')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('vault-entry-a.png')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('viewer-title'))).data, 'a.png');
      expect(tester.widget<Text>(find.byKey(const Key('viewer-count'))).data, '1/2');
      final shown = tester.widget<Image>(find.byKey(const Key('viewer-image-a.png')));
      expect(shown.fit, BoxFit.contain);
      expect(find.byType(ColorFiltered), findsNothing);
      expect(find.byType(ImageFiltered), findsNothing);
      await tester.fling(find.byKey(const Key('viewer-pages')), const Offset(-400, 0), 1500);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('viewer-title'))).data, 'b.png');
      expect(tester.widget<Text>(find.byKey(const Key('viewer-count'))).data, '2/2');
    });

    testWidgets('una imagen que no se puede leer lo dice', (tester) async {
      source.files.remove('file://logo.png');
      await show(tester);
      await tester.tap(find.byKey(const Key('vault-entry-logo.png')));
      await tester.pumpAndSettle();
      expect(find.text('No se pudo abrir esta imagen'), findsOneWidget);
    });

    testWidgets('un archivo que no es imagen se abre con otra app del teléfono', (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const Key('vault-entry-nota.pdf')));
      await tester.pumpAndSettle();
      expect(source.opened, ['file://nota.pdf']);
    });

    testWidgets('el botón de modo cambia a árbol: las carpetas se abren en su sitio, con las imágenes pequeñas', (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const Key('vault-view')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vault-tree')), findsOneWidget);
      expect(find.byKey(const Key('crumb-0')), findsNothing); // el camino es de la cuadrícula
      await tester.tap(find.byKey(const Key('vault-row-Fotos')));
      await tester.pumpAndSettle();
      final fotos = tester.getTopLeft(find.text('Fotos')).dx;
      final child = tester.getTopLeft(find.text('a.png')).dx;
      expect(child, greaterThan(fotos)); // sangrado
      expect(find.descendant(of: find.byKey(const Key('vault-row-a.png')), matching: find.byType(Image)), findsOneWidget);
      // tocar una imagen del árbol la abre, con las demás visibles para pasar
      await tester.tap(find.byKey(const Key('vault-row-b.png')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('viewer-title'))).data, 'b.png');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('vault-view'))); // y de vuelta a la cuadrícula
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vault-grid')), findsOneWidget);
    });

    testWidgets('con la carpeta perdida ofrece elegir otra', (tester) async {
      source
        ..failing = true
        ..lost = true;
      await show(tester);
      expect(find.byKey(const Key('vault-repick')), findsOneWidget);
      await tester.tap(find.byKey(const Key('vault-repick')));
      await tester.pumpAndSettle();
      expect(source.picks, 1);
    });

    testWidgets('una carpeta vacía lo dice', (tester) async {
      source.folders[''] = [];
      await show(tester);
      expect(find.text('> carpeta vacía'), findsOneWidget);
    });

    testWidgets('el botón de cambiar de carpeta abre el selector', (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const Key('vault-change')));
      await tester.pumpAndSettle();
      expect(source.picks, 1);
    });

    testWidgets('en una pantalla baja y estrecha no se desborda', (tester) async {
      await show(tester, size: const Size(320, 560));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('vault-view')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
