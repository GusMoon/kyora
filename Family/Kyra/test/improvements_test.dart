import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/ui/widgets/flat_form.dart';
import 'package:kyora_chat/ui/widgets/cyber_panel.dart';
import 'package:kyora_chat/data/chat_backend.dart';
import 'package:kyora_chat/data/improvement_backend.dart';
import 'package:kyora_chat/models/improvement.dart';
import 'package:kyora_chat/models/profile.dart';
import 'package:kyora_chat/state/improvements_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/auth_gate.dart';
import 'package:kyora_chat/ui/improvements_page.dart';

import 'auth_gate_test.dart' show FakeAccount, MemoryRoleCache;
import 'fake_backend.dart';
import 'fake_engine.dart';
import 'music_test.dart' show FakeMusicBackend, FakeSaver, MemoryMusicStore;
import 'sections.dart';

/// La tabla `feature_requests` en memoria, como si fuera Supabase.
class FakeImprovementBackend implements ImprovementBackend {
  final Map<String, Improvement> rows = {};
  final List<String> deletes = [];
  ChatException? failList;
  ChatException? failAdd;
  ChatException? failFinish;
  Completer<void>? holdFinish;

  @override
  Future<List<Improvement>> list() async {
    if (failList != null) throw failList!;
    return rows.values.toList();
  }

  @override
  Future<void> add(Improvement item) async {
    if (failAdd != null) throw failAdd!;
    rows[item.id] = item;
  }

  @override
  Future<void> finish(String id) async {
    if (holdFinish != null) await holdFinish!.future;
    if (failFinish != null) throw failFinish!;
    deletes.add(id);
    rows.remove(id); // se borra de verdad
  }
}

const _offline = ChatException('Sin conexión con Supabase', retryable: true, code: 'offline');

Improvement _item(String id, String section, {String functions = '', String description = '', DateTime? at}) =>
    Improvement(id: id, section: section, functions: functions, description: description, createdAt: at ?? DateTime.utc(2026, 11, 14, 10));

void main() {
  group('el modelo', () {
    test('las funciones se leen una por línea, sin viñetas ni números', () {
      expect(Improvement.linesOf('- Vista de agenda\n* Arrastrar eventos\n• Colores\n1. Uno\n2) Dos\n\n   \nSin viñeta'), ['Vista de agenda', 'Arrastrar eventos', 'Colores', 'Uno', 'Dos', 'Sin viñeta']);
      expect(Improvement.linesOf(''), isEmpty);
      expect(_item('a', 'A', functions: 'x\r\ny').functionLines, ['x', 'y']);
    });

    test('pide la sección y al menos una función o una descripción (los mismos topes que Merida)', () {
      expect(Improvement.validate(section: '  '), contains('sección'));
      expect(Improvement.validate(section: 'Música'), contains('función o una descripción'));
      expect(Improvement.validate(section: 'Música', functions: 'Cola'), isNull);
      expect(Improvement.validate(section: 'Música', description: 'Más bonita'), isNull);
      expect(Improvement.validate(section: 'x' * 81, functions: 'a'), contains('80'));
      expect(Improvement.validate(section: 'Música', functions: 'a' * 4001), contains('4000'));
    });

    test('va y viene de Supabase con las mismas columnas que Merida', () {
      final i = _item('a', 'Calendario', functions: 'Vista', description: 'Más clara');
      expect(i.toJson(), {'id': 'a', 'section': 'Calendario', 'functions': 'Vista', 'description': 'Más clara', 'created_at': '2026-11-14T10:00:00.000Z'});
      final back = Improvement.fromJson({'id': 'a', 'section': 'Calendario', 'functions': null, 'description': 'x', 'created_at': '2026-11-14T10:00:00+00:00'});
      expect((back.functions, back.description, back.createdAt), ('', 'x', DateTime.utc(2026, 11, 14, 10)));
    });
  });

  group('el controlador', () {
    late FakeImprovementBackend backend;
    late ImprovementsController ctrl;
    var n = 0;
    var now = DateTime.utc(2026, 11, 14, 10);

    setUp(() {
      backend = FakeImprovementBackend();
      n = 0;
      now = DateTime.utc(2026, 11, 14, 10);
      ctrl = ImprovementsController(backend, now: () => now, newId: () => 'id${++n}');
    });

    tearDown(() => ctrl.dispose());

    test('lee las pendientes de la más nueva a la más antigua', () async {
      backend.rows['a'] = _item('a', 'Vieja', at: DateTime.utc(2026, 11, 1));
      backend.rows['b'] = _item('b', 'Nueva', at: DateTime.utc(2026, 11, 13));
      await ctrl.refresh();
      expect(ctrl.state, ImprovementsState.ready);
      expect(ctrl.items.map((i) => i.id), ['b', 'a']);
    });

    test('un fallo al leer se explica y se puede reintentar', () async {
      backend.failList = _offline;
      await ctrl.refresh();
      expect((ctrl.state, ctrl.error), (ImprovementsState.error, 'Sin conexión con Supabase'));
      backend.failList = null;
      await ctrl.refresh();
      expect(ctrl.state, ImprovementsState.ready);
      expect(ctrl.error, isNull);
    });

    test('anotar una mejora la guarda en Supabase y sale en la lista al instante', () async {
      await ctrl.refresh();
      final problem = await ctrl.add(section: '  Finanzas ', functions: ' Presupuestos ', description: ' Avisar ');
      expect(problem, isNull);
      expect(ctrl.items.single.section, 'Finanzas');
      expect(backend.rows['id1']!.functions, 'Presupuestos');
      expect(backend.rows['id1']!.description, 'Avisar');
    });

    test('lo escrito que no vale no se manda y se explica', () async {
      await ctrl.refresh();
      expect(await ctrl.add(section: ' '), contains('sección'));
      expect(await ctrl.add(section: 'Música'), contains('función o una descripción'));
      expect(ctrl.items, isEmpty);
      expect(backend.rows, isEmpty);
    });

    test('si Supabase no la acepta, se quita de la lista y se avisa', () async {
      await ctrl.refresh();
      backend.failAdd = _offline;
      await ctrl.add(section: 'Música', functions: 'Cola');
      expect(ctrl.items, isEmpty);
      expect(ctrl.notice, 'No se guardó la mejora. Sin conexión con Supabase');
    });

    test('«Hecho» la quita de la lista y la BORRA de la base de datos', () async {
      await ctrl.add(section: 'Música', functions: 'Cola');
      await ctrl.add(section: 'Chat', functions: 'Respuestas');
      final music = ctrl.items.firstWhere((i) => i.section == 'Música');
      await ctrl.finish(music);
      expect(ctrl.items.map((i) => i.section), ['Chat']);
      expect(backend.deletes, ['id1']);
      expect(backend.rows.keys, ['id2']); // ya no existe en la base de datos
      // otra lectura (otro dispositivo, o Merida) tampoco la ve
      final other = ImprovementsController(backend);
      addTearDown(other.dispose);
      await other.refresh();
      expect(other.items.map((i) => i.section), ['Chat']);
    });

    test('sale de la lista al instante, sin esperar al servidor', () async {
      await ctrl.add(section: 'Música', functions: 'Cola');
      backend.holdFinish = Completer<void>();
      final item = ctrl.items.single;
      final pending = ctrl.finish(item);
      expect(ctrl.items, isEmpty);
      backend.holdFinish!.complete();
      await pending;
      expect(backend.deletes, ['id1']);
    });

    test('si no se puede borrar, la mejora vuelve a la lista y se avisa', () async {
      await ctrl.add(section: 'Música', functions: 'Cola');
      backend.failFinish = _offline;
      await ctrl.finish(ctrl.items.single);
      expect(ctrl.items.map((i) => i.id), ['id1']);
      expect(ctrl.notice, 'No se pudo borrar la mejora. Sin conexión con Supabase');
      backend.failFinish = null;
      await ctrl.finish(ctrl.items.single);
      expect(ctrl.items, isEmpty);
      expect(ctrl.notice, isNull); // el siguiente cambio que sale bien quita el aviso
    });
  });

  group('la pantalla', () {
    late FakeImprovementBackend backend;
    var n = 0;

    setUp(() {
      backend = FakeImprovementBackend();
      n = 0;
    });

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: ImprovementsPage(backend: backend, create: (b) => ImprovementsController(b, newId: () => 'id${++n}', now: () => DateTime.utc(2026, 11, 14, 10))),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('la pantalla es plana: cabecera con línea fina y sin paneles', (tester) async {
      await open(tester);
      // el estilo plano de la ficha de una tarea y del clima: cabecera «> TÍTULO» con una línea fina, sin paneles ni cajas
      expect(find.byType(FlatHeader), findsOneWidget);
      expect(find.byKey(const Key('flat-backdrop')), findsOneWidget); // el fondo va un poco oscurecido
      expect(find.byType(CyberPanel), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(SegmentedButton<Object>), findsNothing);
    });

    testWidgets('sin pendientes lo dice y el «+» las anota: sección, funciones como viñetas y descripción', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('imp-empty')), findsOneWidget);
      await tester.tap(find.byKey(const Key('imp-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('imp-save')));
      await tester.pump();
      expect(find.text('Escribe qué sección quieres agregar o mejorar.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('imp-section')), 'Calendario');
      await tester.tap(find.byKey(const Key('imp-save')));
      await tester.pump();
      expect(find.text('Anota al menos una función o una descripción.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('imp-functions')), '- Vista de agenda\nArrastrar eventos');
      await tester.enterText(find.byKey(const Key('imp-description')), 'Que se vea mejor');
      await tester.tap(find.byKey(const Key('imp-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('imp-card-id1')), findsOneWidget);
      expect(find.text('Calendario'), findsOneWidget);
      expect(find.text('Vista de agenda'), findsOneWidget); // sin el guion de lo escrito
      expect(find.text('Arrastrar eventos'), findsOneWidget);
      expect(find.text('Que se vea mejor'), findsOneWidget);
      expect(find.byKey(const Key('imp-done-id1')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('imp-count'))).data, '1');
      expect(backend.rows.keys, ['id1']);
    });

    testWidgets('«Hecho» pide confirmación; al confirmar la mejora se borra de la base de datos y deja de verse', (tester) async {
      backend.rows['a'] = _item('a', 'Calendario', functions: 'Vista');
      backend.rows['b'] = _item('b', 'Música', functions: 'Cola', at: DateTime.utc(2026, 11, 1));
      await open(tester);
      expect(find.byKey(const Key('imp-card-a')), findsOneWidget);
      expect(find.byKey(const Key('imp-card-b')), findsOneWidget);
      await tester.tap(find.byKey(const Key('imp-done-a')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('imp-done-text'))).data, contains('Calendario'));
      await tester.tap(find.byKey(const Key('imp-done-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('imp-card-a')), findsOneWidget); // cancelar no borra nada
      expect(backend.deletes, isEmpty);
      await tester.tap(find.byKey(const Key('imp-done-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('imp-done-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('imp-card-a')), findsNothing);
      expect(find.byKey(const Key('imp-card-b')), findsOneWidget);
      expect(backend.deletes, ['a']);
      expect(backend.rows.keys, ['b']);
    });

    testWidgets('si no se puede borrar, la mejora se queda y se avisa', (tester) async {
      backend.rows['a'] = _item('a', 'Calendario', functions: 'Vista');
      await open(tester);
      backend.failFinish = _offline;
      await tester.tap(find.byKey(const Key('imp-done-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('imp-done-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('imp-card-a')), findsOneWidget);
      expect(find.byKey(const Key('imp-notice')), findsOneWidget);
    });

    testWidgets('un fallo al leer se explica y se puede reintentar', (tester) async {
      backend.failList = _offline;
      await open(tester);
      expect(find.byKey(const Key('imp-error')), findsOneWidget);
      backend.failList = null;
      backend.rows['a'] = _item('a', 'Chat', functions: 'Respuestas');
      await tester.tap(find.byKey(const Key('imp-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('imp-card-a')), findsOneWidget);
    });

    testWidgets('el botón de actualizar vuelve a leer (lo que se anotó en Merida aparece)', (tester) async {
      await open(tester);
      backend.rows['m'] = _item('m', 'Desde Merida', functions: 'Algo');
      await tester.tap(find.byKey(const Key('imp-refresh')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('imp-card-m')), findsOneWidget);
    });
  });

  group('en la app', () {
    Future<void> openApp(WidgetTester tester, {ImprovementBackend? improvements, bool signedIn = true, FakeAccount? account}) async {
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
            improvements: improvements,
            now: () => DateTime(2026, 11, 14, 12),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    }

    testWidgets('con su backend, el menú circular ofrece «Mejoras» y se llega a ella', (tester) async {
      final backend = FakeImprovementBackend()..rows['a'] = _item('a', 'Calendario', functions: 'Vista');
      await openApp(tester, improvements: backend);
      expect(await menuOptions(tester), contains('improvements'));
      await goToSection(tester, 'improvements');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pumpAndSettle();
      expect(find.byType(ImprovementsPage), findsOneWidget);
      expect(find.byKey(const Key('imp-card-a')), findsOneWidget);
    });

    testWidgets('sin backend no hay sección de mejoras', (tester) async {
      await openApp(tester);
      expect(await menuOptions(tester), isNot(contains('improvements')));
    });

    testWidgets('si la sesión caduca no llama a Supabase: lo explica y deja reintentar', (tester) async {
      final backend = FakeImprovementBackend();
      final account = FakeAccount(uid: 'u1', profile: const Profile(id: 'u1', username: 'gustavo', role: Role.admin));
      await openApp(tester, improvements: backend, account: account);
      account.expire(); // el administrador sigue dentro (no cerró sesión), pero ya no hay sesión con el servidor
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
      await goToSection(tester, 'improvements');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('imp-error')), findsOneWidget);
      expect(find.textContaining('Sin sesión'), findsOneWidget);
      expect(find.byKey(const Key('imp-retry')), findsOneWidget);
    });
  });
}
