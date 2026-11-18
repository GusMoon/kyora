import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/ui/widgets/flat_form.dart';
import 'package:kyora_chat/ui/widgets/cyber_panel.dart';
import 'package:kyora_chat/data/chat_backend.dart';
import 'package:kyora_chat/state/passwords_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/passwords_page.dart';

import 'password_vault_test.dart' show FakePasswordBackend;

/// La pantalla de Contraseñas con una bóveda en memoria (1 000 vueltas de cifrado en vez de 600 000) y un portapapeles de mentira.
void main() {
  late FakePasswordBackend backend;
  late PasswordsController vault;
  String? clipboard;
  var n = 0;

  setUp(() {
    backend = FakePasswordBackend();
    clipboard = null;
    n = 0;
  });

  /// Deja correr el cifrado (futuros reales) y la pantalla.
  Future<void> io(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, {Duration idle = const Duration(minutes: 5)}) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: PasswordsPage(
          backend: backend,
          create: (b) => vault = PasswordsController(
            b,
            rounds: 1000,
            idle: idle,
            newId: () => 'id${++n}',
            writeClipboard: (text) async => clipboard = text,
            readClipboard: () async => clipboard,
          ),
        ),
      ),
    );
    await io(tester);
  }

  String text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

  Future<void> createVault(WidgetTester tester, {String master = 'una-contraseña-larga!'}) async {
    await tester.enterText(find.byKey(const Key('pw-master')), master);
    await tester.enterText(find.byKey(const Key('pw-master2')), master);
    await tester.tap(find.byKey(const Key('pw-ack')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('pw-create')));
    await io(tester);
  }

  testWidgets('sin bóveda pide crearla: la maestra corta, distinta o sin confirmar no vale', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('pw-create')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('pw-master')), 'corta');
    await tester.enterText(find.byKey(const Key('pw-master2')), 'corta');
    await tester.tap(find.byKey(const Key('pw-create')));
    await tester.pump();
    expect(find.text('Debe tener al menos 12 caracteres.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('pw-master')), 'una-contraseña-larga!');
    await tester.enterText(find.byKey(const Key('pw-master2')), 'otra-contraseña-larga');
    await tester.tap(find.byKey(const Key('pw-create')));
    await tester.pump();
    expect(find.text('Las dos contraseñas no coinciden.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('pw-master2')), 'una-contraseña-larga!');
    await tester.tap(find.byKey(const Key('pw-create')));
    await tester.pump();
    expect(find.text('Confirma que entiendes que no hay forma de recuperarla.'), findsOneWidget);
    expect(backend.meta, isNull);
  });

  testWidgets('el ojo muestra y oculta lo que se escribe', (tester) async {
    await open(tester);
    expect(tester.widget<TextField>(find.byKey(const Key('pw-master'))).obscureText, isTrue);
    await tester.tap(find.byKey(const Key('pw-master-eye')));
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(const Key('pw-master'))).obscureText, isFalse);
  });

  testWidgets('crear la bóveda la deja abierta y vacía', (tester) async {
    await open(tester);
    await createVault(tester);
    expect(backend.meta, isNotNull);
    expect(find.byKey(const Key('pw-empty')), findsOneWidget);
    expect(find.byKey(const Key('pw-lock')), findsOneWidget);
  });

  testWidgets('añadir una entrada con el generador: se guarda cifrada y sale en la lista', (tester) async {
    await open(tester);
    await createVault(tester);
    await tester.tap(find.byKey(const Key('pw-add')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('pw-save')));
    await tester.tap(find.byKey(const Key('pw-save')));
    await tester.pump();
    expect(find.text('Escribe el nombre del servicio.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('pw-service')), 'Correo');
    await tester.ensureVisible(find.byKey(const Key('pw-save')));
    await tester.tap(find.byKey(const Key('pw-save')));
    await tester.pump();
    expect(find.text('Anota al menos el correo, el usuario o la contraseña.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('pw-email')), 'yo@ejemplo.com');
    await tester.enterText(find.byKey(const Key('pw-url')), 'ftp://x');
    await tester.ensureVisible(find.byKey(const Key('pw-save')));
    await tester.tap(find.byKey(const Key('pw-save')));
    await tester.pump();
    expect(find.text('La URL debe empezar con http:// o https://.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('pw-url')), 'https://correo.example');
    await tester.ensureVisible(find.byKey(const Key('pw-generate')));
    await tester.tap(find.byKey(const Key('pw-generate')));
    await tester.pump();
    final generated = tester.widget<TextField>(find.byKey(const Key('pw-password'))).controller!.text;
    expect(generated, hasLength(20));
    expect(text(tester, 'pw-strength-label'), 'fuerte');
    await tester.ensureVisible(find.byKey(const Key('pw-save')));
    await tester.tap(find.byKey(const Key('pw-save')));
    await io(tester);
    expect(find.byKey(const Key('pw-item-id1')), findsOneWidget);
    expect(find.text('Correo'), findsOneWidget);
    expect(find.text('yo@ejemplo.com'), findsOneWidget);
    expect(backend.rows['id1']!.payload, isNot(contains(generated))); // en Supabase solo hay texto cifrado
  });

  testWidgets('tocar una entrada la despliega: la contraseña va oculta, se muestra con el ojo y cada dato se copia', (tester) async {
    await open(tester);
    await createVault(tester);
    await vault.add(service: 'Banco', email: 'yo@ejemplo.com', password: 'secreto-123', url: 'https://banco.example');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pw-value-password-id1')), findsNothing); // cerrada: solo el servicio
    await tester.tap(find.byKey(const Key('pw-head-id1')));
    await tester.pumpAndSettle();
    expect(text(tester, 'pw-value-password-id1'), '••••••••••');
    await tester.tap(find.byKey(const Key('pw-eye-id1')));
    await tester.pump();
    expect(text(tester, 'pw-value-password-id1'), 'secreto-123');
    await tester.tap(find.byKey(const Key('pw-copy-password-id1')));
    await io(tester);
    expect(clipboard, 'secreto-123');
    expect(find.textContaining('Se borrará del portapapeles en 30 segundos'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pw-copy-email-id1')));
    await io(tester);
    expect(clipboard, 'yo@ejemplo.com');
  });

  testWidgets('la búsqueda filtra por servicio, correo, usuario y URL', (tester) async {
    await open(tester);
    await createVault(tester);
    await vault.add(service: 'Zeta', email: 'zeta@x.com', password: 'a');
    await vault.add(service: 'Alfa', username: 'beto', password: 'b');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pw-search')), 'beto');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pw-item-id2')), findsOneWidget);
    expect(find.byKey(const Key('pw-item-id1')), findsNothing);
    await tester.enterText(find.byKey(const Key('pw-search')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Ninguna entrada coincide.'), findsOneWidget);
  });

  testWidgets('editar cambia la entrada y borrar pide confirmación', (tester) async {
    await open(tester);
    await createVault(tester);
    await vault.add(service: 'Banco', email: 'yo@ejemplo.com');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pw-head-id1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pw-edit-id1')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('pw-service'))).controller!.text, 'Banco');
    await tester.enterText(find.byKey(const Key('pw-service')), 'Banco 2');
    await tester.ensureVisible(find.byKey(const Key('pw-save')));
    await tester.tap(find.byKey(const Key('pw-save')));
    await io(tester);
    expect(find.text('Banco 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pw-del-id1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pw-delete-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pw-item-id1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('pw-del-id1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pw-delete-confirm')));
    await io(tester);
    expect(find.byKey(const Key('pw-item-id1')), findsNothing);
    expect(backend.deleted.containsKey('id1'), isTrue);
  });

  testWidgets('bloquear pide la maestra otra vez: una equivocada no abre y la correcta sí', (tester) async {
    await open(tester);
    await createVault(tester);
    await vault.add(service: 'Banco', email: 'yo@ejemplo.com');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pw-lock')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pw-unlock')), findsOneWidget);
    expect(find.byKey(const Key('pw-item-id1')), findsNothing); // nada de lo descifrado queda a la vista
    await tester.enterText(find.byKey(const Key('pw-master')), 'otra-contraseña-larga');
    await tester.tap(find.byKey(const Key('pw-unlock')));
    await io(tester);
    expect(find.text('Contraseña incorrecta.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('pw-master')), 'una-contraseña-larga!');
    await tester.tap(find.byKey(const Key('pw-unlock')));
    await io(tester);
    expect(find.byKey(const Key('pw-item-id1')), findsOneWidget);
  });

  testWidgets('se bloquea al irse la app a segundo plano', (tester) async {
    await open(tester);
    await createVault(tester);
    expect(vault.unlocked, isTrue);
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive); // un aviso del sistema encima: sigue abierta
    expect(vault.unlocked, isTrue);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(vault.unlocked, isFalse);
    for (final back in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      binding.handleAppLifecycleStateChanged(back); // al volver hay que escribir la maestra
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pw-unlock')), findsOneWidget);
  });

  testWidgets('al salir de la pantalla se suelta la clave', (tester) async {
    await open(tester);
    await createVault(tester);
    await vault.add(service: 'Banco', email: 'yo@ejemplo.com');
    final held = vault;
    await tester.pumpWidget(const SizedBox());
    expect(held.items, isEmpty);
  });

  testWidgets('la pantalla es plana: cabecera con línea fina y sin paneles', (tester) async {
    await open(tester);
    // el estilo plano de la ficha de una tarea y del clima: cabecera «> TÍTULO» con una línea fina, sin paneles ni cajas
    expect(find.byType(FlatHeader), findsOneWidget);
    expect(find.byKey(const Key('flat-backdrop')), findsOneWidget); // el fondo va un poco oscurecido
    expect(find.byType(CyberPanel), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(SegmentedButton<Object>), findsNothing);
  });

  testWidgets('un fallo al leer la bóveda se explica y se puede reintentar', (tester) async {
    backend.failWith = const ChatException('Sin conexión con Supabase', retryable: true, code: 'offline');
    await open(tester);
    expect(find.byKey(const Key('pw-error')), findsOneWidget);
    backend.failWith = null;
    await tester.tap(find.byKey(const Key('pw-retry')));
    await io(tester);
    expect(find.byKey(const Key('pw-create')), findsOneWidget);
  });
}
