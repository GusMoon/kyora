import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/contacts_source.dart';
import 'package:kyora_chat/state/contacts_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/contacts_page.dart';

const _ana = Contact(id: '1', name: 'Ana Torres', phones: ['+51 987 654 321']);
const _beto = Contact(id: '2', name: 'beto', phones: ['(01) 555-1234', '+34 600 11 22 33']);
const _carla = Contact(id: '3', name: 'Carla', phones: ['999888777']);
const _uno = Contact(id: '4', name: '1Password', phones: ['000']);

void main() {
  group('los números', () {
    test('para marcar: solo cifras y el «+» del principio', () {
      expect(dialNumber('+51 987-654 321'), '+51987654321');
      expect(dialNumber('(01) 555-1234'), '015551234');
      expect(dialNumber('  987 654 321 '), '987654321');
    });

    test('para WhatsApp: solo cifras, sin «+» ni «00»', () {
      expect(whatsappNumber('+51 987-654 321'), '51987654321');
      expect(whatsappNumber('0034 600 11 22 33'), '34600112233');
      expect(whatsappNumber('999 888 777'), '999888777');
    });

    test('un contacto se lee de lo que manda Android', () {
      final c = Contact.fromMap({'id': 7, 'name': 'Zoe', 'phones': ['1', '2']});
      expect(c.id, '7');
      expect(c.name, 'Zoe');
      expect(c.phones, ['1', '2']);
      expect(c.letter, 'Z');
      expect(c.initial, 'Z');
      expect(const Contact(id: '1', name: '1Password', phones: []).letter, '#');
    });
  });

  group('el controlador', () {
    late FakeContactsSource source;
    late ContactsController controller;

    setUp(() {
      source = FakeContactsSource([_carla, _uno, _beto, _ana]);
      controller = ContactsController(source);
    });

    tearDown(() => controller.dispose());

    test('con permiso lee los contactos y los ordena de la A a la Z (lo que no empieza por letra, al final)', () async {
      await controller.start();
      expect(controller.status, ContactsStatus.ready);
      expect([for (final c in controller.contacts) c.name], ['Ana Torres', 'beto', 'Carla', '1Password']);
      expect(controller.total, 4);
    });

    test('sin permiso espera a que se pida; al darlo, los lee', () async {
      source
        ..granted = false
        ..grantsOnRequest = true;
      await controller.start();
      expect(controller.status, ContactsStatus.denied);
      expect(source.reads, 0);
      await controller.grant();
      expect(source.requests, 1);
      expect(controller.status, ContactsStatus.ready);
    });

    test('si no se da el permiso, sigue sin él', () async {
      source
        ..granted = false
        ..grantsOnRequest = false;
      await controller.start();
      await controller.grant();
      expect(controller.status, ContactsStatus.denied);
    });

    test('un fallo al leer se cuenta y se puede reintentar', () async {
      source.failing = true;
      await controller.start();
      expect(controller.status, ContactsStatus.failed);
      expect(controller.error, 'No se pudieron leer los contactos.');
      source.failing = false;
      await controller.refresh();
      expect(controller.status, ContactsStatus.ready);
      expect(controller.error, isNull);
    });

    test('se busca por nombre (sin distinguir mayúsculas) o por cualquier número, ignorando espacios y signos', () async {
      await controller.start();
      controller.search('BET');
      expect([for (final c in controller.contacts) c.name], ['beto']);
      controller.search('600112');
      expect([for (final c in controller.contacts) c.name], ['beto']);
      controller.search('987 654');
      expect([for (final c in controller.contacts) c.name], ['Ana Torres']);
      controller.search('zzz');
      expect(controller.contacts, isEmpty);
      controller.search('');
      expect(controller.contacts, hasLength(4));
    });

    test('llamar y abrir WhatsApp mandan el número a Android', () async {
      await controller.start();
      expect(await controller.call('+51 987 654 321'), isTrue);
      expect(await controller.whatsapp('+51 987 654 321'), isTrue);
      expect(source.calls, ['+51987654321']);
      expect(source.chats, ['51987654321']);
    });
  });

  group('la pantalla', () {
    late FakeContactsSource source;
    late ContactsController controller;

    setUp(() {
      source = FakeContactsSource([_carla, _beto, _ana, _uno]);
      controller = ContactsController(source);
    });

    tearDown(() => controller.dispose());

    Future<void> show(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: ContactsPage(controller: controller)));
      await tester.pumpAndSettle();
    }

    testWidgets('enseña los contactos por letras, con su primer número', (tester) async {
      await show(tester);
      expect(find.text('// A'), findsOneWidget);
      expect(find.text('// B'), findsOneWidget);
      expect(find.text('// #'), findsOneWidget);
      expect(find.text('Ana Torres'), findsOneWidget);
      expect(find.text('+51 987 654 321'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('contacts-count'))).data, '4/4');
    });

    testWidgets('tocar un contacto enseña todos sus números, cada uno con llamar y WhatsApp', (tester) async {
      await show(tester);
      expect(find.byKey(const Key('call-2-0')), findsNothing);
      await tester.tap(find.byKey(const Key('contact-2')));
      await tester.pumpAndSettle();
      for (final key in ['call-2-0', 'wa-2-0', 'call-2-1', 'wa-2-1']) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      await tester.tap(find.byKey(const Key('contact-2'))); // otra vez: se cierra
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('call-2-0')), findsNothing);
    });

    testWidgets('llamar abre el marcador con ese número y WhatsApp abre su chat', (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const Key('contact-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('call-2-1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('wa-2-1')));
      await tester.pump();
      expect(source.calls, ['+34600112233']);
      expect(source.chats, ['34600112233']);
    });

    testWidgets('solo un contacto abierto a la vez', (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const Key('contact-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('contact-3')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('call-1-0')), findsNothing);
      expect(find.byKey(const Key('call-3-0')), findsOneWidget);
    });

    testWidgets('el buscador deja solo lo que casa y se borra con la cruz', (tester) async {
      await show(tester);
      await tester.enterText(find.byKey(const Key('contacts-search')), 'car');
      await tester.pumpAndSettle();
      expect(find.text('Carla'), findsOneWidget);
      expect(find.text('Ana Torres'), findsNothing);
      expect(tester.widget<Text>(find.byKey(const Key('contacts-count'))).data, '1/4');
      await tester.tap(find.byKey(const Key('contacts-clear')));
      await tester.pumpAndSettle();
      expect(find.text('Ana Torres'), findsOneWidget);
    });

    testWidgets('una búsqueda sin resultados lo dice', (tester) async {
      await show(tester);
      await tester.enterText(find.byKey(const Key('contacts-search')), 'zzzz');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vault-message')), findsNothing);
      expect(find.text('> sin coincidencias'), findsOneWidget);
    });

    testWidgets('sin permiso invita a darlo, y al darlo salen los contactos', (tester) async {
      source
        ..granted = false
        ..grantsOnRequest = true;
      await show(tester);
      expect(find.byKey(const Key('contacts-grant')), findsOneWidget);
      expect(find.text('Ana Torres'), findsNothing);
      await tester.tap(find.byKey(const Key('contacts-grant')));
      await tester.pumpAndSettle();
      expect(source.requests, 1);
      expect(find.text('Ana Torres'), findsOneWidget);
    });

    testWidgets('si falla al leer lo avisa y deja reintentar', (tester) async {
      source.failing = true;
      await show(tester);
      expect(find.text('> No se pudieron leer los contactos.'), findsOneWidget);
      source.failing = false;
      await tester.tap(find.byKey(const Key('contacts-retry')));
      await tester.pumpAndSettle();
      expect(find.text('Ana Torres'), findsOneWidget);
    });

    testWidgets('una agenda vacía lo dice', (tester) async {
      source.contacts = [];
      await show(tester);
      expect(find.text('> la agenda está vacía'), findsOneWidget);
    });

    testWidgets('en una pantalla baja y estrecha no se desborda, ni con un contacto abierto', (tester) async {
      tester.view.physicalSize = const Size(320, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: ContactsPage(controller: controller)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('contact-2')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
