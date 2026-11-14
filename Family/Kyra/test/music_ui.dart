import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/ui/widgets/album_stack.dart';
import 'package:kyora_chat/ui/widgets/disc_player.dart';

/// Ayudas para probar la pantalla de música (pila de álbumes → vista del álbum con su disco → lista en arco).

/// La tarjeta de un álbum en la pila: «Canciones enviadas», la carpeta, sus álbumes y «Nuevo álbum».
Finder card(String id) => find.byKey(ValueKey(id));

/// Lo que hay que arrastrar en la pila para pasar de un álbum al siguiente.
double stackStep(WidgetTester tester) {
  final stack = tester.widget<AlbumStack>(find.byType(AlbumStack));
  return AlbumStack.pixelsFor(AlbumStack.sideFor(tester.getSize(find.byKey(const Key('album-deck')))), stack.speed);
}

/// Lleva la pila hasta la tarjeta número `index` (0 = la primera) arrastrándola con el dedo en vertical, como se haría a mano.
Future<void> deckTo(WidgetTester tester, int index) async {
  final stack = tester.widget<AlbumStack>(find.byType(AlbumStack));
  final at = stack.controller!.current;
  if (index != at) {
    await tester.timedDrag(find.byKey(const Key('album-deck')), Offset(0, -stackStep(tester) * (index - at)), Duration(milliseconds: 1500 * (index - at).abs())); // despacio: sin inercia
    await tester.pumpAndSettle();
  }
}

/// Abre el álbum de la tarjeta `id`, que es la número `index` de la pila: la trae al centro y la toca.
Future<void> openAlbum(WidgetTester tester, int index, String id) async {
  await deckTo(tester, index);
  await tester.tap(card(id));
  await tester.pumpAndSettle();
}

/// El nombre de la canción que se enseña debajo del disco.
String songTitle(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('album-song-title'))).data!;

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

/// Mantiene presionado el disco: se abren sus opciones (aleatorio, mover, borrar, velocidad).
Future<void> holdDisc(WidgetTester tester) async {
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
