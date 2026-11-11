import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/chat_backend.dart';
import 'package:kyora_chat/models/message.dart';
import 'package:kyora_chat/state/chat_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/chat_page.dart';
import 'package:kyora_chat/ui/widgets/hack_text.dart';
import 'package:kyora_chat/ui/widgets/terminal_line.dart';
import 'package:kyora_chat/ui/login_page.dart';
import 'package:kyora_chat/ui/widgets/composer.dart' show Picker;
import 'package:kyora_chat/util/picker.dart';

import 'fake_backend.dart';
import 'sections.dart';

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
      await tester.tap(findIcon(Icons.visibility_outlined));
      await tester.pump();
      expect(hidden(), isFalse);
    });
  });

  group('chat', () {
    testWidgets('es una terminal: cada mensaje es una línea con una barra del color de su dispositivo, el texto y la hora pequeña debajo; sin «PC» ni «MÓVIL»', (tester) async {
      final now = DateTime.now();
      final backend = FakeBackend()
        ..add('pc-1', body: 'hola desde la PC', device: 'pc', sentAt: now.subtract(const Duration(minutes: 2)))
        ..add('mine-1', body: 'respuesta desde el móvil', device: 'movil', sentAt: now.subtract(const Duration(minutes: 1)));
      await openChat(tester, backend);
      expect(find.byKey(const Key('chat-terminal')), findsOneWidget);
      expect(find.text('KYORA :: TERMINAL'), findsOneWidget);
      expect(find.text('en línea'), findsOneWidget);
      expect(find.text('HOY'), findsOneWidget);
      expect(find.text('hola desde la PC'), findsOneWidget);
      expect(find.text('respuesta desde el móvil'), findsOneWidget);
      // ya no se escribe el dispositivo en cada línea
      expect(find.textContaining('PC >', findRichText: true), findsNothing);
      expect(find.text('PC'), findsNothing);
      expect(find.text('MÓVIL'), findsNothing);
      // la barra vertical del principio: un color por dispositivo
      Color bar(String id) => ((tester.widget<DecoratedBox>(find.byKey(Key('bar-$id'))).decoration as BoxDecoration).border! as Border).left.color;
      final c = KyoraColors.classic();
      expect(bar('mine-1'), c.accent);
      expect(bar('pc-1'), c.tasks);
      expect(bar('pc-1'), isNot(bar('mine-1')));
      // sin burbujas ni lados: las dos líneas empiezan en el mismo borde izquierdo
      expect(tester.getTopLeft(find.byKey(const Key('bubble-mine-1'))).dx, closeTo(tester.getTopLeft(find.byKey(const Key('bubble-pc-1'))).dx, 0.5));
      // la hora, pequeña y debajo del texto
      final time = find.byKey(const Key('time-pc-1'));
      expect(tester.getTopLeft(time).dy, greaterThan(tester.getBottomLeft(find.text('hola desde la PC')).dy - 1));
      expect(tester.widget<Text>(time).style!.fontSize, lessThanOrEqualTo(15));
      expect(find.byKey(const Key('sent')), findsOneWidget); // ✓ solo en lo escrito desde este móvil
      expect(find.byKey(const Key('waiting')), findsNothing);
    });

    testWidgets('la etiqueta del dispositivo: movil → MÓVIL, pc → PC y cualquier otro en mayúsculas', (tester) async {
      expect(deviceLabel('movil'), 'MÓVIL');
      expect(deviceLabel('pc'), 'PC');
      expect(deviceLabel('tablet'), 'TABLET');
    });

    testWidgets('sin mensajes la terminal dice que no hay registros', (tester) async {
      await openChat(tester, FakeBackend());
      expect(find.byKey(const Key('chat-empty')), findsOneWidget);
      expect(find.textContaining('sin registros'), findsOneWidget);
      expect(find.byKey(const Key('chat-files')), findsNothing);
    });

    testWidgets('el prompt va abajo del todo, dentro de la terminal', (tester) async {
      await openChat(tester, FakeBackend());
      final window = tester.getRect(find.byKey(const Key('chat-terminal')));
      final prompt = tester.getRect(find.byKey(const Key('prompt')));
      expect(find.descendant(of: find.byKey(const Key('chat-terminal')), matching: find.byKey(const Key('prompt'))), findsOneWidget);
      expect(prompt.bottom, lessThanOrEqualTo(window.bottom));
      expect(prompt.bottom, greaterThan(window.bottom - 70)); // pegado al borde de abajo
    });

    group('los archivos', () {
      final doc = const Attachment(id: 'doc-1', fileName: 'Informe.docx', mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', sizeBytes: 1200, storagePath: 'u/c/v/I.docx');
      final img = const Attachment(id: 'img-1', fileName: 'foto.jpg', mimeType: 'image/jpeg', sizeBytes: 3000, storagePath: 'u/c/n/f.jpg', width: 400, height: 300);

      FakeBackend withFiles() {
        final now = DateTime.now();
        return FakeBackend()
          ..add('viejo', device: 'pc', sentAt: now.subtract(const Duration(minutes: 5)), attachments: [doc])
          ..add('nuevo', device: 'movil', sentAt: now.subtract(const Duration(minutes: 1)), attachments: [img]);
      }

      testWidgets('de forma predeterminada no se ven: solo el texto de la terminal; hay un botón para mostrarlos', (tester) async {
        await openChat(tester, withFiles());
        expect(find.byKey(const Key('chat-files')), findsNothing);
        expect(find.byKey(const Key('strip-file-img-1')), findsNothing);
        expect(find.byKey(const Key('chat-files-toggle')), findsOneWidget);
      });

      testWidgets('el botón los enseña arriba, fuera de la terminal: del más nuevo al más viejo, fotos y documentos; otra vez los oculta', (tester) async {
        await openChat(tester, withFiles());
        await tester.tap(find.byKey(const Key('chat-files-toggle')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('chat-files')), findsOneWidget);
        final imgX = tester.getTopLeft(find.byKey(const Key('strip-file-img-1'))).dx;
        final docX = tester.getTopLeft(find.byKey(const Key('strip-file-doc-1'))).dx;
        expect(imgX, lessThan(docX)); // el más nuevo, primero
        expect(find.descendant(of: find.byKey(const Key('strip-file-doc-1')), matching: find.text('DOCX')), findsOneWidget);
        // fuera de la ventana de la terminal, y encima de ella
        expect(find.descendant(of: find.byKey(const Key('chat-terminal')), matching: find.byKey(const Key('chat-files'))), findsNothing);
        expect(tester.getRect(find.byKey(const Key('chat-files'))).bottom, lessThanOrEqualTo(tester.getRect(find.byKey(const Key('chat-terminal'))).top + 0.5));
        await tester.tap(find.byKey(const Key('chat-files-toggle')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('chat-files')), findsNothing);
      });

      testWidgets('las fichas son de esquinas cortadas, sin redondeos', (tester) async {
        await openChat(tester, withFiles());
        await tester.tap(find.byKey(const Key('chat-files-toggle')));
        await tester.pumpAndSettle();
        final tile = find.byKey(const Key('strip-file-doc-1'));
        expect(find.descendant(of: tile, matching: find.byType(ClipRRect)), findsNothing);
        expect(find.descendant(of: tile, matching: find.byType(ClipPath)), findsWidgets);
      });

      testWidgets('sin archivos, el botón lo dice', (tester) async {
        await openChat(tester, FakeBackend());
        await tester.tap(find.byKey(const Key('chat-files-toggle')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('chat-files-empty')), findsOneWidget);
      });

      testWidgets('tocar una foto de la tira la abre a pantalla completa', (tester) async {
        await openChat(tester, withFiles());
        await tester.tap(find.byKey(const Key('chat-files-toggle')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('strip-file-img-1')));
        await tester.pumpAndSettle();
        expect(find.text('foto.jpg'), findsOneWidget); // el título del visor
      });

      testWidgets('en la terminal un archivo es una línea simple «:: nombre · tamaño», sin flechas ni subrayado ni icono', (tester) async {
        final backend = FakeBackend()
          ..add('f', device: 'pc', sentAt: DateTime.now(), attachments: const [
            Attachment(id: 'att-1', fileName: 'Presupuesto.pdf', mimeType: 'application/pdf', sizeBytes: 2400000, storagePath: 'u/c/f/P.pdf'),
          ]);
        await openChat(tester, backend);
        final line = find.byKey(const Key('file-att-1'));
        expect(line, findsOneWidget);
        expect(find.descendant(of: line, matching: find.textContaining(':: Presupuesto.pdf · 2,3 MB', findRichText: true)), findsOneWidget);
        expect(find.descendant(of: line, matching: find.byType(Icon)), findsNothing);
        expect(find.descendant(of: line, matching: find.byType(InkWell)), findsNothing);
        expect(find.textContaining('↳', findRichText: true), findsNothing);
        final text = tester.widget<Text>(find.descendant(of: line, matching: find.byType(Text)));
        final underlined = (text.textSpan! as TextSpan).children!.any((s) => (s as TextSpan).style?.decoration == TextDecoration.underline);
        expect(underlined, isFalse);
        expect(find.byKey(const Key('strip-file-att-1')), findsNothing); // la tira sigue oculta
      });
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
      expect(find.textContaining('sin conexión'), findsOneWidget);
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

    testWidgets('el efecto de escritura: el historial sale entero y solo se escribe lo que llega o se envía después', (tester) async {
      HackText.enabled = true;
      addTearDown(() => HackText.enabled = false);
      final backend = FakeBackend()..add('viejo', body: 'ya estaba aquí', device: 'pc', sentAt: DateTime.now());
      await openChat(tester, backend);
      await tester.pump(const Duration(milliseconds: 50));
      Text body(String id) => tester.widget<Text>(find.descendant(of: find.byKey(Key('bubble-$id')), matching: find.byType(Text)).first);
      expect(body('viejo').data, 'ya estaba aquí'); // historial: sin escribirse
      backend.add('nuevo', body: 'llegó ahora mismo', device: 'pc', sentAt: DateTime.now());
      backend.emit(const BackendSignal(SignalKind.changed));
      await settle(tester);
      expect(body('nuevo').data, isNull); // escribiéndose
      expect(body('viejo').data, 'ya estaba aquí');
      await tester.pumpAndSettle();
      expect(body('nuevo').data, 'llegó ahora mismo');
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
      expect(find.textContaining('te escribo desde la PC', findRichText: true), findsOneWidget);
    });
  });
}
