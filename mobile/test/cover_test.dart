import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/cover_store.dart';
import 'package:kyora_chat/data/favorites_store.dart';
import 'package:kyora_chat/data/music_store.dart';
import 'package:kyora_chat/models/track.dart';
import 'package:kyora_chat/state/local_music_controller.dart';
import 'package:kyora_chat/state/music_controller.dart';
import 'package:kyora_chat/state/player_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/music_page.dart';
import 'package:kyora_chat/ui/widgets/cover.dart';
import 'package:kyora_chat/util/id3_cover.dart';

import 'fake_engine.dart';
import 'music_test.dart' show FakeMusicBackend, FakeSaver, MemoryMusicStore;

final audio = Uint8List.fromList([for (var i = 0; i < 400; i++) i % 256]);
final picture = Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2, 3, 0xFF, 0xD9]);

List<int> syncsafe(int v) => [(v >> 21) & 0x7F, (v >> 14) & 0x7F, (v >> 7) & 0x7F, v & 0x7F];
List<int> big(int v) => [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

List<int> frame(String id, List<int> data, int version) => [
  ...ascii.encode(id),
  ...(version == 4 ? syncsafe(data.length) : big(data.length)),
  0,
  0,
  ...data,
];

Uint8List tagged(int version, List<List<int>> frames, {int flags = 0, int padding = 0, List<int> before = const []}) {
  final body = [...before, for (final f in frames) ...f, ...List.filled(padding, 0)];
  return Uint8List.fromList([...ascii.encode('ID3'), version, 0, flags, ...syncsafe(body.length), ...body, ...audio]);
}

/// Un lector aparte (no el código que se prueba): `{nombre del dato: su contenido}` y dónde empieza el audio.
({Map<String, List<int>> frames, int audioStart, int version}) parse(Uint8List file) {
  expect(ascii.decode(file.sublist(0, 3)), 'ID3');
  final version = file[3];
  final size = (file[6] << 21) | (file[7] << 14) | (file[8] << 7) | file[9];
  final frames = <String, List<int>>{};
  var at = 10;
  while (at < 10 + size) {
    final id = ascii.decode(file.sublist(at, at + 4));
    final n = version == 4
        ? (file[at + 4] << 21) | (file[at + 5] << 14) | (file[at + 6] << 7) | file[at + 7]
        : (file[at + 4] << 24) | (file[at + 5] << 16) | (file[at + 6] << 8) | file[at + 7];
    expect(frames.containsKey(id), isFalse, reason: 'dato repetido: $id');
    frames[id] = file.sublist(at + 10, at + 10 + n);
    at += 10 + n;
  }
  expect(at, 10 + size);
  return (frames: frames, audioStart: 10 + size, version: version);
}

void expectGood(Uint8List result, {required int version, required Map<String, List<int>> keeps}) {
  final read = parse(result);
  expect(read.version, version);
  expect(read.frames['APIC'], [0, ...ascii.encode('image/jpeg'), 0, 3, 0, ...picture]);
  keeps.forEach((id, data) => expect(read.frames[id], data, reason: id));
  expect(read.frames.keys.toSet(), {'APIC', ...keeps.keys});
  expect(result.sublist(read.audioStart), audio); // el audio, idéntico
}

void main() {
  final title = [3, ...utf8.encode('Canción')];

  group('escribir la imagen en el .mp3', () {
    test('un .mp3 sin etiqueta la estrena, y el audio queda igual', () {
      expectGood(withCover(audio, picture), version: 3, keeps: const {});
    });

    test('un archivo muy corto no se confunde con una etiqueta', () {
      final tiny = Uint8List.fromList(ascii.encode('ID3'));
      final result = withCover(tiny, picture);
      expect(result.sublist(result.length - 3), tiny);
    });

    for (final version in [3, 4]) {
      test('ID3v2.$version: reemplaza la imagen vieja y conserva lo demás', () {
        final old = frame('APIC', [0, ...ascii.encode('image/png'), 0, 3, 0, 9, 9, 9], version);
        final other = frame('APIC', [0, ...ascii.encode('image/png'), 0, 4, 0, 8, 8], version);
        final result = withCover(tagged(version, [frame('TIT2', title, version), old, frame('TPE1', title, version), other], padding: 64), picture);
        expectGood(result, version: version, keeps: {'TIT2': title, 'TPE1': title});
      });

      test('ID3v2.$version: cambiarla dos veces deja solo la última', () {
        final once = withCover(tagged(version, [frame('TIT2', title, version)]), Uint8List.fromList([1, 2, 3]));
        expectGood(withCover(once, picture), version: version, keeps: {'TIT2': title});
      });
    }

    test('la versión antigua (ID3v2.2) se pasa a la 2.3 conservando título y artista', () {
      List<int> old(String id, List<int> data) => [...ascii.encode(id), 0, 0, data.length, ...data];
      final v2 = tagged(2, [
        old('TT2', title),
        old('TP1', title),
        old('PIC', [0, 74, 80, 71, 3, 0, 9, 9]),
        old('XXX', [1]),
      ]);
      expectGood(withCover(v2, picture), version: 3, keeps: {'TIT2': title, 'TPE1': title});
    });

    test('v2.3 «sin sincronización»: se deshace antes de leerla', () {
      final data = [3, 0xFF, 0x00, 0xE0, 65];
      final clean = [3, 0xFF, 0xE0, 65];
      final raw = [...ascii.encode('TIT2'), ...big(clean.length), 0, 0, ...data];
      expectGood(withCover(tagged(3, [raw], flags: 0x80), picture), version: 3, keeps: {'TIT2': clean});
    });

    test('la cabecera extendida no se confunde con los datos', () {
      final v3 = tagged(3, [frame('TIT2', title, 3)], flags: 0x40, before: [...big(6), 0, 0, 0, 0, 0, 0]);
      expectGood(withCover(v3, picture), version: 3, keeps: {'TIT2': title});
      final v4 = tagged(4, [frame('TIT2', title, 4)], flags: 0x40, before: [...syncsafe(6), 1, 0]);
      expectGood(withCover(v4, picture), version: 4, keeps: {'TIT2': title});
    });

    test('v2.4 con pie al final: el audio empieza después del pie', () {
      final tag = tagged(4, [frame('TIT2', title, 4)], flags: 0x10);
      final tagEnd = tag.length - audio.length;
      final file = Uint8List.fromList([...tag.sublist(0, tagEnd), ...ascii.encode('3DI'), 4, 0, 0x10, ...tag.sublist(6, 10), ...audio]);
      expectGood(withCover(file, picture), version: 4, keeps: {'TIT2': title});
    });

    test('v2.4 con tamaños mal escritos por otros programas: se entienden', () {
      final data = List.filled(200, 65);
      final raw = [...ascii.encode('TIT2'), ...big(data.length), 0, 0, ...data];
      expectGood(withCover(tagged(4, [raw]), picture), version: 4, keeps: {'TIT2': data});
    });

    test('datos rotos dentro de la etiqueta: se conserva lo bueno y el audio no se toca', () {
      final broken = [...ascii.encode('TPE1'), ...big(9999), 0, 0, 1, 2, 3];
      expectGood(withCover(tagged(3, [frame('TIT2', title, 3), broken]), picture), version: 3, keeps: {'TIT2': title});
    });

    test('si no se sabe dónde empieza el audio no escribe nada', () {
      Uint8List bad(List<int> head) => Uint8List.fromList([...ascii.encode('ID3'), ...head, ...audio]);
      expect(() => withCover(bad([3, 0, 0, 0x7F, 0x7F, 0x7F, 0x7F]), picture), throwsFormatException); // más grande que el archivo
      expect(() => withCover(bad([3, 0, 0, 0x80, 0, 0, 0]), picture), throwsFormatException); // tamaño imposible
      expect(() => withCover(bad([9, 0, 0, 0, 0, 0, 0]), picture), throwsFormatException); // versión desconocida
    });
  });

  group('cambiar la imagen', () {
    late FakeMusicBackend backend;
    late MemoryMusicStore store;
    late FakeSaver saver;
    late MusicController music;
    late LocalMusicController local;
    late MemoryCoverStore covers;
    late FakeEngine engine;
    late PlayerController player;
    late FavoritesController favorites;

    const treeUri = 'content://tree/musica';
    String uri(String name) => '$treeUri/document/$name';
    LocalSong song(String name) => LocalSong(uri: uri(name), name: name, sizeBytes: 40, modified: DateTime.utc(2026, 1, 1));
    Track named(String title) => local.songs.firstWhere((t) => t.title == title);

    setUp(() {
      backend = FakeMusicBackend();
      store = MemoryMusicStore(since: DateTime.utc(2026, 10, 1))..settings = const MusicSettings(auto: false).withTree(treeUri, 'Mi música');
      saver = FakeSaver()..files = [song('a.mp3'), song('b.mp3'), song('c.mp3')];
      for (final f in saver.files) {
        saver.contents[f.uri] = audio;
      }
      covers = MemoryCoverStore();
      music = MusicController(backend, store, saver);
      local = LocalMusicController(music, saver, covers: covers);
      engine = FakeEngine();
      player = PlayerController(backend, engine, art: local, noteAfter: Duration.zero);
      favorites = FavoritesController();
    });

    tearDown(() {
      player.dispose();
      local.dispose();
      music.dispose();
    });

    test('a una del teléfono se le escribe dentro del archivo y la lista ya enseña la imagen nueva', () async {
      await music.start();
      await pumpEventQueue();
      final before = named('a');
      final updated = await local.changeCover(before, '/foto.jpg');
      expect(saver.written, [uri('a.mp3')]);
      final read = parse(saver.contents[uri('a.mp3')]!);
      expect(read.frames['APIC'], isNotNull);
      expect(saver.contents[uri('a.mp3')]!.sublist(read.audioStart), audio);
      expect(local.artOf(named('a')), saver.storedCovers.single.path);
      expect(saver.storedCovers.single.keep, isFalse); // se puede volver a leer del .mp3
      expect(updated.durationKey, isNot(before.durationKey));
      expect(updated.sizeBytes, saver.contents[uri('a.mp3')]!.length);
      expect(local.isChangingCover(before), isFalse);
    });

    test('cada cambio da una ruta nueva: si no, la pantalla seguiría enseñando la imagen de antes', () async {
      await music.start();
      await pumpEventQueue();
      await local.changeCover(named('a'), '/uno.jpg');
      final first = local.artOf(named('a'));
      await local.changeCover(named('a'), '/dos.jpg');
      expect(local.artOf(named('a')), isNot(first));
    });

    test('a una enviada no se le toca nada en la nube: se recuerda en el teléfono y sobrevive a reabrir la app', () async {
      backend.add('r', cover: 'https://img.test/r.jpg', at: DateTime.utc(2026, 9, 1));
      await music.start();
      await pumpEventQueue();
      final track = music.tracks.single;
      expect(local.artOf(track), isNull);
      await local.changeCover(track, '/foto.jpg');
      expect(saver.written, isEmpty);
      expect(saver.storedCovers.single.keep, isTrue);
      expect(local.artOf(track), saver.storedCovers.single.path);
      expect(player.coverFileOf(track), saver.storedCovers.single.path); // el reproductor también
      final again = LocalMusicController(music, saver, covers: covers);
      expect(again.artOf(track), saver.storedCovers.single.path);
      again.dispose();
      music.prepareForSaving = null;
    });

    test('si la imagen no se puede abrir o no se puede escribir, se explica y la canción queda como estaba', () async {
      await music.start();
      await pumpEventQueue();
      saver.prepareFails = const TrackSaveException('No se pudo abrir esa imagen.');
      await expectLater(local.changeCover(named('a'), '/mala.jpg'), throwsA(isA<TrackSaveException>()));
      expect(saver.written, isEmpty);
      saver.prepareFails = null;
      saver.writeFails = const TrackSaveException('Android ya no deja escribir.', folderLost: true);
      await expectLater(local.changeCover(named('a'), '/foto.jpg'), throwsA(isA<TrackSaveException>()));
      expect(saver.contents[uri('a.mp3')], audio);
      expect(local.artOf(named('a')), isNull);
      expect(local.isChangingCover(named('a')), isFalse);
    });

    test('un .mp3 con la etiqueta dañada se explica y no se escribe', () async {
      saver.contents[uri('a.mp3')] = Uint8List.fromList([...ascii.encode('ID3'), 3, 0, 0, 0x7F, 0x7F, 0x7F, 0x7F, 1, 2, 3]);
      await music.start();
      await pumpEventQueue();
      await expectLater(
        local.changeCover(named('a'), '/foto.jpg'),
        throwsA(isA<TrackSaveException>().having((e) => e.message, 'motivo', contains('dañados'))),
      );
      expect(saver.written, isEmpty);
    });

    test('la imagen elegida va también en la copia que se guarda de una enviada', () async {
      final dir = await Directory.systemTemp.createTemp('kyora_cover_');
      addTearDown(() => dir.delete(recursive: true));
      final image = File('${dir.path}/c.jpg')..writeAsBytesSync(picture);
      covers.covers = {'r': image.path};
      local.dispose();
      local = LocalMusicController(music, saver, covers: covers);
      backend.add('r', at: DateTime.utc(2026, 9, 1));
      await music.start();
      await pumpEventQueue();
      final bytes = await music.prepareForSaving!(music.tracks.single, audio);
      final read = parse(bytes);
      expect(read.frames['APIC']!.sublist(read.frames['APIC']!.length - picture.length), picture);
      final plain = await music.prepareForSaving!(Track.local(song('otra.mp3')), audio);
      expect(plain, audio); // sin imagen elegida no se toca
    });

    test('si le cambias la imagen a la que suena, el motor suelta el archivo y sigue por donde iba', () async {
      await music.start();
      await pumpEventQueue();
      await player.play(named('b'), local.songs);
      engine.emitPosition(const Duration(seconds: 42));
      await pumpEventQueue();
      engine.calls.clear();
      var stoppedFirst = false;
      await player.whileRewriting(named('b'), () async {
        stoppedFirst = engine.calls.contains('stop');
        return local.changeCover(named('b'), '/foto.jpg');
      });
      expect(stoppedFirst, isTrue);
      expect(engine.calls, ['stop', 'setQueue:1', 'seek', 'play']);
      expect(engine.seeks.last, const Duration(seconds: 42));
      expect(engine.isPlaying, isTrue);
      expect(player.current?.title, 'b');
    });

    test('si estaba en pausa sigue en pausa, y aunque la escritura falle el motor vuelve', () async {
      await music.start();
      await pumpEventQueue();
      await player.play(named('b'), local.songs);
      await player.toggle();
      await pumpEventQueue();
      engine.calls.clear();
      saver.writeFails = const TrackSaveException('No hay espacio.');
      await expectLater(player.whileRewriting(named('b'), () => local.changeCover(named('b'), '/foto.jpg')), throwsA(isA<TrackSaveException>()));
      expect(engine.calls, ['stop', 'setQueue:1', 'seek']);
      expect(engine.isPlaying, isFalse);
    });

    test('la canción que va a sonar justo después también se suelta; una lejana no interrumpe nada', () async {
      await music.start();
      await pumpEventQueue();
      await player.play(named('a'), local.songs);
      engine.calls.clear();
      await player.whileRewriting(named('c'), () => local.changeCover(named('c'), '/foto.jpg'));
      expect(engine.calls, isEmpty); // «c» va después de «b»
      await player.whileRewriting(named('b'), () => local.changeCover(named('b'), '/foto.jpg'));
      expect(engine.calls.first, 'stop');
    });

    test('una enviada que suena no se interrumpe: no se escribe ningún archivo', () async {
      backend.add('r', at: DateTime.utc(2026, 9, 1));
      await music.start();
      await pumpEventQueue();
      final track = music.tracks.single;
      await player.play(track, music.tracks);
      engine.calls.clear();
      await player.whileRewriting(track, () => local.changeCover(track, '/foto.jpg'));
      expect(engine.calls, isEmpty);
    });

    group('pantalla', () {
      var picks = <String?>[];

      Future<void> settle(WidgetTester tester) async {
        // el .mp3 se procesa en otro hilo: hace falta tiempo real
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
          await tester.pump(const Duration(milliseconds: 200));
        }
      }

      Future<void> open(WidgetTester tester, String card) async {
        tester.view.physicalSize = const Size(400, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        picks = ['/foto.jpg'];
        await tester.runAsync(music.start);
        await tester.runAsync(pumpEventQueue);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(),
            home: MusicPage(controller: music, local: local, player: player, favorites: favorites, pickCover: () async => picks.removeLast()),
          ),
        );
        await tester.pump();
        await tester.tap(find.byKey(ValueKey(card)));
        await tester.pumpAndSettle();
      }

      Future<void> choose(WidgetTester tester, String id) async {
        await tester.tap(find.byKey(Key('more-$id')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('cover-$id')));
        await tester.pump(const Duration(milliseconds: 400)); // sin «settle»: el indicador de carga gira mientras se procesa
        await settle(tester);
      }

      testWidgets('en el teléfono: menú → «Cambiar imagen» → la fila enseña la nueva y avisa', (tester) async {
        await open(tester, 'card-root');
        final id = 'local:${uri('a.mp3')}';
        await choose(tester, id);
        expect(saver.written, [uri('a.mp3')]);
        expect(
          tester.widget<Cover>(find.descendant(of: find.byKey(Key('local-$id')), matching: find.byType(Cover))).file,
          saver.storedCovers.single.path,
        );
        expect(find.text('Imagen cambiada en el archivo de la canción.'), findsOneWidget);
      });

      testWidgets('la favorita sigue siéndolo aunque el archivo haya cambiado de tamaño', (tester) async {
        await open(tester, 'card-root');
        await favorites.toggle(named('a').durationKey);
        await choose(tester, 'local:${uri('a.mp3')}');
        expect(favorites.isFavorite(named('a').durationKey), isTrue);
        expect(favorites.count, 1);
      });

      testWidgets('cancelar la galería no hace nada', (tester) async {
        await open(tester, 'card-root');
        picks = [null];
        await choose(tester, 'local:${uri('a.mp3')}');
        expect(saver.written, isEmpty);
        expect(saver.storedCovers, isEmpty);
        expect(find.byType(SnackBar), findsNothing);
      });

      testWidgets('un fallo se explica en pantalla', (tester) async {
        await open(tester, 'card-root');
        saver.prepareFails = const TrackSaveException('No se pudo abrir esa imagen.');
        await choose(tester, 'local:${uri('a.mp3')}');
        expect(find.text('No se pudo abrir esa imagen.'), findsOneWidget);
      });

      testWidgets('marcando varias canciones no sale el menú', (tester) async {
        await open(tester, 'card-root');
        final id = 'local:${uri('a.mp3')}';
        expect(find.byKey(Key('more-$id')), findsOneWidget);
        await tester.longPress(find.byKey(Key('local-$id')));
        await tester.pump();
        expect(find.byKey(Key('more-$id')), findsNothing);
      });

      testWidgets('en las enviadas: la imagen elegida manda sobre la que trae, y el aviso dice que es en este teléfono', (tester) async {
        backend.add('r', cover: 'https://img.test/r.jpg', at: DateTime.utc(2026, 9, 1));
        await open(tester, 'card-received');
        await choose(tester, 'r');
        expect(
          tester.widget<Cover>(find.descendant(of: find.byKey(const Key('track-r')), matching: find.byType(Cover))).file,
          saver.storedCovers.single.path,
        );
        expect(find.text('Imagen cambiada en este teléfono.'), findsOneWidget);
        expect(saver.written, isEmpty);
      });
    });
  });
}
