import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/cover_store.dart';
import 'package:kyora_chat/data/music_store.dart';
import 'package:kyora_chat/models/track.dart';
import 'package:kyora_chat/state/local_music_controller.dart';
import 'package:kyora_chat/state/music_controller.dart';

import 'music_test.dart' show FakeMusicBackend, FakeSaver, MemoryMusicStore;

const root = 'content://tree/musica';

LocalSong song(String name, {String dir = 'musica'}) => LocalSong(
      uri: 'content://tree/$dir/document/$name',
      name: name,
      sizeBytes: 1024,
      modified: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
    );

const rock = LocalFolder(uri: 'content://tree/musica/document/Rock', name: 'Rock', count: 2);

/// La carátula se define **por álbum**: todas las canciones de un álbum enseñan la misma.
void main() {
  late FakeMusicBackend backend;
  late FakeSaver saver;
  late MusicController music;
  late LocalMusicController local;
  late MemoryCoverStore covers;

  setUp(() {
    backend = FakeMusicBackend();
    final store = MemoryMusicStore(since: DateTime.utc(2026, 10, 1))..settings = const MusicSettings(auto: false).withTree(root, 'Mi música');
    saver = FakeSaver()
      ..files = [song('a.mp3'), song('b.mp3'), song('c.mp3')]
      ..rootFolders = [rock]
      ..dirSongs[rock.uri] = [song('r1.mp3', dir: 'rock'), song('r2.mp3', dir: 'rock')];
    music = MusicController(backend, store, saver);
    covers = MemoryCoverStore();
    local = LocalMusicController(music, saver, covers: covers);
  });

  tearDown(() {
    local.dispose();
    music.dispose();
  });

  Future<void> start() async {
    await music.start();
    await pumpEventQueue();
  }

  Track named(String file, {String dir = 'musica'}) => Track.local(song(file, dir: dir));

  test('cada canción sabe de qué álbum es: las enviadas, la carpeta principal o su carpeta', () async {
    backend.add('r', at: DateTime.utc(2026, 9, 1));
    await start();
    expect(local.albumIdOf(music.tracks.single), 'received');
    expect(local.albumIdOf(named('a.mp3')), 'root');
    expect(local.albumIdOf(named('r1.mp3', dir: 'rock')), rock.uri); // se leyó por adelantado
    expect(local.albumIdOf(named('r2.mp3', dir: 'rock')), rock.uri);
  });

  test('sin imagen elegida, el álbum enseña la incrustada de su primera canción que la traiga, y todas sus canciones la comparten', () async {
    saver.art[song('b.mp3').uri] = '/art/b.jpg';
    saver.art[song('c.mp3').uri] = '/art/c.jpg';
    await start();
    expect(local.albumArt('root'), '/art/b.jpg'); // «a» no trae; la primera que sí es «b»
    for (final file in ['a.mp3', 'b.mp3', 'c.mp3']) {
      expect(local.artOf(named(file)), '/art/b.jpg', reason: file); // «c» tiene la suya, pero manda la del álbum
    }
  });

  test('un álbum sin ninguna imagen no tiene portada', () async {
    await start();
    expect(local.albumArt('root'), isNull);
    expect(local.albumArt(rock.uri), isNull);
    expect(local.artOf(named('a.mp3')), isNull);
  });

  test('la imagen elegida para el álbum manda sobre las incrustadas, vale para todas sus canciones y no toca a otros álbumes', () async {
    saver.art[song('a.mp3').uri] = '/art/a.jpg';
    saver.art[song('r1.mp3', dir: 'rock').uri] = '/art/r1.jpg';
    await start();
    await local.load(named('r1.mp3', dir: 'rock'));
    await local.setAlbumCover('root', '/mia.jpg');
    final chosen = saver.storedCovers.last.path;
    expect(local.albumArt('root'), chosen);
    for (final file in ['a.mp3', 'b.mp3', 'c.mp3']) {
      expect(local.artOf(named(file)), chosen, reason: file);
    }
    expect(local.artOf(named('r1.mp3', dir: 'rock')), '/art/r1.jpg'); // otro álbum: el suyo, intacto
  });

  test('al cambiar o quitar la imagen elegida se nota al momento (no se queda la anterior en memoria)', () async {
    saver.art[song('a.mp3').uri] = '/art/a.jpg';
    await start();
    expect(local.artOf(named('b.mp3')), '/art/a.jpg');
    await local.setAlbumCover('root', '/uno.jpg');
    final first = saver.storedCovers.last.path;
    expect(local.artOf(named('b.mp3')), first);
    await local.setAlbumCover('root', '/dos.jpg');
    expect(local.artOf(named('b.mp3')), saver.storedCovers.last.path);
    expect(local.artOf(named('b.mp3')), isNot(first));
    await local.clearAlbumCover('root');
    expect(local.artOf(named('b.mp3')), '/art/a.jpg'); // vuelve a la incrustada
    expect(covers.load(), isEmpty);
  });

  test('las canciones enviadas comparten la imagen del álbum «Canciones enviadas»; sin ella, cada una conserva su dirección de internet', () async {
    backend.add('r1', cover: 'https://img.test/1.jpg', at: DateTime.utc(2026, 9, 1));
    backend.add('r2', cover: 'https://img.test/2.jpg', at: DateTime.utc(2026, 9, 2));
    await start();
    expect(local.artOf(music.tracks.first), isNull); // sin imagen elegida: se ve la de internet de cada una
    expect(music.tracks.map((t) => t.coverUrl), ['https://img.test/2.jpg', 'https://img.test/1.jpg']);
    await local.setAlbumCover('received', '/mia.jpg');
    final chosen = saver.storedCovers.last.path;
    for (final track in music.tracks) {
      expect(local.artOf(track), chosen);
    }
    expect(saver.written, isEmpty); // nada se escribe en ningún archivo ni se sube
  });

  test('si el álbum de una canción aún no se leyó, vale la imagen que ella misma trae', () async {
    saver.art[song('x.mp3').uri] = '/art/x.jpg';
    final loose = named('x.mp3');
    expect(local.artOf(loose), isNull);
    await local.load(loose);
    expect(local.artOf(loose), '/art/x.jpg');
  });

  test('ya no hay forma de cambiarle la imagen a una sola canción: el controlador solo conoce las de los álbumes', () async {
    await start();
    // (no existe `changeCover`; esto se comprueba a la hora de compilar). Lo que queda: las portadas se recuerdan por álbum.
    await local.setAlbumCover('root', '/mia.jpg');
    expect(covers.load().keys, ['album:root']);
  });
}
