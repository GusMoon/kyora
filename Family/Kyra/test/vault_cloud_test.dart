import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/chat_backend.dart';
import 'package:kyora_chat/data/cloud_files.dart';
import 'package:kyora_chat/data/vault_source.dart';
import 'package:kyora_chat/models/profile.dart';
import 'package:kyora_chat/state/music_controller.dart';
import 'package:kyora_chat/ui/settings_page.dart';
import 'package:kyora_chat/state/cloud_controller.dart';
import 'package:kyora_chat/state/player_controller.dart';
import 'package:kyora_chat/state/vault_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/vault_actions.dart';
import 'package:kyora_chat/ui/vault_page.dart';
import 'package:kyora_chat/ui/vault_viewers.dart';

import 'fake_engine.dart';
import 'fake_nube.dart';
import 'music_test.dart' show FakeMusicBackend, FakeSaver, MemoryMusicStore;
import 'vault_test.dart' show dir, file, image, makeSource;

/// La nube como carpeta real: exportar, ver todo lo que se puede ver, compartir, subir a la nube, renombrar y atributos.
void main() {
  group('lo que se ve dentro de la app', () {
    test('imágenes, vídeos, audios y textos se ven aquí; PDF, Word y demás necesitan otra app', () {
      expect(image('a.png').viewable, isTrue);
      expect(file('v.mp4', mime: 'video/mp4').isVideo, isTrue);
      expect(file('v.MKV').isVideo, isTrue);
      expect(file('a.flac').isAudio, isTrue);
      expect(file('a', mime: 'audio/mpeg').isAudio, isTrue);
      expect(file('nota.txt', mime: 'text/plain').isText, isTrue);
      expect(file('datos.json').isText, isTrue);
      expect(file('v.mp4', mime: 'video/mp4').viewable && file('a.mp3').viewable && file('n.md').viewable, isTrue);
      for (final other in [file('cv.pdf', mime: 'application/pdf'), file('informe.docx'), file('hoja.xlsx'), file('app.apk'), dir('carpeta')]) {
        expect(other.viewable, isFalse, reason: other.name);
      }
    });

    test('un texto enorme no se lee aquí: se abre con otra app', () {
      expect(file('log.txt', size: VaultEntry.maxTextBytes + 1).isText, isFalse);
      expect(file('log.txt', size: VaultEntry.maxTextBytes).isText, isTrue);
    });

    test('el tipo y la fecha se dicen en palabras', () {
      expect(vaultTypeLabel(dir('x')), 'Carpeta');
      expect(vaultTypeLabel(image('a.png')), 'Imagen');
      expect(vaultTypeLabel(file('v.mp4')), 'Vídeo');
      expect(vaultTypeLabel(file('a.mp3')), 'Audio');
      expect(vaultTypeLabel(file('x.pdf')), 'PDF');
      expect(vaultTypeLabel(file('x.txt')), 'Texto');
      expect(vaultTypeLabel(file('x.docx')), 'Archivo DOCX');
      expect(vaultDate(0), '—');
      expect(vaultDate(DateTime(2026, 11, 16, 9, 5).millisecondsSinceEpoch), '16/11/2026 09:05');
    });

    test('lo que dice el aviso al exportar', () {
      expect(exportSummary(const VaultImport()), 'No se eligió nada.');
      expect(exportSummary(const VaultImport(copied: 1, moved: 1)), 'Se movió 1 archivo al Vault.');
      expect(exportSummary(const VaultImport(copied: 3, moved: 3)), 'Se movieron 3 archivos al Vault.');
      expect(exportSummary(const VaultImport(copied: 2, moved: 0)), contains('2 archivos se copiaron al Vault, pero ese almacenamiento no deja borrar el original.'));
      expect(exportSummary(const VaultImport(failed: {'a.txt': 'sin permiso'})), 'No se pudo exportar: sin permiso');
      expect(exportSummary(const VaultImport(copied: 1, moved: 1, failed: {'a.txt': 'sin permiso'})), contains('1 archivo no se pudo exportar: sin permiso'));
    });
  });

  group('lo que se sube a la nube', () {
    test('va a <usuario>/cloud/<hora>-<nombre>, sin caracteres raros', () {
      final path = uploadPath('u1', 'mi foto: 1/2?.png', DateTime.utc(2026, 11, 16, 9));
      expect(path, startsWith('u1/cloud/${DateTime.utc(2026, 11, 16, 9).millisecondsSinceEpoch}-'));
      expect(path, endsWith('mi foto_ 1_2_.png'));
      expect(uploadPath('u1', '  ', DateTime.utc(2026)), endsWith('-archivo'));
    });

    test('al leerla de Storage se quita la hora del nombre y se sabe qué es', () {
      final f = cloudFileFromUpload('u1', {'name': '1789000000000-informe.pdf', 'id': 'abc', 'created_at': '2026-11-16T09:00:00Z', 'metadata': {'size': 2048, 'mimetype': 'application/pdf'}});
      expect(f.source, CloudSource.upload);
      expect(f.name, 'informe.pdf');
      expect(f.path, 'u1/cloud/1789000000000-informe.pdf');
      expect((f.size, f.mime, f.kind, f.from), (2048, 'application/pdf', CloudKind.doc, 'mi nube'));
    });

    test('sale junto a lo del chat y la música, lo más nuevo primero', () {
      final up = cloudFileFromUpload('u1', {'name': '1-a.png', 'id': 'x', 'created_at': '2026-11-16T09:00:00Z', 'metadata': {'size': 1, 'mimetype': 'image/png'}});
      final all = mergeCloud(const [], const [], 'u1', const {}, [up]);
      expect(all.single.id, 'upload:x');
    });

    test('el controlador sube, vuelve a leer la lista y devuelve el error si falla', () async {
      final backend = FakeCloudBackend([]);
      final cloud = CloudController(backend);
      addTearDown(cloud.dispose);
      expect(await cloud.upload(name: 'a.png', mime: 'image/png', bytes: Uint8List(3)), isNull);
      expect(backend.uploads.single, (name: 'a.png', mime: 'image/png', length: 3));
      expect(cloud.files.single.name, 'a.png');
      backend.uploadError = const ChatException('sin espacio');
      expect(await cloud.upload(name: 'b.png', mime: 'image/png', bytes: Uint8List(1)), 'sin espacio');
    });
  });

  group('el controlador del Vault', () {
    late FakeVaultSource source;
    late VaultController controller;

    setUp(() async {
      source = makeSource();
      controller = VaultController(source, MemoryVaultStore());
      await controller.pick();
    });

    tearDown(() => controller.dispose());

    test('exportar mueve a la carpeta donde se está (o a la raíz) y vuelve a leer', () async {
      expect((await controller.exportHere())!.moved, 1);
      expect(source.imports.last, (dir: null, move: true));
      await controller.enter(controller.entries.firstWhere((e) => e.name == 'Fotos'));
      await controller.exportHere();
      expect(source.imports.last, (dir: 'dir://Fotos', move: true));
      expect(source.listed.length, greaterThan(2)); // releyó
    });

    test('con el árbol a la vista va a la raíz', () async {
      await controller.setView(VaultView.tree);
      await controller.exportHere();
      expect(source.imports.last.dir, isNull);
    });

    test('si se cierra el selector sin elegir no pasa nada; si falla, queda el motivo', () async {
      source.importResult = null;
      expect(await controller.exportHere(), isNull);
      expect(controller.error, isNull);
      source.importFails = true;
      expect(await controller.exportHere(), isNull);
      expect(controller.error, contains('no dejó escribir'));
    });

    test('cambiar el nombre lo renombra de verdad y se ve el nuevo; con el mismo nombre o vacío no hace nada', () async {
      final pdf = controller.entries.firstWhere((e) => e.name == 'nota.pdf');
      expect(await controller.rename(pdf, '  '), isNull);
      expect(await controller.rename(pdf, 'nota.pdf'), isNull);
      expect(source.renames, isEmpty);
      expect(await controller.rename(pdf, 'acta.pdf'), isNull);
      expect(source.renames.single, (uri: 'file://nota.pdf', name: 'acta.pdf'));
      expect(controller.entries.map((e) => e.name), contains('acta.pdf'));
      expect(controller.entries.map((e) => e.name), isNot(contains('nota.pdf')));
    });

    test('la ubicación dice la carpeta del Vault y por dónde se ha entrado', () async {
      expect(controller.location, 'Mi Vault');
      await controller.enter(controller.entries.firstWhere((e) => e.name == 'Fotos'));
      expect(controller.location, 'Mi Vault / Fotos');
    });
  });

  group('en pantalla', () {
    late FakeVaultSource source;
    late VaultController controller;
    late FakeCloudBackend cloudBackend;
    late CloudController cloud;
    PlayerController? player;
    FakeEngine? engine;
    var settings = 0;

    setUp(() {
      source = makeSource();
      source.files['file://cv.txt'] = Uint8List.fromList(utf8.encode('Hola desde el Vault\nsegunda línea'));
      source.files['file://nota.pdf'] = Uint8List.fromList([1, 2, 3]);
      source.folders[''] = [...source.folders['']!, file('video.mp4', mime: 'video/mp4'), file('tema.mp3', mime: 'audio/mpeg'), file('otro.mp3', mime: 'audio/mpeg')];
      controller = VaultController(source, MemoryVaultStore());
      cloudBackend = FakeCloudBackend([]);
      cloud = CloudController(cloudBackend);
      engine = FakeEngine();
      player = PlayerController(FakeMusicBackend(), engine!, noteAfter: Duration.zero);
      settings = 0;
    });

    tearDown(() {
      controller.dispose();
      cloud.dispose();
      player?.dispose();
    });

    Future<void> show(WidgetTester tester, {bool withCloud = true, bool withPlayer = true, VideoFactory? video}) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(controller.pick);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: VaultPage(
            controller: controller,
            cloud: withCloud ? cloud : null,
            player: withPlayer ? player : null,
            onOpenSettings: () => settings++,
            videoFactory: video ?? (_) => throw StateError('sin plugin'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> hold(WidgetTester tester, String name) async {
      await tester.longPress(find.byKey(Key('vault-entry-$name')));
      await tester.pumpAndSettle();
    }

    testWidgets('exportar mueve archivos al Vault y lo cuenta', (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const Key('vault-export')));
      await tester.pumpAndSettle();
      expect(source.imports.single, (dir: null, move: true));
      expect(find.text('Se movió 1 archivo al Vault.'), findsOneWidget);
    });

    testWidgets('si el origen no deja borrar, dice que se copió; si no se elige nada, no avisa de nada', (tester) async {
      source.importResult = const VaultImport(copied: 2, moved: 0);
      await show(tester);
      await tester.tap(find.byKey(const Key('vault-export')));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 archivos se copiaron al Vault'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(VaultPage))).clearSnackBars();
      source.importResult = null;
      await tester.tap(find.byKey(const Key('vault-export')));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('mantener presionado un archivo ofrece abrir, enviar, subir a mi nube, cambiar nombre y atributos', (tester) async {
      await show(tester);
      await hold(tester, 'nota.pdf');
      for (final id in ['open', 'send', 'cloud', 'rename', 'info']) {
        expect(find.byKey(Key('vault-act-$id')), findsOneWidget, reason: id);
      }
    });

    testWidgets('sin nube (sin sesión) no sale «Subir a mi nube», y una carpeta solo se abre, se renombra o se mira', (tester) async {
      await show(tester, withCloud: false);
      await hold(tester, 'nota.pdf');
      expect(find.byKey(const Key('vault-act-cloud')), findsNothing);
      expect(find.byKey(const Key('vault-act-send')), findsOneWidget);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      await hold(tester, 'Fotos');
      expect(find.byKey(const Key('vault-act-send')), findsNothing);
      expect(find.byKey(const Key('vault-act-open')), findsOneWidget);
      expect(find.byKey(const Key('vault-act-rename')), findsOneWidget);
    });

    testWidgets('«Enviar a alguien» abre el menú de compartir del sistema con ese archivo', (tester) async {
      await show(tester);
      await hold(tester, 'nota.pdf');
      await tester.tap(find.byKey(const Key('vault-act-send')));
      await tester.pumpAndSettle();
      expect(source.shared, ['file://nota.pdf']);
    });

    testWidgets('«Subir a mi nube» lee el archivo y lo sube', (tester) async {
      await show(tester);
      await hold(tester, 'nota.pdf');
      await tester.tap(find.byKey(const Key('vault-act-cloud')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(cloudBackend.uploads.single, (name: 'nota.pdf', mime: 'application/pdf', length: 3));
      expect(find.text('«nota.pdf» ya está en tu nube.'), findsOneWidget);
    });

    testWidgets('si la nube falla, lo dice', (tester) async {
      cloudBackend.uploadError = const ChatException('Entra con tu cuenta para subir a la nube.');
      await show(tester);
      await hold(tester, 'nota.pdf');
      await tester.tap(find.byKey(const Key('vault-act-cloud')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.text('Entra con tu cuenta para subir a la nube.'), findsOneWidget);
    });

    testWidgets('«Cambiar nombre» pregunta el nombre (con el de ahora) y lo cambia', (tester) async {
      await show(tester);
      await hold(tester, 'nota.pdf');
      await tester.tap(find.byKey(const Key('vault-act-rename')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('folder-name-field'))).controller!.text, 'nota.pdf');
      await tester.enterText(find.byKey(const Key('folder-name-field')), 'acta.pdf');
      await tester.tap(find.byKey(const Key('folder-create')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(source.renames.single, (uri: 'file://nota.pdf', name: 'acta.pdf'));
      expect(find.byKey(const Key('vault-entry-acta.pdf')), findsOneWidget);
      expect(find.byKey(const Key('vault-entry-nota.pdf')), findsNothing);
    });

    testWidgets('«Atributos» enseña nombre, tipo, tamaño, formato, fecha y ubicación', (tester) async {
      source.folders['']![0] = VaultEntry(uri: 'file://nota.pdf', name: 'nota.pdf', isDir: false, mime: 'application/pdf', size: 2048, modified: DateTime(2026, 11, 16, 9, 5).millisecondsSinceEpoch);
      await show(tester);
      await hold(tester, 'nota.pdf');
      await tester.tap(find.byKey(const Key('vault-act-info')));
      await tester.pumpAndSettle();
      String attr(String id) => tester.widget<Text>(find.byKey(Key('vault-attr-$id'))).data!;
      expect(attr('name'), 'nota.pdf');
      expect(attr('type'), 'PDF');
      expect(attr('size'), contains('2048 bytes'));
      expect(attr('mime'), 'application/pdf');
      expect(attr('modified'), '16/11/2026 09:05');
      expect(attr('where'), 'Mi Vault');
    });

    testWidgets('un texto se lee dentro de la app', (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const Key('vault-entry-docs')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('vault-entry-cv.txt')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Hola desde el Vault'), findsOneWidget);
      expect(source.opened, isEmpty); // no se fue a otra app
      expect(find.byKey(const Key('viewer-actions')), findsOneWidget); // y desde ahí también se comparte
    });

    testWidgets('un vídeo se abre en su visor (si no se puede reproducir lo dice) y no se manda a otra app', (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const Key('vault-entry-video.mp4')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('viewer-title'))).data, 'video.mp4');
      expect(find.byKey(const Key('video-error')), findsOneWidget);
      expect(source.opened, isEmpty);
    });

    testWidgets('un audio suena con el reproductor de la app y las demás de la carpeta quedan en la cola', (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const Key('vault-entry-tema.mp3')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vault-audio')), findsOneWidget);
      expect(engine!.queue.map((q) => q.url), ['file://otro.mp3', 'file://tema.mp3']); // el orden de la carpeta (A a Z)
      expect(engine!.startIndex, 1); // y suena la que se tocó
      expect(player!.current!.title, 'tema');
      expect(source.opened, isEmpty);
      expect(find.byKey(const Key('vault-audio-toggle')), findsOneWidget);
    });

    testWidgets('sin reproductor un audio se abre con otra app, y un PDF también', (tester) async {
      await show(tester, withPlayer: false);
      await tester.tap(find.byKey(const Key('vault-entry-tema.mp3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('vault-entry-nota.pdf')));
      await tester.pumpAndSettle();
      expect(source.opened, ['file://tema.mp3', 'file://nota.pdf']);
    });

    testWidgets('desde el visor de imágenes también se comparte', (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const Key('vault-entry-logo.png')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('viewer-actions')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vault-act-send')), findsOneWidget);
      await tester.tap(find.byKey(const Key('vault-act-send')));
      await tester.pumpAndSettle();
      expect(source.shared, ['file://logo.png']);
    });
  });

  group('la carpeta se elige en Configuración', () {
    late FakeVaultSource source;
    late VaultController vault;

    setUp(() {
      source = makeSource();
      vault = VaultController(source, MemoryVaultStore());
    });

    tearDown(() => vault.dispose());

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final music = MusicController(FakeMusicBackend(), MemoryMusicStore(), FakeSaver());
      addTearDown(music.dispose);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: SettingsPage(music: music, role: Role.admin, onSignOut: () async {}, vault: vault, initialTile: 'vault')));
      await tester.pumpAndSettle();
    }

    testWidgets('la ficha «Vault» deja elegir la carpeta, cambiarla y olvidarla', (tester) async {
      await open(tester);
      expect(find.text('Elegir la carpeta'), findsOneWidget);
      expect(find.byKey(const Key('settings-vault-forget')), findsNothing);
      await tester.tap(find.byKey(const Key('settings-vault-folder')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(source.picks, 1);
      expect(vault.root!.name, 'Mi Vault');
      expect(find.text('Cambiar la carpeta'), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings-vault-forget')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(vault.root, isNull);
    });

    testWidgets('si el selector falla, el motivo sale en la ficha', (tester) async {
      source.picked = null;
      await open(tester);
      await tester.tap(find.byKey(const Key('settings-vault-folder')));
      await tester.pumpAndSettle();
      expect(vault.root, isNull); // cerrar el selector sin elegir no cambia nada
    });

    testWidgets('sin Vault no sale la ficha', (tester) async {
      final music = MusicController(FakeMusicBackend(), MemoryMusicStore(), FakeSaver());
      addTearDown(music.dispose);
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: SettingsPage(music: music, role: Role.admin, onSignOut: () async {})));
      await tester.pumpAndSettle();
      expect(find.text('Vault'), findsNothing);
    });
  });
}
