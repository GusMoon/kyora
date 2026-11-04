import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/ui/widgets/album_deck.dart';

/// Ayudas para probar la pantalla de música (ruleta de álbumes → vista del álbum con su disco → lista en arco).

/// La tarjeta de un álbum en la ruleta: «Canciones enviadas», la carpeta, sus álbumes y «Nuevo álbum».
Finder card(String id) => find.byKey(ValueKey(id));

/// Lleva la ruleta hasta la tarjeta número `index` (0 = la primera) tirando de ella con el dedo, como se haría a mano.
Future<void> deckTo(WidgetTester tester, int index) async {
  final at = tester.widget<AlbumDeck>(find.byType(AlbumDeck)).controller!.current;
  if (index != at) {
    await tester.drag(find.byKey(const Key('album-deck')), Offset(-AlbumDeck.pxPerStep * (index - at), 0));
    await tester.pumpAndSettle();
  }
}

/// Abre el álbum de la tarjeta `id`, que es la número `index` de la ruleta: la trae enfrente y la toca.
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
  final at = Offset(stage.left + 24, stage.bottom - 24);
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

/// Pasa al álbum de la derecha (`-1` = al de la izquierda) deslizando por fuera del disco.
Future<void> swipeAlbum(WidgetTester tester, {bool next = true}) async {
  final stage = tester.getRect(find.byKey(const Key('album-background')));
  await tester.flingFrom(Offset(stage.center.dx, stage.bottom - 30), Offset(next ? -300 : 300, 0), 1500);
  await tester.pumpAndSettle();
}
