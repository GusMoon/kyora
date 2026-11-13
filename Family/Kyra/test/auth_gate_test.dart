import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/account_backend.dart';
import 'package:kyora_chat/data/chat_backend.dart';
import 'package:kyora_chat/data/contacts_source.dart';
import 'package:kyora_chat/data/vault_source.dart';
import 'package:kyora_chat/state/contacts_controller.dart';
import 'package:kyora_chat/state/vault_controller.dart';
import 'package:kyora_chat/models/profile.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/auth_gate.dart';
import 'package:kyora_chat/ui/section_host.dart';
import 'package:kyora_chat/ui/widgets/pixel_glyph.dart';
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

  /// La última cuenta que entró (como la guarda el teléfono).
  String? last;

  @override
  Future<Role?> read(String userId) async => roles[userId];

  @override
  Future<void> write(String userId, Role role) async {
    roles[userId] = role;
    last = userId;
  }

  @override
  Future<({String userId, Role role})?> readLast() async {
    final id = last;
    final role = id == null ? null : roles[id];
    return id == null || role == null ? null : (userId: id, role: role);
  }
}

/// Cierra Configuración con la X: si hay una ficha abierta, la primera vez cierra la ficha y la segunda, la página.
Future<void> closeSettings(WidgetTester tester) async {
  for (var i = 0; i < 2 && find.byKey(const Key('settings-close')).evaluate().isNotEmpty; i++) {
    await tester.tap(find.byKey(const Key('settings-close')));
    await tester.pumpAndSettle();
  }
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

  Future<void> openGate(WidgetTester tester, FakeAccount account, {ContactsController? contacts, VaultController? vault}) async {
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
        contacts: contacts,
        vault: vault,
      ),
    ));
    await settle(tester);
  }

  group('puerta por rol', () {
    testWidgets('sin sesión la app abre igual (Inicio, música...) pero sin chat', (tester) async {
      cache
        ..roles['user-1'] = Role.admin
        ..last = 'user-1';
      await openGate(tester, FakeAccount());
      expect(find.byType(LoginPage), findsNothing);
      expect(find.byKey(const Key('home-time')), findsOneWidget);
      final options = await menuOptions(tester);
      expect(options, containsAll(['home', 'music', 'settings']));
      expect(options, isNot(contains('chat'))); // el chat vive en el servidor
      expect(chat.calls, isEmpty);
      expect(music.listCalls, 0); // la música de la PC tampoco se pide sin sesión
    });

    testWidgets('sin sesión y sin haber entrado nunca también abre (perfil local)', (tester) async {
      await openGate(tester, FakeAccount());
      expect(find.byKey(const Key('home-time')), findsOneWidget);
      expect(await menuOptions(tester), isNot(contains('chat')));
    });

    testWidgets('desde Configuración se abre el acceso; al entrar se cierra solo y aparece el chat', (tester) async {
      cache
        ..roles['user-1'] = Role.admin
        ..last = 'user-1';
      final account = FakeAccount(profile: const Profile(id: 'user-1', username: 'gustavo', role: Role.admin));
      await openGate(tester, account);
      await goToSection(tester, 'settings');
      await tester.pumpAndSettle();
      await openSettingsTile(tester, 'account');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-sign-out')), findsNothing);
      await tester.tap(find.byKey(const Key('settings-sign-in')));
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      await account.signIn('yo@correo.com', 'secreta1');
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsNothing); // se cerró sola
      expect(find.byKey(const Key('settings-sign-out')), findsOneWidget); // la ficha ya enseña que hay sesión
      await closeSettings(tester);
      expect(await menuOptions(tester), contains('chat'));
    });

    testWidgets('si la sesión caduca sola nada se cierra: sigue en Inicio y Configuración lo avisa', (tester) async {
      final account = FakeAccount(uid: 'user-1', profile: const Profile(id: 'user-1', username: 'gustavo', role: Role.admin));
      await openGate(tester, account);
      expect(find.byKey(const Key('home-time')), findsOneWidget);
      account.expire();
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsNothing);
      expect(find.byKey(const Key('home-time')), findsOneWidget);
      await goToSection(tester, 'settings');
      await tester.pumpAndSettle();
      expect(find.text('SESIÓN CADUCADA'), findsOneWidget);
    });

    testWidgets('el administrador entra a Inicio, y tiene inicio, chat y música para deslizar', (tester) async {
      final account = FakeAccount(uid: 'user-1', profile: const Profile(id: 'user-1', username: 'gustavo', role: Role.admin));
      await openGate(tester, account);
      expect(await menuOptions(tester), containsAll(['home', 'chat', 'music', 'settings'])); // en la barra (y Configuración es una opción más)
      expect(find.byKey(const Key('home-time')), findsOneWidget); // empieza en Inicio
      expect(find.byKey(const Key('chat-terminal')), findsNothing);
      await goToSection(tester, 'chat');
      expect(find.byKey(const Key('chat-terminal')), findsOneWidget); // el chat, como terminal
      final chatSection = tester.widget<SectionHost>(find.byType(SectionHost)).sections.firstWhere((s) => s.id == 'chat');
      expect(chatSection.icon, Icons.cloud_outlined); // con el icono de una nube
      expect(chat.calls, contains('ensure'));
      expect(cache.roles['user-1'], Role.admin);
    });

    testWidgets('el pasante entra a Inicio, la música está al lado y no toca el chat', (tester) async {
      final account = FakeAccount(uid: 'user-2', profile: const Profile(id: 'user-2', username: 'ana', role: Role.intern));
      await openGate(tester, account);
      expect(find.byKey(const Key('home-time')), findsOneWidget); // empieza en Inicio
      final options = await menuOptions(tester);
      expect(options, isNot(contains('chat'))); // sin chat
      expect(options, containsAll(['home', 'music']));
      await goToSection(tester, 'music');
      expect(find.byKey(const Key('album-deck')), findsOneWidget); // la pantalla de música
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Chat')), findsNothing);
      expect(chat.calls, isEmpty); // ni conversación, ni mensajes, ni Realtime del chat
    });

    testWidgets('con Contactos y Vault, salen en el menú (también para el pasante) y cada uno abre su pantalla', (tester) async {
      final contacts = ContactsController(FakeContactsSource([const Contact(id: '1', name: 'Ana', phones: ['123'])]));
      final vault = VaultController(FakeVaultSource(), MemoryVaultStore());
      addTearDown(contacts.dispose);
      addTearDown(vault.dispose);
      final account = FakeAccount(uid: 'user-2', profile: const Profile(id: 'user-2', username: 'ana', role: Role.intern));
      await openGate(tester, account, contacts: contacts, vault: vault);
      expect(await menuOptions(tester), containsAll(['home', 'music', 'contacts', 'vault']));
      await goToSection(tester, 'contacts');
      await tester.pumpAndSettle();
      expect(find.text('CONTACTOS'), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
      await goToSection(tester, 'vault');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vault-pick')), findsOneWidget);
    });

    testWidgets('sin Contactos ni Vault configurados no salen', (tester) async {
      final account = FakeAccount(uid: 'user-2', profile: const Profile(id: 'user-2', username: 'ana', role: Role.intern));
      await openGate(tester, account);
      final options = await menuOptions(tester);
      expect(options, isNot(contains('contacts')));
      expect(options, isNot(contains('vault')));
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

    testWidgets('cerrar sesión deja la app abierta, ya sin sesión, y ofrece entrar otra vez', (tester) async {
      final account = FakeAccount(uid: 'user-2', profile: const Profile(id: 'user-2', username: 'ana', role: Role.intern));
      await openGate(tester, account);
      await goToSection(tester, 'settings');
      await tester.pumpAndSettle();
      await revealSignOut(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-sign-out')));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsNothing);
      expect(find.byKey(const Key('home-time')), findsOneWidget);
      await goToSection(tester, 'settings');
      await tester.pumpAndSettle();
      await openSettingsTile(tester, 'account');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-sign-in')), findsOneWidget);
    });
  });

  group('crear cuenta', () {
    Future<void> openRegister(WidgetTester tester, FakeAccount account) async {
      await openGate(tester, account);
      await goToSection(tester, 'settings'); // el acceso se abre desde Configuración → cuenta
      await tester.pumpAndSettle();
      await openSettingsTile(tester, 'account');
      await tester.tap(find.byKey(const Key('settings-sign-in')));
      await tester.pumpAndSettle();
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

    testWidgets('la lista de requisitos de la contraseña se va marcando a medida que se cumplen', (tester) async {
      await openRegister(tester, FakeAccount());
      for (final id in ['length', 'letter', 'number', 'match']) {
        expect(find.byKey(Key('rule-$id-todo')), findsOneWidget, reason: id); // al empezar, todos pendientes
      }
      // solo hay tinta: lo cumplido se distingue por el icono (marcado) y no por el color
      IconData iconOf(String id, bool met) => tester.widget<LcdIcon>(find.byKey(Key('rule-$id-${met ? 'ok' : 'todo'}'))).icon;
      expect(iconOf('length', false), Icons.radio_button_unchecked);

      await tester.enterText(find.byKey(const Key('reg-password')), 'abc');
      await tester.pump();
      expect(find.byKey(const Key('rule-letter-ok')), findsOneWidget);
      expect(iconOf('letter', true), Icons.check_circle);
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
      expect(find.byType(LoginPage), findsNothing); // el acceso también se cerró solo
      await closeSettings(tester);
      expect(find.byKey(const Key('home-time')), findsOneWidget); // entra en Inicio
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
