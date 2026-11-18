import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/favorites_store.dart';
import 'package:kyora_chat/data/music_store.dart';
import 'package:kyora_chat/models/track.dart';
import 'package:kyora_chat/state/local_music_controller.dart';
import 'package:kyora_chat/state/music_controller.dart';
import 'package:kyora_chat/state/player_controller.dart';
import 'package:kyora_chat/ui/neo/neo_music_page.dart';
import 'package:kyora_chat/ui/neo/neo_theme.dart';

import 'fake_engine.dart';
import 'music_test.dart' show FakeMusicBackend, FakeSaver, MemoryMusicStore;

/// La música de KyraFamily: las mismas funciones que la de KyraAdmin (renombrar, mover, borrar, marcar varias, buscar, foto del álbum,
/// favoritas), con los cuadros del diseño cyber-brutalista.
void main() {
  late FakeSaver saver;
  late MusicController music;
  late LocalMusicController local;
  late PlayerController player;
  late FavoritesController favorites;
  const rock = LocalFolder(uri: 'content://tree/musica/document/Rock', name: 'Rock', count: 2);
  const pop = LocalFolder(uri: 'content://tree/musica/document/Pop', name: 'Pop');

  LocalSong song(String dir, String name) => LocalSong(uri: '$dir/$name', name: name, sizeBytes: 10, modified: DateTime.utc(2026));

  setUp(() {
    final store = MemoryMusicStore(since: DateTime.utc(2026, 10, 1))..settings = const MusicSettings(auto: false).withTree('content://tree/musica', 'Mi música');
    saver = FakeSaver()
      ..rootFolders = [rock, pop]
      ..dirSongs[rock.uri] = [song(rock.uri, 'Uno.mp3'), song(rock.uri, 'Dos.mp3')];
    final backend = FakeMusicBackend();
    music = MusicController(backend, store, saver);
    local = LocalMusicController(music, saver);
    player = PlayerController(backend, FakeEngine());
    favorites = FavoritesController(MemoryFavoritesStore());
  });

  tearDown(() {
    player.dispose();
    local.dispose();
    music.dispose();
  });

  Future<void> open(WidgetTester tester, {Future<String?> Function()? pickCover}) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await music.start(remote: false);
    await tester.runAsync(local.refresh);
    await tester.pumpWidget(MaterialApp(
      theme: neoTheme(),
      home: Scaffold(
        body: NeoMusicPage(controller: music, player: player, local: local, favorites: favorites, pickCover: pickCover ?? () async => null),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(key)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
  }

  Future<void> openRock(WidgetTester tester) async {
    await tapKey(tester, 'neo-album-${rock.uri}');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pumpAndSettle();
  }

  testWidgets('los álbumes de la carpeta salen, y «Nuevo álbum» crea uno', (tester) async {
    await open(tester);
    expect(find.byKey(Key('neo-album-${rock.uri}')), findsOneWidget);
    expect(find.byKey(Key('neo-album-${pop.uri}')), findsOneWidget);
    await tapKey(tester, 'neo-new-album');
    await tester.enterText(find.byKey(const Key('neo-ask-field')), 'Jazz');
    await tapKey(tester, 'neo-ask-ok');
    expect(saver.created.map((c) => c.name), ['Jazz']);
  });

  testWidgets('el menú del álbum: cambiar nombre', (tester) async {
    await open(tester);
    await tapKey(tester, 'neo-album-more-${rock.uri}');
    expect(find.byKey(const Key('neo-album-opt-rename')), findsOneWidget);
    expect(find.byKey(const Key('neo-album-opt-cover')), findsOneWidget);
    expect(find.byKey(const Key('neo-album-opt-delete')), findsOneWidget);
    await tapKey(tester, 'neo-album-opt-rename');
    await tester.enterText(find.byKey(const Key('neo-ask-field')), 'Rock clásico');
    await tapKey(tester, 'neo-ask-ok');
    expect(saver.renames.map((r) => r.name), ['Rock clásico']);
  });

  testWidgets('«Enviadas» no se puede renombrar ni borrar: solo la foto', (tester) async {
    await open(tester);
    await tapKey(tester, 'neo-album-more-received');
    expect(find.byKey(const Key('neo-album-opt-cover')), findsOneWidget);
    expect(find.byKey(const Key('neo-album-opt-rename')), findsNothing);
    expect(find.byKey(const Key('neo-album-opt-delete')), findsNothing);
  });

  testWidgets('borrar un álbum con canciones: «Borrar todo» lo borra con ellas', (tester) async {
    await open(tester);
    await tapKey(tester, 'neo-album-more-${rock.uri}');
    await tapKey(tester, 'neo-album-opt-delete');
    expect(find.byKey(const Key('neo-album-move-first')), findsOneWidget);
    await tapKey(tester, 'neo-album-delete-all');
    expect(saver.folderDeletes, [rock.uri]);
  });

  testWidgets('borrar un álbum pasando antes sus canciones a otro', (tester) async {
    await open(tester);
    await tapKey(tester, 'neo-album-more-${rock.uri}');
    await tapKey(tester, 'neo-album-opt-delete');
    await tapKey(tester, 'neo-album-move-first');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pumpAndSettle();
    await tapKey(tester, 'neo-move-folder-Pop');
    await tapKey(tester, 'neo-move-here');
    expect(saver.moves.single.to, pop.uri);
    expect(saver.moves.single.uris, hasLength(2));
    expect(saver.folderDeletes, [rock.uri]);
  });

  testWidgets('dentro del álbum: mover y renombrar una canción con su menú', (tester) async {
    await open(tester);
    await openRock(tester);
    final uno = local.songs.firstWhere((t) => t.title == 'Uno');
    await tapKey(tester, 'neo-track-more-${uno.id}');
    expect(find.byKey(const Key('neo-song-opt-move')), findsOneWidget);
    await tapKey(tester, 'neo-song-opt-move');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pumpAndSettle();
    await tapKey(tester, 'neo-move-folder-Pop');
    await tapKey(tester, 'neo-move-here');
    expect(saver.moves.single.uris, [uno.localUri]);
    expect(saver.moves.single.to, pop.uri);
    final dos = local.songs.firstWhere((t) => t.title == 'Dos');
    await tapKey(tester, 'neo-track-more-${dos.id}');
    await tapKey(tester, 'neo-song-opt-rename');
    await tester.enterText(find.byKey(const Key('neo-ask-field')), 'Segunda');
    await tapKey(tester, 'neo-ask-ok');
    expect(saver.renames.last.name, contains('Segunda'));
  });

  testWidgets('borrar una canción pide confirmar', (tester) async {
    await open(tester);
    await openRock(tester);
    final uno = local.songs.firstWhere((t) => t.title == 'Uno');
    await tapKey(tester, 'neo-track-more-${uno.id}');
    await tapKey(tester, 'neo-song-opt-delete');
    expect(saver.deletes, isEmpty);
    await tapKey(tester, 'neo-confirm');
    expect(saver.deletes.single, [uno.localUri]);
  });

  testWidgets('marcar varias: todas, y borrarlas', (tester) async {
    await open(tester);
    await openRock(tester);
    await tapKey(tester, 'neo-album-select');
    expect(find.byKey(const Key('neo-selection-bar')), findsOneWidget);
    await tapKey(tester, 'neo-select-all');
    expect(local.selectedCount, 2);
    await tapKey(tester, 'neo-select-delete');
    await tapKey(tester, 'neo-confirm');
    expect(saver.deletes.single, hasLength(2));
  });

  testWidgets('buscar dentro del álbum', (tester) async {
    await open(tester);
    await openRock(tester);
    final uno = local.songs.firstWhere((t) => t.title == 'Uno');
    final dos = local.songs.firstWhere((t) => t.title == 'Dos');
    await tapKey(tester, 'neo-album-search');
    await tester.enterText(find.byKey(const Key('neo-album-search-field')), 'dos');
    await tester.pumpAndSettle();
    expect(find.byKey(Key('neo-track-${dos.id}')), findsOneWidget);
    expect(find.byKey(Key('neo-track-${uno.id}')), findsNothing);
  });

  testWidgets('favorita desde el menú de la canción', (tester) async {
    await open(tester);
    await openRock(tester);
    final uno = local.songs.firstWhere((t) => t.title == 'Uno');
    await tapKey(tester, 'neo-track-more-${uno.id}');
    await tapKey(tester, 'neo-song-opt-fav');
    expect(favorites.isFavorite(uno.durationKey), isTrue);
  });

  testWidgets('cambiar la foto de un álbum', (tester) async {
    await open(tester, pickCover: () async => '/fotos/rock.jpg');
    await tapKey(tester, 'neo-album-more-${rock.uri}');
    await tapKey(tester, 'neo-album-opt-cover');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pumpAndSettle();
    expect(local.albumCoverOf(rock.uri), isNotNull);
  });
}
