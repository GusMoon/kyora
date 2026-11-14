import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/chat_backend.dart';
import 'package:kyora_chat/data/chat_repository.dart' show explainPostgrest;
import 'package:kyora_chat/data/cloud_files.dart';
import 'package:kyora_chat/data/server_stats.dart';
import 'package:kyora_chat/state/cloud_controller.dart';
import 'package:kyora_chat/state/server_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'fake_nube.dart';
import 'reminders_test.dart' show FakeScheduler;

/// Lo mismo que prueba Merida (`tests/server.test.ts`): los límites del plan gratuito, el 80 %, el formato, el aviso de una vez al día y la
/// lectura de lo que devuelve `server_stats()`.
void main() {
  const limits = QuotaLimits();

  group('los límites y el 80 %', () {
    test('los límites del plan gratuito son 500 MB de base de datos y 1 GB de archivos, y el aviso es al 80 %', () {
      expect([freeDbMb, freeFilesMb, warnAt, criticalAt], [500, 1024, 0.8, 0.95]);
      expect(const QuotaLimits().dbMb, 500);
      expect(const QuotaLimits().filesMb, 1024);
    });

    test('el nivel cambia justo en el 80 % y en el 95 %', () {
      expect(levelOf(0.79), QuotaLevel.ok);
      expect(levelOf(0.8), QuotaLevel.warn);
      expect(levelOf(0.949), QuotaLevel.warn);
      expect(levelOf(0.95), QuotaLevel.critical);
      expect(levelOf(1.2), QuotaLevel.critical);
    });

    test('400 MB de 500 es el 80 %: avisa; 399 MB no', () {
      expect(overQuota(statsOf(399, 10), limits), isEmpty);
      final over = overQuota(statsOf(400, 10), limits);
      expect(over.map((q) => q.id), [QuotaId.db]);
      expect(over.single.level, QuotaLevel.warn);
      expect(over.single.ratio, 0.8);
    });

    test('avisa de cada límite por separado (base de datos y archivos)', () {
      expect(overQuota(statsOf(450, 900), limits).map((q) => q.id), [QuotaId.db, QuotaId.files]);
      expect(overQuota(statsOf(10, 1000), limits).map((q) => q.id), [QuotaId.files]);
    });

    test('respeta los límites que cambies (otro plan)', () {
      expect(overQuota(statsOf(450, 10), const QuotaLimits(dbMb: 8192, filesMb: 102400)), isEmpty);
      expect(overQuota(statsOf(450, 10), const QuotaLimits(dbMb: 500, filesMb: 1)).map((q) => q.id), [QuotaId.db, QuotaId.files]);
    });

    test('el porcentaje se redondea hacia abajo (no dice 80 % sin haber llegado) y puede pasar de 100', () {
      expect(percent(0.7999), '79 %');
      expect(percent(0.8), '80 %');
      expect(percent(1.234), '123 %');
    });

    test('da el tamaño en B, KB, MB y GB', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(2048), '2 KB');
      expect(formatBytes((412.3 * mb).round()), '412,3 MB');
      expect(formatBytes((1.5 * 1024 * mb).round()), '1,50 GB');
    });

    test('el texto de la advertencia dice cuánto llevas y cuánto queda; y si te pasaste, lo dice', () {
      final db = quotas(statsOf(420, 0), limits).first;
      expect(warningText(db), 'Base de datos: llevas 84 % del plan gratuito (420,0 MB de 500,0 MB; quedan 80,0 MB).');
      final over = quotas(statsOf(520, 0), limits).first;
      expect(warningText(over), contains('superaste el límite'));
    });

    test('solo se vuelve a notificar pasado un día', () {
      final t = DateTime.utc(2026, 11, 13, 10);
      expect(shouldRenotify(null, t), isTrue);
      expect(shouldRenotify(t, t.add(renotifyAfter - const Duration(milliseconds: 1))), isFalse);
      expect(shouldRenotify(t, t.add(renotifyAfter)), isTrue);
    });

    test('los límites solo aceptan enteros entre 1 y 10 millones', () {
      expect(validMb(500, 1), 500);
      expect(validMb(0, 7), 7);
      expect(validMb(1.5, 7), 7);
      expect(validMb('500', 7), 7);
      expect(validMb(10000001, 7), 7);
    });
  });

  group('lo que se guarda en el teléfono', () {
    test('los límites se guardan y se leen; uno corrupto o fuera de rango vuelve al del plan gratuito', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await PrefsServerStore.open();
      expect(await store.loadLimits(), const QuotaLimits());
      await store.saveLimits(const QuotaLimits(dbMb: 8192, filesMb: 102400));
      expect(await (await PrefsServerStore.open()).loadLimits(), const QuotaLimits(dbMb: 8192, filesMb: 102400));
      SharedPreferences.setMockInitialValues({'server.limit.db': -3, 'server.limit.files': 20000000});
      expect(await (await PrefsServerStore.open()).loadLimits(), const QuotaLimits());
    });

    test('lo último notificado se guarda y se lee, y un valor corrupto no rompe', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await PrefsServerStore.open();
      final at = DateTime.utc(2026, 11, 13, 10);
      await store.saveWarned({QuotaId.db: at});
      expect(await (await PrefsServerStore.open()).loadWarned(), {QuotaId.db: at});
      SharedPreferences.setMockInitialValues({'server.warned': '{no es json'});
      expect(await (await PrefsServerStore.open()).loadWarned(), isEmpty);
      SharedPreferences.setMockInitialValues({'server.warned': '{"db":"ayer","files":5}'});
      expect((await (await PrefsServerStore.open()).loadWarned()).keys, [QuotaId.files]);
    });
  });

  group('lo que devuelve la función', () {
    test('se limpia: los bigint llegan como texto y lo que falta queda en cero', () {
      final s = parseStats({
        'db_bytes': '441450496',
        'storage_bytes': 5,
        'storage_objects': '2',
        'buckets': [{'bucket': 'chat-files', 'objects': '2', 'bytes': '5'}],
        'tables': [{'name': 'tasks', 'bytes': '8192', 'rows': '3'}],
        'at': '2026-11-13T10:00:00Z',
      });
      expect((s.dbBytes, s.storageBytes, s.storageObjects), (441450496, 5, 2));
      expect((s.buckets.single.bucket, s.buckets.single.objects, s.buckets.single.bytes), ('chat-files', 2, 5));
      expect((s.tables.single.name, s.tables.single.bytes, s.tables.single.rows), ('tasks', 8192, 3));
      expect(s.at, DateTime.utc(2026, 11, 13, 10));
      final empty = parseStats(null);
      expect(empty.dbBytes, 0);
      expect(empty.buckets, isEmpty);
      expect(empty.tables, isEmpty);
    });

    test('si la función no existe, dice que hay que volver a ejecutar schema.sql', () {
      final e = explainPostgrest(const PostgrestException(message: 'Could not find the function public.server_stats without parameters in the schema cache', code: 'PGRST202'));
      expect(e.message, contains('server_stats'));
      expect(e.message, contains('schema.sql'));
      // cualquier otra función que falte conserva su mensaje de siempre
      final other = explainPostgrest(const PostgrestException(message: 'Could not find the function public.list_messages', code: 'PGRST202'));
      expect(other.message, isNot(contains('server_stats')));
    });

    test('otros errores se propagan tal cual', () {
      final e = explainPostgrest(const PostgrestException(message: 'sin red', code: '500'));
      expect(e.message, 'sin red');
    });
  });

  group('el controlador del servidor', () {
    late FakeServerBackend backend;
    late MemoryServerStore store;
    late FakeScheduler scheduler;
    var now = DateTime.utc(2026, 11, 13, 10);

    ServerController make() => ServerController(backend, store, scheduler: scheduler, now: () => now, every: const Duration(hours: 5));

    setUp(() {
      backend = FakeServerBackend(statsOf(420, 300));
      store = MemoryServerStore();
      scheduler = FakeScheduler();
      now = DateTime.utc(2026, 11, 13, 10);
    });

    test('al empezar mide y deja los dos límites con lo que llevas', () async {
      final c = make();
      addTearDown(c.dispose);
      await c.start();
      await c.measure();
      expect(c.stats, isNotNull);
      expect(c.quotaList.map((q) => percent(q.ratio)), ['84 %', '29 %']);
      expect(c.warnings.map((q) => q.id), [QuotaId.db]);
      expect(c.error, isNull);
    });

    test('al llegar al 80 % avisa con una notificación; no la repite en el día, y sí pasado un día', () async {
      final c = make();
      addTearDown(c.dispose);
      await c.measure();
      expect(scheduler.shown.length, 1);
      final (title, body) = scheduler.shown.values.single;
      expect(title, contains('llenando'));
      expect(body, contains('84 %'));
      await c.measure();
      expect(scheduler.shown.length, 1);
      expect(scheduler.permissionAsks, 1); // el permiso se pide una vez, antes del primer aviso
      scheduler.shown.clear();
      now = now.add(const Duration(hours: 25));
      await c.measure();
      expect(scheduler.shown.length, 1);
    });

    test('cada límite avisa por separado, con su propio número de notificación', () async {
      backend.stats = statsOf(450, 900);
      final c = make();
      addTearDown(c.dispose);
      await c.measure();
      expect(scheduler.shown.keys.toSet(), {ServerController.notifIdBase, ServerController.notifIdBase + 1});
    });

    test('por debajo del 80 % no avisa; y si baja y vuelve a subir, avisa otra vez', () async {
      backend.stats = statsOf(100, 100);
      final c = make();
      addTearDown(c.dispose);
      await c.measure();
      expect(scheduler.shown, isEmpty);
      expect(c.warnings, isEmpty);
      backend.stats = statsOf(450, 100);
      await c.measure();
      expect(scheduler.shown.length, 1);
      backend.stats = statsOf(100, 100); // se liberó espacio: el aviso se olvida
      await c.measure();
      expect(await store.loadWarned(), isEmpty);
      scheduler.shown.clear();
      backend.stats = statsOf(450, 100);
      await c.measure();
      expect(scheduler.shown.length, 1); // sin esperar a que pase el día
    });

    test('lo avisado se recuerda aunque se reabra la app', () async {
      final a = make();
      await a.measure();
      a.dispose();
      scheduler.shown.clear();
      final b = make();
      addTearDown(b.dispose);
      await b.measure();
      expect(scheduler.shown, isEmpty);
    });

    test('cambiar los límites se guarda y vuelve a comprobar: con otro plan ya no está cerca', () async {
      final c = make();
      addTearDown(c.dispose);
      await c.measure();
      expect(c.warnings, isNotEmpty);
      await c.setLimits(const QuotaLimits(dbMb: 8192, filesMb: 102400));
      expect(c.warnings, isEmpty);
      expect(await store.loadLimits(), const QuotaLimits(dbMb: 8192, filesMb: 102400));
      await c.setLimits(const QuotaLimits(dbMb: 0, filesMb: 1)); // un valor imposible no cambia el que ya había
      expect(c.limits.dbMb, 8192);
      expect(c.limits.filesMb, 1);
    });

    test('si no se puede medir lo dice (por ejemplo, que falta schema.sql) y no pierde lo último que midió', () async {
      final c = make();
      addTearDown(c.dispose);
      await c.measure();
      backend.error = const ChatException('Falta la función server_stats en Supabase. Vuelve a ejecutar schema.sql.');
      await c.measure();
      expect(c.error, contains('server_stats'));
      expect(c.stats, isNotNull);
      backend.error = null;
      await c.measure();
      expect(c.error, isNull);
    });

    test('una medición en curso no empieza otra', () async {
      final c = make();
      addTearDown(c.dispose);
      backend.hold = Completer<void>();
      final first = c.measure();
      await c.measure();
      expect(backend.calls, 1);
      expect(c.measuring, isTrue);
      backend.hold!.complete();
      await first;
      expect(c.measuring, isFalse);
    });

    test('sin notificaciones el aviso sigue saliendo dentro de la app', () async {
      scheduler.failSchedule = true;
      final c = make();
      addTearDown(c.dispose);
      await c.measure();
      expect(c.warnings, isNotEmpty);
      expect(c.error, isNull);
    });

    test('mide solo cada cierto tiempo', () async {
      final c = ServerController(backend, store, scheduler: scheduler, now: () => now, every: const Duration(milliseconds: 20));
      addTearDown(c.dispose);
      await c.start();
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(backend.calls, greaterThan(2));
    });
  });

  group('los archivos de la nube', () {
    test('un archivo por ruta, lo más nuevo primero, y las canciones dicen a quién van', () {
      final merged = mergeCloud(
        [
          {'id': 'a1', 'message_id': 'm1', 'storage_path': 'u/a/foto.jpg', 'file_name': 'foto.jpg', 'mime_type': 'image/jpeg', 'size_bytes': 10, 'created_at': '2026-11-10T10:00:00Z', 'message': {'sender_device': 'pc', 'deleted_at': null}},
          {'id': 'a2', 'message_id': 'm2', 'storage_path': 'u/b/borrada.pdf', 'file_name': 'borrada.pdf', 'mime_type': 'application/pdf', 'size_bytes': 10, 'created_at': '2026-11-11T10:00:00Z', 'message': {'sender_device': 'pc', 'deleted_at': '2026-11-11T11:00:00Z'}},
        ],
        [
          {'id': 't1', 'title': 'Canción', 'file_name': 'cancion.mp3', 'storage_path': 'u/m/cancion.mp3', 'mime_type': 'audio/mpeg', 'size_bytes': 5, 'created_at': '2026-11-12T10:00:00Z', 'recipient_id': 'me'},
          {'id': 't2', 'title': 'Canción', 'file_name': 'cancion.mp3', 'storage_path': 'u/m/cancion.mp3', 'mime_type': 'audio/mpeg', 'size_bytes': 5, 'created_at': '2026-11-12T10:00:00Z', 'recipient_id': 'ana-id'},
        ],
        'me',
        {'ana-id': 'ana'},
      );
      expect(merged.map((f) => f.name), ['cancion.mp3', 'foto.jpg']); // la del mensaje borrado no cuenta
      expect(merged.first.from, 'para ti, para ana'); // el mismo MP3 para dos: se muestra una vez
      expect(merged.first.kind, CloudKind.audio);
      expect(merged.last.from, 'PC');
      expect(merged.last.kind, CloudKind.image);
    });

    test('el tipo sale del tipo MIME o de la extensión', () {
      expect(kindOf('image/png'), CloudKind.image);
      expect(kindOf('audio/mpeg'), CloudKind.audio);
      expect(kindOf('video/mp4'), CloudKind.video);
      expect(kindOf('application/pdf'), CloudKind.doc);
      expect(kindOf('application/octet-stream', 'datos.CSV'), CloudKind.doc);
      expect(kindOf('application/octet-stream', 'raro.bin'), CloudKind.other);
    });

    test('cuánto hace que llegó', () {
      final now = DateTime.utc(2026, 11, 13, 12);
      expect(agoLabel(now, now), 'ahora');
      expect(agoLabel(now.subtract(const Duration(minutes: 5)), now), 'hace 5 min');
      expect(agoLabel(now.subtract(const Duration(hours: 3)), now), 'hace 3 h');
      expect(agoLabel(now.subtract(const Duration(hours: 30)), now), 'ayer');
    });

    test('el controlador lista, filtra por tipo y borra de verdad (y dice por qué si no pudo)', () async {
      final backend = FakeCloudBackend([cloudFile('1', 'a.pdf'), cloudFile('2', 'b.jpg', mime: 'image/jpeg'), cloudFile('3', 'c.mp3', mime: 'audio/mpeg', source: CloudSource.music)]);
      final c = CloudController(backend);
      addTearDown(c.dispose);
      await c.load();
      expect(c.files.length, 3);
      expect(c.totals.count, 3);
      expect(c.totals.byKind[CloudKind.image], 1);
      c.setFilter(CloudKind.audio);
      expect(c.visible.map((f) => f.name), ['c.mp3']);
      c.setFilter(null);
      backend.deleteError = const ChatException('El servidor no dejó borrar este archivo.');
      expect(await c.delete(c.files.first), 'El servidor no dejó borrar este archivo.');
      expect(c.files.length, 3);
      backend.deleteError = null;
      final target = c.files.firstWhere((f) => f.name == 'b.jpg');
      expect(await c.delete(target), isNull);
      expect(backend.deleted, [target.id]);
      expect(c.files.map((f) => f.name), isNot(contains('b.jpg')));
      backend.listError = const ChatException('Sin conexión', retryable: true);
      await c.load();
      expect(c.error, 'Sin conexión');
    });
  });
}
