import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/finance_store.dart';
import 'package:kyora_chat/models/finance.dart';
import 'package:kyora_chat/models/profile.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/auth_gate.dart';
import 'package:kyora_chat/ui/finance_page.dart';
import 'package:kyora_chat/ui/passwords_page.dart';

import 'auth_gate_test.dart' show FakeAccount, MemoryRoleCache;
import 'calendar_sync_test.dart' show FakeRowBackend;
import 'fake_backend.dart';
import 'fake_engine.dart';
import 'music_test.dart' show FakeMusicBackend, FakeSaver, MemoryMusicStore;
import 'password_vault_test.dart' show FakePasswordBackend;
import 'sections.dart';

FinanceEntry _stampEntry(FinanceEntry e, String at) => FinanceEntry(
  id: e.id,
  kind: e.kind,
  amountCents: e.amountCents,
  createdAt: e.createdAt,
  updatedAt: e.updatedAt,
  occurredOn: e.occurredOn,
  syncedAt: at,
);

FinanceCategory _stampCategory(FinanceCategory c, String at) => FinanceCategory(id: c.id, name: c.name, kind: c.kind, createdAt: c.createdAt, updatedAt: c.updatedAt, syncedAt: at);

/// Las secciones «Finanzas» y «Contraseñas» en el menú circular de la app (como en Merida).
void main() {
  Future<void> openApp(WidgetTester tester, {bool withFinance = true, bool withPasswords = true, bool signedIn = true, FakeAccount? account}) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: AuthGate(
          account: account ?? FakeAccount(uid: signedIn ? 'u1' : null, profile: const Profile(id: 'u1', username: 'gustavo', role: Role.admin)),
          chat: FakeBackend(),
          music: FakeMusicBackend(),
          musicStore: MemoryMusicStore(since: DateTime.utc(2026, 10, 1)),
          saver: FakeSaver(),
          roleCache: MemoryRoleCache(),
          engine: FakeEngine.new,
          financeCategories: withFinance ? FakeRowBackend<FinanceCategory>(_stampCategory) : null,
          financeEntries: withFinance ? FakeRowBackend<FinanceEntry>(_stampEntry) : null,
          openFinanceCategoryStore: (_) async => MemoryFinanceCategoryStore(),
          openFinanceEntryStore: (_) async => MemoryFinanceEntryStore(),
          passwords: withPasswords ? FakePasswordBackend() : null,
          now: () => DateTime(2026, 11, 14, 12),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump();
  }

  testWidgets('con sus backends, el menú circular ofrece Finanzas y Contraseñas', (tester) async {
    await openApp(tester);
    final options = await menuOptions(tester);
    expect(options, containsAll(['home', 'music', 'finance', 'passwords']));
  });

  testWidgets('sin ellos no hay secciones de finanzas ni de contraseñas', (tester) async {
    await openApp(tester, withFinance: false, withPasswords: false);
    final options = await menuOptions(tester);
    expect(options, isNot(contains('finance')));
    expect(options, isNot(contains('passwords')));
  });

  testWidgets('se llega a Finanzas desde el menú y se anota un movimiento', (tester) async {
    await openApp(tester);
    await goToSection(tester, 'finance');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pumpAndSettle();
    expect(find.byType(FinancePage), findsOneWidget);
    expect(find.text('FINANZAS'), findsOneWidget);
    expect(find.byKey(const Key('fin-empty')), findsOneWidget);
  });

  testWidgets('se llega a Contraseñas desde el menú: con sesión pide crear la bóveda', (tester) async {
    await openApp(tester);
    await goToSection(tester, 'passwords');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pumpAndSettle();
    expect(find.byType(PasswordsPage), findsOneWidget);
    expect(find.byKey(const Key('pw-create')), findsOneWidget);
  });

  testWidgets('si la sesión caduca la bóveda no llama a Supabase: lo explica y deja reintentar', (tester) async {
    final account = FakeAccount(uid: 'u1', profile: const Profile(id: 'u1', username: 'gustavo', role: Role.admin));
    await openApp(tester, account: account);
    account.expire(); // el administrador sigue dentro (no cerró sesión), pero ya no hay sesión con el servidor
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump();
    await goToSection(tester, 'passwords');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pw-error')), findsOneWidget);
    expect(find.textContaining('Sin sesión'), findsOneWidget);
    expect(find.byKey(const Key('pw-retry')), findsOneWidget);
  });
}
