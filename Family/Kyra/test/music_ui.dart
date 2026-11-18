import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/ui/widgets/album_grid.dart';
import 'package:kyora_chat/ui/widgets/disc_player.dart';

/// Ayudas para probar la pantalla de música (cuadrícula de álbumes → vista del álbum con su disco → lista en arco).

/// La tarjeta de un álbum en la cuadrícula: «Canciones enviadas», la carpeta, sus álbumes y «Nuevo álbum».
Finder card(String id) => find.byKey(ValueKey(id));

/// Lleva la cuadrícula hasta el álbum número `index` (0 = el primero), para que se vea.
Future<void> deckTo(WidgetTester tester, int index) async {
  final grid = tester.widget<AlbumGrid>(find.byType(AlbumGrid));
  grid.controller!.jumpTo(index);
  await tester.pumpAndSettle();
}

/// Abre el álbum de la tarjeta `id`, que es el número `index` de la cuadrícula: lo muestra y lo toca.
Future<void> openAlbum(WidgetTester tester, int index, String id) async {
  await deckTo(tester, index);
  await tester.tap(card(id));
  await tester.pumpAndSettle();
}

/// Destapa el nombre y los controles: al entrar solo se ven el disco y el fondo; tocar el centro del disco reproduce y los enseña.
Future<void> armDisc(WidgetTester tester) async {
  if (find.byKey(const Key('album-song-title')).evaluate().isNotEmpty) return;
  await tester.tap(find.byType(DiscPlayer));
  await tester.pump(const Duration(milliseconds: 300));
}

/// El nombre de la canción que se enseña debajo del disco (si aún no se tocó el centro del disco, lo toca).
Future<String> songTitle(WidgetTester tester) async {
  await armDisc(tester);
  return tester.widget<Text>(find.byKey(const Key('album-song-title'))).data!;
}

/// Abre (o cierra) la lista de canciones del álbum: doble toque fuera del disco.
Future<void> openList(WidgetTester tester) async {
  final stage = tester.getRect(find.byKey(const Key('album-background')));
  final at = Offset(stage.left + 24, stage.top + 120); // por encima del disco: abajo puede estar la tarjeta de lo que suena
  await tester.tapAt(at);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tapAt(at);
  await tester.pumpAndSettle();
}

/// Trae al centro una fila de la lista y la pone a sonar con el botón de la píldora.
Future<void> playRow(WidgetTester tester, Finder row, String id) async {
  await tester.tap(row);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('arc-play-$id')));
}

/// Mantiene presionado el disco (tras destapar la canción tocando su centro): se abre el disco de opciones (mover, borrar, velocidad y tono, nombre).
Future<void> holdDisc(WidgetTester tester) async {
  await armDisc(tester);
  await tester.longPress(find.byType(DiscPlayer));
  await tester.pumpAndSettle();
}

/// El orden de la pila de música de las pruebas (`music_screen_test`): enviadas, la carpeta, Jazz, Rock.
const _stackIds = ['card-received', 'card-root', 'card-folder-Jazz', 'card-folder-Rock'];
const _stackTitles = ['Canciones enviadas', 'Mi música', 'Jazz', 'Rock'];

/// Pasa al álbum siguiente (`next: false` = al anterior). Mantener el disco ya no sirve para esto: se vuelve a la pila (la canción sigue
/// sonando) y se abre el otro álbum.
Future<void> swipeAlbum(WidgetTester tester, {bool next = true}) async {
  final shown = tester.widget<Text>(find.byKey(const Key('album-title'))).data!;
  final target = _stackTitles.indexOf(shown) + (next ? 1 : -1);
  await tester.pageBack();
  await tester.pumpAndSettle();
  await tester.runAsync(pumpEventQueue);
  await tester.pump();
  await openAlbum(tester, target, _stackIds[target]);
}
