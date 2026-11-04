import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/chat_backend.dart';
import 'package:kyora_chat/models/message.dart';
import 'package:kyora_chat/state/chat_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/chat_page.dart';
import 'package:kyora_chat/ui/login_page.dart';
import 'package:kyora_chat/ui/widgets/composer.dart' show Picker;
import 'package:kyora_chat/util/picker.dart';

import 'fake_backend.dart';

Widget app(Widget home) => MaterialApp(theme: buildTheme(), home: home);

/// Deja pasar el tiempo real (las pruebas de pantalla corren en un reloj falso: las esperas del controlador, no).
Future<void> settle(WidgetTester tester, [int ms = 80]) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await tester.pump();
}

Future<ChatController> openChat(
  WidgetTester tester,
  FakeBackend backend, {
  Picker? picker,
  int? maxFileBytes,
}) async {
  final controller = ChatController(
    backend,
    retryDelay: const Duration(milliseconds: 20),
    catchUpDelay: const Duration(milliseconds: 10),
    maxFileBytes: maxFileBytes ?? 50 * 1000 * 1000,
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(app(ChatPage(backend: backend, controller: controller, picker: picker)));
  await tester.runAsync(controller.start);
  await tester.pump();
  return controller;
}

void main() {
  group('acceso', () {
    testWidgets('pide correo y contraseña si están vacíos', (tester) async {
      var calls = 0;
      await tester.pumpWidget(app(LoginPage(onSignIn: (e, p) async => calls++)));
      await tester.tap(find.byKey(const Key('login-button')));
      await tester.pump();
      expect(find.text('Escribe tu correo y tu contraseña.'), findsOneWidget);
      expect(calls, 0);
    });

    testWidgets('entra con lo escrito y enseña el error en español si falla', (tester) async {
      final seen = <(String, String)>[];
      await tester.pumpWidget(app(LoginPage(onSignIn: (email, password) async {
        seen.add((email, password));
        throw const ChatException('Correo o contraseña incorrectos.', code: 'invalid_credentials');
      })));
      await tester.enterText(find.byKey(const Key('email')), 'yo@correo.com');
      await tester.enterText(find.byKey(const Key('password')), 'secreta');
      await tester.tap(find.byKey(const Key('login-button')));
      await tester.pump();
      await tester.pump();
      expect(seen, [('yo@correo.com', 'secreta')]);
      expect(find.byKey(const Key('login-error')), findsOneWidget);
      expect(find.text('Correo o contraseña incorrectos.'), findsOneWidget);
    });

    testWidgets('la contraseña va oculta y se puede mostrar', (tester) async {
      await tester.pumpWidget(app(LoginPage(onSignIn: (e, p) async {})));
      bool hidden() => tester.widget<TextField>(find.byKey(const Key('password'))).obscureText;
      expect(hidden(), isTrue);
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump();
      expect(hidden(), isFalse);
    });
  });

  group('chat', () {
    testWidgets('enseña lo que mandó la PC a la izquierda y lo mío a la derecha, con su hora y estado', (tester) async {
      final now = DateTime.now();
      final backend = FakeBackend()
        ..add('pc-1', body: 'hola desde la PC', device: 'pc', sentAt: now.subtract(const Duration(minutes: 2)))
        ..add('mine-1', body: 'respuesta desde el móvil', device: 'movil', sentAt: now.subtract(const Duration(minutes: 1)));
      await openChat(tester, backend);
      expect(find.text('En línea'), findsOneWidget);
      expect(find.text('Hoy'), findsOneWidget);
      expect(find.text('hola desde la PC'), findsOneWidget);
      expect(find.text('respuesta desde el móvil'), findsOneWidget);
      expect(find.text('pc'), findsOneWidget); // el nombre del dispositivo, solo en lo ajeno
      final pc = tester.getCenter(find.byKey(const Key('bubble-pc-1'))).dx;
      final mine = tester.getCenter(find.byKey(const Key('bubble-mine-1'))).dx;
      expect(mine, greaterThan(pc));
      expect(find.byKey(const Key('sent')), findsOneWidget); // ✓ solo en mis mensajes enviados
      expect(find.byKey(const Key('waiting')), findsNothing);
    });

    testWidgets('sin mensajes dice dónde aparecerá lo de la PC', (tester) async {
      await openChat(tester, FakeBackend());
      expect(find.textContaining('Lo que mandes desde la PC aparece aquí'), findsOneWidget);
    });

    testWidgets('el botón de enviar está apagado sin nada escrito y envía al pulsarlo', (tester) async {
      final backend = FakeBackend();
      await openChat(tester, backend);
      expect(tester.widget<IconButton>(find.byKey(const Key('send'))).onPressed, isNull);
      await tester.enterText(find.byKey(const Key('message-field')), 'hola PC');
      await tester.pump();
      await tester.tap(find.byKey(const Key('send')));
      await tester.pump();
      await settle(tester);
      expect(backend.remote.values.single.body, 'hola PC');
      expect(backend.remote.values.single.device, 'movil');
      expect(find.byKey(const Key('waiting')), findsNothing);
      expect(find.byKey(const Key('sent')), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('message-field'))).controller!.text, isEmpty);
    });

    testWidgets('sin conexión el mensaje queda «En espera» y la cabecera avisa', (tester) async {
      final backend = FakeBackend();
      await openChat(tester, backend);
      backend.offline = true;
      await tester.enterText(find.byKey(const Key('message-field')), 'sin red');
      await tester.pump();
      await tester.tap(find.byKey(const Key('send')));
      await settle(tester, 40);
      expect(find.byKey(const Key('waiting')), findsOneWidget);
      expect(find.textContaining('Sin conexión'), findsOneWidget);
      backend.offline = false;
      await tester.pump(const Duration(milliseconds: 50)); // pasa el tiempo de espera del reintento (reloj de la prueba)
      await settle(tester);
      expect(find.byKey(const Key('sent')), findsOneWidget);
      expect(backend.remote.length, 1);
    });

    testWidgets('un mensaje con error enseña el motivo y se reintenta con «Reintentar»', (tester) async {
      final backend = FakeBackend()..sendError = const ChatException('El mensaje está vacío.', code: 'empty_message');
      await openChat(tester, backend);
      await tester.enterText(find.byKey(const Key('message-field')), 'texto');
      await tester.pump();
      await tester.tap(find.byKey(const Key('send')));
      await settle(tester);
      expect(find.textContaining('No se envió: El mensaje está vacío.'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      await settle(tester);
      expect(find.text('Reintentar'), findsNothing);
      expect(backend.remote.length, 1);
    });

    testWidgets('mantener pulsado permite borrar con confirmación', (tester) async {
      final backend = FakeBackend()..add('a', body: 'para borrar', device: 'movil', sentAt: DateTime.now());
      await openChat(tester, backend);
      await tester.longPress(find.byKey(const Key('bubble-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-delete')));
      await tester.pumpAndSettle();
      expect(find.text('¿Borrar el mensaje?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm-delete')));
      await tester.pump();
      await settle(tester);
      expect(backend.deleted, {'a'});
      expect(find.text('para borrar'), findsNothing);
    });

    testWidgets('los archivos salen como tarjeta con su nombre y tamaño', (tester) async {
      final backend = FakeBackend()
        ..add('f', device: 'pc', sentAt: DateTime.now(), attachments: const [
          Attachment(id: 'att-1', fileName: 'Presupuesto.pdf', mimeType: 'application/pdf', sizeBytes: 2400000, storagePath: 'u/c/f/P.pdf'),
        ]);
      await openChat(tester, backend);
      expect(find.byKey(const Key('file-att-1')), findsOneWidget);
      expect(find.text('Presupuesto.pdf'), findsOneWidget);
      expect(find.text('2,3 MB'), findsOneWidget);
    });

    testWidgets('adjuntar: elige de la galería, queda como ficha y se puede quitar', (tester) async {
      final backend = FakeBackend();
      PickSource? asked;
      await openChat(tester, backend, picker: (source) async {
        asked = source;
        return [OutgoingFile(path: 'C:/fotos/gato.jpg', name: 'gato.jpg', size: 2048)];
      });
      await tester.tap(find.byKey(const Key('attach')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-gallery')));
      await tester.pumpAndSettle();
      expect(asked, PickSource.gallery);
      expect(find.byKey(const Key('staged-C:/fotos/gato.jpg')), findsOneWidget);
      expect(tester.widget<IconButton>(find.byKey(const Key('send'))).onPressed, isNotNull); // con solo un archivo ya se puede enviar
      tester.widget<InputChip>(find.byType(InputChip)).onDeleted!();
      await tester.pump();
      expect(find.byKey(const Key('staged-C:/fotos/gato.jpg')), findsNothing);
    });

    testWidgets('un archivo demasiado grande se rechaza con un aviso y no se crea el mensaje', (tester) async {
      final backend = FakeBackend();
      final controller = await openChat(tester, backend, maxFileBytes: 10, picker: (source) async {
        return [OutgoingFile(path: 'C:/grande.bin', name: 'grande.bin', size: 50)];
      });
      await tester.tap(find.byKey(const Key('attach')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-file')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('send')));
      await tester.pump();
      expect(find.textContaining('«grande.bin» pesa'), findsOneWidget);
      expect(controller.messages, isEmpty);
    });

    testWidgets('lo que llega de la PC por Realtime aparece solo', (tester) async {
      final backend = FakeBackend();
      await openChat(tester, backend);
      backend.add('nuevo', body: 'te escribo desde la PC', device: 'pc', sentAt: DateTime.now());
      backend.emit(const BackendSignal(SignalKind.changed));
      await settle(tester);
      expect(find.text('te escribo desde la PC'), findsOneWidget);
    });
  });
}
