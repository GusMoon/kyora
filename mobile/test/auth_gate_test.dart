import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/account_backend.dart';
import 'package:kyora_chat/data/chat_backend.dart';
import 'package:kyora_chat/models/profile.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/auth_gate.dart';
import 'package:kyora_chat/ui/login_page.dart';
import 'package:kyora_chat/ui/register_page.dart';

import 'fake_backend.dart';
import 'sections.dart';
import 'fake_engine.dart';
import 'music_test.dart' show FakeMusicBackend, FakeSaver, MemoryMusicStore;

class FakeAccount implements AccountBackend {
  FakeAccount({String? uid, this.profile}) {
    _uid = uid;
  }

  String? _uid;
  Profile? profile;
  ChatException? profileError;
  ChatException? signUpError;

  /// Si es `false`, el registro no deja dentro (Supabase pide confirmar el correo).
  bool signUpSignsIn = true;
  int profileCalls = 0;
  final List<(String, String, String)> signUps = [];
  final _changes = StreamController<void>.broadcast();

  @override
  bool get signedIn => _uid != null;

  @override
  String? get userId => _uid;

  @override
  Stream<void> get authChanges => _changes.stream;

  @override
  Future<void> signIn(String email, String password) async {
    _uid = 'user-1';
    _changes.add(null);
  }

  @override
  Future<bool> signUp({required String username, required String email, required String password}) async {
    final error = signUpError;
    if (error != null) throw error;
    signUps.add((username, email, password));
    if (!signUpSignsIn) return false;
    _uid = 'user-2';
    profile = Profile(id: 'user-2', username: username, role: Role.intern);
    _changes.add(null);
    return true;
  }

  @override
  Future<void> signOut() async {
    _uid = null;
    _changes.add(null);
  }

  /// La sesión caduca sola (Supabase no pudo renovar el token): no es que la persona cierre sesión.
  void expire() {
    _uid = null;
    _changes.add(null);
  }

  /// La persona `uid` vuelve a tener sesión (entró otra vez).
  void restore(String uid) {
    _uid = uid;
    _changes.add(null);
  }

  @override
  Future<Profile?> myProfile() async {
    profileCalls++;
    final error = profileError;
    if (error != null) throw error;
    return profile;
  }
}

class MemoryRoleCache implements RoleCache {
  final Map<String, Role> roles = {};

  @override
  Future<Role?> read(String userId) async => roles[userId];

  @override
  Future<void> write(String userId, Role role) async => roles[userId] = role;
}

Future<void> settle(WidgetTester tester, [int ms = 60]) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await tester.pump();
}

void main() {
  late FakeBackend chat;
  late FakeMusicBackend music;
  late MemoryRoleCache cache;

  setUp(() {
    chat = FakeBackend();
    music = FakeMusicBackend();
    cache = MemoryRoleCache();
  });

  Future<void> openGate(WidgetTester tester, FakeAccount account) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: AuthGate(
        account: account,
        chat: chat,
        music: music,
        musicStore: MemoryMusicStore(since: DateTime.utc(2026, 10, 1)),
        saver: FakeSaver(),
        roleCache: cache,
        engine: FakeEngine.new,
      ),
    ));
    await settle(tester);
  }

  group('puerta por rol', () {
    testWidgets('sin sesión enseña el acceso con la opción de crear cuenta', (tester) async {
      await openGate(tester, FakeAccount());
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byKey(const Key('create-account')), findsOneWidget);
    });

    testWidgets('el administrador entra a Inicio, y tiene inicio, chat y música para deslizar', (tester) async {
      final account = FakeAccount(uid: 'user-1', profile: const Profile(id: 'user-1', username: 'gustavo', role: Role.admin));
      await openGate(tester, account);
      expect(await menuOptions(tester), containsAll(['home', 'chat', 'music', 'settings'])); // en el menú circular (y Configuración es una opción más)
      expect(find.byKey(const Key('radial-menu')), findsNothing); // que se cierra al soltar sin elegir
      expect(find.byKey(const Key('home-greeting')), findsOneWidget); // empieza en Inicio
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Chat')), findsNothing);
      await goToSection(tester, 'chat');
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Chat')), findsOneWidget);
      expect(chat.calls, contains('ensure'));
      expect(cache.roles['user-1'], Role.admin);
    });

    testWidgets('el pasante entra a Inicio, la música está al lado y no toca el chat', (tester) async {
      final account = FakeAccount(uid: 'user-2', profile: const Profile(id: 'user-2', username: 'ana', role: Role.intern));
      await openGate(tester, account);
      expect(find.byKey(const Key('home-greeting')), findsOneWidget); // empieza en Inicio
      final options = await menuOptions(tester);
      expect(options, isNot(contains('chat'))); // sin chat
      expect(options, containsAll(['home', 'music']));
      await goToSection(tester, 'music');
      expect(find.byKey(const Key('album-deck')), findsOneWidget); // la pantalla de música
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Chat')), findsNothing);
      expect(chat.calls, isEmpty); // ni conversación, ni mensajes, ni Realtime del chat
    });

    testWidgets('una cuenta sin perfil se trata como pasante (la vista con menos permisos)', (tester) async {
      await openGate(tester, FakeAccount(uid: 'user-3'));
      expect(await menuOptions(tester), isNot(contains('chat')));
      await goToSection(tester, 'music');
      expect(find.byKey(const Key('album-deck')), findsOneWidget); // la pantalla de música
      expect(chat.calls, isEmpty);
    });

    testWidgets('sin internet usa el rol de la última vez', (tester) async {
      cache.roles['user-1'] = Role.admin;
      final account = FakeAccount(uid: 'user-1')..profileError = const ChatException('Sin conexión con Supabase', retryable: true, code: 'offline');
      await openGate(tester, account);
      expect(await menuOptions(tester), contains('chat'));
    });

    testWidgets('sin internet y sin rol guardado lo dice y deja reintentar', (tester) async {
      final account = FakeAccount(uid: 'user-1')..profileError = const ChatException('Sin conexión con Supabase', retryable: true, code: 'offline');
      await openGate(tester, account);
      expect(find.byKey(const Key('role-error')), findsOneWidget);
      expect(find.text('Sin conexión con Supabase'), findsOneWidget);
      account
        ..profileError = null
        ..profile = const Profile(id: 'user-1', username: 'gustavo', role: Role.admin);
      await tester.tap(find.byKey(const Key('role-retry')));
      await tester.pump();
      await settle(tester);
      await tester.pump();
      expect(find.byKey(const Key('role-error')), findsNothing);
      expect(await menuOptions(tester), contains('chat'));
    });

    testWidgets('el rol guardado de otra cuenta no se usa', (tester) async {
      cache.roles['otro'] = Role.admin;
      final account = FakeAccount(uid: 'user-2')..profileError = const ChatException('Sin conexión con Supabase', retryable: true, code: 'offline');
      await openGate(tester, account);
      expect(find.byKey(const Key('role-error')), findsOneWidget);
    });

    testWidgets('cerrar sesión vuelve al acceso', (tester) async {
      final account = FakeAccount(uid: 'user-2', profile: const Profile(id: 'user-2', username: 'ana', role: Role.intern));
      await openGate(tester, account);
      await tester.tap(find.byKey(const Key('home-settings'))); // el botón de Inicio abre la configuración
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('settings-sign-out')));
      await tester.tap(find.byKey(const Key('settings-sign-out')));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
    });
  });

  group('crear cuenta', () {
    Future<void> openRegister(WidgetTester tester, FakeAccount account) async {
      await openGate(tester, account);
      await tester.tap(find.byKey(const Key('create-account')));
      await tester.pumpAndSettle();
      expect(find.byType(RegisterPage), findsOneWidget);
    }

    Future<void> fill(WidgetTester tester, {String user = 'ana_p', String email = 'ana@correo.com', String pass = 'secreta1', String? repeat}) async {
      await tester.enterText(find.byKey(const Key('reg-username')), user);
      await tester.enterText(find.byKey(const Key('reg-email')), email);
      await tester.enterText(find.byKey(const Key('reg-password')), pass);
      await tester.enterText(find.byKey(const Key('reg-repeat')), repeat ?? pass);
    }

    Future<void> submit(WidgetTester tester) async {
      await tester.pump(); // el botón se activa tras escribir
      await tester.ensureVisible(find.byKey(const Key('reg-button')));
      await tester.tap(find.byKey(const Key('reg-button')));
      await tester.pump();
      await settle(tester);
    }

    bool createEnabled(WidgetTester tester) => tester.widget<FilledButton>(find.byKey(const Key('reg-button'))).onPressed != null;

    Future<void> scrollToButton(WidgetTester tester) => tester.ensureVisible(find.byKey(const Key('reg-button')));

    testWidgets('la lista de requisitos de la contraseña se pone en verde a medida que se cumplen', (tester) async {
      await openRegister(tester, FakeAccount());
      for (final id in ['length', 'letter', 'number', 'match']) {
        expect(find.byKey(Key('rule-$id-todo')), findsOneWidget, reason: id); // al empezar, todos pendientes
      }
      Color colorOf(String id, bool met) => tester.widget<Icon>(find.byKey(Key('rule-$id-${met ? 'ok' : 'todo'}'))).color!;
      expect(colorOf('length', false), KyoraColors.classic().dim);

      await tester.enterText(find.byKey(const Key('reg-password')), 'abc');
      await tester.pump();
      expect(find.byKey(const Key('rule-letter-ok')), findsOneWidget);
      expect(colorOf('letter', true), KyoraColors.classic().ok);
      expect(find.byKey(const Key('rule-length-todo')), findsOneWidget);
      expect(find.byKey(const Key('rule-number-todo')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('reg-password')), 'abc123');
      await tester.pump();
      expect(find.byKey(const Key('rule-length-ok')), findsOneWidget);
      expect(find.byKey(const Key('rule-number-ok')), findsOneWidget);
      expect(find.byKey(const Key('rule-match-todo')), findsOneWidget); // falta repetirla

      await tester.enterText(find.byKey(const Key('reg-repeat')), 'abc12');
      await tester.pump();
      expect(find.byKey(const Key('rule-match-todo')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('reg-repeat')), 'abc123');
      await tester.pump();
      expect(find.byKey(const Key('rule-match-ok')), findsOneWidget);
      expect(find.byKey(const Key('rule-length-todo')), findsNothing);
    });

    testWidgets('el botón solo se activa cuando todo está en verde, y no llama a Supabase antes', (tester) async {
      final account = FakeAccount();
      await openRegister(tester, account);
      await scrollToButton(tester);
      expect(createEnabled(tester), isFalse);

      await fill(tester, pass: '123'); // corta, sin letra
      await tester.pump();
      expect(createEnabled(tester), isFalse);
      await fill(tester, pass: 'secreta'); // sin número
      await tester.pump();
      expect(createEnabled(tester), isFalse);
      await fill(tester, repeat: 'otra-cosa'); // no coinciden
      await tester.pump();
      expect(createEnabled(tester), isFalse);
      await fill(tester, user: 'ab'); // usuario corto
      await tester.pump();
      expect(createEnabled(tester), isFalse);
      expect(find.text('Entre 3 y 24 caracteres.'), findsOneWidget);
      await fill(tester, email: 'sin-arroba');
      await tester.pump();
      expect(createEnabled(tester), isFalse);
      expect(find.textContaining('Escribe un correo con @'), findsOneWidget);

      await fill(tester);
      await tester.pump();
      expect(createEnabled(tester), isTrue);
      expect(account.signUps, isEmpty);
    });

    testWidgets('vale cualquier correo con @: Gmail, Outlook, Hotmail o uno inventado, y un usuario con espacios', (tester) async {
      for (final email in ['ana@gmail.com', 'ana@outlook.com', 'ana@hotmail.es', 'ana@inventado.xyz', 'ana@inventado', 'a.b+c@x.co']) {
        expect(emailProblem(email), isNull, reason: email);
      }
      for (final email in ['', 'ana', 'ana@', '@gmail.com', 'an a@gmail.com', 'a@b@c']) {
        expect(emailProblem(email), isNotNull, reason: email);
      }
      expect(usernameProblem('Gustavo Marrufo'), isNull);
      expect(usernameProblem('  ana  '), isNull);
      expect(usernameProblem('ana!'), isNotNull);
      final account = FakeAccount();
      await openRegister(tester, account);
      await fill(tester, user: 'Ana María', email: 'ana@inventado.xyz');
      await tester.pump();
      expect(createEnabled(tester), isTrue);
    });

    testWidgets('crea la cuenta, entra solo como pasante y la pantalla de registro se cierra', (tester) async {
      final account = FakeAccount();
      await openRegister(tester, account);
      await fill(tester, user: '  María 01 ');
      await submit(tester);
      expect(account.signUps, [('María 01', 'ana@correo.com', 'secreta1')]);
      await tester.pumpAndSettle(); // termina la animación de cerrar la pantalla
      expect(find.byType(RegisterPage), findsNothing);
      expect(find.byType(LoginPage), findsNothing);
      expect(find.byKey(const Key('home-greeting')), findsOneWidget); // entra en Inicio
      expect(await menuOptions(tester), isNot(contains('chat')));
    });

    testWidgets('un usuario repetido se explica en la propia pantalla y no cierra nada', (tester) async {
      final account = FakeAccount()..signUpError = const ChatException('Ese nombre de usuario ya está en uso.', code: 'username_taken');
      await openRegister(tester, account);
      await fill(tester);
      await submit(tester);
      expect(find.byKey(const Key('reg-error')), findsOneWidget);
      expect(find.text('Ese nombre de usuario ya está en uso.'), findsOneWidget);
      expect(find.byType(RegisterPage), findsOneWidget);
    });

    testWidgets('si Supabase pide confirmar el correo, vuelve al acceso con un aviso', (tester) async {
      final account = FakeAccount()..signUpSignsIn = false;
      await openRegister(tester, account);
      await fill(tester);
      await submit(tester);
      await tester.pumpAndSettle();
      expect(find.byType(RegisterPage), findsNothing);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text(confirmEmailNotice), findsOneWidget);
    });
  });
}
