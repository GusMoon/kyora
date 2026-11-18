import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/account_backend.dart';
import 'package:kyora_chat/data/chat_backend.dart';
import 'package:kyora_chat/models/message.dart';
import 'package:kyora_chat/models/presence.dart';
import 'package:kyora_chat/models/profile.dart';
import 'package:kyora_chat/data/chat_notifier.dart';
import 'package:kyora_chat/data/direct_backend.dart';
import 'package:kyora_chat/state/direct_chat_controller.dart';
import 'package:kyora_chat/state/presence_beat.dart';
import 'package:kyora_chat/state/users_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/settings_page.dart';
import 'package:kyora_chat/ui/users_panel.dart';

import 'auth_gate_test.dart' show FakeAccount;
import 'fake_admin.dart';
import 'fake_direct.dart';
import 'music_test.dart' show FakeMusicBackend, FakeSaver, MemoryMusicStore;
import 'package:kyora_chat/state/music_controller.dart';

/// El modo visitante: cómo se entra con un nombre, el chat privado, la presencia y el panel «Usuarios» del administrador.

PresenceEntry entry(String name, {Role role = Role.intern, bool online = false, bool verified = true, DateTime? seen, bool me = false, bool pending = false}) =>
    PresenceEntry(id: 'id-$name', username: name, role: role, verified: verified, online: online, lastSeen: seen, me: me, codePending: pending);

void main() {
  group('con qué correo se entra', () {
    test('un nombre se vuelve <nombre>@kyra.local (en minúsculas y sin espacios de más)', () {
      expect(loginEmail('Ana'), 'ana@kyra.local');
      expect(loginEmail('  Maria_01 '), 'maria_01@kyra.local');
    });
    test('un correo se deja tal cual (el administrador usa el de siempre)', () {
      expect(loginEmail(' yo@correo.com '), 'yo@correo.com');
    });
  });

  group('el perfil', () {
    test('lee si ya verificó su código (y sin esa columna se da por verificado)', () {
      expect(Profile.fromJson({'id': 'a', 'username': 'ana', 'role': 'intern', 'verified': false}).verified, isFalse);
      expect(Profile.fromJson({'id': 'a', 'username': 'ana', 'role': 'intern'}).verified, isTrue);
    });
    test('el rol se enseña como Administrador o Visitante', () {
      expect(roleLabel(Role.admin), 'Administrador');
      expect(roleLabel(Role.intern), 'Visitante');
    });
  });

  group('en línea o hace cuánto', () {
    final now = DateTime.utc(2026, 11, 17, 12);
    test('en línea, hace un momento, minutos, horas, días y nunca', () {
      expect(lastSeenText(entry('a', online: true), now), 'en línea');
      expect(lastSeenText(entry('a', seen: now.subtract(const Duration(seconds: 20))), now), 'hace un momento');
      expect(lastSeenText(entry('a', seen: now.subtract(const Duration(minutes: 5))), now), 'hace 5 min');
      expect(lastSeenText(entry('a', seen: now.subtract(const Duration(hours: 3))), now), 'hace 3 h');
      expect(lastSeenText(entry('a', seen: now.subtract(const Duration(days: 2))), now), 'hace 2 d');
      expect(lastSeenText(entry('a'), now), 'nunca entró');
    });
  });

  group('el chat privado 1 a 1', () {
    late FakeDirectBackend backend;
    late FakeChatNotifier notifier;
    late DirectChatsController chats;
    var counter = 0;
    var foreground = true;

    setUp(() {
      backend = FakeDirectBackend();
      notifier = FakeChatNotifier();
      counter = 0;
      foreground = true;
      chats = DirectChatsController(backend, notifier: notifier, appInForeground: () => foreground, newId: () => 'id-${++counter}');
    });
    tearDown(() => chats.dispose());

    Future<void> settleAsync() async {
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('el directorio son todos los demás (sin uno mismo)', () async {
      await chats.start();
      await chats.loadPeople();
      expect(chats.people.map((p) => p.username), ['gustavo', 'luis']);
    });

    test('abrir un chat con alguien, escribir y que aparezca en la lista', () async {
      await chats.start();
      expect(chats.threads, isEmpty);
      final thread = await chats.openWith(const ChatUser(id: 'user-2', username: 'luis'));
      await settleAsync();
      final pending = thread.send('  hola luis ');
      expect(thread.messages.single.state, SendState.pending);
      expect(await pending, isTrue);
      expect(thread.messages.single.state, SendState.sent);
      expect(thread.messages.single.body, 'hola luis');
      expect(backend.sent, ['hola luis']);
      await settleAsync();
      expect(chats.threads.single.other.username, 'luis');
      expect(chats.threads.single.last!.body, 'hola luis');
    });

    test('no manda mensajes vacíos', () async {
      await chats.start();
      final thread = await chats.openWith(const ChatUser(id: 'user-2', username: 'luis'));
      expect(await thread.send('   '), isFalse);
      expect(backend.sent, isEmpty);
    });

    test('si falla el envío queda con su error y se reintenta con el mismo id (sin duplicar)', () async {
      await chats.start();
      final thread = await chats.openWith(const ChatUser(id: 'user-2', username: 'luis'));
      await settleAsync();
      backend.sendError = const ChatException('Sin conexión con Supabase', retryable: true, code: 'offline');
      await thread.send('hola');
      expect(thread.messages.single.state, SendState.failed);
      expect(thread.messages.single.error, 'Sin conexión con Supabase');
      backend.sendError = null;
      await thread.retry('id-1');
      expect(thread.messages, hasLength(1));
      expect(thread.messages.single.state, SendState.sent);
      expect(backend.server, hasLength(1));
    });

    test('los no leídos se cuentan y se ponen a cero al ver la conversación', () async {
      backend.receive('m1', body: 'hola');
      backend.receive('m2', body: '¿estás?');
      await chats.start();
      expect(chats.unread, 2);
      final thread = chats.controllerFor(chats.threads.single);
      await thread.markRead();
      await settleAsync();
      expect(chats.unread, 0);
    });

    test('«borrar para mí» lo quita solo de mi vista: en el servidor sigue', () async {
      backend.receive('m1', body: 'primero');
      backend.receive('m2', body: 'segundo');
      await chats.start();
      final thread = chats.controllerFor(chats.threads.single);
      await settleAsync();
      expect(thread.messages.map((m) => m.id), ['m1', 'm2']);
      await thread.hide('m1');
      expect(thread.messages.map((m) => m.id), ['m2']);
      expect(backend.calls, contains('hide:m1'));
      expect(backend.server.map((m) => m.id), ['m1', 'm2']); // la base de datos no cambia
      await thread.refresh();
      expect(thread.messages.map((m) => m.id), ['m2']); // y no vuelve
    });

    test('«vaciar chat» deja la conversación vacía solo para mí', () async {
      backend.receive('m1');
      backend.receive('m2');
      await chats.start();
      final thread = chats.controllerFor(chats.threads.single);
      await settleAsync();
      await thread.clear();
      expect(thread.messages, isEmpty);
      expect(backend.server, hasLength(2)); // la base de datos no cambia
      await thread.refresh();
      expect(thread.messages, isEmpty);
    });

    test('lo que llega por Realtime aparece solo, y lo que borra el administrador desaparece', () async {
      await chats.start();
      final m = backend.receive('m9', body: 'nuevo');
      final thread = chats.controllerFor(await backend.openThread('admin-1'));
      await settleAsync();
      expect(thread.messages.map((x) => x.id), ['m9']);
      backend.server.clear();
      backend.emit(DirectSignal(SignalKind.deleted, messageId: m.id, threadId: m.threadId));
      await settleAsync();
      expect(thread.messages, isEmpty);
    });

    test('un mensaje que llega con la app en segundo plano avisa con una notificación (con el nombre de quien escribe)', () async {
      await chats.start();
      await chats.loadPeople();
      foreground = false;
      final m = backend.receive('m1', body: 'ya llegué');
      backend.emit(DirectSignal(SignalKind.changed, messageId: m.id, threadId: m.threadId, senderId: 'admin-1', body: 'ya llegué'));
      await settleAsync();
      expect(notifier.shown, [('gustavo', 'ya llegué')]);
    });

    test('con la conversación a la vista no se avisa; con otra abierta, sí', () async {
      await chats.start();
      final m = backend.receive('m1', body: 'hola');
      chats.visibleThread = m.threadId;
      backend.emit(DirectSignal(SignalKind.changed, messageId: m.id, threadId: m.threadId, senderId: 'admin-1', body: 'hola'));
      await settleAsync();
      expect(notifier.shown, isEmpty);
      chats.visibleThread = 'otra';
      backend.emit(DirectSignal(SignalKind.changed, messageId: 'm2', threadId: m.threadId, senderId: 'admin-1', body: 'oye'));
      await settleAsync();
      expect(notifier.shown, hasLength(1));
    });

    test('lo que mando yo no se avisa', () async {
      await chats.start();
      foreground = false;
      backend.emit(const DirectSignal(SignalKind.changed, messageId: 'x', threadId: 't', senderId: 'user-1', body: 'mío'));
      await settleAsync();
      expect(notifier.shown, isEmpty);
    });

    test('si no se puede abrir, dice por qué', () async {
      backend.listError = const ChatException('Tu cuenta aún no está verificada.', code: 'not_verified');
      await chats.start();
      expect(chats.error, 'Tu cuenta aún no está verificada.');
    });

    test('«en vivo» sigue a la conexión', () async {
      await chats.start();
      expect(chats.live, isFalse);
      backend.emit(const DirectSignal(SignalKind.connected));
      await settleAsync();
      expect(chats.live, isTrue);
      backend.emit(const DirectSignal(SignalKind.disconnected));
      await settleAsync();
      expect(chats.live, isFalse);
    });

    test('la supervisión del administrador ve todo y borra de verdad', () async {
      backend.receive('m1', body: 'hola');
      backend.receive('m2', body: 'otro', from: 'user-2');
      final admin = DirectSupervisionController(backend);
      addTearDown(admin.dispose);
      await admin.refresh();
      expect(admin.threads, hasLength(2));
      final first = admin.threads.first;
      expect(await admin.messagesOf(first.id), hasLength(1));
      await admin.deleteMessage('m1');
      expect(backend.server.map((m) => m.id), ['m2']);
      await admin.deleteThread(first.id);
      expect(admin.threads, hasLength(1));
    });
  });

  group('el latido de presencia', () {
    testWidgets('late al empezar y cada 30 s; al parar deja de latir; un fallo no lo rompe', (tester) async {
      final backend = FakeAdminBackend();
      final beat = PresenceBeat(backend);
      addTearDown(beat.stop);
      beat.start();
      beat.start(); // repetir no duplica
      await tester.pump();
      expect(backend.touches, 1);
      await tester.pump(const Duration(seconds: 30));
      expect(backend.touches, 2);
      backend.error = const ChatException('Sin conexión con Supabase', retryable: true, code: 'offline');
      await tester.pump(const Duration(seconds: 30));
      expect(backend.touches, 3); // lo intentó y falló, sin romper nada
      backend.error = null;
      await tester.pump(const Duration(seconds: 30));
      expect(backend.touches, 4);
      beat.nudge(); // al volver a la app late ya
      await tester.pump();
      expect(backend.touches, 5);
      beat.stop();
      await tester.pump(const Duration(seconds: 90));
      expect(backend.touches, 5);
      expect(beat.running, isFalse);
    });

    testWidgets('sin empezar, «nudge» no hace nada', (tester) async {
      final backend = FakeAdminBackend();
      PresenceBeat(backend).nudge();
      await tester.pump();
      expect(backend.touches, 0);
    });
  });

  group('el panel de usuarios del administrador', () {
    late FakeAdminBackend backend;
    late UsersController users;

    setUp(() {
      backend = FakeAdminBackend([
        entry('gustavo', role: Role.admin, online: true, me: true),
        entry('ana', online: true),
        entry('luis', seen: DateTime.now().toUtc().subtract(const Duration(hours: 2))),
        entry('nueva', verified: false, pending: true),
      ]);
      users = UsersController(backend);
    });
    tearDown(() => users.dispose());

    test('lee las cuentas y cuenta las que están en línea', () async {
      await users.refresh();
      expect(users.entries, hasLength(4));
      expect(users.onlineCount, 2);
      expect(users.loading, isFalse);
    });

    test('crear una cuenta devuelve su código y vuelve a leer la lista', () async {
      await users.refresh();
      final issued = await users.create(username: 'marta', password: 'secreta1', role: Role.intern);
      expect(issued!.code, '482913');
      expect(issued.username, 'marta');
      expect(backend.calls, ['create:marta:intern']);
      expect(users.entries.map((e) => e.username), contains('marta'));
    });

    test('si falla, queda el motivo y no hay código', () async {
      backend.error = const ChatException('Ese nombre de usuario ya existe.', code: 'username_taken');
      final issued = await users.create(username: 'ana', password: 'secreta1', role: Role.intern);
      expect(issued, isNull);
      expect(users.error, 'Ese nombre de usuario ya existe.');
    });

    test('cambiar el rol, pedir otro código y quitar el acceso', () async {
      await users.refresh();
      final ana = users.entries.firstWhere((e) => e.username == 'ana');
      expect(await users.changeRole(ana, Role.admin), isTrue);
      expect(users.entries.firstWhere((e) => e.username == 'ana').role, Role.admin);
      final code = await users.newCode(ana);
      expect(code!.code, '482913');
      expect(await users.remove(ana), isTrue);
      expect(users.entries.map((e) => e.username), isNot(contains('ana')));
      expect(backend.calls, ['role:id-ana:admin', 'code:id-ana', 'remove:id-ana']);
    });

    testWidgets('se vuelve a leer sola cada 30 s mientras está abierto', (tester) async {
      users.start();
      await tester.pump();
      final first = backend.lists;
      await tester.pump(const Duration(seconds: 30));
      expect(backend.lists, greaterThan(first));
      users.stop();
      final stopped = backend.lists;
      await tester.pump(const Duration(seconds: 60));
      expect(backend.lists, stopped);
    });

    testWidgets('el panel enseña quién está en línea y hace cuánto se vio a los demás', (tester) async {
      await users.refresh();
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: UsersPanel(controller: users))));
      expect(find.byKey(const Key('users-count')), findsOneWidget);
      expect(find.textContaining('2 en línea de 4'), findsOneWidget);
      expect(find.text('gustavo (tú)'), findsOneWidget);
      expect(find.textContaining('Visitante · en línea'), findsOneWidget); // ana
      expect(find.textContaining('hace 2 h'), findsOneWidget); // luis
      expect(find.textContaining('código pendiente'), findsOneWidget); // la cuenta nueva
    });

    testWidgets('crear una cuenta desde el panel enseña el código de 6 dígitos una sola vez', (tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await users.refresh();
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: UsersPanel(controller: users))));
      await tester.tap(find.byKey(const Key('users-create')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('users-new-name')), 'ab'); // muy corto
      await tester.enterText(find.byKey(const Key('users-new-password')), 'secreta1');
      await tester.tap(find.byKey(const Key('users-new-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('users-new-error')), findsOneWidget);
      expect(backend.calls, isEmpty); // no llamó al servidor
      await tester.enterText(find.byKey(const Key('users-new-name')), 'Marta');
      await tester.tap(find.byKey(const Key('users-new-submit')));
      await tester.pumpAndSettle();
      expect(backend.calls, ['create:marta:intern']);
      expect(find.byKey(const Key('users-code')), findsOneWidget);
      expect(find.text('482913'), findsOneWidget);
      await tester.tap(find.byKey(const Key('users-code-done')));
      await tester.pumpAndSettle();
      expect(find.text('482913'), findsNothing); // no se vuelve a mostrar
      expect(find.byKey(const Key('users-row-marta')), findsOneWidget);
    });

    testWidgets('con tu propia cuenta no se hace nada desde el panel', (tester) async {
      await users.refresh();
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: UsersPanel(controller: users))));
      await tester.tap(find.byKey(const Key('users-row-gustavo')), warnIfMissed: false); // la fila propia no se toca
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('users-act-role')), findsNothing);
      await tester.tap(find.byKey(const Key('users-row-ana')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('users-act-role')), findsOneWidget);
    });
  });

  group('la ficha «Usuarios» de Configuración', () {
    Future<void> open(WidgetTester tester, {required Role role, UsersController? users}) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final music = MusicController(FakeMusicBackend(), MemoryMusicStore(since: DateTime.utc(2026, 10, 1)), FakeSaver());
      addTearDown(music.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: SettingsPage(music: music, role: role, onSignOut: () async {}, account: FakeAccount(uid: 'u1'), users: users),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('el administrador la ve, con cuántos están en línea', (tester) async {
      final users = UsersController(FakeAdminBackend([entry('gustavo', role: Role.admin, online: true, me: true), entry('ana', online: true)]));
      addTearDown(users.dispose);
      await open(tester, role: Role.admin, users: users);
      expect(find.byKey(const Key('mosaic-tile-users')), findsOneWidget);
      expect(find.text('2 EN LÍNEA'), findsOneWidget);
    });

    testWidgets('quien no es administrador no la ve', (tester) async {
      final users = UsersController(FakeAdminBackend());
      addTearDown(users.dispose);
      await open(tester, role: Role.intern, users: users);
      expect(find.byKey(const Key('mosaic-tile-users')), findsNothing);
    });
  });
}
