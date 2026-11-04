import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/wallpaper_store.dart';
import 'package:kyora_chat/state/wallpaper_controller.dart';

const _five = [Color(0xFF112233), Color(0xFF445566), Color(0xFF778899), Color(0xFFAABBCC), Color(0xFFDDEEFF)];

void main() {
  late MemoryWallpaperStore store;

  setUp(() => store = MemoryWallpaperStore());

  test('sin fondo no hay ruta, paleta ni color', () {
    final c = WallpaperController(store, lookup: (_) async => _five);
    expect(c.hasWallpaper, isFalse);
    expect(c.palette, isEmpty);
    expect(c.seed, isNull);
  });

  test('al poner un fondo se copia, se sacan sus 5 colores, se guardan y se avisa', () async {
    final c = WallpaperController(store, lookup: (_) async => _five);
    var told = 0;
    c.addListener(() => told++);
    expect(await c.set('/galeria/foto.jpg'), isTrue);
    expect(store.kept, ['/galeria/foto.jpg']);
    expect(c.path, '/galeria/foto.jpg');
    expect(c.palette, _five);
    expect(c.seed, isNotNull);
    expect(store.state.path, '/galeria/foto.jpg');
    expect(store.state.palette, [for (final color in _five) color.toARGB32()]);
    expect(told, greaterThanOrEqualTo(2)); // «leyendo» y «listo»
    expect(c.busy, isFalse);
  });

  test('si la imagen no se lee, se queda el fondo anterior y se borra la copia', () async {
    final c = WallpaperController(store, lookup: (path) async => path == '/mala.jpg' ? null : _five);
    await c.set('/buena.jpg');
    expect(await c.set('/mala.jpg'), isFalse);
    expect(c.path, '/buena.jpg');
    expect(c.palette, _five);
    expect(store.discarded, ['/mala.jpg']);
  });

  test('cambiar de fondo borra la copia del anterior', () async {
    final c = WallpaperController(store, lookup: (_) async => _five);
    await c.set('/uno.jpg');
    await c.set('/dos.jpg');
    expect(store.discarded, ['/uno.jpg']);
    expect(c.path, '/dos.jpg');
  });

  test('quitar el fondo vuelve al gris y lo olvida', () async {
    final c = WallpaperController(store, lookup: (_) async => _five);
    await c.set('/uno.jpg');
    await c.clear();
    expect(c.hasWallpaper, isFalse);
    expect(c.palette, isEmpty);
    expect(c.seed, isNull);
    expect(store.state.path, isNull);
    expect(store.discarded, ['/uno.jpg']);
  });

  test('al abrir la app recuerda el fondo y su paleta sin volver a analizar la imagen', () async {
    store.state = WallpaperState(path: '/uno.jpg', palette: [for (final color in _five) color.toARGB32()]);
    var lookups = 0;
    final c = WallpaperController(store, lookup: (_) async {
      lookups++;
      return _five;
    });
    expect(c.path, '/uno.jpg');
    expect(c.palette, _five);
    expect(lookups, 0);
  });

  test('si se guardó la imagen pero no la paleta, la calcula al abrir', () async {
    store.state = const WallpaperState(path: '/uno.jpg');
    final c = WallpaperController(store, lookup: (_) async => _five);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(c.palette, _five);
    expect(store.state.palette, isNotEmpty);
  });
}
