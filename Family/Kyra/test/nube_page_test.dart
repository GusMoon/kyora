import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/chat_backend.dart';
import 'package:kyora_chat/data/cloud_files.dart';
import 'package:kyora_chat/data/server_stats.dart';
import 'package:kyora_chat/data/vault_source.dart';
import 'package:kyora_chat/models/profile.dart';
import 'package:kyora_chat/state/cloud_controller.dart';
import 'package:kyora_chat/state/music_controller.dart';
import 'package:kyora_chat/state/server_controller.dart';
import 'package:kyora_chat/state/vault_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/nube_page.dart';
import 'package:kyora_chat/ui/settings_page.dart';

import 'auth_gate_test.dart' show FakeAccount;
import 'fake_backend.dart';
import 'fake_nube.dart';
import 'music_test.dart' show FakeMusicBackend, MemoryMusicStore, FakeSaver;
import 'reminders_test.dart' show FakeScheduler;

/// La sección Nube: las pestañas, lo que dice sin sesión, los archivos del servidor y lo que ocupa tu proyecto de Supabase.
void main() {
  final now = DateTime.utc(2026, 11, 13, 12);
  late FakeServerBackend serverBackend;
  late FakeCloudBackend cloudBackend;
  late MemoryServerStore serverStore;
  late FakeScheduler scheduler;
  late ServerController server;
  late CloudController cloud;
  late VaultController vault;
  late FakeBackend chat;
  final opened = <String>[];

  setUp(() {
    serverBackend = FakeServerBackend(statsOf(420, 300, buckets: const [BucketStat(bucket: 'chat-files', objects: 41, bytes: 255852544)], tables: const [TableStat(name: 'messages', rows: 12840, bytes: 39845888)]));
    cloudBackend = FakeCloudBackend([
      cloudFile('1', 'informe.pdf', size: 3 * mb, at: DateTime.utc(2026, 11, 13, 11, 30)),
      cloudFile('2', 'foto.jpg', mime: 'image/jpeg', size: 200000, from: 'móvil', at: DateTime.utc(2026, 11, 13, 9), thumb: 'u/2/foto_thumb.jpg'),
      cloudFile('3', 'cancion.mp3', mime: 'audio/mpeg', size: 5 * mb, source: CloudSource.music, from: 'para ti', at: DateTime.utc(2026, 11, 10, 12)),
    ]);
    serverStore = MemoryServerStore();
    scheduler = FakeScheduler();
    server = ServerController(serverBackend, serverStore, scheduler: scheduler, now: () => now, every: const Duration(hours: 5));
    cloud = CloudController(cloudBackend);
    vault = VaultController(FakeVaultSource(), MemoryVaultStore());
    chat = FakeBackend();
    opened.clear();
  });

  tearDown(() {
    server.dispose();
    cloud.dispose();
    vault.dispose();
  });

  Future<void> open(WidgetTester tester, FakeAccount account, {bool admin = false, bool withVault = true, bool withCloud = true, NubeTab initial = NubeTab.cloud}) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: NubePage(
        account: account,
        admin: admin,
        server: withCloud ? server : null,
        cloud: withCloud ? cloud : null,
        vault: withVault ? vault : null,
        chat: chat,
        now: () => now,
        initial: initial,
        openUrl: (url) async {
          opened.add(url);
          return true;
        },
      ),
    ));
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
  }

  FakeAccount signedIn({Role role = Role.admin}) => FakeAccount(uid: 'user-1', profile: Profile(id: 'user-1', username: 'gustavo', role: role));

  /// Muestra lo que hay en la lista de la Nube (si aún no se construyó, desplaza hasta que salga).
  Future<void> reveal(WidgetTester tester, Finder target) async {
    if (target.evaluate().isNotEmpty) {
      await tester.ensureVisible(target.first);
    } else {
      final list = find.descendant(of: find.byKey(const Key('nube-cloud')), matching: find.byType(Scrollable));
      if (list.evaluate().isNotEmpty) await tester.scrollUntilVisible(target, 300, scrollable: list.first);
    }
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await reveal(tester, find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
  }

  group('las pestañas', () {
    testWidgets('el administrador tiene Nube, Local y Chat; empieza en la Nube', (tester) async {
      await open(tester, signedIn(), admin: true);
      for (final t in ['cloud', 'local', 'chat']) {
        expect(find.byKey(Key('nube-tab-$t')), findsOneWidget, reason: t);
      }
      expect(find.text('[NUBE]'), findsOneWidget);
      expect(find.byKey(const Key('srv')), findsOneWidget);
    });

    testWidgets('el pasante no tiene la pestaña del chat', (tester) async {
      await open(tester, signedIn(role: Role.intern));
      expect(find.byKey(const Key('nube-tab-cloud')), findsOneWidget);
      expect(find.byKey(const Key('nube-tab-local')), findsOneWidget);
      expect(find.byKey(const Key('nube-tab-chat')), findsNothing);
    });

    testWidgets('Local enseña el Vault (sin carpeta elegida, invita a elegirla) y al volver a la Nube no se pierde nada', (tester) async {
      await open(tester, signedIn());
      expect(find.byKey(const Key('vault-pick')), findsNothing);
      await tapKey(tester, 'nube-tab-local');
      expect(find.byKey(const Key('vault-pick')), findsOneWidget);
      expect(find.text('[LOCAL]'), findsOneWidget);
      await tapKey(tester, 'nube-tab-cloud');
      expect(find.byKey(const Key('vault-pick')), findsNothing);
      expect(find.byKey(const Key('srv')), findsOneWidget);
    });

    testWidgets('el chat solo se abre al entrar en su pestaña y es la terminal de siempre', (tester) async {
      await open(tester, signedIn(), admin: true);
      expect(chat.calls, isEmpty); // todavía no se abrió el chat
      await tapKey(tester, 'nube-tab-chat');
      expect(find.byKey(const Key('chat-terminal')), findsOneWidget);
      expect(chat.calls, contains('ensure'));
    });

    testWidgets('sin Vault ni Supabase de archivos y sin ser administrador no hay nada que enseñar', (tester) async {
      await open(tester, signedIn(role: Role.intern), withVault: false, withCloud: false);
      expect(find.byKey(const Key('nube-page')), findsNothing);
    });

    testWidgets('con una sola pestaña no hace falta la barra', (tester) async {
      await open(tester, signedIn(role: Role.intern), withVault: false);
      expect(find.byKey(const Key('nube-tab-cloud')), findsNothing);
      expect(find.byKey(const Key('srv')), findsOneWidget);
    });
  });

  group('sin sesión', () {
    testWidgets('Nube y Chat piden entrar (sin llamar a Supabase) y Local funciona igual', (tester) async {
      var signIns = 0;
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: NubePage(account: FakeAccount(), admin: true, server: server, cloud: cloud, vault: vault, chat: chat, onSignIn: () => signIns++),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nube-signed-out')), findsOneWidget);
      expect(find.textContaining('Entra con tu cuenta'), findsOneWidget);
      expect(serverBackend.calls, 0);
      expect(cloudBackend.lists, 0);
      await tester.tap(find.byKey(const Key('nube-sign-in')));
      expect(signIns, 1);
      await tapKey(tester, 'nube-tab-chat');
      expect(find.byKey(const Key('nube-signed-out')), findsOneWidget);
      expect(chat.calls, isEmpty);
      await tapKey(tester, 'nube-tab-local');
      expect(find.byKey(const Key('vault-pick')), findsOneWidget);
    });

    testWidgets('al entrar la pestaña se llena sola', (tester) async {
      final account = FakeAccount();
      await open(tester, account);
      expect(find.byKey(const Key('nube-signed-out')), findsOneWidget);
      await account.signIn('yo@correo.com', 'secreta1');
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nube-signed-out')), findsNothing);
      expect(find.byKey(const Key('srv')), findsOneWidget);
    });
  });

  group('los archivos del servidor', () {
    testWidgets('al abrir lee el servidor y enseña cada archivo con su tamaño, quién lo mandó y cuándo', (tester) async {
      await open(tester, signedIn());
      expect(cloudBackend.lists, 1);
      expect(find.text('3 archivos en el servidor (8,2 MB).'), findsOneWidget);
      expect(find.text('informe.pdf'), findsOneWidget);
      expect(find.text('3,0 MB · PC · hace 30 min'), findsOneWidget);
      expect(find.text('195 KB · móvil · hace 3 h'), findsOneWidget);
      await reveal(tester, find.text('cancion.mp3'));
      expect(find.text('5,0 MB · para ti · 10 nov'), findsOneWidget);
    });

    testWidgets('los filtros por tipo dejan solo ese tipo, y volver a tocar el filtro los muestra todos', (tester) async {
      await open(tester, signedIn());
      expect(find.byKey(const Key('cloud-filter-all')), findsOneWidget);
      await tapKey(tester, 'cloud-filter-audio');
      expect(find.text('cancion.mp3'), findsOneWidget);
      expect(find.text('informe.pdf'), findsNothing);
      await tapKey(tester, 'cloud-filter-audio');
      expect(find.text('informe.pdf'), findsOneWidget);
      await tapKey(tester, 'cloud-filter-doc');
      expect(find.text('foto.jpg'), findsNothing);
      await tapKey(tester, 'cloud-filter-all');
      expect(find.text('foto.jpg'), findsOneWidget);
    });

    testWidgets('tocar un archivo lo abre con una dirección temporal; «Bajar» pide la del mismo archivo con su nombre', (tester) async {
      await open(tester, signedIn());
      await tapKey(tester, 'cloud-open-chat:1');
      expect(cloudBackend.urls, contains(('u/1/informe.pdf', null)));
      expect(opened, ['https://nube.test/u/1/informe.pdf']);
      await tapKey(tester, 'cloud-download-chat:1');
      expect(cloudBackend.urls, contains(('u/1/informe.pdf', 'informe.pdf')));
      expect(opened.last, contains('download=informe.pdf'));
    });

    testWidgets('borrar pide confirmación: «Cancelar» no borra nada; «Borrar» lo quita del servidor de verdad', (tester) async {
      await open(tester, signedIn());
      await tapKey(tester, 'cloud-delete-chat:1');
      expect(find.text('¿Borrar del servidor?'), findsOneWidget);
      expect(find.textContaining('informe.pdf'), findsWidgets);
      await tapKey(tester, 'cloud-cancel');
      expect(cloudBackend.deleted, isEmpty);
      expect(find.text('informe.pdf'), findsOneWidget);
      await tapKey(tester, 'cloud-delete-chat:1');
      await tapKey(tester, 'cloud-confirm');
      expect(cloudBackend.deleted, ['chat:1']);
      expect(find.text('informe.pdf'), findsNothing);
      expect(find.text('Borrado del servidor.'), findsOneWidget);
    });

    testWidgets('una canción avisa de que se borra para todos los que la tenían', (tester) async {
      await open(tester, signedIn());
      await tapKey(tester, 'cloud-delete-music:3');
      expect(find.textContaining('para todos los que la tenían'), findsOneWidget);
      await tapKey(tester, 'cloud-cancel');
    });

    testWidgets('si el servidor no deja borrar, lo dice y el archivo se queda', (tester) async {
      await open(tester, signedIn());
      cloudBackend.deleteError = const ChatException('El servidor no dejó borrar este archivo.');
      await tapKey(tester, 'cloud-delete-chat:1');
      await tapKey(tester, 'cloud-confirm');
      expect(find.text('El servidor no dejó borrar este archivo.'), findsOneWidget);
      expect(find.text('informe.pdf'), findsOneWidget);
    });

    testWidgets('sin archivos lo dice, y si falla la lectura enseña el motivo; «Actualizar» vuelve a leer', (tester) async {
      cloudBackend.files = [];
      await open(tester, signedIn());
      expect(find.text('No hay archivos en el servidor.'), findsOneWidget);
      cloudBackend.listError = const ChatException('Sin conexión con Supabase', retryable: true);
      await tapKey(tester, 'cloud-refresh');
      expect(find.text('Sin conexión con Supabase'), findsOneWidget);
      cloudBackend.listError = null;
      cloudBackend.files = [cloudFile('9', 'nuevo.pdf')];
      await tapKey(tester, 'cloud-refresh');
      expect(find.text('nuevo.pdf'), findsOneWidget);
    });
  });

  group('lo que ocupa el servidor', () {
    testWidgets('con el 84 % de la base de datos enseña la advertencia, los dos medidores y el desglose', (tester) async {
      await open(tester, signedIn());
      expect(serverBackend.calls, 1); // mide al abrir
      final warn = find.byKey(const Key('srv-warn'));
      expect(warn, findsOneWidget);
      expect(find.descendant(of: warn, matching: find.textContaining('84 % del plan gratuito')), findsOneWidget);
      expect(find.descendant(of: warn, matching: find.textContaining('Base de datos: llevas 84 %')), findsOneWidget);
      expect(find.text('Tu servidor se está llenando.'), findsOneWidget);
      expect(find.text('84 %'), findsOneWidget);
      expect(find.text('29 %'), findsOneWidget);
      expect(find.byKey(const Key('srv-meter-db')), findsOneWidget);
      expect(find.byKey(const Key('srv-meter-files')), findsOneWidget);
      expect(find.byKey(const Key('srv-mark-db')), findsOneWidget); // la marca del 80 %
      final c = KyoraColors.classic();
      expect(tester.widget<ColoredBox>(find.byKey(const Key('srv-bar-db'))).color, c.reminders); // amarillo: pasó el 80 %
      expect(tester.widget<ColoredBox>(find.byKey(const Key('srv-bar-files'))).color, c.accent); // el otro va bien
      expect(find.text('420,0 MB de 500,0 MB'), findsOneWidget);
      expect(find.byKey(const Key('srv-breakdown')), findsNothing);
      await tapKey(tester, 'srv-more');
      expect(find.textContaining('chat-files'), findsOneWidget);
      expect(find.textContaining('12840 filas'), findsOneWidget);
      expect(find.textContaining('no se pueden medir desde la app'), findsOneWidget); // el tráfico y los usuarios activos no salen por ninguna API
    });

    testWidgets('lo notifica una vez, con el texto de la advertencia', (tester) async {
      await open(tester, signedIn());
      expect(scheduler.shown.length, 1);
      expect(scheduler.shown.values.single.$2, contains('84 %'));
    });

    testWidgets('por debajo del 80 % no hay advertencia y las barras van del color normal', (tester) async {
      serverBackend.stats = statsOf(100, 100);
      await open(tester, signedIn());
      expect(find.byKey(const Key('srv-warn')), findsNothing);
      expect(scheduler.shown, isEmpty);
      expect(tester.widget<ColoredBox>(find.byKey(const Key('srv-bar-db'))).color, KyoraColors.classic().accent);
    });

    testWidgets('al pasar del 95 % es crítico (en rojo) y al pasar el límite lo dice', (tester) async {
      serverBackend.stats = statsOf(10, 1100);
      await open(tester, signedIn());
      expect(find.text('Superaste un límite del plan gratuito.'), findsOneWidget);
      expect(tester.widget<ColoredBox>(find.byKey(const Key('srv-bar-files'))).color, KyoraColors.classic().warn);
      expect(find.text('107 %'), findsOneWidget);
    });

    testWidgets('usa los límites de Configuración: con otro plan ya no está cerca', (tester) async {
      await open(tester, signedIn());
      expect(find.byKey(const Key('srv-warn')), findsOneWidget);
      await tester.runAsync(() => server.setLimits(const QuotaLimits(dbMb: 8192, filesMb: 1024)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('srv-warn')), findsNothing);
    });

    testWidgets('si falta la función lo dice, y «Medir ahora» vuelve a pedir las estadísticas', (tester) async {
      serverBackend.error = const ChatException('Falta la función server_stats en Supabase. Vuelve a ejecutar Server/supabase/schema.sql en el SQL Editor.');
      await open(tester, signedIn());
      expect(find.byKey(const Key('srv-error')), findsOneWidget);
      expect(find.textContaining('server_stats'), findsOneWidget);
      serverBackend.error = null;
      final before = serverBackend.calls;
      await tapKey(tester, 'srv-measure');
      expect(serverBackend.calls, before + 1);
      expect(find.byKey(const Key('srv-error')), findsNothing);
      expect(find.byKey(const Key('srv-meter-db')), findsOneWidget);
    });

  });

  group('los límites en Configuración', () {
    Future<void> openSettings(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final music = MusicController(FakeMusicBackend(), MemoryMusicStore(), FakeSaver());
      addTearDown(music.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: SettingsPage(music: music, role: Role.admin, onSignOut: () async {}, server: server, initialTile: 'server'),
      ));
      await tester.runAsync(server.start);
      await tester.pumpAndSettle();
    }

    testWidgets('la ficha «Servidor» enseña los dos límites y los guarda', (tester) async {
      await openSettings(tester);
      expect(find.byKey(const Key('settings-limits')), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('settings-limit-db'))).controller!.text, '500');
      expect(tester.widget<TextField>(find.byKey(const Key('settings-limit-files'))).controller!.text, '1024');
      await tester.enterText(find.byKey(const Key('settings-limit-db')), '8192');
      await tester.enterText(find.byKey(const Key('settings-limit-files')), '102400');
      await tester.tap(find.byKey(const Key('settings-limits-save')));
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      expect(server.limits, const QuotaLimits(dbMb: 8192, filesMb: 102400));
      expect(await serverStore.loadLimits(), const QuotaLimits(dbMb: 8192, filesMb: 102400));
    });

    testWidgets('un número que no vale lo dice y no cambia nada; «Volver al plan gratuito» los restablece', (tester) async {
      await openSettings(tester);
      await tester.enterText(find.byKey(const Key('settings-limit-db')), 'mucho');
      await tester.tap(find.byKey(const Key('settings-limits-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Escribe un número entero de MB'), findsOneWidget);
      expect(server.limits, const QuotaLimits());
      await tester.runAsync(() => server.setLimits(const QuotaLimits(dbMb: 8192, filesMb: 2048)));
      await tester.tap(find.byKey(const Key('settings-limits-reset')));
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      expect(server.limits, const QuotaLimits());
      expect(tester.widget<TextField>(find.byKey(const Key('settings-limit-db'))).controller!.text, '500');
    });
  });
}
