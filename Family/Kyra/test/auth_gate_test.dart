import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/app_flavor.dart';
import 'package:kyora_chat/data/account_backend.dart';
import 'package:kyora_chat/data/chat_backend.dart';
import 'package:kyora_chat/data/contacts_source.dart';
import 'package:kyora_chat/data/dock_store.dart';
import 'package:kyora_chat/data/installed_apps.dart';
import 'package:kyora_chat/data/appearance_store.dart';
import 'package:kyora_chat/state/dock_controller.dart';
import 'package:kyora_chat/state/appearance_controller.dart';
import 'package:kyora_chat/ui/neo/neo_themes.dart';
import 'package:kyora_chat/ui/widgets/section_motion.dart' show HologramReveal;
import 'package:kyora_chat/ui/neo/neo_settings_page.dart';
import 'package:kyora_chat/ui/neo/neo_theme.dart';
import 'package:kyora_chat/data/vault_source.dart';
import 'package:kyora_chat/state/contacts_controller.dart';
import 'package:kyora_chat/state/vault_controller.dart';
import 'package:kyora_chat/models/profile.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/auth_gate.dart';
import 'package:kyora_chat/ui/guest_shell.dart';
import 'package:kyora_chat/ui/section_host.dart';
import 'package:kyora_chat/ui/login_page.dart';

import 'fake_backend.dart';
import 'fake_direct.dart';
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
  ChatException? signInError;
  ChatException? claimError;
  int profileCalls = 0;

  /// Lo que se escribió para entrar (nombre o correo, contraseña) y los códigos que se canjearon.
  final List<(String, String)> signIns = [];
  final List<String> claims = [];
  final _changes = StreamController<void>.broadcast();

  @override
  bool get signedIn => _uid != null;

  @override
  String? get userId => _uid;

  @override
  Stream<void> get authChanges => _changes.stream;

  @override
  Future<void> signIn(String identifier, String password) async {
    final error = signInError;
    if (error != null) throw error;
    signIns.add((identifier, password));
    _uid = profile?.id ?? 'user-1';
    _changes.add(null);
  }

  @override
  Future<void> claimAccount(String code) async {
    final error = claimError;
    if (error != null) throw error;
    claims.add(code);
    final p = profile;
    if (p != null) profile = Profile(id: p.id, username: p.username, role: p.role, verified: true);
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

/// Desplaza la lista de Ajustes del visitante hasta que se vea ese widget (la lista construye solo lo que está cerca).
Future<void> showInSettings(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(find.byKey(key), 120, scrollable: find.descendant(of: find.byType(NeoSettingsPage), matching: find.byType(Scrollable)).first);
  await tester.pumpAndSettle();
}

/// Toca una pestaña de la barra de abajo del modo visitante (`music`, `chat` o `settings`).
Future<void> tapNav(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(Key('nav-$id')));
  await tester.pumpAndSettle();
}

void main() {
  late FakeBackend chat;
  late FakeMusicBackend music;
  late MemoryRoleCache cache;
  late MemoryRememberedAccount remembered;
  late FakeDirectBackend direct;

  setUp(() {
    chat = FakeBackend();
    music = FakeMusicBackend();
    cache = MemoryRoleCache();
    remembered = MemoryRememberedAccount();
    direct = FakeDirectBackend();
  });

  Future<void> openGate(WidgetTester tester, FakeAccount account, {ContactsController? contacts, VaultController? vault, bool withFamily = true, DockController? dock, AppearanceController? appearance, AppFlavor? flavor}) async {
    // la cinta del modo visitante se queda quieta con «menos animaciones» (si no, nunca se asienta la pantalla)
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
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
        direct: withFamily ? direct : null,
        remembered: remembered,
        dock: dock,
        appearance: appearance,
        flavor: flavor,
      ),
    ));
    await settle(tester);
  }

  const admin = Profile(id: 'user-1', username: 'gustavo', role: Role.admin);
  const ana = Profile(id: 'user-1', username: 'ana', role: Role.intern);

  group('al instalar: modo visitante', () {
    testWidgets('sin sesión solo hay Música y Chat, con la barra de navegación abajo (y Ajustes)', (tester) async {
      await openGate(tester, FakeAccount());
      expect(find.byType(GuestShell), findsOneWidget);
      expect(find.byType(SectionHost), findsNothing); // nada del launcher
      expect(find.byKey(const Key('home-time')), findsNothing);
      for (final id in ['music', 'chat', 'settings']) {
        expect(find.byKey(Key('nav-$id')), findsOneWidget, reason: id);
      }
      expect(find.byKey(const Key('neo-album-received')), findsOneWidget); // empieza en Música
      expect(chat.calls, isEmpty);
      expect(music.listCalls, 0); // la música de la PC tampoco se pide sin sesión
      expect(find.byType(LoginPage), findsNothing);
    });

    testWidgets('la última cuenta era administradora pero sin sesión: también modo visitante', (tester) async {
      cache
        ..roles['user-1'] = Role.admin
        ..last = 'user-1';
      await openGate(tester, FakeAccount());
      expect(find.byType(GuestShell), findsOneWidget);
      expect(find.byKey(const Key('home-time')), findsNothing);
    });

    testWidgets('el chat sin sesión está bloqueado y lleva a Ajustes', (tester) async {
      await openGate(tester, FakeAccount());
      await tapNav(tester, 'chat');
      expect(find.byKey(const Key('neo-chat-locked')), findsOneWidget);
      expect(direct.calls, isEmpty);
      await tester.tap(find.byKey(const Key('neo-chat-go-settings')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('neo-name')), findsOneWidget); // ya en Ajustes, con el acceso
    });

    testWidgets('en Ajustes el administrador entra con su cuenta y aparece todo; ya no hay modo visitante', (tester) async {
      final account = FakeAccount(profile: admin);
      await openGate(tester, account);
      await tapNav(tester, 'settings');
      await showInSettings(tester, const Key('neo-admin-login'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('neo-admin-login')));
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      await account.signIn('yo@correo.com', 'secreta1');
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsNothing); // se cerró sola
      expect(find.byType(GuestShell), findsNothing);
      expect(find.byKey(const Key('home-time')), findsOneWidget); // el launcher completo
      expect(await menuOptions(tester), containsAll(['home', 'nube', 'music', 'settings']));
      expect(cache.roles['user-1'], Role.admin);
    });

    testWidgets('un administrador que aún no canjeó su código NO ve todo: sigue en modo visitante', (tester) async {
      final account = FakeAccount(uid: 'user-1', profile: const Profile(id: 'user-1', username: 'gustavo', role: Role.admin, verified: false));
      await openGate(tester, account);
      expect(find.byType(GuestShell), findsOneWidget);
      expect(find.byKey(const Key('home-time')), findsNothing);
    });
  });

  group('puerta por rol', () {
    testWidgets('si la sesión del administrador caduca sola nada se cierra: sigue en Inicio y Configuración lo avisa', (tester) async {
      final account = FakeAccount(uid: 'user-1', profile: admin);
      await openGate(tester, account);
      expect(find.byKey(const Key('home-time')), findsOneWidget);
      account.expire();
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsNothing);
      expect(find.byType(GuestShell), findsNothing);
      expect(find.byKey(const Key('home-time')), findsOneWidget);
      await goToSection(tester, 'settings');
      await tester.pumpAndSettle();
      expect(find.text('SESIÓN CADUCADA'), findsOneWidget);
    });

    testWidgets('el administrador entra a Inicio, y tiene inicio, nube (con el chat) y música para deslizar', (tester) async {
      final account = FakeAccount(uid: 'user-1', profile: admin);
      await openGate(tester, account);
      expect(await menuOptions(tester), containsAll(['home', 'nube', 'music', 'chats', 'settings'])); // en la barra (y Configuración es una opción más); «Chats» es el chat privado
      expect(find.byKey(const Key('home-time')), findsOneWidget); // empieza en Inicio
      expect(find.byKey(const Key('chat-terminal')), findsNothing);
      await goToSection(tester, 'nube');
      expect(find.byKey(const Key('chat-terminal')), findsOneWidget); // el chat, como terminal (sin Vault ni Supabase de archivos, es la única pestaña)
      final nubeSection = tester.widget<SectionHost>(find.byType(SectionHost)).sections.firstWhere((s) => s.id == 'nube');
      expect(nubeSection.icon, Icons.cloud_outlined); // con el icono de una nube
      expect(chat.calls, contains('ensure'));
      expect(cache.roles['user-1'], Role.admin);
    });

    testWidgets('un visitante con sesión sigue en modo visitante: sin Inicio, sin Contactos ni Vault, y no toca el chat del administrador', (tester) async {
      final contacts = ContactsController(FakeContactsSource([const Contact(id: '1', name: 'Ana', phones: ['123'])]));
      final vault = VaultController(FakeVaultSource(), MemoryVaultStore());
      addTearDown(contacts.dispose);
      addTearDown(vault.dispose);
      final account = FakeAccount(uid: 'user-1', profile: ana);
      await openGate(tester, account, contacts: contacts, vault: vault);
      expect(find.byType(GuestShell), findsOneWidget);
      expect(find.byKey(const Key('home-time')), findsNothing);
      expect(find.text('CONTACTOS'), findsNothing);
      expect(chat.calls, isEmpty); // ni conversación, ni mensajes, ni Realtime del chat del PC
      expect(cache.roles['user-1'], Role.intern);
    });

    testWidgets('una cuenta sin perfil se trata como visitante (la vista con menos permisos)', (tester) async {
      await openGate(tester, FakeAccount(uid: 'user-3'));
      expect(find.byType(GuestShell), findsOneWidget);
      expect(chat.calls, isEmpty);
    });

    testWidgets('sin internet usa el rol de la última vez', (tester) async {
      cache.roles['user-1'] = Role.admin;
      final account = FakeAccount(uid: 'user-1')..profileError = const ChatException('Sin conexión con Supabase', retryable: true, code: 'offline');
      await openGate(tester, account);
      expect(find.byType(GuestShell), findsNothing);
      expect(await menuOptions(tester), contains('nube'));
    });

    testWidgets('sin internet y sin rol guardado lo dice y deja reintentar', (tester) async {
      final account = FakeAccount(uid: 'user-1')..profileError = const ChatException('Sin conexión con Supabase', retryable: true, code: 'offline');
      await openGate(tester, account);
      expect(find.byKey(const Key('role-error')), findsOneWidget);
      expect(find.text('Sin conexión con Supabase'), findsOneWidget);
      account
        ..profileError = null
        ..profile = admin;
      await tester.tap(find.byKey(const Key('role-retry')));
      await tester.pump();
      await settle(tester);
      await tester.pump();
      expect(find.byKey(const Key('role-error')), findsNothing);
      expect(await menuOptions(tester), contains('nube'));
    });

    testWidgets('el rol guardado de otra cuenta no se usa', (tester) async {
      cache.roles['otro'] = Role.admin;
      final account = FakeAccount(uid: 'user-2')..profileError = const ChatException('Sin conexión con Supabase', retryable: true, code: 'offline');
      await openGate(tester, account);
      expect(find.byKey(const Key('role-error')), findsOneWidget);
    });

    testWidgets('cuando el administrador cierra sesión la app vuelve al modo visitante (Música y Chat)', (tester) async {
      final account = FakeAccount(uid: 'user-1', profile: admin);
      await openGate(tester, account);
      await goToSection(tester, 'settings');
      await tester.pumpAndSettle();
      await revealSignOut(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-sign-out')));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsNothing);
      expect(find.byType(GuestShell), findsOneWidget);
      expect(find.byKey(const Key('home-time')), findsNothing);
      expect(find.byKey(const Key('nav-chat')), findsOneWidget);
    });
  });

  group('Kyra solo es launcher para el administrador', () {
    late FakeInstalledApps apps;
    late DockController dock;

    setUp(() {
      apps = FakeInstalledApps(const []);
      dock = DockController(MemoryDockStore(), apps);
    });

    testWidgets('un visitante (o sin sesión) deja el launcher apagado: Kyra es una app normal', (tester) async {
      await openGate(tester, FakeAccount(), dock: dock);
      expect(find.byType(GuestShell), findsOneWidget);
      expect(apps.launcherEnabledCalls, [false]);
      expect(apps.launcherEnabled, isFalse);
    });

    testWidgets('el administrador enciende el launcher', (tester) async {
      await openGate(tester, FakeAccount(uid: 'user-1', profile: admin), dock: dock);
      expect(find.byKey(const Key('home-time')), findsOneWidget);
      expect(apps.launcherEnabledCalls, [true]);
      expect(apps.launcherEnabled, isTrue);
    });

    testWidgets('si el administrador cierra sesión, el launcher se apaga (y Kyra deja de ser la pantalla de inicio)', (tester) async {
      apps.launcher = true;
      final account = FakeAccount(uid: 'user-1', profile: admin);
      await openGate(tester, account, dock: dock);
      expect(apps.launcherEnabledCalls, [true]);
      await goToSection(tester, 'settings');
      await tester.pumpAndSettle();
      await revealSignOut(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-sign-out')));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.byType(GuestShell), findsOneWidget);
      expect(apps.launcherEnabledCalls, [true, false]);
      expect(dock.isLauncher, isFalse);
    });
  });

  group('KyraFamily: apariencia (10 temas y modo oscuro)', () {
    late MemoryAppearanceStore store;
    late AppearanceController appearance;

    setUp(() {
      store = MemoryAppearanceStore();
      appearance = AppearanceController(store);
    });

    NeoScheme schemeOf(WidgetTester tester) => Theme.of(tester.element(find.byKey(const Key('nav-music')))).extension<NeoScheme>()!;

    testWidgets('sin elegir nada: el tema de siempre en claro; ya no se elige imagen de fondo', (tester) async {
      await openGate(tester, FakeAccount(), appearance: appearance);
      expect(schemeOf(tester), NeoScheme.standard);
      await tapNav(tester, 'settings');
      await showInSettings(tester, const Key('neo-dark-toggle'));
      expect(find.byKey(const Key('neo-colors-choose')), findsNothing);
      for (final t in NeoThemes.all) {
        expect(find.byKey(Key('neo-theme-${t.id}')), findsOneWidget, reason: t.id);
      }
    });

    testWidgets('elegir un tema y el modo oscuro cambia los colores de toda la app y se recuerda', (tester) async {
      await openGate(tester, FakeAccount(), appearance: appearance);
      await tapNav(tester, 'settings');
      await showInSettings(tester, const Key('neo-theme-sakura'));
      await tester.tap(find.byKey(const Key('neo-theme-sakura')));
      await tester.pumpAndSettle();
      expect(schemeOf(tester), NeoScheme.of(NeoThemes.byId('sakura')));
      expect(store.value.themeId, 'sakura');
      await showInSettings(tester, const Key('neo-dark-toggle'));
      await tester.tap(find.byKey(const Key('neo-dark-toggle')));
      await tester.pumpAndSettle();
      final dark = schemeOf(tester);
      expect(dark.dark, isTrue);
      expect(dark, NeoScheme.of(NeoThemes.byId('sakura'), dark: true));
      expect(tester.widget<ColoredBox>(find.byKey(const Key('neo-background'))).color, dark.bg);
      expect(store.value.dark, isTrue);
      // al volver a abrir la app se recuerda
      expect(AppearanceController(store).scheme, dark);
    });
  });

  group('los temas siempre se leen bien', () {
    test('hay 10, de los cuatro estilos, con ids distintos', () {
      expect(NeoThemes.all, hasLength(10));
      expect(NeoThemes.all.map((t) => t.id).toSet(), hasLength(10));
      expect(NeoThemes.all.map((t) => t.group).toSet(), NeoThemeGroup.values.toSet());
      expect(NeoThemes.byId('no-existe'), NeoThemes.standard);
    });

    test('en claro y en oscuro: el acento se lee sobre el fondo, y el texto sobre el acento y sobre el pop', () {
      for (final t in NeoThemes.all) {
        for (final dark in [false, true]) {
          final s = NeoScheme.of(t, dark: dark);
          final where = '${t.id} ${dark ? 'oscuro' : 'claro'}';
          expect(contrastRatio(s.ink, s.bg), greaterThanOrEqualTo(12), reason: 'texto $where');
          expect(contrastRatio(s.accent, s.bg), greaterThanOrEqualTo(4.5), reason: 'acento $where');
          expect(contrastRatio(s.accentDeep, s.bg), greaterThanOrEqualTo(7), reason: 'acento hondo $where');
          expect(contrastRatio(s.onAccent, s.accent), greaterThanOrEqualTo(4.5), reason: 'sobre el acento $where');
          expect(contrastRatio(s.onPop, s.pop), greaterThanOrEqualTo(4.5), reason: 'sobre el pop $where');
        }
      }
    });
  });

  group('KyraAdmin: solo cuentas de administrador', () {
    Future<void> signInWith(WidgetTester tester, String email) async {
      await tester.enterText(find.byKey(const Key('email')), email);
      await tester.enterText(find.byKey(const Key('password')), 'secreta1');
      await tester.tap(find.byKey(const Key('login-button')));
      await settle(tester);
      await tester.pumpAndSettle();
    }

    testWidgets('sin sesión pide el acceso: no hay modo visitante ni nada de la app', (tester) async {
      await openGate(tester, FakeAccount(), flavor: AppFlavor.admin);
      expect(find.byKey(const ValueKey('admin-login')), findsOneWidget);
      expect(find.byType(GuestShell), findsNothing);
      expect(find.byKey(const Key('home-time')), findsNothing);
    });

    testWidgets('un administrador entra y tiene toda la app', (tester) async {
      final account = FakeAccount(profile: admin);
      await openGate(tester, account, flavor: AppFlavor.admin);
      await signInWith(tester, 'yo@correo.com');
      expect(account.signedIn, isTrue);
      expect(find.byKey(const Key('home-time')), findsOneWidget);
      expect(await menuOptions(tester), containsAll(['home', 'nube', 'music', 'settings']));
    });

    testWidgets('una cuenta que no es de administrador NO entra: se cierra su sesión y se dice por qué', (tester) async {
      final account = FakeAccount(profile: ana);
      await openGate(tester, account, flavor: AppFlavor.admin);
      await signInWith(tester, 'ana');
      expect(account.signedIn, isFalse);
      expect(find.byKey(const ValueKey('admin-login')), findsOneWidget);
      expect(find.byKey(const Key('home-time')), findsNothing);
      expect(find.byKey(const Key('login-notice')), findsOneWidget);
      expect(find.textContaining('solo para cuentas de administrador'), findsOneWidget);
    });

    testWidgets('una sesión de visitante que ya estaba abierta (versión anterior) tampoco pasa', (tester) async {
      final account = FakeAccount(uid: 'user-1', profile: ana);
      await openGate(tester, account, flavor: AppFlavor.admin);
      await tester.pumpAndSettle();
      expect(account.signedIn, isFalse);
      expect(find.byKey(const ValueKey('admin-login')), findsOneWidget);
      expect(find.byKey(const Key('login-notice')), findsOneWidget);
    });

    testWidgets('un administrador sin verificar no pasa', (tester) async {
      final account = FakeAccount(uid: 'user-1', profile: const Profile(id: 'user-1', username: 'gustavo', role: Role.admin, verified: false));
      await openGate(tester, account, flavor: AppFlavor.admin);
      await tester.pumpAndSettle();
      expect(account.signedIn, isFalse);
      expect(find.textContaining('no está verificada'), findsOneWidget);
    });

    testWidgets('al cerrar sesión vuelve al acceso', (tester) async {
      final account = FakeAccount(uid: 'user-1', profile: admin);
      await openGate(tester, account, flavor: AppFlavor.admin);
      expect(find.byKey(const Key('home-time')), findsOneWidget);
      await goToSection(tester, 'settings');
      await tester.pumpAndSettle();
      await revealSignOut(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-sign-out')));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('admin-login')), findsOneWidget);
    });
  });

  group('KyraFamily: sin cuentas de administrador', () {
    Future<void> signInFamily(WidgetTester tester, String name) async {
      await tapNav(tester, 'settings');
      await tester.enterText(find.byKey(const Key('neo-name')), name);
      await tester.enterText(find.byKey(const Key('neo-password')), 'secreta1');
      await tester.tap(find.byKey(const Key('neo-sign-in')));
      await settle(tester);
      await tester.pumpAndSettle();
    }

    testWidgets('solo el modo visitante y sin acceso de administrador en Ajustes', (tester) async {
      await openGate(tester, FakeAccount(), flavor: AppFlavor.family);
      expect(find.byType(GuestShell), findsOneWidget);
      await tapNav(tester, 'settings');
      expect(find.byKey(const Key('neo-admin-login')), findsNothing);
      expect(find.text('ADMINISTRADOR'), findsNothing);
    });

    testWidgets('un miembro de la familia entra con normalidad', (tester) async {
      final account = FakeAccount(profile: ana);
      await openGate(tester, account, flavor: AppFlavor.family);
      await signInFamily(tester, 'ana');
      expect(account.signedIn, isTrue);
      expect(find.byKey(const Key('neo-username')), findsOneWidget);
      expect(find.byKey(const Key('neo-access-notice')), findsNothing);
    });

    testWidgets('una cuenta de administrador NO entra: se cierra su sesión y Ajustes dice por qué', (tester) async {
      final account = FakeAccount(profile: admin);
      await openGate(tester, account, flavor: AppFlavor.family);
      await signInFamily(tester, 'gustavo');
      expect(account.signedIn, isFalse);
      expect(find.byType(GuestShell), findsOneWidget);
      expect(find.byKey(const Key('home-time')), findsNothing);
      expect(find.byKey(const Key('neo-access-notice')), findsOneWidget);
      expect(find.textContaining('Usa KyraAdmin'), findsOneWidget);
      expect(find.byKey(const Key('neo-name')), findsOneWidget); // y puede volver a intentar con otra cuenta
      expect(direct.calls, isEmpty); // el chat de la familia no llegó a abrirse
      expect(await remembered.read(), isNull);
    });

    testWidgets('una sesión de administrador que ya estaba abierta tampoco pasa', (tester) async {
      final account = FakeAccount(uid: 'user-1', profile: admin);
      await openGate(tester, account, flavor: AppFlavor.family);
      await tester.pumpAndSettle();
      expect(account.signedIn, isFalse);
      expect(find.byType(GuestShell), findsOneWidget);
      expect(find.byKey(const Key('home-time')), findsNothing);
      expect(direct.calls, isEmpty);
    });
  });

  group('KyraFamily: barra inferior y deslizar entre pantallas', () {
    Future<void> swipe(WidgetTester tester, double dx) async {
      await tester.dragFrom(const Offset(400, 110), Offset(dx, 0)); // sobre la cabecera (un campo de texto se queda con el gesto)
    }

    testWidgets('la barra tiene las tres pantallas, del mismo tamaño; en la elegida solo crece el icono y cambia de color', (tester) async {
      await openGate(tester, FakeAccount(), flavor: AppFlavor.family);
      final music = tester.getSize(find.byKey(const Key('nav-music')));
      final chat = tester.getSize(find.byKey(const Key('nav-chat')));
      expect(music, chat); // las celdas no cambian de tamaño
      double scale(String id) => tester.widget<AnimatedScale>(find.byKey(Key('nav-icon-$id'))).scale;
      Color? color(String id) => tester.widget<Icon>(find.descendant(of: find.byKey(Key('nav-icon-$id')), matching: find.byType(Icon)).first).color;
      expect(scale('music'), greaterThan(scale('chat')));
      final s = NeoScheme.standard;
      expect(color('music'), s.accent);
      expect(color('chat'), s.dim);
      await tapNav(tester, 'chat');
      expect(tester.getSize(find.byKey(const Key('nav-music'))), music); // sigue igual
      expect(scale('chat'), greaterThan(scale('music')));
      expect(color('chat'), s.accent);
      // ni la celda elegida lleva fondo propio
      expect(find.descendant(of: find.byKey(const Key('nav-chat')), matching: find.byWidgetPredicate((w) => w is Container && w.decoration != null)), findsNothing);
    });

    testWidgets('deslizar a la izquierda va a la pantalla siguiente y a la derecha a la anterior', (tester) async {
      await openGate(tester, FakeAccount(), flavor: AppFlavor.family);
      expect(find.byKey(const Key('neo-album-received')), findsOneWidget);
      await swipe(tester, -150);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('neo-chat-locked')), findsOneWidget);
      expect(find.byKey(const Key('neo-album-received')), findsNothing);
      await swipe(tester, -150);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('neo-name')), findsOneWidget); // Ajustes
      await swipe(tester, -150); // no hay más a la derecha: se queda
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('neo-name')), findsOneWidget);
      await swipe(tester, 150);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('neo-chat-locked')), findsOneWidget);
      await swipe(tester, 150);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('neo-album-received')), findsOneWidget);
    });

    testWidgets('un roce corto no cambia de pantalla', (tester) async {
      await openGate(tester, FakeAccount(), flavor: AppFlavor.family);
      await swipe(tester, -30);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('neo-album-received')), findsOneWidget);
    });

    testWidgets('el cambio es un desplazamiento borroso: durante él se ven las dos pantallas desenfocadas, y al terminar solo la nueva y nítida', (tester) async {
      // sin «menos animaciones»: el efecto corre de verdad
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: AuthGate(
          account: FakeAccount(),
          chat: chat,
          music: music,
          musicStore: MemoryMusicStore(since: DateTime.utc(2026, 10, 1)),
          saver: FakeSaver(),
          roleCache: cache,
          engine: FakeEngine.new,
          direct: direct,
          remembered: remembered,
          flavor: AppFlavor.family,
        ),
      ));
      await settle(tester);
      bool blurred() => tester.widgetList<ImageFiltered>(find.byType(ImageFiltered, skipOffstage: false)).any((f) => f.enabled);
      expect(blurred(), isFalse);
      await tester.tap(find.byKey(const Key('nav-chat')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(find.byKey(const Key('neo-album-received')), findsOneWidget); // la que se va, corriendo hacia un lado
      expect(find.byKey(const Key('neo-chat-locked')), findsOneWidget); // la que llega
      expect(blurred(), isTrue);
      expect(find.byType(HologramReveal), findsNothing); // ya no hay holograma
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('neo-album-received')), findsNothing);
      expect(find.byKey(const Key('neo-chat-locked')), findsOneWidget);
      expect(blurred(), isFalse); // ya en su sitio: nítida
    });

    testWidgets('las pantallas siguen vivas al cambiar: lo escrito en Ajustes no se pierde', (tester) async {
      await openGate(tester, FakeAccount(), flavor: AppFlavor.family);
      await tapNav(tester, 'settings');
      await tester.enterText(find.byKey(const Key('neo-name')), 'ana');
      await tapNav(tester, 'chat');
      await tapNav(tester, 'settings');
      expect(find.text('ana'), findsOneWidget);
    });
  });

  group('el visitante entra con su nombre', () {
    Future<void> openSettingsTab(WidgetTester tester, FakeAccount account) async {
      await openGate(tester, account);
      await tapNav(tester, 'settings');
    }

    testWidgets('nombre y contraseña; queda recordado y la próxima vez solo pide la contraseña', (tester) async {
      final account = FakeAccount(profile: ana);
      await openSettingsTab(tester, account);
      expect(find.byKey(const Key('neo-name')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('neo-name')), 'Ana');
      await tester.enterText(find.byKey(const Key('neo-password')), 'secreta1');
      await tester.tap(find.byKey(const Key('neo-sign-in')));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(account.signIns, [('Ana', 'secreta1')]);
      expect(find.byKey(const Key('neo-username')), findsOneWidget); // la tarjeta de su cuenta
      expect(find.text('ANA'), findsOneWidget);
      expect(await remembered.read(), 'ana');
      expect(find.byType(GuestShell), findsOneWidget); // sigue en modo visitante

      // sale y vuelve: ahora solo la contraseña
      await showInSettings(tester, const Key('neo-sign-out'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('neo-sign-out')));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('neo-remembered')), findsOneWidget);
      expect(find.text('ANA'), findsOneWidget);
      expect(find.byKey(const Key('neo-name')), findsNothing);
      await tester.enterText(find.byKey(const Key('neo-password')), 'otra-clave');
      await tester.tap(find.byKey(const Key('neo-sign-in')));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(account.signIns.last, ('ana', 'otra-clave')); // la app supo quién era sin que lo escribiera
      expect(find.byKey(const Key('neo-username')), findsOneWidget);
    });

    testWidgets('«No soy yo» olvida el nombre y vuelve a pedirlo', (tester) async {
      remembered = MemoryRememberedAccount('ana');
      await openSettingsTab(tester, FakeAccount(profile: ana));
      expect(find.byKey(const Key('neo-remembered')), findsOneWidget);
      await showInSettings(tester, const Key('neo-forget'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('neo-forget')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('neo-name')), findsOneWidget);
      expect(await remembered.read(), isNull);
    });

    testWidgets('si se equivoca, el error sale en español y no entra', (tester) async {
      final account = FakeAccount(profile: ana)..signInError = const ChatException('Usuario o contraseña incorrectos.', code: 'invalid_credentials');
      await openSettingsTab(tester, account);
      await tester.enterText(find.byKey(const Key('neo-name')), 'ana');
      await tester.enterText(find.byKey(const Key('neo-password')), 'mal');
      await tester.tap(find.byKey(const Key('neo-sign-in')));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.text('Usuario o contraseña incorrectos.'), findsOneWidget);
      expect(account.signedIn, isFalse);
      expect(await remembered.read(), isNull);
    });

    testWidgets('pide el nombre y la contraseña antes de llamar a Supabase', (tester) async {
      final account = FakeAccount(profile: ana);
      await openSettingsTab(tester, account);
      await tester.tap(find.byKey(const Key('neo-sign-in')));
      await tester.pumpAndSettle();
      expect(find.text('Escribe tu nombre y tu contraseña.'), findsOneWidget);
      expect(account.signIns, isEmpty);
    });

    testWidgets('una cuenta nueva pide su código de 6 dígitos; al canjearlo se activa y se recuerda', (tester) async {
      final account = FakeAccount(profile: const Profile(id: 'user-1', username: 'ana', role: Role.intern, verified: false));
      await openSettingsTab(tester, account);
      await tester.enterText(find.byKey(const Key('neo-name')), 'ana');
      await tester.enterText(find.byKey(const Key('neo-password')), 'secreta1');
      await tester.tap(find.byKey(const Key('neo-sign-in')));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('neo-code')), findsOneWidget); // falta verificar
      expect(await remembered.read(), isNull); // aún no se recuerda

      // el chat avisa que falta verificar
      await tapNav(tester, 'chat');
      expect(find.byKey(const Key('neo-chat-locked')), findsOneWidget);
      expect(direct.calls, isEmpty);
      await tapNav(tester, 'settings');

      await tester.enterText(find.byKey(const Key('neo-code')), '12');
      await tester.tap(find.byKey(const Key('neo-verify')));
      await tester.pumpAndSettle();
      expect(find.text('El código tiene 6 dígitos.'), findsOneWidget);
      expect(account.claims, isEmpty);

      account.claimError = const ChatException('Ese código no es correcto.', code: 'code_invalid');
      await tester.enterText(find.byKey(const Key('neo-code')), '111111');
      await tester.tap(find.byKey(const Key('neo-verify')));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.text('Ese código no es correcto.'), findsOneWidget);

      account.claimError = null;
      await tester.enterText(find.byKey(const Key('neo-code')), '123456');
      await tester.tap(find.byKey(const Key('neo-verify')));
      await settle(tester);
      await settle(tester);
      await tester.pumpAndSettle();
      expect(account.claims, ['123456']);
      expect(find.byKey(const Key('neo-code')), findsNothing);
      expect(find.byKey(const Key('neo-username')), findsOneWidget); // ya es una cuenta normal
      expect(await remembered.read(), 'ana');
    });

    testWidgets('con la cuenta verificada el chat privado se abre: lista, conversación, escribir y borrar para mí', (tester) async {
      direct.receive('m1', body: 'bienvenida');
      final account = FakeAccount(uid: 'user-1', profile: ana);
      await openGate(tester, account);
      await tapNav(tester, 'chat');
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('neo-chat-locked')), findsNothing);
      expect(find.byKey(const Key('neo-thread-gustavo')), findsOneWidget); // la conversación con quien escribió
      expect(find.byKey(const Key('neo-unread-gustavo')), findsOneWidget);
      await tester.tap(find.byKey(const Key('neo-thread-gustavo')));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.text('bienvenida'), findsOneWidget);
      expect(direct.calls, contains(startsWith('read:'))); // al verla se da por leída
      await tester.enterText(find.byKey(const Key('neo-composer')), 'hola gustavo');
      await tester.tap(find.byKey(const Key('neo-send')));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(direct.sent, ['hola gustavo']);
      expect(find.text('hola gustavo'), findsOneWidget);
      // borrar para mí: deja de verse, pero en el servidor sigue
      await tester.longPress(find.byKey(const Key('neo-msg-m1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('neo-msg-hide')));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.text('bienvenida'), findsNothing);
      expect(direct.server.map((m) => m.id), contains('m1'));
    });

    testWidgets('«Nuevo chat» enseña a todas las cuentas (menos la propia) y abre la conversación con la elegida', (tester) async {
      final account = FakeAccount(uid: 'user-1', profile: ana);
      await openGate(tester, account);
      await tapNav(tester, 'chat');
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('neo-chat-empty')), findsOneWidget);
      await tester.tap(find.byKey(const Key('neo-new-chat')));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('neo-person-gustavo')), findsOneWidget);
      expect(find.byKey(const Key('neo-person-luis')), findsOneWidget);
      expect(find.byKey(const Key('neo-person-ana')), findsNothing);
      await tester.tap(find.byKey(const Key('neo-person-luis')));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('neo-thread-title')), findsOneWidget);
      expect(find.text('LUIS'), findsOneWidget);
      await tester.tap(find.byKey(const Key('neo-thread-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('neo-new-chat')), findsOneWidget);
    });

    testWidgets('«vaciar chat» lo deja vacío solo para mí', (tester) async {
      direct.receive('m1', body: 'uno');
      direct.receive('m2', body: 'dos');
      await openGate(tester, FakeAccount(uid: 'user-1', profile: ana));
      await tapNav(tester, 'chat');
      await settle(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('neo-thread-gustavo')));
      await settle(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('neo-thread-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('neo-thread-clear')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('neo-thread-clear-confirm')));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.text('uno'), findsNothing);
      expect(find.text('dos'), findsNothing);
      expect(find.byKey(const Key('neo-thread-empty')), findsOneWidget);
      expect(direct.server, hasLength(2)); // la base de datos no cambia
    });

    testWidgets('no hay manera de crear una cuenta desde la app', (tester) async {
      await openSettingsTab(tester, FakeAccount());
      expect(find.byKey(const Key('create-account')), findsNothing);
      expect(find.textContaining('crea el administrador'), findsOneWidget);
    });
  });
}
